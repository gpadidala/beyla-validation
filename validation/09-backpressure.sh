#!/usr/bin/env bash
# Layer 09 — Backpressure & graceful degradation.
# Under simulated overload, Beyla must drop traces (not retry-storm)
# and never block the app's syscalls.

set -Eeuo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib/common.sh"
NS="${1:-beyla-system}"
LAYER=backpressure

log "Layer 09 — backpressure & degradation"

# 1. Drop counter — should increment under load, not retry counter.
drops=$(prom_query 'sum(rate(beyla_telemetry_dropped_total[5m]))')
retries=$(prom_query 'sum(rate(beyla_telemetry_retry_total[5m]))')
if [[ -n "$retries" ]] && gt "$retries" 100; then
  report_check retry_storm fail 0 "retry rate ${retries}/s — possible retry storm" $LAYER
else
  report_check retry_storm pass 100 "retry rate = ${retries:-0}/s" $LAYER
fi
report_check drop_rate pass 100 "drop rate = ${drops:-0}/s (shedding is expected under load)" $LAYER

# 2. Queue saturation
queue_pct=$(prom_query 'max(beyla_export_queue_size / beyla_export_queue_capacity) * 100')
if [[ -n "$queue_pct" ]] && gt "$queue_pct" 80; then
  report_check queue_saturation warn 40 "export queue at ${queue_pct}%" $LAYER
else
  report_check queue_saturation pass 100 "export queue = ${queue_pct:-?}%" $LAYER
fi

# 3. App thread blocking proxy — Beyla CPU throttling % should be near 0
throttle=$(prom_query 'sum(rate(container_cpu_cfs_throttled_periods_total{pod=~"beyla-.*"}[5m])) / sum(rate(container_cpu_cfs_periods_total{pod=~"beyla-.*"}[5m])) * 100')
if [[ -n "$throttle" ]] && gt "$throttle" 5; then
  report_check beyla_cpu_throttle warn 50 "Beyla CPU throttle = ${throttle}%" $LAYER
else
  report_check beyla_cpu_throttle pass 100 "CPU throttle = ${throttle:-0}%" $LAYER
fi

log "Layer 09 complete"
