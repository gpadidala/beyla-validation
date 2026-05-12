# Threat model

Beyla is privileged. This document enumerates what it can see, what it can do, and how this framework constrains both.

## Capabilities granted

| Capability | Why | Risk |
|-----------|-----|------|
| `CAP_BPF` | load eBPF programs | can read kernel memory via probes |
| `CAP_SYS_ADMIN` | required for some BPF op modes | broad — partially superseded by CAP_BPF on 5.8+ |
| `CAP_PERFMON` | perf events for CPU profiling | can read PMCs |
| `CAP_NET_RAW` | raw socket access | can sniff packets the kernel sees |

We do NOT grant `privileged: true` — only the four caps above. This blocks a wide range of container escapes that full-privileged would enable.

## What Beyla sees

- **All in-clear traffic** to/from instrumented pods (HTTP, gRPC w/o TLS, SQL plaintext).
- **TLS-encrypted traffic at SSL entry/exit** — via uprobes on `SSL_read`/`SSL_write` and Go's `crypto/tls`. So Beyla CAN see decrypted HTTPS bodies.
- **Process command lines** of every pod on its node (via `/proc`).
- **Kernel structures** that BPF helpers expose (task struct, sockets, file descriptors).

## What Beyla CANNOT see (by design in this repo)

- App memory outside the probed call sites
- Secrets at rest (no /var, /etc, /run access mounted)
- Other clusters (NetworkPolicy locks egress to in-cluster LGTM only)
- Anything in namespaces in `discovery.excludeNamespaces`

## Risks & mitigations

### R1 — Compromised Beyla image runs malicious BPF
**Mitigation:**
- Image is digest-pinned in `values-prod.yaml`
- Image built from upstream + our entrypoint only — no third-party code
- Supply chain: Dockerfile pulls a specific upstream tag, then re-bases on distroless
- ImagePullPolicy `IfNotPresent` + admission controller can enforce digest pinning

### R2 — Beyla scrapes secrets from app HTTP bodies
**Mitigation:**
- `attributes.select.http_server_request_duration_seconds.exclude` drops sensitive labels
- Optional OTel Collector with `attributes/scrub` processor for body redaction
- Beyla doesn't capture request/response bodies by default — only headers and routes
- App owners can add `beyla.grafana.com/instrument: "false"` to opt out

### R3 — Cross-tenant data leakage via Pyroscope
**Mitigation:**
- Pyroscope `auth_enabled: true` in prod (X-Scope-OrgID header required)
- NetworkPolicy restricts Beyla egress to the LGTM stack only
- Multi-tenancy validation in `validation/10-multi-tenancy.sh`

### R4 — Beyla CPU/memory exhausts the node
**Mitigation:**
- Resource limits enforced in DaemonSet
- Backpressure: drops sampling at 70% CPU watermark before reaching limit
- High `PriorityClass` ensures Beyla survives, doesn't get killed silently

### R5 — eBPF verifier rejects probe → silent loss of coverage
**Mitigation:**
- `beyla_ebpf_program_load_failures_total` alert fires within 2 min
- Pod readiness probe fails → DaemonSet marked degraded → operator paged

### R6 — Beyla SA misused to enumerate cluster
**Mitigation:**
- ClusterRole is **read-only** (no create/update/delete verbs — enforced by validation)
- Audit logs every Beyla SA API call

## What this framework does NOT defend against

- A privileged-enough attacker on the node already (root on host can do anything Beyla can do plus more)
- Kernel CVEs that exploit BPF verifier (mitigation: kernel patching SLO, not in scope)
- Insider with cluster-admin

For those, layer host-level controls (eBPF runtime allow-listing via tetragon/falco, kernel CVE patch SLO, audit log SIEM).
