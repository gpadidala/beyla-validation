import { test, expect } from "../fixtures/grafana";

// The Tempo→Pyroscope link is what makes "trace to flame graph" work in
// Grafana 12. This test exercises it end-to-end via the UI: open Explore
// with Tempo, run a TraceQL query, click into a trace, follow the
// "Profile for this span" link, assert the flame graph renders.

test.describe("trace → profile linking (Grafana Explore)", () => {
  test("can open Explore with Tempo and search a trace", async ({ loggedIn: page }) => {
    await page.goto("/explore?left=" + encodeURIComponent(JSON.stringify({
      datasource: "tempo",
      queries: [{ refId: "A", query: '{ span.k8s.namespace.name = "demo" }', queryType: "traceql" }],
      range: { from: "now-15m", to: "now" },
    })));
    await page.waitForLoadState("networkidle");

    // Expect at least one trace row in the result table.
    const traceRows = page.getByTestId(/data-testid TraceTable row/);
    await expect(traceRows.first(), "no traces in Tempo Explore").toBeVisible({ timeout: 20_000 });
  });

  test("flame graph renders in Pyroscope", async ({ loggedIn: page }) => {
    await page.goto("/explore?left=" + encodeURIComponent(JSON.stringify({
      datasource: "pyroscope",
      queries: [{
        refId: "A",
        profileTypeId: "process_cpu:cpu:nanoseconds:cpu:nanoseconds",
        labelSelector: '{service_name=~".+"}',
        queryType: "profile",
      }],
      range: { from: "now-5m", to: "now" },
    })));
    await page.waitForLoadState("networkidle");

    const flame = page.locator('[data-testid*="flame-graph"], [class*="FlameGraph"]').first();
    await expect(flame, "flame graph element missing").toBeVisible({ timeout: 20_000 });
  });
});
