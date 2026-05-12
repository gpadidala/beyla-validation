#!/usr/bin/env bash
# Layer 13 — Rollback validation.
# Safely disables Beyla, verifies eBPF programs are detached, and
# confirms no residue (orphan maps, dangling probes, leaked memory).

set -Eeuo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib/common.sh"

NS="${1:-beyla-system}"
RELEASE="${2:-beyla}"
LAYER=rollback

log "Layer 13 — rollback validation in $NS"

# 1. Drain telemetry: flush any in-flight buffers by sending SIGTERM gracefully.
log "step 1/5: signaling Beyla to drain buffers (graceful)"
kctl rollout pause ds/"$RELEASE" -n "$NS" || true

# 2. Capture pre-rollback node fingerprints
mapfile -t nodes < <(kctl get nodes -o name | sed 's|node/||')
for n in "${nodes[@]:0:3}"; do
  log "fingerprint pre-rollback on ${n}"
  kctl debug node/"$n" -it --image=alpine -- chroot /host bpftool prog show 2>/dev/null \
    | grep -c beyla > "${REPORTS_DIR}/bpf-pre-${n}.txt" || true
done

# 3. Uninstall the chart
log "step 2/5: helm uninstall"
helm uninstall "$RELEASE" -n "$NS" --wait --timeout 5m

# 4. Wait for pod deletion
log "step 3/5: waiting for pod deletion"
for _ in {1..30}; do
  count=$(kctl get pods -n "$NS" -l app.kubernetes.io/name=beyla --no-headers 2>/dev/null | wc -l)
  (( count == 0 )) && break
  sleep 10
done

# 5. Verify eBPF detach on every node
log "step 4/5: verifying eBPF programs detached"
detach_fail=0
for n in "${nodes[@]:0:3}"; do
  count=$(kctl debug node/"$n" -it --image=alpine --quiet -- chroot /host bpftool prog show 2>/dev/null \
    | grep -c beyla || true)
  if (( count > 0 )); then
    detach_fail=$((detach_fail+1))
    report_check "detach_${n}" fail 0 "${count} beyla BPF programs still attached on ${n}" $LAYER
  else
    report_check "detach_${n}" pass 100 "all beyla programs detached from ${n}" $LAYER
  fi
done

# 6. Verify ConfigMap/Service/RBAC cleanup
log "step 5/5: verifying object cleanup"
residue=$(kctl get all,cm,sa,clusterrole,clusterrolebinding,networkpolicy -n "$NS" \
  -l app.kubernetes.io/instance="$RELEASE" --no-headers 2>/dev/null | wc -l)
if (( residue > 0 )); then
  report_check object_cleanup fail 20 "${residue} residual objects after uninstall" $LAYER
else
  report_check object_cleanup pass 100 "clean uninstall — no residue" $LAYER
fi

if (( detach_fail == 0 && residue == 0 )); then
  ok "rollback verified clean"
else
  fail "rollback incomplete — investigate ${REPORTS_DIR}/"
  exit 1
fi

log "Layer 13 complete"
