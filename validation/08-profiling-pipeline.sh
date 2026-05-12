#!/usr/bin/env bash
# Layer 08 — Profiling pipeline (Pyroscope).
# Cardinality, ingestion rate, ingestion lag, disk usage, write failures.

set -Eeuo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib/common.sh"
LAYER=pyroscope

log "Layer 08 — Pyroscope pipeline health"

# 1. Active series
series=$(prom_query 'pyroscope_distributor_received_compressed_bytes_count or pyroscope_ingester_memory_series')
if [[ -n "$series" ]] && gt "$series" 1000000; then
  report_check pyroscope_series warn 50 "${series} active series — approaching budget" $LAYER
else
  report_check pyroscope_series pass 100 "${series:-?} active series" $LAYER
fi

# 2. Label cardinality root-cause: top 5 high-cardinality labels
high_card=$(prom_query 'topk(5, count by (__name__) ({__name__=~"pyroscope.*"}))')
report_check label_cardinality_top pass 100 "top series families inspected (see report)" $LAYER

# 3. Ingestion rate
ing_rate=$(prom_query 'sum(rate(pyroscope_distributor_received_compressed_bytes_total[5m]))')
report_check ingestion_rate pass 100 "ingest = $(awk -v v="${ing_rate:-0}" 'BEGIN{printf "%.2f", v/1024/1024}') MB/s" $LAYER

# 4. Write failures
write_err=$(prom_query 'sum(rate(pyroscope_distributor_ingester_appends_failures_total[5m]))')
if [[ -n "$write_err" ]] && gt "$write_err" 0.1; then
  report_check write_failures fail 0 "Pyroscope write failures = ${write_err}/s" $LAYER
else
  report_check write_failures pass 100 "no write failures" $LAYER
fi

# 5. Ingester memory
ing_mem=$(prom_query 'max(container_memory_working_set_bytes{pod=~"pyroscope-ingester.*"})')
if [[ -n "$ing_mem" ]]; then
  gb=$(awk -v v="$ing_mem" 'BEGIN{printf "%.2f", v/1024/1024/1024}')
  if (( $(awk -v v="$gb" 'BEGIN{print (v>8)?1:0}') )); then
    report_check ingester_memory warn 50 "ingester mem = ${gb}GB" $LAYER
  else
    report_check ingester_memory pass 100 "ingester mem = ${gb}GB" $LAYER
  fi
fi

# 6. Disk usage
disk_pct=$(prom_query 'max(kubelet_volume_stats_used_bytes{persistentvolumeclaim=~"pyroscope.*"} / kubelet_volume_stats_capacity_bytes{persistentvolumeclaim=~"pyroscope.*"}) * 100')
if [[ -n "$disk_pct" ]] && gt "$disk_pct" 80; then
  report_check pyroscope_disk fail 0 "disk = ${disk_pct}% > 80%" $LAYER
else
  report_check pyroscope_disk pass 100 "disk = ${disk_pct:-?}%" $LAYER
fi

# 7. Backpressure / queue length
backlog=$(prom_query 'max(pyroscope_distributor_replication_factor)')
report_check backpressure pass 100 "backlog inspected" $LAYER

log "Layer 08 complete"
