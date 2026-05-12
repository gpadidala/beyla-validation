// Single source of truth for which dashboards exist and what we expect
// to see when they're working. Each entry's uid matches the JSON file
// committed under ../dashboards/.

export type DashboardSpec = {
  uid: string;
  title: string;
  /** Panel titles we expect to render with data. */
  requiredPanels: string[];
  /** PromQL we expect to return at least 1 result after the stack is warm. */
  smokeQuery?: string;
};

export const DASHBOARDS: DashboardSpec[] = [
  {
    uid: "beyla-health",
    title: "Beyla • Health",
    requiredPanels: ["DaemonSet ready %", "Pods running", "Beyla CPU per pod", "Beyla memory working set"],
    smokeQuery: "count(up{job=~\"alloy|beyla\"})",
  },
  {
    uid: "alloy-health",
    title: "Alloy • Pipeline Health",
    requiredPanels: [
      "Alloy pods running",
      "Components healthy %",
      "Pipeline throughput — metrics out",
      "Pipeline throughput — traces out",
    ],
    smokeQuery: "sum(alloy_component_controller_running_components)",
  },
  {
    uid: "beyla-app-delta",
    title: "Beyla • Application Latency Δ vs Baseline",
    requiredPanels: ["Worst Δ P99 vs baseline", "P99 latency by service (current vs baseline)"],
    smokeQuery: "sum(rate(http_server_request_duration_seconds_count[5m]))",
  },
  {
    uid: "beyla-kernel",
    title: "Beyla • Kernel & eBPF",
    requiredPanels: ["System CPU % per node", "Context switches / sec"],
  },
  {
    uid: "beyla-pyroscope",
    title: "Beyla • Pyroscope Pipeline",
    requiredPanels: ["Ingest (MB/s)", "Active series", "Write failures /s"],
  },
  {
    uid: "beyla-network",
    title: "Beyla • Network Impact",
    requiredPanels: ["TCP retransmit rate %", "Service-graph P99"],
  },
  {
    uid: "beyla-scorecard",
    title: "Beyla • Rollout Scorecard",
    requiredPanels: ["Application impact score", "OVERALL — GO if ≥ 80"],
  },
  {
    uid: "beyla-meta-obs",
    title: "Beyla • Cost of Observability",
    requiredPanels: ["Beyla CPU burn % of cluster", "Beyla mem burn % of cluster"],
  },
];
