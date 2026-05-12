#!/usr/bin/env bash
# Layer 05 — Control plane impact.
# API server P99, etcd, controller manager — Beyla's k8s metadata watch
# can flood the API server if mis-configured.

set -Eeuo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib/common.sh"
LAYER=control-plane

log "Layer 05 — control plane impact"

# 1. API server P99 request latency (excluding watches which are long-lived)
api_p99=$(prom_query 'histogram_quantile(0.99, sum by (le) (rate(apiserver_request_duration_seconds_bucket{verb!~"WATCH|CONNECT"}[5m])))')
if [[ -n "$api_p99" ]] && gt "$api_p99" 1; then
  report_check apiserver_p99 fail 0 "API server P99 = ${api_p99}s > 1s" $LAYER
else
  report_check apiserver_p99 pass 100 "API server P99 = ${api_p99:-?}s" $LAYER
fi

# 2. etcd commit P99
etcd_p99=$(prom_query 'histogram_quantile(0.99, rate(etcd_disk_backend_commit_duration_seconds_bucket[5m]))')
if [[ -n "$etcd_p99" ]] && gt "$etcd_p99" 0.25; then
  report_check etcd_p99 fail 0 "etcd commit P99 = ${etcd_p99}s > 250ms" $LAYER
else
  report_check etcd_p99 pass 100 "etcd commit P99 = ${etcd_p99:-?}s" $LAYER
fi

# 3. Beyla's API server impact — list/watch from beyla SA only
beyla_qps=$(prom_query 'sum(rate(apiserver_request_total{user_username=~".*beyla.*|system:serviceaccount:beyla-system:beyla"}[5m]))')
if [[ -n "$beyla_qps" ]] && gt "$beyla_qps" 50; then
  report_check beyla_api_qps fail 0 "Beyla SA generating ${beyla_qps} QPS to API server" $LAYER
else
  report_check beyla_api_qps pass 100 "Beyla SA QPS = ${beyla_qps:-0}" $LAYER
fi

# 4. controller-manager work queue depth
cm_depth=$(prom_query 'max(workqueue_depth)')
if [[ -n "$cm_depth" ]] && gt "$cm_depth" 1000; then
  report_check controller_queue warn 60 "max workqueue depth = ${cm_depth}" $LAYER
else
  report_check controller_queue pass 100 "workqueue depth = ${cm_depth:-?}" $LAYER
fi

log "Layer 05 complete"
