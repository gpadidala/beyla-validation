#!/usr/bin/env bash
# Shared helpers for validation scripts.
# Every script sources this file and uses report_pass/report_fail/report_warn
# to write a structured JSON line. scorecard.py reads those lines.

set -Eeuo pipefail

# ----- Environment -------------------------------------------------------
: "${PROM_URL:=http://prometheus.monitoring.svc.cluster.local:9090}"
: "${TEMPO_URL:=http://tempo.monitoring.svc.cluster.local:3200}"
: "${PYROSCOPE_URL:=http://pyroscope.monitoring.svc.cluster.local:4040}"
: "${KUBECTL:=kubectl}"
: "${REPORTS_DIR:=./reports}"
: "${LOOKBACK:=10m}"
: "${LATENCY_REGRESSION_PCT:=5}"     # % degradation tolerated
: "${ERROR_RATE_REGRESSION_PCT:=10}"

# ----- Logging -----------------------------------------------------------
log()   { printf '[%s] %s\n' "$(date -u +%H:%M:%SZ)" "$*"; }
ok()    { printf '\033[32m✓\033[0m %s\n' "$*"; }
warn()  { printf '\033[33m!\033[0m %s\n' "$*"; }
fail()  { printf '\033[31m✗\033[0m %s\n' "$*" >&2; }

# ----- Report writer -----------------------------------------------------
# Usage: report_check <name> <pass|fail|warn> <score 0-100> <message> [layer]
report_check() {
  local name="$1" status="$2" score="$3" msg="$4" layer="${5:-unknown}"
  local out="${REPORTS_DIR}/checks.jsonl"
  mkdir -p "$(dirname "$out")"
  printf '{"ts":"%s","layer":"%s","check":"%s","status":"%s","score":%s,"message":%s}\n' \
    "$(date -u +%FT%TZ)" "$layer" "$name" "$status" "$score" "$(printf '%s' "$msg" | jq -Rs .)" \
    >> "$out"
  case "$status" in
    pass) ok   "$layer/$name — $msg" ;;
    warn) warn "$layer/$name — $msg" ;;
    fail) fail "$layer/$name — $msg" ;;
  esac
}

# ----- PromQL helper -----------------------------------------------------
# Usage: prom_query 'sum(rate(...))' → prints scalar value, or empty on error.
prom_query() {
  local q="$1"
  curl -sfG --data-urlencode "query=${q}" "${PROM_URL}/api/v1/query" \
    | jq -r '.data.result[0].value[1] // empty'
}

# Usage: prom_query_avg_over '<expr>' '10m'
prom_avg_over() {
  local q="$1" range="$2"
  prom_query "avg_over_time((${q})[${range}:])"
}

# ----- K8s helpers -------------------------------------------------------
kctl()  { $KUBECTL "$@"; }
beyla_pods() { kctl get pods -l app.kubernetes.io/name=beyla --all-namespaces -o name; }

# ----- Numeric comparisons ----------------------------------------------
# Returns 0 if $1 <= $2 (using bc for float).
le() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a<=b)}'; }
ge() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a>=b)}'; }
gt() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a>b)}';  }

# ----- Trap --------------------------------------------------------------
trap 'fail "unexpected error at line $LINENO in $0"' ERR
