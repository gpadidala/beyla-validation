# Incident: Pyroscope down or write failures

**Severity:** P2 — observability degraded but app unaffected (Beyla buffers).
Escalates to P1 if Beyla buffer fills and starts impacting node memory.

## Detection
- `PyroscopeWriteFailures` firing
- `PyroscopeDiskHigh` / `PyroscopeIngesterMemoryHigh`
- Pyroscope distributor pods restarting

## First 5 minutes

```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=pyroscope
kubectl logs -n monitoring -l app.kubernetes.io/component=distributor --tail=200
```

Check the [Pyroscope dashboard](http://grafana/d/beyla-pyroscope). Three failure modes:

| Symptom | Cause | Action |
|--------|-------|--------|
| Pods Pending | resource limit / PVC unavailable | check events, expand PVC if disk full |
| Pods CrashLoopBackOff | config error or OOM | check container logs, raise memory limit |
| Pods Running, write failures | downstream storage full | expand storage; verify retention |

## Beyla side — does this hurt the app?

Check Beyla queue saturation:
```promql
max(beyla_export_queue_size / beyla_export_queue_capacity)
```
- < 0.5 → fine, app unaffected
- 0.5 – 0.8 → Beyla shedding profiles, app unaffected
- > 0.8 → near OOM risk on Beyla pods; mitigate immediately

## Mitigation order

1. **Free disk** — increase PVC or rotate old blocks (Pyroscope retains 14d default).
2. **Scale ingesters** — add replicas if memory-bound.
3. **Stop profile ingest from Beyla** — keeps app healthy:
   ```bash
   kubectl set env ds/beyla -n beyla-system BEYLA_PROFILES_ENABLED=false
   ```
4. **Hard cap series** in Pyroscope `limits_config.max_series_per_user`.

## Post-incident
- Investigate which tenant blew the budget (`pyroscope_top_tenants` query)
- Add per-tenant rate limit if not yet in place
- Update [cost-model-inputs.yaml](../cost/cost-model-inputs.yaml) with new capacity numbers
