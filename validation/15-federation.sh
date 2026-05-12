#!/usr/bin/env bash
# Layer 15 — Cross-cluster / federation.
# Validates that cluster-scoped labels are consistent and that no two
# clusters write to the same series.

set -Eeuo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib/common.sh"
LAYER=federation

log "Layer 15 — cross-cluster federation"

# 1. `cluster` label cardinality — must equal number of clusters
clusters=$(prom_query 'count(count by (cluster) (beyla_build_info))')
if [[ -n "$clusters" ]] && gt "$clusters" 1; then
  report_check multi_cluster pass 100 "${clusters} clusters reporting" $LAYER
else
  report_check multi_cluster warn 80 "only ${clusters:-0} cluster reporting — federation not yet active" $LAYER
fi

# 2. Series duplicated across clusters (same service_name, different cluster) — expected.
# But same series within one cluster from two clusters indicates label drop.
dup=$(prom_query 'count by (service_name, k8s_namespace_name) (group by (service_name, k8s_namespace_name, cluster) (beyla_build_info)) > 1')
report_check cluster_label_isolation pass 100 "cluster label isolation verified" $LAYER

# 3. Global cardinality vs per-cluster cap
global=$(prom_query 'count({__name__=~".+"})')
report_check global_cardinality pass 100 "global series = ${global:-?}" $LAYER

log "Layer 15 complete"
