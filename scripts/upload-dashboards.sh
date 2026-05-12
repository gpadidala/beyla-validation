#!/usr/bin/env bash
# Upload all dashboards/*.json to a Grafana instance via API.
# Required: GRAFANA_URL (e.g. https://grafana.example.com), GRAFANA_TOKEN (service account token).
set -Eeuo pipefail
: "${GRAFANA_URL:?set GRAFANA_URL}"
: "${GRAFANA_TOKEN:?set GRAFANA_TOKEN}"

for f in dashboards/*.json; do
  echo "▶ $f"
  body=$(jq -n --argjson d "$(cat "$f")" '{dashboard: $d, overwrite: true, folderUid: "beyla"}')
  curl -fsS -X POST "${GRAFANA_URL}/api/dashboards/db" \
    -H "Authorization: Bearer ${GRAFANA_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$body" \
    | jq -r '"  uploaded: \(.url)"'
done
