#!/usr/bin/env bash
# Layer 09 — Backpressure & graceful degradation.
# Beyla doesn't expose explicit drop/retry counters — backpressure shows
# up as elevated eBPF flush latency (beyla_ebpf_tracer_flushes histogram)
# and rising export error rate (beyla_otel_*_export_errors_total).

set -Eeuo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib/common.sh"
NS="${1:-alloy}"
LAYER=backpressure

log "Layer 09 — backpressure & degradation"

# 1. eBPF flush latency P99 — high values mean ringbuf is overflowing
flush_p99=$(prom_query 'histogram_quantile(0.99, sum by (le) (rate(beyla_ebpf_tracer_flushes_bucket[5m])))')
if [[ -n "$flush_p99" ]] && gt "$flush_p99" 1; then
  report_check ebpf_flush_latency fail 30 "ringbuf flush P99 = ${flush_p99}s > 1s (events may be lost)" $LAYER
else
  report_check ebpf_flush_latency pass 100 "ringbuf flush P99 = ${flush_p99:-?}s" $LAYER
fi

# 2. Export error rate — climbing under backpressure
err_ratio=$(prom_query 'sum(rate(beyla_otel_trace_export_errors_total[5m])) / clamp_min(sum(rate(beyla_otel_trace_exports_total[5m])), 1)')
if [[ -n "$err_ratio" ]] && gt "$err_ratio" 0.05; then
  report_check export_error_ratio fail 0 "trace export error ratio = $err_ratio > 5%" $LAYER
else
  report_check export_error_ratio pass 100 "export error ratio = ${err_ratio:-0}" $LAYER
fi

# 3. Beyla CPU throttle % — Beyla can't keep up if cgroup-throttled
throttle=$(prom_query 'sum(rate(container_cpu_cfs_throttled_periods_total{pod=~"beyla-.*|alloy-.*"}[5m])) / sum(rate(container_cpu_cfs_periods_total{pod=~"beyla-.*|alloy-.*"}[5m])) * 100')
if [[ -n "$throttle" ]] && gt "$throttle" 5; then
  report_check beyla_cpu_throttle warn 50 "Beyla/Alloy CPU throttle = ${throttle}%" $LAYER
else
  report_check beyla_cpu_throttle pass 100 "CPU throttle = ${throttle:-0}%" $LAYER
fi

# 4. Memory headroom
mem_pct=$(prom_query 'max(container_memory_working_set_bytes{pod=~"beyla-.*|alloy-.*"} / container_spec_memory_limit_bytes{pod=~"beyla-.*|alloy-.*"}) * 100')
if [[ -n "$mem_pct" ]] && gt "$mem_pct" 80; then
  report_check memory_headroom warn 40 "Beyla/Alloy memory at ${mem_pct}% of limit" $LAYER
else
  report_check memory_headroom pass 100 "memory = ${mem_pct:-?}% of limit" $LAYER
fi

log "Layer 09 complete"
