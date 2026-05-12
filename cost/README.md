# Cost model

Projects Beyla + Pyroscope infrastructure cost from rollout parameters. Inputs are in [cost-model-inputs.yaml](cost-model-inputs.yaml); the script outputs a per-environment monthly + annual breakdown.

```bash
python3 cost-model.py --inputs cost-model-inputs.yaml --env prod
python3 cost-model.py --inputs cost-model-inputs.yaml --env all --json
```

## What's modelled

- Beyla DaemonSet CPU + memory (request × node count × 730h)
- Pyroscope ingester capacity (CPU / mem / disk scaled by series and replication)
- Egress charges (10% of telemetry crosses region — adjust per topology)
- Storage retention based on `pyroscope.storage_retention_days`

## What's NOT modelled

- Prometheus / Tempo / Loki cost (those are pre-existing in the LGTM stack)
- Engineering time to onboard
- Cost of an incident the framework prevents (estimate this separately)

## How accurate is it?

Within ±25% in our experience. The largest swing factor is **cardinality** — if label drop rules fail and Pyroscope series double, ingester memory roughly doubles. The model assumes the cardinality budget in [values.yaml](../deploy/helm/beyla/values.yaml) is enforced.
