import { test, expect } from "../fixtures/grafana";
import { DASHBOARDS } from "../fixtures/dashboards";

// For every dashboard in dashboards/, we:
//  1. confirm it is provisioned (the API returns metadata for the uid)
//  2. open it in the browser, wait for panels to render
//  3. assert each required panel is present
//  4. assert no required panel shows the "No data" placeholder
//  5. capture a screenshot for visual review
//
// Optional dashboards (gRPC, DB, process, network-flows) are skipped if
// their smokeQuery returns 0 — those panels depend on Beyla features
// that may not be enabled in every environment.

test.describe("dashboards render with data", () => {
  for (const d of DASHBOARDS) {
    test(`${d.uid} — ${d.title}`, async ({ loggedIn: page, grafana }) => {
      // Optional dashboards: skip if the underlying data simply isn't there.
      if (d.optional && d.smokeQuery) {
        const probe = await grafana.promQuery(d.smokeQuery);
        const v = Number(probe.data.result[0]?.value?.[1] ?? 0);
        if (v === 0) {
          test.skip(true, `optional dashboard — smoke query returned 0 (feature not enabled in this env)`);
        }
      }

      // 1. API check
      const meta = await grafana.get<{ dashboard: { title: string }; meta: { url: string } }>(
        `/api/dashboards/uid/${d.uid}`,
      );
      expect(meta.dashboard.title).toBe(d.title);

      // 2. Navigate and wait for the dashboard to render.
      await page.goto(meta.meta.url);
      await page.waitForLoadState("networkidle");

      // Wait for panels to actually finish querying.
      await page.waitForFunction(
        () =>
          !document.querySelector('[data-testid="data-testid Panel header"][aria-busy="true"]') &&
          document.querySelectorAll('[data-testid="data-testid Panel header"]').length > 0,
        null,
        { timeout: 20_000 },
      );

      // 3. Required panels present
      for (const title of d.requiredPanels) {
        const panel = page.getByTestId(/data-testid Panel header/).filter({ hasText: title });
        await expect(panel.first(), `panel "${title}" not found in ${d.uid}`).toBeVisible();
      }

      // 4. No "No data" on required panels
      for (const title of d.requiredPanels) {
        const noData = page
          .locator(`[data-testid^="data-testid Panel header"]:has-text("${title}")`)
          .locator("xpath=ancestor::*[contains(@class,'panel-container')]")
          .getByText(/no data/i);
        await expect(noData, `panel "${title}" shows No data`).toHaveCount(0);
      }

      // 5. Screenshot for visual diff / archive
      await page.screenshot({
        path: `screenshots/${d.uid}.png`,
        fullPage: true,
        animations: "disabled",
      });

      // 6. Optional: smoke-query the data source the dashboard depends on.
      if (d.smokeQuery && !d.optional) {
        const r = await grafana.promQuery(d.smokeQuery);
        expect(r.status).toBe("success");
      }
    });
  }
});
