# Alloy + Beyla (recommended deployment)

This directory contains the Grafana Alloy configuration that embeds Beyla as a native Alloy component (`beyla.ebpf`). Alloy runs as a DaemonSet on every node; Beyla loads eBPF programs inside the Alloy pod; data flows out via a single OTel pipeline to Prometheus, Tempo, and Pyroscope.

## Why Alloy mode

- **One agent per node** — no separate Beyla and Otel-collector pods to coordinate
- **Tail sampling, k8s enrichment, batching** are all in-pipeline, no external collector
- **Standard Grafana stack** — upstream `grafana/alloy` Helm chart is the install vector
- **Live debug UI** at `:12345/-/debug` shows the component graph and current flow

## Files

| File | Purpose |
|------|---------|
| [config.alloy](config.alloy) | Full Alloy River config — Beyla + Pyroscope eBPF + processors + exporters |
| [values.yaml](values.yaml) | Helm values for `grafana/alloy` chart (DaemonSet, security context, mounts) |
| [values-canary.yaml](values-canary.yaml) | 1% node canary overrides |
| [values-prod.yaml](values-prod.yaml) | Prod overrides (digest-pinned image, tighter limits) |
| [alloy-configmap.yaml](alloy-configmap.yaml) | ConfigMap stub (real content loaded from `config.alloy` at apply time) |

## Install

```bash
# 1. Preflight (kernel/BTF/runtime checks)
make preflight

# 2. Add the Grafana Helm repo
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# 3. Create the namespace + ConfigMap from our config.alloy
kubectl create ns alloy --dry-run=client -o yaml | kubectl apply -f -
kubectl create configmap alloy-config-beyla -n alloy \
  --from-file=config.alloy=alloy/config.alloy \
  --dry-run=client -o yaml | kubectl apply -f -

# 4. Install Alloy with our values
helm upgrade --install alloy grafana/alloy \
  -n alloy \
  -f alloy/values.yaml \
  -f alloy/values-canary.yaml \
  --atomic --timeout 5m
```

Or use the Makefile shortcut:

```bash
make alloy-install ENV=canary
```

## How data flows

```
                      ┌──────────────────────────────────────┐
                      │ Alloy pod (DaemonSet, 1 per node)    │
                      │                                      │
   App pods on node ──┤ beyla.ebpf       ──┐                 │
                      │ pyroscope.ebpf   ──┤                 │
                      │                    ├─► batch         │
                      │                    │   k8sattributes │
                      │                    │   tail_sampling │
                      │                    │                 │
                      │                    ├─► prom_rw   ────┼──► Prometheus
                      │                    ├─► otlp/tempo ───┼──► Tempo
                      │                    └─► pyroscope.write┼──► Pyroscope
                      └──────────────────────────────────────┘
```

## Verify the install

```bash
# DaemonSet ready
kubectl rollout status ds/alloy -n alloy --timeout=5m

# Component graph (port-forward then open in browser)
kubectl port-forward -n alloy ds/alloy 12345:12345
# → http://localhost:12345

# Check Beyla is loaded as a component
curl -s http://localhost:12345/api/v0/web/components | jq '.[] | select(.module_id | startswith("beyla.")) | .module_id'
# expect: "beyla.ebpf/default"

# Smoke test: Beyla should be emitting metrics
curl -s http://localhost:12345/metrics | grep -c beyla_
```

## Tuning

All knobs in [config.alloy](config.alloy) are designed to be set via env vars in [values.yaml](values.yaml). The hot ones:

| Env var | Default | What it controls |
|--------|---------|-----------------|
| `TARGET_NAMESPACES` | `demo,checkout,payments` | Which namespaces Beyla watches |
| `CLUSTER_NAME` | `aks-prod-eus` | `cluster` label on all metrics |
| `PROMETHEUS_REMOTE_WRITE_URL` | in-cluster Prometheus | Where RED metrics go |
| `TEMPO_OTLP_ENDPOINT` | in-cluster Tempo | Where traces go |
| `PYROSCOPE_ENDPOINT` | in-cluster Pyroscope | Where profiles go |
| `ALLOY_LOG_LEVEL` | `info` | drop to `warn` in prod |

Changing any of these is a Helm upgrade — no config.alloy edit needed.

## Alternative: direct Beyla DaemonSet

If you prefer Beyla without Alloy (simpler, but no tail sampling / k8s enrichment in-stream), see [../deploy/helm/beyla/](../deploy/helm/beyla/). The two are mutually exclusive — pick one.

The validation scripts and dashboards work with both modes.
