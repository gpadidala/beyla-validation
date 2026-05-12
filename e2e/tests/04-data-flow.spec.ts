import { test, expect } from "../fixtures/grafana";

// End-to-end data-flow assertions.
// Beyla (inside Alloy) ─► Prometheus / Tempo / Pyroscope ─► Grafana.
// If any link is broken, exactly one of these tests fails — pinpointing
// the failure to a stage.
//
// All Beyla metric names verified against
// grafana.com/docs/beyla/latest/metrics.

test.describe("Alloy + Beyla → LGTM data flow", () => {
  test("Beyla is up (RED metrics flowing)", async ({ grafana }) => {
    const r = await grafana.promQuery(
      'sum(rate({__name__=~"http_server_request_duration_seconds_count|http_server_request_duration_count"}[1m]))',
    );
    expect(r.status).toBe("success");
    const v = Number(r.data.result[0]?.value?.[1] ?? 0);
    expect(v, "Beyla request count is zero — Beyla isn't seeing app traffic").toBeGreaterThan(0);
  });

  test("Beyla is instrumenting at least one process", async ({ grafana }) => {
    const r = await grafana.promQuery("sum(beyla_instrumented_processes)");
    const v = Number(r.data.result[0]?.value?.[1] ?? 0);
    expect(v, "beyla_instrumented_processes == 0 — discovery not finding pods").toBeGreaterThan(0);
  });

  test("Beyla is exporting traces", async ({ grafana }) => {
    const r = await grafana.promQuery("sum(rate(beyla_otel_trace_exports_total[5m]))");
    const v = Number(r.data.result[0]?.value?.[1] ?? 0);
    expect(v, "beyla_otel_trace_exports_total rate is zero").toBeGreaterThan(0);
  });

  test("Beyla trace export error ratio < 1%", async ({ grafana }) => {
    const r = await grafana.promQuery(
      "sum(rate(beyla_otel_trace_export_errors_total[5m])) / clamp_min(sum(rate(beyla_otel_trace_exports_total[5m])), 1)",
    );
    const v = Number(r.data.result[0]?.value?.[1] ?? 0);
    expect(v, `trace export error ratio = ${v}`).toBeLessThan(0.01);
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
    const { traces } = await grafana.traceSearch('{ span.service.name =~ ".+" }');
    expect(traces.length, "no traces found in Tempo").toBeGreaterThan(0);
  });
});
