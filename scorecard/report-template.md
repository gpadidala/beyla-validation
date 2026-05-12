# Beyla Rollout Scorecard — {{ENV}}

**Generated:** {{TIMESTAMP}}
**Cluster:** {{CLUSTER}}
**Phase:** {{PHASE}} (canary → namespace → staging → prod-wave-1 → prod-wave-2)
**Overall score:** {{SCORE}} / 100
**Verdict:** {{VERDICT}}

---

## Per-layer breakdown

| Layer | Weight | Score | Pass | Warn | Fail | Notes |
|------|------:|------:|-----:|-----:|-----:|------|
| Application impact   | 25% | {{APP_SCORE}}   | … | … | … | P50/P95/P99 latency, throughput, errors |
| Kernel & eBPF        | 15% | {{KERN_SCORE}}  | … | … | … | bpftool, dmesg, system CPU |
| Telemetry accuracy   | 10% | {{TELE_SCORE}}  | … | … | … | span completeness, profile freshness |
| Kubernetes cluster   | 10% | {{K8S_SCORE}}   | … | … | … | restarts, OOMKills, pressure |
| Control plane        |  5% | {{CP_SCORE}}    | … | … | … | API server P99, etcd commit |
| Autoscaling          |  5% | {{HPA_SCORE}}   | … | … | … | HPA churn, CA scale-ups |
| Network              |  5% | {{NET_SCORE}}   | … | … | … | retransmits, svc-to-svc |
| Pyroscope pipeline   | 10% | {{PYRO_SCORE}}  | … | … | … | ingest, series, disk |
| Backpressure         |  5% | {{BP_SCORE}}    | … | … | … | queues, retries, drops |
| Multi-tenancy        |  2% | {{MT_SCORE}}    | … | … | … | per-tenant fairness |
| Security             |  5% | {{SEC_SCORE}}   | … | … | … | caps, RBAC, NetworkPolicy |
| Chaos                |  2% | {{CHAOS_SCORE}} | … | … | … | failure simulation |
| Time sync            |  1% | {{TIME_SCORE}}  | … | … | … | NTP, clock skew |

---

## Failed checks

{{FAILED_CHECKS}}

## Recommendations

{{RECOMMENDATIONS}}

## Decision

{{VERDICT_DETAIL}}

---

## Next steps if GO

1. Run `make promote ENV={{NEXT_ENV}}`
2. Watch the [Beyla Health dashboard](http://grafana/d/beyla-health) for 30 minutes
3. Re-run scorecard at `{{NEXT_ENV}}` after stabilization

## Next steps if NO-GO

1. Run `make rollback ENV={{ENV}}` immediately
2. Review failed checks in this report
3. File issue in the `beyla-validation` repo with the report attached
4. Do not re-attempt before the root cause is identified and fixed
