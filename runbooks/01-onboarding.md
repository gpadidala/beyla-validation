# Onboarding a new service / cluster to Beyla

## TL;DR
1. Run preflight on the target cluster
2. Label nodes (for canary) or services (for namespace scope)
3. `make install ENV=canary NAMESPACE=<beyla-system>`
4. Wait 30 min, run `make validate && make scorecard`
5. Promote if score ≥ threshold

## Step-by-step

### 1. Preflight
```bash
make preflight
```
Verifies kernel ≥ 5.8, BTF available, cgroup v2, supported k8s version. If any node fails, stop here — Beyla will not work.

### 2. Decide the scope
- **Canary** — 1% of nodes. Label them:
  ```bash
  kubectl label nodes -l '!agentpool=systempool' --overwrite \
    beyla.grafana.com/canary=true | head -n $((NODE_COUNT / 100))
  ```
- **Service opt-in** — add to your Deployment:
  ```yaml
  spec:
    template:
      metadata:
        labels:
          beyla.grafana.com/instrument: "true"
  ```

### 3. Install
```bash
make install ENV=canary NAMESPACE=beyla-system
kubectl rollout status ds/beyla -n beyla-system
```

### 4. Validate
```bash
make validate ENV=canary TARGET_NS=<your-namespace>
make scorecard ENV=canary
```

### 5. Watch
Open the [Beyla Health](http://grafana/d/beyla-health) and [Application Latency Δ](http://grafana/d/beyla-app-delta) dashboards. Leave running 30 min. No alerts firing? Promote.

## Failure modes during onboarding

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| Beyla pods CrashLoopBackOff | BTF missing on node | install kernel headers or ship BTFHub initContainer |
| Pods Running but no metrics | `discovery.pod_label_selector` not matching | check pod labels and Beyla logs |
| Pods Running but high CPU | wrong traffic profile | switch from `medium` to `low` for canary |
| Cardinality alerts firing | label drop rules not enforced | confirm `cardinality.dropLabels` in values |
