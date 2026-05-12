# Incident: Beyla high CPU / system CPU spike

**Severity:** P2 — investigate within 1 hour. Escalate to P1 if app latency regressing.

## Detection
Alerts that fire:
- `BeylaCPUThrottling` — Beyla itself throttled
- `NodeSystemCPUHigh` — host system CPU > 15%

## First 5 minutes
1. Confirm scope: how many nodes? Single node or fleet-wide?
   ```bash
   kubectl get pods -n beyla-system -l app.kubernetes.io/name=beyla \
     -o custom-columns=POD:.metadata.name,NODE:.spec.nodeName
   ```
2. Check the [Kernel & eBPF dashboard](http://grafana/d/beyla-kernel) — system CPU by node.
3. Check for app impact on [Application Latency Δ](http://grafana/d/beyla-app-delta). Regressing > 5%? → P1, page on-call.

## Diagnostic queries

```promql
# Beyla CPU usage per pod
sum by (pod) (rate(container_cpu_usage_seconds_total{pod=~"beyla-.*"}[5m]))

# Are we throttling?
sum(rate(container_cpu_cfs_throttled_periods_total{pod=~"beyla-.*"}[5m]))
/ sum(rate(container_cpu_cfs_periods_total{pod=~"beyla-.*"}[5m]))

# Cardinality blowing up?
sum(rate(prometheus_tsdb_head_series_created_total[5m]))
```

## Likely causes & fixes

| Cause | Indicator | Fix |
|------|-----------|-----|
| Label cardinality explosion | series creation > 5k/s | drop a high-cardinality label in `cardinality.dropLabels`, helm upgrade |
| Traffic surge | app RPS up + Beyla CPU up | switch to `low` profile temporarily |
| Tracing too aggressive | trace queue saturation high | drop sampling: `beyla.traces.samplingRatio` 0.05 → 0.01 |
| Profiling too frequent | Pyroscope ingest high | drop `beyla.profiles.cpuSamplingHz` to 7 |
| Bug in Beyla version | only happens on one image | pin to last-known-good digest |

## Emergency mitigations (in order)

1. **Drop profiling** — fastest relief:
   ```bash
   kubectl set env ds/beyla -n beyla-system BEYLA_PROFILES_ENABLED=false
   kubectl rollout restart ds/beyla -n beyla-system
   ```
2. **Drop tracing**:
   ```bash
   helm upgrade beyla deploy/helm/beyla --reuse-values --set beyla.traces.enabled=false
   ```
3. **Full rollback** if no relief in 15 min:
   ```bash
   make rollback ENV=<env>
   ```

## After resolution
- File the root cause in the issue tracker
- Update [scorecard thresholds](../scorecard/thresholds.yaml) if needed
- Update this runbook with new diagnostic queries
