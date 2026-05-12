# Compatibility matrix

Beyla's eBPF programs depend on specific kernel features (CO-RE, BTF, fentry, ringbuf). This matrix is the source of truth for what we support; `kernel-probe-test.sh` enforces it in CI and preflight.

## Kernel

| Kernel | Status | Notes |
|-------|--------|-------|
| < 5.8  | ❌ Unsupported | Missing CAP_BPF split, ringbuf, fentry |
| 5.8 – 5.10 | ⚠️ Best-effort | OK for HTTP/1; profiling unstable |
| 5.11 – 5.14 | ✅ Supported | Full feature set; some BTF gaps on older distros |
| 5.15+ (LTS) | ✅ Preferred | Default on Ubuntu 22.04 AKS pools |
| 6.x | ✅ Supported | RHEL 9.4+, Ubuntu 24.04 |

## BTF (BPF Type Format)

Beyla requires kernel BTF (`/sys/kernel/btf/vmlinux`). Distros without it need `BTFHub` shipped via initContainer. The matrix:

| Distro | BTF in-kernel | Action |
|-------|---------------|--------|
| Ubuntu 22.04+ | ✅ | none |
| Ubuntu 20.04 | ⚠️ optional | install `linux-headers-*` |
| Amazon Linux 2 | ❌ | ship BTFHub blob via initContainer |
| Bottlerocket | ✅ | none |
| AKS Ubuntu | ✅ | none |
| AKS Mariner | ✅ (2.0+) | none |

## Kubernetes

| K8s | Status |
|----|--------|
| < 1.25 | ❌ Unsupported (PSP retired here) |
| 1.25 – 1.27 | ⚠️ Use Pod Security Standards `privileged` |
| 1.28+ | ✅ Supported |
| 1.30+ | ✅ Preferred (test target) |

## Container runtime

| Runtime | Status | Notes |
|--------|--------|-------|
| containerd 1.7+ | ✅ | required for cgroup-v2 + eBPF perf events |
| containerd 1.6 | ⚠️ | works; missing per-pod perf event cgroup |
| CRI-O | ✅ | tested 1.27+ |
| docker (legacy) | ❌ | not supported |

## Cgroups

| Version | Status |
|--------|--------|
| cgroup v1 | ⚠️ degraded — no per-pod CPU profiles |
| cgroup v2 (unified) | ✅ required for full feature set |

## CSP-specific

| CSP | Tested? | Notes |
|----|---------|-------|
| AKS (Azure) | ✅ — primary | Ubuntu 22.04, kernel 5.15 |
| GKE (Google) | ✅ | Container-Optimized OS, kernel 6.1 |
| EKS (AWS) | ⚠️ partial | Bottlerocket OK; AL2 needs BTFHub |
| On-prem RKE2 | ✅ | tested with RHEL 9.4 + kernel 5.14 |
