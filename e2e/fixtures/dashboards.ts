// Single source of truth for which dashboards exist and what we expect
// to see when they're working. Each entry's uid matches a JSON file
// committed under ../dashboards/.
//
// All metric names are verified against grafana.com/docs/beyla/latest/metrics.
// See ../../docs/beyla-metrics-reference.md for the canonical list.

export type DashboardSpec = {
  uid: string;
  title: string;
  /** Panel titles we expect to render with data. */
  requiredPanels: string[];
  /** PromQL we expect to return at least 1 result after the stack is warm. */
  smokeQuery?: string;
  /** Set to true if the dashboard requires an optional Beyla feature (network/process/grpc/db). */
  optional?: boolean;
};

export const DASHBOARDS: DashboardSpec[] = [
  {
    uid: "alloy-health",
    title: "Alloy • Pipeline Health",
    requiredPanels: ["Alloy pods running", "Components healthy %"],
    smokeQuery: "sum(alloy_component_controller_running_components)",
  },
  {
    uid: "beyla-health",
    title: "Beyla • Health",
    requiredPanels: [
      "Beyla pods (or Alloy-with-Beyla)",
      "Processes instrumented (cluster total)",
      "OTel export throughput",
    ],
    smokeQuery: "count(beyla_internal_build_info)",
  },
  {
    uid: "beyla-red-official",
    title: "Beyla • RED Metrics (official, 19923)",
    requiredPanels: ["Slowest HTTP routes (P95)", "Duration", "Request rate", "Error rate"],
    smokeQuery:
      'sum(rate({__name__=~"http_server_request_duration_seconds_count|http_server_request_duration_count"}[5m]))',
  },
  {
    uid: "beyla-app-delta",
    title: "Beyla • Application Latency Δ vs Baseline",
    requiredPanels: ["Worst Δ P99 vs baseline", "P99 server latency — current vs baseline"],
    smokeQuery:
      'sum(rate({__name__=~"http_server_request_duration_seconds_count|http_server_request_duration_count"}[5m]))',
  },
  {
    uid: "beyla-grpc",
    title: "Beyla • gRPC RED",
    requiredPanels: ["Duration P50/P95/P99 — gRPC server"],
    smokeQuery:
      'count({__name__=~"rpc_server_duration_seconds_count|rpc_server_duration_count"})',
    optional: true,
  },
  {
    uid: "beyla-database",
    title: "Beyla • Database Client",
    requiredPanels: ["DB P50/P95/P99 by service"],
    smokeQuery:
      'count({__name__=~"db_client_operation_duration_seconds_count|db_client_operation_duration_count"})',
    optional: true,
  },
  {
    uid: "beyla-process",
    title: "Beyla • Process Metrics",
    requiredPanels: ["CPU utilization ratio per service", "Resident memory per service"],
    smokeQuery: "count(process_cpu_utilization_ratio)",
    optional: true,
  },
  {
    uid: "beyla-network-flows",
    title: "Beyla • Network Flows (eBPF)",
    requiredPanels: ["Flow throughput (cluster total)"],
    smokeQuery: "sum(rate(beyla_network_flow_bytes[5m]))",
    optional: true,
  },
  {
    uid: "beyla-kernel",
    title: "Beyla • Kernel & eBPF",
    requiredPanels: ["System CPU % per node", "Context switches / sec"],
  },
  {
    uid: "beyla-pyroscope",
    title: "Beyla • Pyroscope Pipeline",
    requiredPanels: ["Ingest (MB/s)", "Active series"],
  },
  {
    uid: "beyla-network",
    title: "Beyla • Network Impact",
    requiredPanels: ["TCP retransmit rate %"],
  },
  {
    uid: "beyla-scorecard",
    title: "Beyla • Rollout Scorecard",
    requiredPanels: ["Application impact score", "OVERALL — GO if ≥ 80"],
  },
  {
    uid: "beyla-meta-obs",
    title: "Beyla • Cost of Observability",
    requiredPanels: ["Beyla CPU % of cluster"],
  },
];
