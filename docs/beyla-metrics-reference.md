# Beyla metrics — canonical reference

**Source of truth:** [grafana.com/docs/beyla/latest/metrics](https://grafana.com/docs/beyla/latest/metrics/) and the official dashboard [grafana.com/grafana/dashboards/19923](https://grafana.com/grafana/dashboards/19923-beyla-red-metrics/).

Every dashboard, alert, validation script, and PromQL query in this repo MUST use the metric names below. If you add a new query, check this table first — invented metric names produce silently broken dashboards.

## Naming quirk: `_seconds` suffix

Beyla emits histograms under **two names** for cross-compatibility:

| Format | Name |
|--------|------|
| OTel (default) | `http_server_request_duration_seconds_bucket` |
| Prom-style (older) | `http_server_request_duration_bucket` |

Always match both with this regex pattern in queries:

```promql
{__name__=~"http_server_request_duration_seconds_bucket|http_server_request_duration_bucket"}
```

The official dashboard does this everywhere — we follow the same convention.

## Application metrics

| Metric | Type | Direction | Notes |
|-------|------|-----------|-------|
| `http_server_request_duration_seconds` | histogram | inbound HTTP | RED golden |
| `http_server_request_body_size_bytes` | histogram | inbound HTTP | |
| `http_server_response_body_size_bytes` | histogram | inbound HTTP | |
| `http_client_request_duration_seconds` | histogram | outbound HTTP | RED golden |
| `http_client_request_body_size_bytes` | histogram | outbound HTTP | |
| `http_client_response_body_size_bytes` | histogram | outbound HTTP | |
| `rpc_server_duration_seconds` | histogram | inbound gRPC | |
| `rpc_client_duration_seconds` | histogram | outbound gRPC | |
| `db_client_operation_duration_seconds` | histogram | DB client | SQL / Mongo / Redis |
| `messaging_publish_duration` | histogram | producer | Kafka / RabbitMQ |
| `messaging_process_duration` | histogram | consumer | Kafka / RabbitMQ |

## Process metrics (per-process, requires `process` feature)

| Metric | Type |
|-------|------|
| `process_cpu_time_seconds_total` | counter |
| `process_cpu_utilization_ratio` | gauge |
| `process_memory_usage_bytes` | gauge (UpDownCounter) |
| `process_memory_virtual_bytes` | gauge |
| `process_disk_io_bytes_total` | counter |
| `process_network_io_bytes_total` | counter |

## Network metrics (requires `network` feature)

| Metric | Type |
|-------|------|
| `beyla_network_flow_bytes` | counter |
| `beyla_network_inter_zone_bytes` | counter |

## Beyla self-metrics

| Metric | Type | What it tells you |
|-------|------|-------------------|
| `beyla_internal_build_info` | gauge | one series per running Beyla, labels include version + revision |
| `beyla_instrumented_processes` | gauge | how many PIDs Beyla is currently attached to |
| `beyla_instrumentation_errors_total` | counter | uprobe/kprobe attach failures — use this for "Beyla can't load" alert |
| `beyla_ebpf_tracer_flushes` | histogram | how often the eBPF ringbuf is flushed; spike = backpressure |
| `beyla_otel_metric_exports_total` | counter | successful metric exports |
| `beyla_otel_metric_export_errors_total` | counter | failed metric exports — alert if non-zero |
| `beyla_otel_trace_exports_total` | counter | successful span exports |
| `beyla_otel_trace_export_errors_total` | counter | failed span exports — alert if non-zero |
| `beyla_prometheus_http_requests_total` | counter | hits on Beyla's `/metrics` endpoint |

## Canonical labels

| Label | Source |
|------|--------|
| `service_name` | from process / OTel resource |
| `service_namespace` | from OTel resource (rare) |
| `k8s_namespace_name` | from kubernetes attributes (when enabled) |
| `k8s_pod_name` | from kubernetes attributes |
| `k8s_deployment_name` | from kubernetes attributes |
| `http_route` | from Beyla route discovery (use `unmatched: heuristic`) |
| `http_request_method` | GET/POST/... |
| `http_response_status_code` | 200/4xx/5xx |
| `rpc_method` | gRPC method name |
| `rpc_grpc_status_code` | 0–16 (0 = OK) |
| `cluster` | added by Alloy `external_labels` |
| `instance`, `job` | standard scrape labels |

## Metrics that DO NOT exist (common mistakes)

These names look plausible but Beyla **never emits them**. If you see them in a query, fix it:

| Wrong name | Correct alternative |
|-----------|---------------------|
| `beyla_otel_traces_total` | `beyla_otel_trace_exports_total` |
| `beyla_otel_traces_failed_total` | `beyla_otel_trace_export_errors_total` |
| `beyla_otel_traces_dropped_total` | (does not exist — drops aren't directly exposed) |
| `beyla_otel_traces_sampled_total` | (compute from sampler config, not a metric) |
| `beyla_build_info` | `beyla_internal_build_info` |
| `beyla_ebpf_programs_loaded_total` | `beyla_instrumented_processes` |
| `beyla_ebpf_program_load_failures_total` | `beyla_instrumentation_errors_total` |
| `beyla_export_queue_size` / `_capacity` | (does not exist — use `beyla_ebpf_tracer_flushes` histogram) |
| `beyla_telemetry_dropped_total` | (does not exist) |
| `beyla_telemetry_retry_total` | (does not exist) |

## Reference dashboard

We vendor the official Grafana dashboard as [`dashboards/beyla-red-official.json`](../dashboards/beyla-red-official.json) — its panels are the canonical example of correct query construction. When in doubt, copy a panel from there and modify it.
