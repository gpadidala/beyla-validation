#!/usr/bin/env bash
# Validate dashboard JSON: parseable, has uid + title, panels have targets.
set -Eeuo pipefail
fails=0
for f in dashboards/*.json; do
  python3 - <<EOF
import json, sys
d = json.load(open("$f"))
assert d.get("uid"), "missing uid in $f"
assert d.get("title"), "missing title in $f"
for p in d.get("panels", []):
    if p.get("type") in ("row", "text"):
        continue
    assert p.get("targets"), f"$f panel {p.get('id')} missing targets"
print("ok $f")
EOF
done
