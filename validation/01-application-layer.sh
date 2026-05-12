#!/usr/bin/env bash
# Layer 01 — Application impact.
# Validates that Beyla's overhead does not regress P50/P95/P99 latency,
# throughput, or error rates by more than the configured threshold.
#
# Usage: 01-application-layer.sh <target_namespace> [reports_dir]

set -Eeuo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib/common.sh"

NS="${1:?target namespace required}"
REPORTS_DIR="${2:-${REPORTS_DIR}}"
LAYER=application

log "Layer 01 — application impact in namespace=$NS, lookback=$LOOKBACK"

# Pre-rollout baseline is stored as recording rules: app:latency_p99_baseline:5m
# Post-rollout values come from the live histogram exported by Beyla.

services=$(prom_query "group by (service_name) (rate(http_server_request_duration_seconds_count{k8s_namespace_name=\"$NS\"}[5m]))" \
  | jq -r '.[] | .metric.service_name' 2>/dev/null || true)
services_list=$(kctl get svc -n "$NS" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')

for svc in $services_list; do
  for q in 0.5 0.95 0.99; do
    cur=$(prom_query "histogram_quantile(${q}, sum by (le) (rate(http_server_request_duration_seconds_bucket{service_name=\"${svc}\",k8s_namespace_name=\"${NS}\"}[5m])))")
    base=$(prom_query "app:latency_p${q/0./}_baseline:5m{service_name=\"${svc}\"}")
    if [[ -z "$cur" || -z "$base" ]]; then
      report_check "latency_p${q/0./}_${svc}" warn 70 "missing data (cur=$cur, base=$base)" $LAYER
      continue
    fi
    delta_pct=$(awk -v c="$cur" -v b="$base" 'BEGIN{ if(b==0){print 0}else{print ((c-b)/b)*100}}')
    if gt "$delta_pct" "$LATENCY_REGRESSION_PCT"; then
      report_check "latency_p${q/0./}_${svc}" fail 0 "P${q/0./} regressed ${delta_pct}% (cur=${cur}s, base=${base}s)" $LAYER
    else
      report_check "latency_p${q/0./}_${svc}" pass 100 "Δ=${delta_pct}% within budget" $LAYER
    fi
  done

  # Throughput
  cur_rps=$(prom_query "sum(rate(http_server_request_duration_seconds_count{service_name=\"${svc}\",k8s_namespace_name=\"${NS}\"}[5m]))")
  base_rps=$(prom_query "app:rps_baseline:5m{service_name=\"${svc}\"}")
  if [[ -n "$cur_rps" && -n "$base_rps" ]]; then
    drop_pct=$(awk -v c="$cur_rps" -v b="$base_rps" 'BEGIN{ if(b==0){print 0}else{print ((b-c)/b)*100}}')
    if gt "$drop_pct" 5; then
      report_check "throughput_${svc}" fail 0 "throughput dropped ${drop_pct}% (cur=${cur_rps}, base=${base_rps})" $LAYER
    else
      report_check "throughput_${svc}" pass 100 "throughput stable Δ=${drop_pct}%" $LAYER
    fi
  fi

  # Error rate
  err_pct=$(prom_query "sum(rate(http_server_request_duration_seconds_count{service_name=\"${svc}\",http_response_status_code=~\"5..\"}[5m])) / sum(rate(http_server_request_duration_seconds_count{service_name=\"${svc}\"}[5m])) * 100")
  if [[ -n "$err_pct" ]] && gt "$err_pct" "$ERROR_RATE_REGRESSION_PCT"; then
    report_check "error_rate_${svc}" fail 0 "5xx rate ${err_pct}% > ${ERROR_RATE_REGRESSION_PCT}%" $LAYER
  else
    report_check "error_rate_${svc}" pass 100 "5xx rate=${err_pct:-0}%" $LAYER
  fi
done

log "Layer 01 complete"
