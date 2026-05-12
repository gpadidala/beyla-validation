#!/usr/bin/env bash
# Layer 11 — Security posture.
# Privileged container scope, RBAC, NetworkPolicy enforcement, cross-tenant leakage.

set -Eeuo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib/common.sh"
NS="${1:-beyla-system}"
LAYER=security

log "Layer 11 — security posture"

# 1. Capabilities — only the ones we declared should be granted.
expected="CAP_BPF CAP_NET_RAW CAP_PERFMON CAP_SYS_ADMIN"
got=$(kctl get ds -n "$NS" beyla -o jsonpath='{.spec.template.spec.containers[0].securityContext.capabilities.add}' \
  | tr -d '[]"' | tr ',' '\n' | sort | xargs)
if [[ "$got" == "$expected" ]]; then
  report_check capabilities pass 100 "only expected caps granted: $got" $LAYER
else
  report_check capabilities fail 0 "unexpected caps: $got (expected: $expected)" $LAYER
fi

# 2. NetworkPolicy present
if kctl get networkpolicy -n "$NS" beyla >/dev/null 2>&1; then
  report_check networkpolicy pass 100 "NetworkPolicy present" $LAYER
else
  report_check networkpolicy fail 0 "no NetworkPolicy — Beyla can egress anywhere" $LAYER
fi

# 3. ClusterRole permissions — verb scope check (must not include create/update/delete on anything)
verbs=$(kctl get clusterrole beyla -o jsonpath='{.rules[*].verbs}' | tr -d '[]"' | tr ' ' '\n' | sort -u)
if echo "$verbs" | grep -qE '^(create|update|delete|patch)$'; then
  report_check rbac_write_verbs fail 0 "ClusterRole has write verbs: $(echo $verbs)" $LAYER
else
  report_check rbac_write_verbs pass 100 "read-only verbs only: $(echo $verbs)" $LAYER
fi

# 4. Pod Security Standard
psa=$(kctl get ns "$NS" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}')
if [[ "$psa" != "privileged" ]]; then
  report_check pod_security_standard warn 60 "Pod Security level = ${psa:-none} (Beyla needs 'privileged' due to caps)" $LAYER
else
  report_check pod_security_standard pass 100 "Pod Security = privileged (expected for eBPF)" $LAYER
fi

# 5. Cross-tenant — Beyla should never expose tenant-A's metrics to tenant-B.
# Sanity: check that Pyroscope returns 401/403 without a tenant header.
status=$(curl -s -o /dev/null -w '%{http_code}' "${PYROSCOPE_URL}/api/v1/profiles")
if [[ "$status" == "401" || "$status" == "403" ]]; then
  report_check tenant_isolation pass 100 "Pyroscope rejects unauth requests (HTTP $status)" $LAYER
else
  report_check tenant_isolation warn 60 "Pyroscope HTTP $status without auth — verify tenant header enforcement" $LAYER
fi

log "Layer 11 complete"
