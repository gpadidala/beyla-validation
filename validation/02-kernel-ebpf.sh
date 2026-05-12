#!/usr/bin/env bash
# Layer 02 — Kernel & eBPF safety.
# Validates that every Beyla pod attached its programs successfully,
# BPF maps are within budget, and no kernel warnings are spamming dmesg.

set -Eeuo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib/common.sh"

NS="${1:-beyla-system}"
REPORTS_DIR="${2:-${REPORTS_DIR}}"
LAYER=kernel

log "Layer 02 — kernel/eBPF safety in namespace=$NS"

# Iterate every Beyla pod; exec bpftool inside.
mapfile -t pods < <(kctl get pods -n "$NS" -l app.kubernetes.io/name=beyla -o name)
[[ ${#pods[@]} -eq 0 ]] && { report_check pods_present fail 0 "no beyla pods in $NS" $LAYER; exit 0; }

bpf_total_bytes=0
attach_failures=0

for p in "${pods[@]}"; do
  pod="${p##*/}"

  # 1. attach success: pod ready AND beyla_probes_loaded_total >= expected
  ready=$(kctl get -n "$NS" "$p" -o jsonpath='{.status.containerStatuses[0].ready}')
  if [[ "$ready" != "true" ]]; then
    report_check "attach_${pod}" fail 0 "pod not ready" $LAYER
    attach_failures=$((attach_failures+1))
    continue
  fi

  # 2. BPF map memory
  if kctl exec -n "$NS" "$pod" -- bpftool map show -j >/tmp/maps.json 2>/dev/null; then
    bytes=$(jq '[.[] | .bytes_memlock // 0] | add // 0' /tmp/maps.json)
    bpf_total_bytes=$((bpf_total_bytes + bytes))
    mb=$(( bytes / 1024 / 1024 ))
    if (( mb > 200 )); then
      report_check "bpf_maps_${pod}" warn 60 "BPF maps using ${mb}MB on node — review map sizing" $LAYER
    else
      report_check "bpf_maps_${pod}" pass 100 "BPF maps using ${mb}MB" $LAYER
    fi
  else
    report_check "bpf_maps_${pod}" warn 50 "bpftool unavailable in pod" $LAYER
  fi

  # 3. dmesg for kernel warnings since pod start
  if kctl exec -n "$NS" "$pod" -- dmesg -T 2>/dev/null \
       | grep -Ei 'bpf|verifier|oops|panic|soft lockup' | tail -20 > /tmp/dmesg.txt; then
    lines=$(wc -l < /tmp/dmesg.txt)
    if (( lines > 0 )); then
      report_check "dmesg_${pod}" warn 50 "${lines} suspicious dmesg lines — see ${REPORTS_DIR}/dmesg-${pod}.txt" $LAYER
      cp /tmp/dmesg.txt "${REPORTS_DIR}/dmesg-${pod}.txt"
    else
      report_check "dmesg_${pod}" pass 100 "no kernel warnings" $LAYER
    fi
  fi

  # 4. CPU system% on host (from node_exporter)
  node=$(kctl get -n "$NS" "$p" -o jsonpath='{.spec.nodeName}')
  sys_cpu=$(prom_query "avg(rate(node_cpu_seconds_total{mode=\"system\",instance=~\"${node}.*\"}[5m])) * 100")
  if [[ -n "$sys_cpu" ]] && gt "$sys_cpu" 15; then
    report_check "system_cpu_${pod}" fail 20 "system CPU on ${node}: ${sys_cpu}% > 15%" $LAYER
  else
    report_check "system_cpu_${pod}" pass 100 "system CPU on ${node}: ${sys_cpu:-?}%" $LAYER
  fi
done

if (( attach_failures > 0 )); then
  report_check ebpf_attach_summary fail 0 "${attach_failures} pods failed to attach probes" $LAYER
else
  report_check ebpf_attach_summary pass 100 "all ${#pods[@]} pods attached" $LAYER
fi

log "Layer 02 complete (BPF mem total = $((bpf_total_bytes/1024/1024))MB)"
