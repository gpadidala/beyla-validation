# Progressive rollout plan

Beyla touches the kernel on every node and a misbehaving build can DoS the LGTM stack via cardinality. The rollout is **gated by automated scorecard** at every step. No human judgment between phases — the scorecard says GO or NO-GO.

## Phases

| Phase | Scope | Sampling | Duration | Gate |
|------|-------|---------|----------|------|
| 0 — Preflight | none (compatibility check only) | n/a | 1 hr | `make preflight` PASS |
| 1 — Canary | 1% of nodes, 1 namespace (`demo`), 1 deployment | 1% traces, 7 Hz profiles | 24 hr | scorecard ≥ 80 |
| 2 — Namespace | 1 full namespace, all nodes | 5% traces, 19 Hz profiles | 48 hr | scorecard ≥ 85, no SLO burn |
| 3 — Cluster (staging) | all namespaces, staging cluster | 5% traces, 19 Hz profiles | 72 hr | scorecard ≥ 85, chaos PASS |
| 4 — Production wave 1 | 25% of prod nodes | 3% traces, 19 Hz profiles | 24 hr | scorecard ≥ 90 |
| 5 — Production wave 2 | 100% of prod nodes | 3% traces, 19 Hz profiles | ongoing | scorecard ≥ 90 |

## Mechanism

- **Canary node selection** — label 1% of nodes with `beyla.grafana.com/canary=true`. The `values-canary.yaml` `nodeSelector` pins Beyla to only those nodes.
- **Namespace gating** — `discovery.pod_label_selector: beyla.grafana.com/instrument=true` means a service joins the rollout by opting in via label.
- **Sampling control** — start ultra-conservative, ramp via Helm values upgrade. Sampling is a property of the running Beyla, no app changes needed.
- **Promote** — `make promote ENV=<current>` reads the latest scorecard, refuses to advance if score < threshold, and upgrades the next environment.

## Halt criteria

Stop and rollback immediately on **any** of:

- Application P99 latency regression > 5% sustained 10 min
- Application error rate > 1% sustained 5 min
- Beyla DaemonSet < 95% ready for 5 min
- Pyroscope write failures > 0.1/s for 5 min
- Any node enters MemoryPressure / DiskPressure
- Trace-ingestion SLO fast-burn alert fires

Rollback: `make rollback ENV=<current>` — validated by `validation/13-rollback.sh`.

## Feature flags

Each major Beyla capability is independently toggled via Helm values:

| Capability | Value path | Default | Why togglable |
|-----------|-----------|---------|---------------|
| RED metrics | `beyla.metrics.enabled` | true | Cheap; rarely disabled |
| Distributed traces | `beyla.traces.enabled` | true | Disable if Tempo overloaded |
| Continuous profiling | `beyla.profiles.enabled` | true | Disable first under load |
| Network feature | `beyla.network.enable` | false | Adds tc/socket-filter cost |
| Service-graph | `beyla.features` includes `application_service_graph` | true | Disable if cardinality explodes |

A `disable-profiles` Helm upgrade is < 60 seconds and reversible — keep that path warm.
