# Beyla feature flags

Every Beyla capability is independently toggled. Order of disablement under load (most-sheddable first):

1. `beyla.network.enable` — tc/socket-filter overhead
2. `beyla.profiles.enabled` — Pyroscope ingest pressure
3. `beyla.features` ⊃ `application_service_graph` — high-cardinality dimension
4. `beyla.traces.enabled` — Tempo pressure (keep metrics)
5. `beyla.metrics.enabled` — last resort; you've lost RED

## Toggling at runtime

A Helm upgrade rolls one node at a time (`maxUnavailable: 10%`). For an emergency *cluster-wide* toggle that bypasses the rolling restart:

```bash
kubectl set env ds/beyla -n beyla-system BEYLA_PROFILES_ENABLED=false
```

The entrypoint wrapper rereads this on next pod restart. To force immediate restart of all pods:

```bash
kubectl rollout restart ds/beyla -n beyla-system
```

## Per-namespace opt-in

Services join the rollout by labelling their pods:

```yaml
metadata:
  labels:
    beyla.grafana.com/instrument: "true"
```

Without this label, Beyla ignores the pod entirely. This means a noisy service can be excluded without disabling Beyla cluster-wide.
