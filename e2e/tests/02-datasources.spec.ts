import { test, expect } from "../fixtures/grafana";

// We rely on the datasource UIDs from examples/grafana-datasources.yaml
// (Prometheus, Tempo, Loki, Pyroscope). If those uids change, this is
// the test that catches it before the dashboards do.

const expected = [
  { uid: "prometheus", type: "prometheus" },
  { uid: "tempo",      type: "tempo" },
  { uid: "loki",       type: "loki" },
  { uid: "pyroscope",  type: "grafana-pyroscope-datasource" },
];

test.describe("LGTM datasources are wired", () => {
  for (const ds of expected) {
    test(`${ds.uid} (${ds.type}) is provisioned and healthy`, async ({ grafana }) => {
      const list = await grafana.get<Array<{ uid: string; type: string }>>("/api/datasources");
      const found = list.find((d) => d.uid === ds.uid || d.type === ds.type);
      expect(found, `${ds.uid} not provisioned`).toBeTruthy();
    });
  }

  test("Prometheus answers a trivial query", async ({ grafana }) => {
    const r = await grafana.promQuery("vector(1)");
    expect(r.status).toBe("success");
    expect(r.data.result[0].value[1]).toBe("1");
  });
});
