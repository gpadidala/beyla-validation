#!/usr/bin/env bash
# Lint Alloy River configs by running `alloy fmt --test` inside a container.
# Skips cleanly if Docker isn't available — CI will catch it.
set -Eeuo pipefail

if ! command -v docker >/dev/null; then
  echo "docker not available — skipping alloy fmt"
  exit 0
fi

for f in alloy/config.alloy examples/alloy-config-local.alloy; do
  [[ -f "$f" ]] || continue
  echo "▶ alloy fmt --test $f"
  docker run --rm -v "$PWD":/work -w /work grafana/alloy:v1.4.2 \
    fmt --test "$f" >/dev/null
  echo "  ✓ syntax OK"
done
