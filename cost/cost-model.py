#!/usr/bin/env python3
"""Capacity & cost projection for Beyla + Pyroscope rollout.

Reads cost-model-inputs.yaml, prints a per-environment breakdown plus a
12-month forecast assuming linear traffic growth.

Usage:
    python3 cost-model.py --inputs cost-model-inputs.yaml --env prod
    python3 cost-model.py --inputs cost-model-inputs.yaml --env all --json
"""
from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass

try:
    import yaml
except ImportError:
    sys.stderr.write("pip install pyyaml\n")
    sys.exit(1)


@dataclass
class CostInputs:
    cloud: str
    region: str
    cpu_price_per_core_hour: float
    mem_price_per_gib_hour: float
    egress_price_per_gb: float
    managed_disk_price_per_gb_month: float
    beyla: dict
    telemetry: dict
    pyroscope: dict
    nodes: int
    services: int


def merge(defaults: dict, env: dict) -> dict:
    out = {**defaults}
    for k, v in env.items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = {**out[k], **v}
        else:
            out[k] = v
    return out


def project(env_name: str, raw: dict) -> dict:
    cpu_h = raw["beyla"]["cpu_request_per_node_cores"] * raw["nodes"] * 730  # core-hours/month
    mem_h = raw["beyla"]["mem_request_per_node_gib"]  * raw["nodes"] * 730

    rps_total = raw["services"] * raw["telemetry"]["request_rate_per_service_rps"]
    spans_per_sec = rps_total * raw["telemetry"]["trace_sampling_ratio"]
    span_bytes_per_day = spans_per_sec * raw["telemetry"]["avg_span_bytes"] * 86400

    profile_samples_per_sec = raw["services"] * raw["telemetry"]["profile_sampling_hz"]
    profile_bytes_per_day = (
        profile_samples_per_sec * raw["telemetry"]["avg_profile_bytes_per_sample"] * 86400
    )

    series_total = raw["services"] * 5000  # rough series-per-service after label drops
    pyro_series_total = raw["services"] * 1000  # function-level samples
    pyro_cpu = (
        pyro_series_total / 1_000_000
        * raw["pyroscope"]["ingester_cpu_cores_per_1m_series"]
        * raw["pyroscope"]["replication_factor"]
    )
    pyro_mem = (
        pyro_series_total / 1_000_000
        * raw["pyroscope"]["ingester_mem_gib_per_1m_series"]
        * raw["pyroscope"]["replication_factor"]
    )
    pyro_disk_gb = (
        profile_bytes_per_day / 1024**3
        * raw["pyroscope"]["storage_retention_days"]
        * raw["pyroscope"]["replication_factor"]
    )

    # ── Monthly costs ────────────────────────────────────────────────
    cost = {
        "beyla_cpu":   cpu_h    * raw["cpu_price_per_core_hour"],
        "beyla_mem":   mem_h    * raw["mem_price_per_gib_hour"],
        "pyro_cpu":    pyro_cpu * 730 * raw["cpu_price_per_core_hour"],
        "pyro_mem":    pyro_mem * 730 * raw["mem_price_per_gib_hour"],
        "pyro_disk":   pyro_disk_gb * raw["managed_disk_price_per_gb_month"],
        "egress":      (span_bytes_per_day + profile_bytes_per_day) / 1024**3
                       * 30 * raw["egress_price_per_gb"] * 0.1,  # 10% crosses region/internet
    }
    cost["total_monthly_usd"] = sum(cost.values())

    return {
        "env": env_name,
        "inputs": {
            "nodes": raw["nodes"],
            "services": raw["services"],
            "rps_total": rps_total,
            "trace_sampling": raw["telemetry"]["trace_sampling_ratio"],
        },
        "capacity": {
            "span_gb_per_day": round(span_bytes_per_day / 1024**3, 2),
            "profile_gb_per_day": round(profile_bytes_per_day / 1024**3, 2),
            "pyro_ingester_cpu_cores": round(pyro_cpu, 1),
            "pyro_ingester_mem_gib":   round(pyro_mem, 1),
            "pyro_disk_gb":            round(pyro_disk_gb, 0),
        },
        "cost_monthly_usd": {k: round(v, 2) for k, v in cost.items()},
        "cost_annual_usd": round(cost["total_monthly_usd"] * 12, 2),
    }


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--inputs", required=True)
    p.add_argument("--env", default="prod")
    p.add_argument("--json", action="store_true")
    args = p.parse_args()

    with open(args.inputs) as fh:
        cfg = yaml.safe_load(fh)

    envs = list(cfg["environments"].keys()) if args.env == "all" else [args.env]
    results = []
    for env in envs:
        merged = merge(cfg["defaults"], cfg["environments"][env])
        results.append(project(env, merged))

    if args.json:
        print(json.dumps(results, indent=2))
        return

    for r in results:
        print(f"\n═══ {r['env']} ═══")
        print(f"  nodes={r['inputs']['nodes']}  services={r['inputs']['services']}  rps={r['inputs']['rps_total']}")
        print(f"  span data:    {r['capacity']['span_gb_per_day']} GB/day")
        print(f"  profile data: {r['capacity']['profile_gb_per_day']} GB/day")
        print(f"  Pyroscope:    {r['capacity']['pyro_ingester_cpu_cores']} CPU / "
              f"{r['capacity']['pyro_ingester_mem_gib']} GiB / "
              f"{r['capacity']['pyro_disk_gb']} GB disk")
        print(f"  cost breakdown (USD/month):")
        for k, v in r["cost_monthly_usd"].items():
            print(f"    {k:18s} ${v:>10,.2f}")
        print(f"  ANNUAL:       ${r['cost_annual_usd']:>10,.2f}")


if __name__ == "__main__":
    main()
