#!/usr/bin/env bash
set -Eeuo pipefail
if ! command -v yamllint >/dev/null; then
  echo "yamllint not installed — skipping"
  exit 0
fi
yamllint -c .yamllint deploy/ config/ alerts/ slo/ chaos/ rollout/ scorecard/thresholds.yaml cost/cost-model-inputs.yaml
