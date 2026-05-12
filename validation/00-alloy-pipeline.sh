#!/usr/bin/env bash
# Layer 00 — Alloy pipeline health.
# Runs BEFORE the rest of the validation suite: if Alloy isn't shipping
# data, every downstream test would just measure a broken pipeline.

set -Eeuo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib/common.sh"

NS="${1:-alloy}"
REPORTS_DIR="${2:-${REPORTS_DIR}}"
LAYER=alloy

log "Layer 00 — Alloy pipeline in namespace=$NS"

# Skip cleanly if direct-Beyla mode is in use (no alloy DaemonSet).
if ! kctl get ds alloy -n "$NS" >/dev/null 2>&1; then
  report_check alloy_mode warn 80 "no alloy DaemonSet — running in direct Beyla mode" $LAYER
  exit 0
fi

# 1. DaemonSet coverage
desired=$(kctl get ds alloy -n "$NS" -o jsonpath='{.status.desiredNumberScheduled}')
ready=$(kctl get ds alloy -n "$NS" -o jsonpath='{.status.numberReady}')
if [[ "$desired" == "$ready" && "$desired" -gt 0 ]]; then
  report_check ds_coverage pass 100 "${ready}/${desired} alloy pods ready" $LAYER
else
  report_check ds_coverage fail 0 "${ready}/${desired} alloy pods ready" $LAYER
fi

# 2. Components — query the Alloy live debug API on one pod
pod=$(kctl get pods -n "$NS" -l app.kubernetes.io/name=alloy -o name | head -1)
if [[ -n "$pod" ]]; then
  comps=$(kctl exec -n "$NS" "$pod" -- wget -qO- http://localhost:12345/api/v0/web/components 2>/dev/null || true)
  if [[ -n "$comps" ]]; then
    # beyla.ebpf must exist and be healthy
    beyla_state=$(echo "$comps" | jq -r '.[] | select(.local_id=="beyla.ebpf/default") | .health.state' 2>/dev/null || echo missing)
    if [[ "$beyla_state" == "healthy" ]]; then
      report_check beyla_component pass 100 "beyla.ebpf/default is healthy" $LAYER
    else
      report_check beyla_component fail 0 "beyla.ebpf/default state=${beyla_state}" $LAYER
    fi

    # pyroscope.ebpf
    pyro_state=$(echo "$comps" | jq -r '.[] | select(.local_id=="pyroscope.ebpf/default") | .health.state' 2>/dev/null || echo missing)
    if [[ "$pyro_state" == "healthy" ]]; then
      report_check pyroscope_component pass 100 "pyroscope.ebpf/default is healthy" $LAYER
    else
      report_check pyroscope_component warn 60 "pyroscope.ebpf/default state=${pyro_state}" $LAYER
    fi

    # All exporters healthy
    bad_exporters=$(echo "$comps" | jq -r '.[] | select(.local_id | test("^otelcol\\.exporter|^prometheus\\.remote_write|^pyroscope\\.write")) | select(.health.state != "healthy") | .local_id' 2>/dev/null | tr '\n' ',' || true)
    if [[ -z "$bad_exporters" ]]; then
      report_check exporters_healthy pass 100 "all exporters healthy" $LAYER
    else
      report_check exporters_healthy fail 20 "unhealthy exporters: $bad_exporters" $LAYER
    fi
  else
    report_check live_debug_api warn 60 "Alloy live debug API unreachable from inside pod" $LAYER
  fi
fi

# 3. Config last loaded successfully (via Prometheus)
ts=$(prom_query 'alloy_config_last_load_success_timestamp_seconds')
if [[ -n "$ts" && "$ts" != "0" ]]; then
  report_check config_loaded pass 100 "config last-load ts=${ts}" $LAYER
else
  report_check config_loaded fail 0 "config_last_load_success_timestamp_seconds == 0 (reload failed)" $LAYER
fi

# 4. Exporters actually sending
send_rate=$(prom_query 'sum(rate(otelcol_exporter_sent_metric_points_total[5m])) + sum(rate(otelcol_exporter_sent_spans_total[5m]))')
if [[ -n "$send_rate" ]] && gt "$send_rate" 0; then
  report_check exporter_throughput pass 100 "exporters shipping ${send_rate} items/sec" $LAYER
else
  report_check exporter_throughput fail 0 "no data leaving Alloy in last 5m" $LAYER
fi

# 5. Exporter failures must be near zero
fail_rate=$(prom_query 'sum(rate(otelcol_exporter_send_failed_metric_points_total[5m])) + sum(rate(otelcol_exporter_send_failed_spans_total[5m]))')
if [[ -n "$fail_rate" ]] && gt "$fail_rate" 1; then
  report_check exporter_failures fail 0 "${fail_rate} send failures/sec" $LAYER
else
  report_check exporter_failures pass 100 "fail rate = ${fail_rate:-0}/sec" $LAYER
fi

log "Layer 00 complete"
