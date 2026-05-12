import { test, expect } from "../fixtures/grafana";

// Talk directly to the Alloy HTTP API (port 12345) to validate the
// component graph — independently of whatever Grafana shows.
const ALLOY_URL = process.env.ALLOY_URL ?? "http://localhost:12345";

test.describe("Alloy pipeline health", () => {
  test("Alloy /-/ready returns 200", async ({ request }) => {
    const r = await request.get(`${ALLOY_URL}/-/ready`);
    expect(r.status()).toBe(200);
  });

  test("beyla.ebpf component is loaded and healthy", async ({ request }) => {
    const r = await request.get(`${ALLOY_URL}/api/v0/web/components`);
    expect(r.ok()).toBeTruthy();
    const components = (await r.json()) as Array<{ module_id?: string; local_id?: string; health: { state: string } }>;

    const beyla = components.find(
      (c) => c.local_id === "beyla.ebpf/default" || c.module_id === "beyla.ebpf/default",
    );
    expect(beyla, "beyla.ebpf/default component not found in Alloy").toBeTruthy();
    expect(beyla!.health.state, "beyla.ebpf/default is unhealthy").toBe("healthy");
  });

  test("pyroscope.ebpf component is healthy", async ({ request }) => {
    const r = await request.get(`${ALLOY_URL}/api/v0/web/components`);
    const components = (await r.json()) as Array<{ local_id?: string; health: { state: string } }>;
    const pyro = components.find((c) => c.local_id === "pyroscope.ebpf/default");
    expect(pyro?.health.state).toBe("healthy");
  });

  test("all exporters are healthy", async ({ request }) => {
    const r = await request.get(`${ALLOY_URL}/api/v0/web/components`);
    const components = (await r.json()) as Array<{ local_id?: string; health: { state: string } }>;
    const exporters = components.filter(
      (c) =>
        c.local_id?.startsWith("otelcol.exporter.") ||
        c.local_id?.startsWith("prometheus.remote_write") ||
        c.local_id?.startsWith("pyroscope.write"),
    );
    expect(exporters.length, "no exporters discovered").toBeGreaterThan(0);
    for (const e of exporters) {
      expect(e.health.state, `${e.local_id} is unhealthy`).toBe("healthy");
    }
  });

  test("config last loaded successfully", async ({ grafana }) => {
    const r = await grafana.promQuery("alloy_config_last_load_success_timestamp_seconds");
    expect(r.status).toBe("success");
    const ts = Number(r.data.result[0]?.value?.[1] ?? 0);
    expect(ts, "Alloy config last-load timestamp is zero — reload failed").toBeGreaterThan(0);
  });

  test("no exporter is dropping data", async ({ grafana }) => {
    const r = await grafana.promQuery(
      "sum(rate(otelcol_exporter_send_failed_spans_total[5m])) + sum(rate(otelcol_exporter_send_failed_metric_points_total[5m]))",
    );
    const v = Number(r.data.result[0]?.value?.[1] ?? 0);
    expect(v, "Alloy exporter send failures > 0/s").toBeLessThanOrEqual(0);
  });
});
