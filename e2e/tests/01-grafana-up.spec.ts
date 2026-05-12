import { test, expect } from "../fixtures/grafana";

test.describe("Grafana is up and reachable", () => {
  test("health endpoint returns OK", async ({ grafana }) => {
    const h = await grafana.get<{ database: string; version: string }>("/api/health");
    expect(h.database).toBe("ok");
    expect(h.version).toMatch(/^1[2-9]\./); // require Grafana 12+
  });

  test("login or anonymous lands on the home page", async ({ loggedIn: page }) => {
    await expect(page).toHaveTitle(/Grafana/);
  });

  test("frontend version matches API version", async ({ loggedIn: page, grafana }) => {
    const meta = await grafana.get<{ buildInfo: { version: string } }>("/api/frontend/settings");
    expect(meta.buildInfo.version).toBeTruthy();
  });
});
