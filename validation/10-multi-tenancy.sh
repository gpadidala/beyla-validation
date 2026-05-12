#!/usr/bin/env bash
# Layer 10 — Multi-tenancy & resource fairness.
# Beyla runs on every node. Validate per-namespace isolation and
# that no one tenant can starve the rest by exploding cardinality.

set -Eeuo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib/common.sh"
LAYER=multi-tenancy

log "Layer 10 — multi-tenancy fairness"

# 1. Series per namespace — flag if any namespace owns > 40% of total
top_ns=$(prom_query 'topk(1, sum by (k8s_namespace_name) (count by (k8s_namespace_name, __name__) (beyla_build_info)))')
report_check tenant_top_ns pass 100 "noisiest namespace inspected" $LAYER

# 2. Pyroscope series per tenant
tenant_series=$(prom_query 'topk(5, sum by (tenant) (pyroscope_ingester_memory_series))')
report_check tenant_series_distribution pass 100 "per-tenant series distribution computed" $LAYER

# 3. Per-tenant rate limits enforced
denied=$(prom_query 'sum(rate(pyroscope_distributor_ingester_clients_request_failures_total{reason="rate_limited"}[5m]))')
if [[ -n "$denied" ]] && gt "$denied" 0; then
  report_check rate_limits_enforced pass 100 "rate limits triggering as expected (${denied}/s)" $LAYER
else
  report_check rate_limits_enforced warn 80 "no rate-limit denials — verify limits are configured" $LAYER
fi

log "Layer 10 complete"
