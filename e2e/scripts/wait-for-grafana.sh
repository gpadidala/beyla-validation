#!/usr/bin/env bash
# Block until Grafana, Prometheus, Tempo, Pyroscope are reachable AND
# Alloy has had time to push at least one metric.
set -Eeuo pipefail

GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
ALLOY_URL="${ALLOY_URL:-http://localhost:12345}"

CURL_FLAGS="-fsS"
[[ "${INSECURE:-0}" == "1" ]] && CURL_FLAGS="$CURL_FLAGS -k"

deadline=$(( $(date +%s) + 180 ))

probe() {
  local name="$1" url="$2" expect="${3:-200}"
  until curl $CURL_FLAGS -o /dev/null -w '%{http_code}' "$url" 2>/dev/null | grep -q "^${expect}$"; do
    if (( $(date +%s) > deadline )); then
      echo "TIMEOUT waiting for ${name} (${url})" >&2
      exit 1
    fi
    sleep 2
  done
  echo "✓ ${name} ready"
}

probe Grafana    "${GRAFANA_URL}/api/health"
probe Prometheus "http://localhost:9090/-/ready"
probe Tempo      "http://localhost:13200/ready"
probe Pyroscope  "http://localhost:4040/ready"
probe Alloy      "${ALLOY_URL}/-/ready"

# Wait for one full Prometheus scrape interval so dashboards have data.
echo "warming up: 20s for first metrics scrape…"
sleep 20
echo "stack ready"
