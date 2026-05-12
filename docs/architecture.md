# Architecture

## Data flow

```
┌─────────────────────────────────┐
│ Application Pod                 │
│  (no SDK, no code change)       │
└──────────────┬──────────────────┘
               │  (kernel syscalls: accept, read, write, ssl_*)
               ▼
┌─────────────────────────────────┐
│ Linux Kernel                    │
│  ┌───────────────────────────┐  │
│  │ eBPF programs (Beyla)     │  │
│  │  - kprobe / uprobe        │  │
│  │  - fentry/fexit (5.8+)    │  │
│  │  - socket filter / tc     │  │
│  └────────────┬──────────────┘  │
└───────────────┼─────────────────┘
                │ events via ringbuf
                ▼
┌─────────────────────────────────┐
│ Beyla DaemonSet pod             │
│   (privileged, per node)        │
│   - decode protocols (HTTP*, gRPC, SQL)
│   - build RED metrics
│   - emit spans (OTLP)
│   - sample CPU stacks
│   - K8s metadata enrichment
└────┬───────┬───────┬────────────┘
     │       │       │
     ▼       ▼       ▼
  Prom   Tempo   Pyroscope
  (RED   (spans) (profiles)
  metrics)

         ▼
       Grafana
       (dashboards, exemplars, trace → log → profile linking)
```

## Why DaemonSet

- One Beyla per node = one set of eBPF programs per kernel.
- Pod restart on a node tears down all probes cleanly.
- No sidecar overhead per app pod.
- Resource limits apply per node, not per app — better cost predictability.

## Why no app changes

Beyla attaches to TCP/HTTP syscalls and OpenSSL/Go runtime symbols. It identifies routes via socket inspection, so the app does nothing. This is also Beyla's biggest limitation: protocols it doesn't decode (custom binary protocols, MQTT, AMQP) get bytes-in/bytes-out but no semantic spans.

## Why we built this framework around Beyla

Beyla is **privileged on every node** and **shares a cardinality budget with every other producer in your Prometheus / Pyroscope clusters**. Two failure modes account for most production incidents:

1. **eBPF probe load failure on a kernel version** — silently degrades coverage. Mitigation: `compatibility/kernel-probe-test.sh` + the `BeylaProbeLoadFailures` alert.
2. **Cardinality explosion via a label we forgot to drop** — caps Prometheus. Mitigation: `cardinality.dropLabels` enforced at source, `ServiceCardinalityBudgetExceeded` alert.

Everything else in this repo is built to detect, score, and gate those two failure modes.

## Component map

| Component | Role | Lives in |
|----------|------|----------|
| Beyla DaemonSet | eBPF agent | every node |
| ConfigMap | runtime config | one per Helm release |
| OTel Collector (optional) | tail sampling, PII scrub | between Beyla and storage |
| Prometheus | metrics store + recording rules | `monitoring` namespace |
| Tempo | trace store | `monitoring` namespace |
| Pyroscope | profile store | `monitoring` namespace |
| Grafana 12.4 | UI + datasource linking | `monitoring` namespace |
| Flagger | canary controller | `flagger-system` |
| ChaosMesh | chaos experiments | `chaos-mesh` |

## Multi-cluster

Each cluster's Beyla writes to the **local** LGTM stack. Federation happens at the Mimir / Tempo / Pyroscope distributed read path — Grafana queries multiple datasources scoped by `cluster` label.

Why not write across clusters directly? Egress cost and single-point-of-failure. Each cluster is independent in the write path; federation is read-only.
