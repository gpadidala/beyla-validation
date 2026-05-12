import { test, expect } from "../fixtures/grafana";

// End-to-end data-flow assertions.
// Beyla (inside Alloy) ─► Prometheus / Tempo / Pyroscope ─► Grafana.
// If any link is broken, exactly one of these tests fails — pinpointing the
// failure to a stage.

test.describe("Alloy + Beyla → LGTM data flow", () => {
  test("Beyla is up (RED metrics are flowing)", async ({ grafana }) => {
    const r = await grafana.promQuery("sum(rate(http_server_request_duration_seconds_count[1m]))");
    expect(r.status).toBe("success");
    const v = Number(r.data.result[0]?.value?.[1] ?? 0);
    expect(v, "Beyla request count is zero — Beyla isn't seeing app traffic").toBeGreaterThan(0);
  });

  test("Alloy is up and exporting", async ({ grafana }) => {
    const r = await grafana.promQuery('count(up{job="alloy"} == 1)');
    expect(r.status).toBe("success");
    expect(Number(r.data.result[0]?.value?.[1] ?? 0)).toBeGreaterThan(0);
  });

  test("Prometheus is receiving samples from Alloy", async ({ grafana }) => {
    const r = await grafana.promQuery("rate(prometheus_remote_storage_samples_in_total[5m])");
    expect(Number(r.data.result[0]?.value?.[1] ?? 0)).toBeGreaterThan(0);
  });

  test("Tempo is receiving spans from Alloy", async ({ grafana }) => {
    // tempo_distributor_spans_received_total is exposed by Tempo's own /metrics
    const r = await grafana.promQuery("sum(rate(tempo_distributor_spans_received_total[5m]))");
    const v = Number(r.data.result[0]?.value?.[1] ?? 0);
    expect(v, "Tempo received zero spans in the last 5m").toBeGreaterThan(0);
  });

  test("Pyroscope is receiving profiles", async ({ grafana }) => {
    const has = await grafana.profileExists(
      'process_cpu:cpu:nanoseconds:cpu:nanoseconds{service_name=~".+"}',
    );
    expect(has, "no fresh CPU profiles found in Pyroscope in last 5m").toBeTruthy();
  });

  test("Tempo has searchable traces for instrumented services", async ({ grafana }) => {
    const { traces } = await grafana.traceSearch('{ span.k8s.namespace.name = "demo" }');
    expect(traces.length, "no traces found for namespace=demo").toBeGreaterThan(0);
  });

  test("service graph metric exists (Beyla emits it)", async ({ grafana }) => {
    const r = await grafana.promQuery("sum(rate(traces_service_graph_request_total[5m]))");
    expect(r.status).toBe("success");
    // service graph may be 0 in early seconds — accept zero but require the metric to exist
    expect(r.data.result.length, "traces_service_graph_request_total metric absent").toBeGreaterThan(0);
  });
});
