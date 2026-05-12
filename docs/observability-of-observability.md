# Observability of observability

The Beyla DaemonSet is itself a production service. It has SLOs, an oncall path, and a meta-observability dashboard. If we can't see Beyla, we can't trust anything it produces.

## SLOs

Defined in [slo/observability-slos.yaml](../slo/observability-slos.yaml):

| SLO | Target | Why |
|----|-------|-----|
| Trace ingestion availability | 99.9% | If Tempo refuses spans, RED metrics are still safe — but trace UX dies |
| Profile freshness | 99% within 5 min | Operators rely on profiles for incident debugging |
| Query latency | 99% < 3s | Grafana panel timeouts kill the workflow |
| Profile write success | 99.95% | Higher than ingestion because writes are critical |

Burn-rate alerts in [slo/burn-rate-alerts.yaml](../slo/burn-rate-alerts.yaml) use the multi-window/multi-burn-rate (MWMBR) pattern: a fast-burn at 14.4× and a slow-burn at 6×.

## Meta dashboard

[dashboards/meta-observability.json](../dashboards/meta-observability.json) shows:

- **CPU burn %** — how much of the cluster Beyla itself consumes
- **Memory burn %** — same for memory
- **Storage growth** — how fast Pyroscope is filling disk
- **Telemetry efficiency** — spans-per-CPU-second (a "useful work" ratio)

These are the cost-of-observability metrics. If CPU burn > 5% of cluster, **you are paying more for observability than the observability is worth**. Either downscale or reconsider scope.

## Alerts that page oncall

Severity = `critical` in [alerts/](../alerts/):

| Alert | What it means |
|------|---------------|
| `BeylaDaemonSetDegraded` | We are flying blind on some nodes |
| `BeylaProbeLoadFailures` | Kernel/BTF mismatch — coverage degrading |
| `PyroscopeWriteFailures` | Profile data being lost |
| `TraceIngestionFastBurn` | SLO budget will exhaust in < 2 days |
| `AppLatencyRegression` | Beyla rollout regressing the app |
| `AppErrorRateSpike` | Beyla rollout breaking the app |

Severity = `warning` in the same files: ticket, no page.

## Audit & traceability

- Every Helm upgrade is versioned in git — `helm history beyla` matches a commit
- Every chaos experiment is a versioned YAML — what ran, when, on what
- Every rollout phase emits a scorecard report committed to `reports/<env>/<timestamp>/`
- Every alert annotation links to a specific runbook in [runbooks/](../runbooks/)
