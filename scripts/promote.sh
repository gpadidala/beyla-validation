#!/usr/bin/env bash
# Promote from one environment to the next, gated by the latest scorecard.
# Refuses to promote if score < environment threshold or scorecard missing.
set -Eeuo pipefail
ENV="${1:?usage: promote.sh <canary|staging|prod>}"

next_env() {
  case "$1" in
    canary)  echo staging ;;
    staging) echo prod ;;
    prod)    echo "" ;;
    *)       echo "" ;;
  esac
}

NEXT="$(next_env "$ENV")"
[[ -z "$NEXT" ]] && { echo "no environment after $ENV"; exit 1; }

# Find latest scorecard for current env
latest=$(ls -td reports/"$ENV"/* 2>/dev/null | head -1 || true)
[[ -z "$latest" ]] && { echo "no scorecard for $ENV — run 'make validate ENV=$ENV && make scorecard ENV=$ENV'"; exit 1; }

python3 scorecard/scorecard.py --reports "$latest" --thresholds scorecard/thresholds.yaml --env "$ENV" --json > /tmp/sc.json
verdict=$(jq -r '.verdict' /tmp/sc.json)
score=$(jq -r '.overall'  /tmp/sc.json)

echo "Scorecard for $ENV: $verdict ($score / 100)"
if [[ "$verdict" == "NO-GO" ]]; then
  echo "Refusing to promote — NO-GO verdict."
  exit 2
fi
if [[ "$verdict" == "GO-WITH-REMEDIATION" ]]; then
  printf 'Verdict is GO-WITH-REMEDIATION. Type PROMOTE to continue: '
  read -r ans
  [[ "$ans" == "PROMOTE" ]] || { echo "aborted"; exit 1; }
fi

echo "Promoting $ENV → $NEXT"
make install ENV="$NEXT"
