#!/usr/bin/env bash
# Cluster preflight: K8s version, Helm, kubectl context, LGTM endpoints.
# Use compatibility/kernel-probe-test.sh for kernel/BTF/runtime.

set -Eeuo pipefail
fail() { printf '\033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }
ok()   { printf '\033[32m✓\033[0m %s\n' "$*"; }

command -v kubectl >/dev/null || fail "kubectl not in PATH"
command -v helm    >/dev/null || fail "helm not in PATH"
command -v jq      >/dev/null || fail "jq not in PATH"

ctx=$(kubectl config current-context)
ok "kubectl context: $ctx"

# Confirm operator intent — refuse to run in unknown contexts.
case "$ctx" in
  *prod*|*aks-prod*) printf '\033[33m!\033[0m PROD CONTEXT — type PROD to continue: '; read -r ans
                     [[ "$ans" == "PROD" ]] || fail "aborted" ;;
esac

kubectl version --output=json | jq -e '.serverVersion.major' >/dev/null || fail "API server unreachable"
ok "API server reachable"

# LGTM endpoints reachable from operator workstation (not strictly required
# but a useful smoke test).
for svc in prometheus tempo loki pyroscope; do
  if kubectl get svc -n monitoring "$svc" >/dev/null 2>&1; then
    ok "monitoring/${svc} service present"
  else
    fail "monitoring/${svc} not found — install LGTM stack first"
  fi
done

ok "preflight passed"
