#!/usr/bin/env bash
# Kernel/eBPF/BTF preflight probe. Runs against the current cluster.
# Exits non-zero if any node fails to meet requirements.

set -Eeuo pipefail
: "${KUBECTL:=kubectl}"

red()    { printf '\033[31m✗\033[0m %s\n' "$*"; }
green()  { printf '\033[32m✓\033[0m %s\n' "$*"; }
yellow() { printf '\033[33m!\033[0m %s\n' "$*"; }

min_kernel="5.8"
min_k8s="1.27"
fails=0

# 1. K8s version
k8s=$($KUBECTL version -o json | python3 -c 'import sys,json;d=json.load(sys.stdin)["serverVersion"];print(f"{d[\"major\"]}.{d[\"minor\"].rstrip(\"+\")}")')
if [[ "$(printf '%s\n%s\n' "$min_k8s" "$k8s" | sort -V | head -1)" == "$min_k8s" ]]; then
  green "K8s version $k8s ≥ $min_k8s"
else
  red "K8s version $k8s < $min_k8s"
  fails=$((fails+1))
fi

# 2. Kernel & BTF on every node — launch a tiny privileged pod with debug
for node in $($KUBECTL get nodes -o name | sed 's|node/||'); do
  out=$($KUBECTL debug node/"$node" -it --image=alpine --quiet -- chroot /host /bin/sh -c '
    KERNEL=$(uname -r)
    BTF=$([ -f /sys/kernel/btf/vmlinux ] && echo yes || echo no)
    CGROUP=$([ -f /sys/fs/cgroup/cgroup.controllers ] && echo v2 || echo v1)
    RUNTIME=$(crictl version 2>/dev/null | awk -F: "/RuntimeName/ {gsub(/ /,\"\",\$2);print \$2}")
    RUNTIME_VER=$(crictl version 2>/dev/null | awk -F: "/RuntimeVersion/ {gsub(/ /,\"\",\$2);print \$2}")
    echo "$KERNEL|$BTF|$CGROUP|$RUNTIME|$RUNTIME_VER"
  ' 2>/dev/null | tail -1)

  IFS='|' read -r kernel btf cgroup runtime runtime_ver <<<"$out"
  kernel_short=$(echo "$kernel" | cut -d. -f1-2)

  if [[ "$(printf '%s\n%s\n' "$min_kernel" "$kernel_short" | sort -V | head -1)" == "$min_kernel" ]]; then
    green "$node — kernel $kernel ≥ $min_kernel"
  else
    red "$node — kernel $kernel < $min_kernel"
    fails=$((fails+1))
  fi

  if [[ "$btf" == "yes" ]]; then
    green "$node — BTF present"
  else
    yellow "$node — BTF MISSING (install linux-headers or ship BTFHub initContainer)"
    fails=$((fails+1))
  fi

  if [[ "$cgroup" == "v2" ]]; then
    green "$node — cgroup v2"
  else
    yellow "$node — cgroup v1 (per-pod profiles degraded)"
  fi

  green "$node — runtime $runtime $runtime_ver"
done

if (( fails > 0 )); then
  red "$fails compatibility issue(s). DO NOT install Beyla until resolved."
  exit 1
fi
green "all nodes pass — Beyla install eligible"
