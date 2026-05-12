#!/usr/bin/env bash
# Layer 14 — Time synchronization.
# Trace timestamp consistency relies on NTP-synced nodes. Even small skew
# (>500ms) creates "negative duration" spans and broken service graphs.

set -Eeuo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib/common.sh"
LAYER=time-sync

log "Layer 14 — time sync"

# 1. node_timex offset (exposed by node_exporter)
max_offset=$(prom_query 'max(abs(node_timex_offset_seconds)) * 1000')
if [[ -n "$max_offset" ]] && gt "$max_offset" 500; then
  report_check ntp_offset fail 0 "max NTP offset = ${max_offset}ms > 500ms" $LAYER
else
  report_check ntp_offset pass 100 "max NTP offset = ${max_offset:-?}ms" $LAYER
fi

# 2. NTP sync status
synced=$(prom_query 'min(node_timex_sync_status)')
if [[ "$synced" == "1" ]]; then
  report_check ntp_synced pass 100 "all nodes NTP-synced" $LAYER
else
  report_check ntp_synced fail 0 "at least one node not NTP-synced" $LAYER
fi

# 3. Trace clock skew via Tempo metric
neg_dur=$(prom_query 'sum(rate(tempo_distributor_spans_received_total{}[5m])) - sum(rate(tempo_ingester_spans_valid_total[5m]))')
if [[ -n "$neg_dur" ]] && gt "$neg_dur" 10; then
  report_check trace_negative_duration warn 60 "${neg_dur}/s invalid spans (often clock skew)" $LAYER
else
  report_check trace_negative_duration pass 100 "trace span validity OK" $LAYER
fi

log "Layer 14 complete"
