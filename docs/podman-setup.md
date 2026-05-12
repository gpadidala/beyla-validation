# Running the local stack on Podman

The repo works with both Docker and Podman. Pick whichever is convenient:

```bash
make dev-up                       # auto-detects: docker if present, else podman
make dev-up ENGINE=podman         # force podman
make dev-up ENGINE=docker         # force docker
```

The Makefile picks the engine via `$(ENGINE)` and routes every container command through it. The compose file is the same in both cases; a small override (`docker-compose.podman.yaml`) is auto-merged when ENGINE=podman to add SELinux `:Z` labels and `security_opt: label=disable` on Alloy.

---

## macOS setup (one-time)

Podman on macOS runs containers inside a Linux VM, exactly like Docker Desktop. Install and start the VM **rootful** — eBPF features Beyla needs (host PID namespace, BPF caps, debugfs) require it.

```bash
# 1. Install
brew install podman podman-compose

# 2. Create a rootful VM (default size; bump CPU/RAM if you instrument many services)
podman machine init --rootful --cpus 4 --memory 4096
podman machine start

# 3. Smoke check
podman info | grep -E '(rootless|os)'
# rootless: false      ← required for eBPF
# os: linux

# 4. Validate compose works
podman compose version
```

If `podman machine` already exists and is rootless, recreate it:

```bash
podman machine stop
podman machine rm
podman machine init --rootful --cpus 4 --memory 4096
podman machine start
```

## Linux setup

If you already run Docker rootless or Podman as a regular user, the eBPF mounts (`/sys/fs/bpf`, `/sys/kernel/debug`) won't be accessible. Use rootful Podman:

```bash
sudo podman compose -f docker-compose.yaml -f docker-compose.podman.yaml up -d
```

Or set up Podman with eBPF capabilities for your user (more involved — refer to your distro's docs).

---

## Differences you may notice

| Behavior | Docker | Podman |
|---------|--------|--------|
| `init: true` (zombie reap) | uses tini | uses conmon — same effect |
| `pid: host` | host = the VM | host = the VM (rootful) or user ns (rootless) |
| Privileged + CAP_BPF | works | works (rootful) |
| Volume label `:Z` | ignored | applied (SELinux) |
| Network DNS for service names | works | works |
| `podman-compose` (pip) | n/a | older fork — prefer native `podman compose` |

If you hit `permission denied` on `/sys/fs/bpf/...`, you're rootless; switch to rootful.

---

## Testing both engines

```bash
make dev-up    ENGINE=docker
make e2e
make dev-down  ENGINE=docker

make dev-up    ENGINE=podman
make e2e
make dev-down  ENGINE=podman
```

Both should produce identical Playwright pass results — the framework is engine-agnostic by design.
