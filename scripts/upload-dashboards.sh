#!/usr/bin/env bash
# Upload all dashboards/*.json to a Grafana instance via API.
# Required: GRAFANA_URL (e.g. https://grafana.example.com), GRAFANA_TOKEN.
# Optional: INSECURE=1 → curl -k (skip TLS verification, for self-signed certs).
set -Eeuo pipefail
: "${GRAFANA_URL:?set GRAFANA_URL}"
: "${GRAFANA_TOKEN:?set GRAFANA_TOKEN}"

CURL_FLAGS="-fsS"
if [[ "${INSECURE:-0}" == "1" ]]; then
  CURL_FLAGS="$CURL_FLAGS -k"
  echo "WARNING: INSECURE=1 — TLS verification disabled" >&2
fi

for f in dashboards/*.json; do
  echo "▶ $f"
  body=$(jq -n --argjson d "$(cat "$f")" '{dashboard: $d, overwrite: true, folderUid: "beyla"}')
  curl $CURL_FLAGS -X POST "${GRAFANA_URL}/api/dashboards/db" \
    -H "Authorization: Bearer ${GRAFANA_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$body" \
    | jq -r '"  uploaded: \(.url)"'
done
