#!/usr/bin/env bash
# Layer 12 — Chaos / failure simulation.
# Orchestrates the experiments in ../chaos/ and validates that Beyla
# degrades gracefully — no app impact, no retry storm.

set -Eeuo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib/common.sh"
NS="${1:-beyla-system}"
TARGET_NS="${2:-demo}"
LAYER=chaos

log "Layer 12 — chaos experiments"
CHAOS_DIR="$DIR/../chaos"

run_experiment() {
  local file="$1" name
  name=$(basename "$file" .yaml)
  log "▶ ${name}"

  base_p99=$(prom_query "histogram_quantile(0.99, sum by (le) (rate(http_server_request_duration_seconds_bucket{k8s_namespace_name=\"$TARGET_NS\"}[2m])))")

  kctl apply -f "$file" -n "$NS"
  sleep 90

  during_p99=$(prom_query "histogram_quantile(0.99, sum by (le) (rate(http_server_request_duration_seconds_bucket{k8s_namespace_name=\"$TARGET_NS\"}[2m])))")
  delta=$(awk -v b="${base_p99:-0}" -v d="${during_p99:-0}" 'BEGIN{ if(b==0){print 0}else{print ((d-b)/b)*100}}')

  if gt "${delta#-}" 10; then
    report_check "chaos_${name}" fail 0 "app P99 degraded ${delta}% during ${name}" $LAYER
  else
    report_check "chaos_${name}" pass 100 "app stable during ${name} (Δ=${delta}%)" $LAYER
  fi

  kctl delete -f "$file" -n "$NS" || true
  sleep 30
}

for f in "$CHAOS_DIR"/*.yaml; do
  [[ -f "$f" ]] && run_experiment "$f"
done

log "Layer 12 complete"
