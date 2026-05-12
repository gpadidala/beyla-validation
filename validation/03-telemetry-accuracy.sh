#!/usr/bin/env bash
# Layer 03 — Telemetry accuracy.
# Uses REAL Beyla metric names (see docs/beyla-metrics-reference.md).

set -Eeuo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib/common.sh"

NS="${1:?namespace required}"
REPORTS_DIR="${2:-${REPORTS_DIR}}"
LAYER=telemetry

log "Layer 03 — telemetry accuracy in namespace=$NS"

# 1. Tempo ingest rate (Tempo's own counter, not a Beyla metric)
trace_rate=$(prom_query "sum(rate(tempo_distributor_spans_received_total[5m]))")
trace_rate=${trace_rate:-0}
if gt "$trace_rate" 0; then
  report_check tempo_ingest_rate pass 100 "Tempo ingesting ${trace_rate} spans/sec" $LAYER
else
  report_check tempo_ingest_rate fail 0 "zero traces ingested" $LAYER
fi

# 2. Beyla emitting traces? (real metric: beyla_otel_trace_exports_total)
beyla_traces=$(prom_query 'sum(rate(beyla_otel_trace_exports_total[5m]))')
if [[ -n "$beyla_traces" ]] && gt "$beyla_traces" 0; then
  report_check beyla_trace_exports pass 100 "Beyla exporting ${beyla_traces} traces/sec" $LAYER
else
  report_check beyla_trace_exports fail 0 "Beyla exporting zero traces" $LAYER
fi

# 3. Trace export error ratio (Beyla side)
err_ratio=$(prom_query 'sum(rate(beyla_otel_trace_export_errors_total[5m])) / clamp_min(sum(rate(beyla_otel_trace_exports_total[5m])), 1)')
if [[ -n "$err_ratio" ]] && gt "$err_ratio" 0.01; then
  report_check trace_export_errors fail 30 "Beyla trace export error ratio = $err_ratio" $LAYER
else
  report_check trace_export_errors pass 100 "trace export error ratio = ${err_ratio:-0}" $LAYER
fi

# 4. Application request volume vs spans emitted (sanity coherence)
req_count=$(prom_query "sum(rate({__name__=~\"http_server_request_duration_seconds_count|http_server_request_duration_count\",k8s_namespace_name=\"$NS\"}[5m]))")
if [[ -n "$req_count" ]] && gt "$req_count" 0; then
  report_check app_traffic_seen pass 100 "Beyla sees ${req_count} req/s in $NS" $LAYER
else
  report_check app_traffic_seen warn 50 "no app traffic visible to Beyla in $NS" $LAYER
fi

# 5. Profile freshness — Pyroscope query for recent CPU profiles
fresh=$(curl -sf "${PYROSCOPE_URL}/api/v1/query?query=process_cpu:cpu:nanoseconds:cpu:nanoseconds{service_name!=\"\"}" \
  -G --data-urlencode "from=now-5m" --data-urlencode "until=now" \
  | jq -r '.flamebearer.numTicks // 0' 2>/dev/null || echo 0)
if [[ "${fresh:-0}" -gt 0 ]]; then
  report_check profile_freshness pass 100 "Pyroscope has fresh profiles" $LAYER
else
  report_check profile_freshness fail 0 "no profiles in last 5m" $LAYER
fi

log "Layer 03 complete"
