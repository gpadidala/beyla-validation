# beyla-validation

Production-grade framework for rolling out **Grafana Beyla** (eBPF auto-instrumentation: RED metrics, distributed traces, continuous profiling) on Kubernetes — using **Grafana Alloy** as the on-node agent — with **end-to-end Playwright validation** that every Grafana dashboard renders with real data.

Target stack: **Alloy 1.4+ · Beyla (embedded) · Prometheus · Tempo · Loki · Pyroscope · Grafana 12.4**, optional Istio. Primary cluster: AKS, GKE-compatible.

---

## What this repo gives you

| Layer | Artifact |
|------|---------|
| Agent | [Alloy](alloy/) DaemonSet config with `beyla.ebpf` + `pyroscope.ebpf` components, OTel processors (batch, k8s attributes, tail sampling), 3 exporters |
| Deployment | Upstream `grafana/alloy` Helm chart + our values (canary/staging/prod) + Kustomize as alternative |
| Validation | 16 layered shell scripts + **Playwright E2E** suite (login, dashboard render, data-flow assertions, trace→profile linking) |
| Observability | 5 PromQL libraries, 7 PrometheusRule bundles, **8 Grafana dashboards** (including Alloy health) |
| Reliability | Sloth SLOs, burn-rate alerts, 5 ChaosMesh experiments |
| Rollout | 5-phase progressive (canary 1% → prod 100%), Flagger canary, feature flags |
| Compatibility | Kernel × K8s × runtime matrix + probe test |
| Cost | Capacity model (Python) for CPU/mem/disk/egress |
| Decisions | Automated GO/NO-GO scorecard, weighted thresholds, per-env gating |
| Operations | 6 runbooks (onboarding, high CPU, Pyroscope down, cardinality, rollback, DR) |

---

## Two-minute quickstart (local docker-compose)

```bash
make dev-up                    # boots Alloy + LGTM + a demo app
make e2e                       # Playwright: validates the whole pipeline end-to-end
make e2e-report                # open the HTML report with screenshots of every dashboard

# When you're done:
make dev-down
```

The Playwright suite **brings up Grafana, logs in, navigates every dashboard, asserts panels show data, follows trace→profile links, and screenshots each dashboard.** If any link in the chain is broken, exactly one test fails.

---

## In-cluster quickstart

```bash
# 0. Preflight: kernel/BTF/runtime/k8s checks
make preflight

# 1. Install Alloy (with Beyla embedded) on 1% of nodes, one namespace
make alloy-install ENV=canary

# 2. Open Alloy's live debug UI (component graph)
make alloy-debug              # → http://localhost:12345

# 3. Run validation: shell suite + Playwright against the cluster
make validate ENV=canary
GRAFANA_URL=https://grafana.example.com GRAFANA_TOKEN=glsa_xxx \
  make e2e-cluster ENV=canary

# 4. Score the rollout (auto GO/NO-GO)
make scorecard ENV=canary

# 5. Promote, or rollback
make promote   ENV=staging
make rollback  ENV=canary
```

---

## Architecture

```
┌────────────────────────────────────────────────────────────────────────┐
│ Kubernetes node                                                        │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │ Alloy pod  (DaemonSet — one per node, privileged + CAP_BPF)      │  │
│  │                                                                  │  │
│  │   beyla.ebpf "default"     ─┐                                    │  │
│  │   pyroscope.ebpf "default" ─┤                                    │  │
│  │                             │                                    │  │
│  │   ┌─────────────────────────┴─┐                                  │  │
│  │   │ otelcol.processor.batch    │                                 │  │
│  │   │ otelcol.processor.k8sattr  │   live debug UI :12345          │  │
│  │   │ otelcol.processor.tailsamp │                                 │  │
│  │   └────────────┬───────────────┘                                 │  │
│  │                │                                                 │  │
│  │   ┌────────────┼────────────────┐                                │  │
│  │   ▼            ▼                ▼                                │  │
│  │ prom_rw   otlp/tempo     pyroscope.write                         │  │
│  └────┼──────────┼──────────────────┼──────────────────────────────┘  │
└───────┼──────────┼──────────────────┼───────────────────────────────────┘
        ▼          ▼                  ▼
   Prometheus    Tempo            Pyroscope
        └──────────┴──────────────────┘
                       │
                       ▼
                    Grafana 12.4
                  (dashboards + Explore + trace→profile)
```

Why this shape: one agent per node, native Beyla, tail sampling and k8s enrichment in-stream, no separate OTel collector. Recommended Grafana production pattern as of 2025.

See [docs/architecture.md](docs/architecture.md) for the full data flow.

---

## Repo layout

```
beyla-validation/
├── alloy/                 # ★ Primary deployment — Alloy + Beyla via grafana/alloy chart
│   ├── config.alloy       # full River config (Beyla + Pyroscope + exporters)
│   ├── values*.yaml       # Helm values per environment
│   └── README.md
├── e2e/                   # ★ Playwright end-to-end suite
│   ├── tests/             # 6 specs: grafana-up, datasources, dashboards, data-flow, alloy, trace→profile
│   ├── fixtures/          # grafana.ts (API helper), dashboards.ts (spec)
│   ├── screenshots/       # produced by test run, one per dashboard
│   └── README.md
├── deploy/                # Alternative: direct Beyla DaemonSet (no Alloy) — Helm + Kustomize
├── config/                # Beyla configs (when running standalone)
├── validation/            # 16 layered shell scripts (00-alloy + 01-15)
├── promql/                # Query library by domain
├── dashboards/            # 8 Grafana JSON dashboards
├── alerts/                # 7 PrometheusRule CRs (incl. alloy-alerts)
├── slo/                   # Sloth SLOs + burn-rate alerts
├── chaos/                 # 5 ChaosMesh experiments
├── rollout/               # Progressive rollout plan, Flagger canary, feature flags
├── compatibility/         # Kernel/K8s/runtime matrix + probe test
├── cost/                  # Capacity & cost model
├── scorecard/             # Automated GO/NO-GO
├── runbooks/              # 6 incident & operations runbooks
├── docs/                  # Architecture, threat model, meta-obs
├── examples/              # LGTM + Alloy local-dev configs
├── docker-compose.yaml    # Alloy + LGTM + demo app
└── Makefile               # `make <target>` is the entry point
```

---

## Dashboards (all validated by Playwright)

| UID | Title | Required panels validated |
|-----|------|--------------------------|
| `alloy-health` | Alloy • Pipeline Health | pods running, components healthy %, metric/trace throughput |
| `beyla-health` | Beyla • Health | DaemonSet ready %, pods, CPU/memory per pod |
| `beyla-app-delta` | Beyla • Application Latency Δ vs Baseline | worst Δ P99, regression count, P99 current vs baseline |
| `beyla-kernel` | Beyla • Kernel & eBPF | system CPU %, context switches |
| `beyla-pyroscope` | Beyla • Pyroscope Pipeline | ingest MB/s, active series, write failures |
| `beyla-network` | Beyla • Network Impact | TCP retransmits, service-graph P99 |
| `beyla-scorecard` | Beyla • Rollout Scorecard | per-layer scores, overall GO/NO-GO |
| `beyla-meta-obs` | Beyla • Cost of Observability | CPU/mem burn %, storage growth projection |

Each panel listed has a Playwright assertion that it renders **with data**, not "No data". Screenshots are committed to `e2e/screenshots/` for visual review.

---

## Default cluster assumptions

Overrides per-cluster in [alloy/values-*.yaml](alloy/):

| Param | Default | Override |
|------|---------|---------|
| Cluster | `aks-prod-eus` | `extraEnv[CLUSTER_NAME]` |
| Region | `eastus` | n/a (label) |
| Kubernetes | `1.30.x` | enforced by preflight |
| Node OS | Ubuntu 22.04 | `nodeSelector` |
| Kernel | `5.15+` (Beyla floor `5.8`) | enforced by `kernel-probe-test.sh` |
| Container runtime | `containerd 1.7+` | n/a |
| Target namespaces | `demo,checkout,payments` | `extraEnv[TARGET_NAMESPACES]` |
| Trace sampling | head 5% + tail (errors + slow) | inline in `config.alloy` |

---

## Safety contract

Alloy runs **privileged with `CAP_BPF` / `CAP_SYS_ADMIN`** on every node — Beyla loads eBPF programs from inside the Alloy pod. The framework enforces:

1. **Preflight gate** — `compatibility/kernel-probe-test.sh` runs before install.
2. **Canary first** — never install on >1% of nodes without a scorecard PASS.
3. **In-stream auto-throttle** — Beyla drops sampling at the configured CPU/mem watermarks.
4. **Tail sampling at the agent** — errors and slow traces always kept; cheap base rate everywhere else.
5. **NetworkPolicy** — Alloy egress locked to the LGTM stack.
6. **Cardinality budget** — label drop rules enforced inside `beyla.ebpf`, alerted at 80% of budget.
7. **Hard rollback** — `make rollback` removes the DaemonSet, verifies eBPF detach, confirms zero residue.
8. **E2E gate** — Playwright suite must pass before promote (CI enforces).

See [docs/threat-model.md](docs/threat-model.md) for the full security model.

---

## Two modes, your choice

| Mode | What it is | When to use |
|------|-----------|-------------|
| **Alloy mode (recommended)** | Beyla embedded as Alloy component; one DaemonSet | Production. Tail sampling + k8s enrichment in-stream. |
| Direct Beyla mode | Standalone Beyla DaemonSet, exports straight to LGTM | Simpler ops, or when Alloy can't be deployed. See [deploy/helm/beyla/](deploy/helm/beyla/). |

`make rollback` auto-detects which mode is installed and cleans up appropriately.

---

## License

Apache-2.0. See [LICENSE](LICENSE).
