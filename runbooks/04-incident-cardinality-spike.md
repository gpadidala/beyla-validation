# Incident: cardinality spike

**Severity:** P2 — observability cost surges, possible Prometheus OOM in hours.

## Detection
- `PromHighChurn` — series creation > 5k/s
- `ServiceCardinalityBudgetExceeded`
- Prometheus memory rising sharply

## First 5 minutes

```promql
# Top label keys by series count
topk(20, count by (__name__) ({__name__=~".+"}))

# Which Beyla pod is contributing the most?
topk(10, count by (pod) ({__name__=~"http_server.*"}))

# What's the offending label?
topk(20, count by (le, service_name, http_route, k8s_pod_name) (http_server_request_duration_seconds_bucket))
```

The offender is almost always one of:
- `http_route` matched `unmatched: wildcard` instead of `heuristic`
- `k8s.pod.uid` snuck back in (verify `cardinality.dropLabels`)
- `db.statement` with no scrubbing — unique per query

## Fix

1. **Drop the label** at Beyla:
   ```yaml
   # values.yaml
   cardinality:
     dropLabels:
       - http.user_agent
       - http.client_ip
       - k8s.pod.uid
       - <NEW_OFFENDER>
   ```
   ```bash
   make upgrade ENV=<env>
   ```

2. **Reload Prometheus** to drop stale series faster:
   ```bash
   curl -X POST http://prometheus.monitoring.svc.cluster.local:9090/-/reload
   ```

3. **For HTTP routes** — never use `unmatched: wildcard`. Stay with `heuristic`.

## Prevention
- Cardinality alerts are configured in [cardinality-alerts.yaml](../alerts/cardinality-alerts.yaml). Verify they fire **before** Prometheus OOMs (typical lag: 30 min).
- Add the offending label pattern to the `cardinality.dropLabels` in `values.yaml` so it's prevented permanently.
