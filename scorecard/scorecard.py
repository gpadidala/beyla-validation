#!/usr/bin/env python3
"""Automated GO/NO-GO scorecard for the Beyla rollout.

Reads validation/run-all.sh output (JSONL at <reports>/checks.jsonl) and a
thresholds file. Produces:
  - per-layer score (weighted, hard-fail-aware)
  - overall score
  - GO / GO-with-remediation / NO-GO verdict
  - markdown report

Usage:
    scorecard.py --reports reports/canary/20260511T120000Z \\
                 --thresholds thresholds.yaml \\
                 --env canary \\
                 --out report.md
"""
from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from datetime import datetime
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.stderr.write("pip install pyyaml\n")
    sys.exit(1)


def load_checks(reports_dir: Path) -> list[dict]:
    f = reports_dir / "checks.jsonl"
    if not f.exists():
        sys.exit(f"no checks.jsonl in {reports_dir}")
    return [json.loads(line) for line in f.read_text().splitlines() if line.strip()]


def score_layer(checks: list[dict], hard_cap: int) -> tuple[float, int, int, int]:
    """Return (score, pass, warn, fail)."""
    if not checks:
        return 0.0, 0, 0, 0
    p = sum(1 for c in checks if c["status"] == "pass")
    w = sum(1 for c in checks if c["status"] == "warn")
    f = sum(1 for c in checks if c["status"] == "fail")
    avg = sum(c.get("score", 0) for c in checks) / len(checks)
    if f > 0:
        avg = min(avg, hard_cap)
    return avg, p, w, f


def verdict(score: float, thresholds: dict) -> str:
    if score >= thresholds["go"]:
        return "GO"
    if score >= thresholds["partial"]:
        return "GO-WITH-REMEDIATION"
    return "NO-GO"


def emoji(v: str) -> str:
    return {"GO": "[OK]", "GO-WITH-REMEDIATION": "[WARN]", "NO-GO": "[FAIL]"}[v]


def render_markdown(layers: dict, overall: float, v: str, env: str, ts: str) -> str:
    lines = [
        f"# Beyla Rollout Scorecard — {env}",
        "",
        f"**Generated:** {ts}",
        f"**Environment:** {env}",
        f"**Overall score:** {overall:.1f} / 100",
        f"**Verdict:** {emoji(v)} **{v}**",
        "",
        "## Per-layer breakdown",
        "",
        "| Layer | Score | Pass | Warn | Fail |",
        "|------|------:|-----:|-----:|-----:|",
    ]
    for layer, info in sorted(layers.items(), key=lambda x: -x[1]["weight"]):
        lines.append(
            f"| {layer} | {info['score']:.1f} | {info['pass']} | {info['warn']} | {info['fail']} |"
        )

    fails = [c for layer in layers.values() for c in layer["failed_checks"]]
    if fails:
        lines += ["", "## Failed checks", ""]
        for c in fails:
            lines.append(f"- **{c['layer']}/{c['check']}** — {c['message']}")

    lines += [
        "",
        "## Decision",
        "",
        f"{emoji(v)} **{v}**" + (
            "" if v == "GO" else
            " — investigate failing checks above before promoting." if v == "GO-WITH-REMEDIATION" else
            " — DO NOT promote. Rollback if instability persists."
        ),
        "",
    ]
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--reports", required=True)
    ap.add_argument("--thresholds", required=True)
    ap.add_argument("--env", default="canary")
    ap.add_argument("--out", default="-")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    cfg = yaml.safe_load(Path(args.thresholds).read_text())
    if abs(sum(cfg["weights"].values()) - 1.0) > 0.01:
        sys.exit(f"weights must sum to 1.0, got {sum(cfg['weights'].values())}")

    env_cfg = cfg.get("environments", {}).get(args.env, {})
    thresholds = env_cfg.get("thresholds", cfg["thresholds"])

    checks = load_checks(Path(args.reports))
    by_layer: dict[str, list[dict]] = defaultdict(list)
    for c in checks:
        by_layer[c["layer"]].append(c)

    layers = {}
    overall = 0.0
    for layer, weight in cfg["weights"].items():
        layer_checks = by_layer.get(layer, [])
        hard_cap = cfg["hard_fail_cap"].get(layer, cfg["hard_fail_cap"]["default"])
        score, p, w, f = score_layer(layer_checks, hard_cap)
        layers[layer] = {
            "score": score,
            "weight": weight,
            "pass": p, "warn": w, "fail": f,
            "failed_checks": [c for c in layer_checks if c["status"] == "fail"],
        }
        overall += score * weight

    v = verdict(overall, thresholds)
    md = render_markdown(layers, overall, v, args.env, datetime.utcnow().isoformat() + "Z")

    if args.json:
        print(json.dumps({"overall": overall, "verdict": v, "layers": {k: v["score"] for k, v in layers.items()}}, indent=2))
    elif args.out == "-":
        print(md)
    else:
        Path(args.out).write_text(md)
        print(f"wrote {args.out}", file=sys.stderr)

    # Exit code: 0 = GO, 1 = GO-WITH-REMEDIATION, 2 = NO-GO. Lets CI gate.
    sys.exit({"GO": 0, "GO-WITH-REMEDIATION": 1, "NO-GO": 2}[v])


if __name__ == "__main__":
    main()
