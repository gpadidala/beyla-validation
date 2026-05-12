# Emergency rollback

**When to run:** app is regressing, Beyla can't be relied on to self-heal, and you need Beyla off NOW.

This is the documented escape hatch. The `make rollback` target wraps `validation/13-rollback.sh` and verifies cleanup.

## TL;DR

```bash
make rollback ENV=<canary|staging|prod>
```

That command:
1. Pauses the DaemonSet so no rolling-update interleaving occurs
2. Runs `helm uninstall beyla` (waits up to 5m for clean termination)
3. Verifies all Beyla pods are gone
4. Spot-checks 3 nodes via `kubectl debug` + `bpftool prog show | grep beyla` — must be empty
5. Confirms all Helm-managed objects are removed

Exit code 0 = verified clean. Anything else = manual cleanup needed.

## Manual cleanup if the script reports residue

```bash
# 1. Force-delete stuck pods
kubectl delete pods -n beyla-system -l app.kubernetes.io/name=beyla --force --grace-period=0

# 2. Detach orphaned eBPF programs (run on each node via debug pod)
for node in $(kubectl get nodes -o name | sed 's|node/||'); do
  kubectl debug node/$node -it --image=alpine -- chroot /host bash -c \
    'for p in $(bpftool prog show -j | jq -r ".[] | select(.name | startswith(\"beyla\")) | .id"); do bpftool prog detach $p; done'
done

# 3. Clean up dangling BPF maps
for node in ...; do
  kubectl debug node/$node ... 'bpftool map show -j | jq -r ".[] | select(.name | startswith(\"beyla\")) | .id" | xargs -I{} bpftool map delete id {}'
done

# 4. Remove pinned objects
# /sys/fs/bpf/beyla/ — wipe via chroot
```

## After rollback

- Confirm app P99 returns to baseline within 15 min
- Open an incident review (template: [scorecard/report-template.md](../scorecard/report-template.md))
- Do NOT re-attempt rollout until the root cause is documented and the fix is verified

## Rollback safety properties

- **Never destructive to app data** — Beyla writes no app state
- **Never destructive to telemetry already stored** — Prometheus/Tempo/Pyroscope retention is untouched
- **eBPF programs are torn down on pod stop** — no kernel residue if pod exits cleanly
- **NetworkPolicy persists 30s after delete** — expected; allows in-flight responses to drain
