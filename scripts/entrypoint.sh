#!/bin/sh
# Beyla entrypoint wrapper.
# Falls back to the baked /etc/beyla/fallback.yaml if the mounted ConfigMap
# is missing. This keeps the DaemonSet pods from CrashLoopBackOff while an
# operator fixes the config — pods stay alive and emit a clear warning
# instead of getting evicted under pressure.

set -e

CONFIG="/etc/beyla/config.yaml"
FALLBACK="/etc/beyla/fallback.yaml"

if [ ! -f "$CONFIG" ]; then
  echo "WARN: $CONFIG missing — using baked fallback config. ConfigMap likely not mounted." >&2
  CONFIG="$FALLBACK"
fi

# Refuse to run if kernel is below the supported floor — fail fast and loud.
KERNEL=$(uname -r | cut -d. -f1-2)
MAJOR=${KERNEL%.*}; MINOR=${KERNEL#*.}
if [ "$MAJOR" -lt 5 ] || { [ "$MAJOR" -eq 5 ] && [ "$MINOR" -lt 8 ]; }; then
  echo "FATAL: kernel ${KERNEL} below required 5.8 — Beyla cannot attach probes." >&2
  exit 78  # EX_CONFIG
fi

exec /beyla --config="$CONFIG" "$@"
