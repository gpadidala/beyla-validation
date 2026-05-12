#!/usr/bin/env bash
# Layer 04 — Kubernetes cluster impact.
# Node pressure, pod restarts, OOMKills, DaemonSet footprint.

set -Eeuo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib/common.sh"

NS="${1:-beyla-system}"
REPORTS_DIR="${2:-${REPORTS_DIR}}"
LAYER=k8s

log "Layer 04 — cluster impact in namespace=$NS"

# 1. Beyla pod restarts in last hour
restarts=$(kctl get pods -n "$NS" -l app.kubernetes.io/name=beyla -o json \
  | jq '[.items[].status.containerStatuses[]?.restartCount // 0] | add // 0')
if (( restarts > 0 )); then
  report_check beyla_restarts warn 50 "${restarts} container restarts across DaemonSet" $LAYER
else
  report_check beyla_restarts pass 100 "no restarts" $LAYER
fi

# 2. OOMKills
ookills=$(kctl get events -A --field-selector reason=OOMKilling -o json \
  | jq '.items | length')
if (( ookills > 0 )); then
  report_check oomkills fail 0 "${ookills} OOMKill events in cluster" $LAYER
else
  report_check oomkills pass 100 "no OOMKills" $LAYER
fi

# 3. Node pressure: MemoryPressure, DiskPressure, PIDPressure
press=$(kctl get nodes -o json | jq '[.items[].status.conditions[] | select(.type | test("Pressure")) | select(.status=="True")] | length')
if (( press > 0 )); then
  report_check node_pressure fail 0 "${press} node pressure conditions" $LAYER
else
  report_check node_pressure pass 100 "all nodes clear" $LAYER
fi

# 4. DaemonSet desired vs ready
desired=$(kctl get ds -n "$NS" beyla -o jsonpath='{.status.desiredNumberScheduled}')
ready=$(kctl get ds -n "$NS" beyla -o jsonpath='{.status.numberReady}')
if [[ "$desired" != "$ready" ]]; then
  report_check daemonset_coverage fail 20 "${ready}/${desired} pods ready" $LAYER
else
  report_check daemonset_coverage pass 100 "all ${desired} pods ready" $LAYER
fi

# 5. Scheduling latency (proxy via kube-scheduler metric)
sched_p99=$(prom_query 'histogram_quantile(0.99, sum by (le) (rate(scheduler_scheduling_attempt_duration_seconds_bucket[5m])))')
if [[ -n "$sched_p99" ]] && gt "$sched_p99" 1; then
  report_check scheduling_latency warn 60 "scheduler P99 = ${sched_p99}s" $LAYER
else
  report_check scheduling_latency pass 100 "scheduler P99 = ${sched_p99:-?}s" $LAYER
fi

log "Layer 04 complete"
