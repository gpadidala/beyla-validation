# Disaster recovery

## Scope

This is **observability** disaster recovery. Loss of Beyla telemetry does not affect apps. Loss of Pyroscope/Tempo data hurts post-mortems but is recoverable from object storage.

## What's backed up

| Asset | Backup mechanism | RPO | RTO |
|------|------------------|-----|-----|
| Pyroscope blocks | shipped to object storage (Azure Blob `pyroscope-prod`) | 5 min | 1 hr |
| Tempo blocks | object storage (`tempo-prod`) | 5 min | 1 hr |
| Prometheus | local TSDB; long-term in Thanos / Mimir | 2 hr | 4 hr |
| Beyla config | Helm chart in git | n/a (versioned) | minutes |
| Recording rules / SLO defs | this repo | n/a (versioned) | minutes |

## What's NOT backed up

- In-flight traces buffered in Beyla queues (max 5–10 min loss window per node)
- Profiles from the last `pyroscope.ingester.flush_interval` window (typically 15 min)

## Restoring Pyroscope

```bash
# 1. Stop Pyroscope writes (set Beyla profiles.enabled=false)
make upgrade ENV=prod --set beyla.profiles.enabled=false

# 2. Restore blocks from object storage
pyroscope-restore --bucket pyroscope-prod \
                  --from 2026-05-10T00:00:00Z \
                  --to   2026-05-11T00:00:00Z \
                  --target ./pyroscope-data

# 3. Mount the restored blocks into a fresh Pyroscope cluster
kubectl apply -f recovery/pyroscope-pvc-restored.yaml

# 4. Resume Beyla writes
make upgrade ENV=prod --set beyla.profiles.enabled=true
```

## Restoring Beyla itself

Beyla is stateless. To restore: `make install ENV=<env>`. The DaemonSet rebuilds itself from the git-versioned Helm chart in minutes.

## DR drill cadence

Quarterly. Steps:
1. Pick a non-prod cluster
2. Simulate Pyroscope loss via `chaos/01-pyroscope-down.yaml` for 30 min
3. Restore from backup
4. Compare query results pre/post — should match within retention window

Document drill results in `docs/dr-drill-YYYY-QN.md`.
