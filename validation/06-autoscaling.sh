#!/usr/bin/env bash
# Layer 06 — Autoscaling impact (HPA / VPA / Cluster Autoscaler).
# Catches false-positive scale events caused by Beyla CPU overhead.

set -Eeuo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib/common.sh"
NS="${1:?namespace required}"
REPORTS_DIR="${2:-${REPORTS_DIR}}"
LAYER=autoscaling

log "Layer 06 — autoscaling impact in $NS"

# 1. HPA scale events in last hour for $NS
scales=$(kctl get events -n "$NS" --field-selector reason=SuccessfulRescale -o json \
  | jq --arg t "$(date -u -d '1 hour ago' +%FT%TZ 2>/dev/null || date -u -v-1H +%FT%TZ)" \
       '[.items[] | select(.lastTimestamp > $t)] | length')
if (( scales > 5 )); then
  report_check hpa_churn warn 40 "${scales} HPA rescale events in last hour — investigate" $LAYER
else
  report_check hpa_churn pass 100 "${scales} HPA rescales" $LAYER
fi

# 2. HPA current CPU utilization vs target
hpa_diff=$(kctl get hpa -n "$NS" -o json \
  | jq '[.items[] | (.status.currentCPUUtilizationPercentage // 0) - (.spec.targetCPUUtilizationPercentage // 80)] | max // 0')
if (( hpa_diff > 20 )); then
  report_check hpa_pressure warn 50 "HPA running ${hpa_diff}% above target — Beyla overhead suspected" $LAYER
else
  report_check hpa_pressure pass 100 "HPA within target" $LAYER
fi

# 3. Cluster autoscaler node additions
ca_adds=$(prom_query 'increase(cluster_autoscaler_scaled_up_nodes_total[1h])')
if [[ -n "$ca_adds" ]] && gt "$ca_adds" 3; then
  report_check cluster_autoscale warn 50 "${ca_adds} nodes added by CA in last hour" $LAYER
else
  report_check cluster_autoscale pass 100 "CA scale-up = ${ca_adds:-0}" $LAYER
fi

log "Layer 06 complete"
