# E2E validation (Playwright)

Browser-driven and API-driven validation of the **full pipeline**: Alloy boots, loads Beyla, sees app traffic, ships metrics to Prometheus, traces to Tempo, profiles to Pyroscope; and Grafana renders every dashboard with data.

If any link is broken, exactly one test fails.

## What gets validated

| Test file | What it asserts |
|----------|----------------|
| `01-grafana-up.spec.ts` | Grafana 12+ is alive, login works |
| `02-datasources.spec.ts` | Prometheus, Tempo, Loki, Pyroscope datasources are provisioned and answer |
| `03-dashboards-render.spec.ts` | All 8 dashboards render, required panels show data, screenshots saved |
| `04-data-flow.spec.ts` | Beyla → Prometheus / Tempo / Pyroscope data is actually arriving |
| `05-alloy-pipeline.spec.ts` | Alloy's `beyla.ebpf` + `pyroscope.ebpf` + all exporters are healthy |
| `06-trace-to-profile.spec.ts` | Grafana Explore: TraceQL search works, flame graph renders |

## Run it

### Local (auto-bring-up docker-compose)

```bash
cd e2e
npm install
npm run test:install            # one-off: install Chromium
npm test                        # boots ../docker-compose.yaml, runs all tests
npm run test:report             # opens reports/html/index.html
```

### Local (existing stack already up)

```bash
SKIP_WEBSERVER=1 npm test
```

### Against a real cluster

```bash
# Service account token (Grafana → Administration → Service accounts)
export GRAFANA_URL=https://grafana.example.com
export GRAFANA_TOKEN=glsa_xxx
export ALLOY_URL=https://alloy-debug.example.com    # port-forward or ingress
export SKIP_WEBSERVER=1
npm test
```

### From the parent Makefile

```bash
make e2e             # headless, against local stack
make e2e-headed      # watch it run
make e2e-cluster ENV=staging   # against a real cluster (uses GRAFANA_TOKEN env)
```

## Outputs

- `reports/html/` — interactive HTML report
- `reports/junit.xml` — for CI consumption
- `reports/results.json` — for downstream tooling
- `screenshots/<dashboard-uid>.png` — one per dashboard, attached to the HTML report

## Adding a new dashboard

1. Drop `dashboards/<your>.json` in the repo
2. Add an entry in `e2e/fixtures/dashboards.ts` with `uid`, `title`, and the `requiredPanels` that MUST show data
3. Re-run `npm test` — the dashboard test runs automatically

## Auth modes

Set in `.env` or as environment variables:

| Mode | Env vars | Use case |
|------|---------|---------|
| Anonymous | none | local docker-compose |
| Service account token | `GRAFANA_TOKEN` | CI / cluster (preferred) |
| Basic auth | `GRAFANA_USER` + `GRAFANA_PASS` | one-off, dev |

## CI integration

`.github/workflows/ci.yml` runs `make e2e` on every PR; the JUnit + HTML reports are uploaded as artifacts.
