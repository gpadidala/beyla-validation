#!/usr/bin/env bash
# Orchestrate all 15 validation layers, capturing JSONL output per layer
# into ${REPORTS_DIR}/checks.jsonl for the scorecard.

set -Eeuo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

NS="${1:-beyla-system}"
TARGET_NS="${2:-demo}"
REPORTS_DIR="${3:-./reports/$(date -u +%Y%m%dT%H%M%SZ)}"
export REPORTS_DIR
mkdir -p "$REPORTS_DIR"

. "$DIR/lib/common.sh"

log "running all 15 layers → ${REPORTS_DIR}"

ordered=(
  "01-application-layer.sh   $TARGET_NS"
  "02-kernel-ebpf.sh         $NS"
  "03-telemetry-accuracy.sh  $TARGET_NS"
  "04-kubernetes-cluster.sh  $NS"
  "05-control-plane.sh"
  "06-autoscaling.sh         $TARGET_NS"
  "07-network.sh"
  "08-profiling-pipeline.sh"
  "09-backpressure.sh        $NS"
  "10-multi-tenancy.sh"
  "11-security.sh            $NS"
  "12-chaos.sh               $NS $TARGET_NS"
  "13-rollback.sh"            # SKIPPED by default unless ROLLBACK=1
  "14-time-sync.sh"
  "15-federation.sh"
)

failed=0
for cmd in "${ordered[@]}"; do
  script=$(echo "$cmd" | awk '{print $1}')
  args=$(echo "$cmd"  | cut -d' ' -f2-)

  if [[ "$script" == "13-rollback.sh" && "${ROLLBACK:-0}" != "1" ]]; then
    log "skipping $script (set ROLLBACK=1 to run)"
    continue
  fi

  log "═══ $script ═══"
  if ! bash "$DIR/$script" $args "$REPORTS_DIR"; then
    fail "$script exited non-zero — continuing"
    failed=$((failed+1))
  fi
done

log "done. ${failed} layer(s) had errors."
log "report: ${REPORTS_DIR}/checks.jsonl"
log "next:   python3 scorecard/scorecard.py --reports ${REPORTS_DIR} --thresholds scorecard/thresholds.yaml"
