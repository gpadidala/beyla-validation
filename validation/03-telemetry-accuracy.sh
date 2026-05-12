#!/usr/bin/env bash
# Layer 03 — Telemetry accuracy.
# Validates trace completeness, span coverage, and profile freshness.

set -Eeuo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib/common.sh"

NS="${1:?namespace required}"
REPORTS_DIR="${2:-${REPORTS_DIR}}"
LAYER=telemetry

log "Layer 03 — telemetry accuracy in namespace=$NS"

# 1. Trace ingest rate
trace_rate=$(prom_query "sum(rate(tempo_distributor_spans_received_total{}[5m]))")
[[ -z "$trace_rate" ]] && trace_rate=0
if gt 0 "$trace_rate"; then
  report_check tempo_ingest_rate fail 0 "zero traces ingested" $LAYER
else
  report_check tempo_ingest_rate pass 100 "Tempo ingesting ${trace_rate} spans/sec" $LAYER
fi

# 2. Sampling effectiveness — observed vs configured ratio
configured=$(prom_query "beyla_otel_traces_sampler_arg")
sampled=$(prom_query "sum(rate(beyla_otel_traces_sampled_total[5m])) / sum(rate(beyla_otel_traces_total[5m]))")
if [[ -n "$configured" && -n "$sampled" ]]; then
  drift=$(awk -v s="$sampled" -v c="$configured" 'BEGIN{print (s-c < 0 ? c-s : s-c)*100}')
  if gt "$drift" 2; then
    report_check sampling_drift warn 70 "observed sampling=${sampled} vs configured=${configured} (Δ=${drift}%)" $LAYER
  else
    report_check sampling_drift pass 100 "sampling within 2% of configured" $LAYER
  fi
fi

# 3. Span completeness — every request should generate at least 1 span.
# Compare request_count from Beyla metrics vs spans emitted.
req_count=$(prom_query "sum(rate(http_server_request_duration_seconds_count{k8s_namespace_name=\"$NS\"}[5m]))")
span_count=$(prom_query "sum(rate(beyla_otel_traces_total{k8s_namespace_name=\"$NS\"}[5m]))")
if [[ -n "$req_count" && -n "$span_count" && "$req_count" != "0" ]]; then
  expected_span_rate=$(awk -v r="$req_count" -v s="$configured" 'BEGIN{print r*s}')
  obs_drift=$(awk -v e="$expected_span_rate" -v o="$span_count" 'BEGIN{ if(e==0){print 0}else{print ((o-e)/e)*100}}')
  if gt "${obs_drift#-}" 20; then
    report_check span_completeness warn 60 "span emission Δ=${obs_drift}% from expected" $LAYER
  else
    report_check span_completeness pass 100 "spans match request rate" $LAYER
  fi
fi

# 4. Profile freshness — Pyroscope query for recent profile.
fresh=$(curl -sf "${PYROSCOPE_URL}/api/v1/query?query=process_cpu:cpu:nanoseconds:cpu:nanoseconds{service_name!=\"\"}" \
  -G --data-urlencode "from=now-5m" --data-urlencode "until=now" \
  | jq -r '.flamebearer.numTicks // 0')
if [[ "${fresh:-0}" -gt 0 ]]; then
  report_check profile_freshness pass 100 "Pyroscope has fresh profiles" $LAYER
else
  report_check profile_freshness fail 0 "no profiles in last 5m" $LAYER
fi

log "Layer 03 complete"
