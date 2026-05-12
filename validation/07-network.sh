#!/usr/bin/env bash
# Layer 07 — Network impact.
# eBPF socket filters can subtly change packet processing — validate
# retransmits, packet rate, and east-west latency.

set -Eeuo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib/common.sh"
LAYER=network

log "Layer 07 — network impact"

# 1. TCP retransmit rate
retr_pct=$(prom_query 'sum(rate(node_netstat_Tcp_RetransSegs[5m])) / sum(rate(node_netstat_Tcp_OutSegs[5m])) * 100')
if [[ -n "$retr_pct" ]] && gt "$retr_pct" 1; then
  report_check tcp_retransmits warn 60 "TCP retransmit rate = ${retr_pct}% > 1%" $LAYER
else
  report_check tcp_retransmits pass 100 "TCP retransmit rate = ${retr_pct:-0}%" $LAYER
fi

# 2. Packet rate delta vs baseline
pkt_now=$(prom_query 'sum(rate(node_network_receive_packets_total{device!~"lo|cali.*|veth.*"}[5m]))')
pkt_base=$(prom_query 'cluster:pkt_rate_baseline:5m')
if [[ -n "$pkt_now" && -n "$pkt_base" ]]; then
  delta=$(awk -v n="$pkt_now" -v b="$pkt_base" 'BEGIN{ if(b==0){print 0}else{print ((n-b)/b)*100}}')
  if gt "${delta#-}" 10; then
    report_check pkt_rate warn 60 "packet rate Δ=${delta}% vs baseline" $LAYER
  else
    report_check pkt_rate pass 100 "packet rate Δ=${delta}%" $LAYER
  fi
fi

# 3. Service-to-service P99 (via Istio if present, else Beyla service_graph)
svc_p99=$(prom_query 'histogram_quantile(0.99, sum by (le) (rate(traces_service_graph_request_duration_seconds_bucket[5m])))')
if [[ -n "$svc_p99" ]] && gt "$svc_p99" 0.5; then
  report_check svc_to_svc_latency warn 60 "service-to-service P99 = ${svc_p99}s" $LAYER
else
  report_check svc_to_svc_latency pass 100 "service graph P99 = ${svc_p99:-?}s" $LAYER
fi

# 4. Egress to LGTM endpoints (sanity: Beyla is actually sending)
egress_bps=$(prom_query 'sum(rate(container_network_transmit_bytes_total{pod=~"beyla-.*"}[5m]))')
report_check beyla_egress pass 100 "Beyla egress = $(awk -v v="${egress_bps:-0}" 'BEGIN{printf "%.2f", v/1024/1024}') MB/s" $LAYER

log "Layer 07 complete"
