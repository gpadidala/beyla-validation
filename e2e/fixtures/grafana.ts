import { test as base, expect, APIRequestContext, Page } from "@playwright/test";

// ─── Shared types ───────────────────────────────────────────────────────────

export type GrafanaAPI = {
  /** Raw GET against /api with auth + JSON parsing. */
  get<T = unknown>(path: string): Promise<T>;
  /** POST a Prometheus-style PromQL via Grafana datasource proxy. */
  promQuery(query: string, dsUid?: string): Promise<PromResult>;
  /** Pyroscope flame-graph fetch via Grafana datasource proxy. */
  profileExists(query: string, dsUid?: string): Promise<boolean>;
  /** Tempo TraceQL search via Grafana datasource proxy. */
  traceSearch(traceql: string, dsUid?: string): Promise<{ traces: unknown[] }>;
};

export type PromResult = {
  status: "success" | "error";
  data: { resultType: string; result: Array<{ metric: Record<string, string>; value: [number, string] }> };
};

// ─── Fixtures ───────────────────────────────────────────────────────────────

type Fixtures = {
  grafanaUrl: string;
  loggedIn: Page;
  grafana: GrafanaAPI;
};

export const test = base.extend<Fixtures>({
  grafanaUrl: [process.env.GRAFANA_URL ?? "http://localhost:3000", { option: true }],

  // Log in to Grafana once per test. With anonymous auth (local dev) this
  // is a no-op; with basic auth it submits the login form.
  loggedIn: async ({ page, grafanaUrl }, use) => {
    await page.goto(grafanaUrl);

    const user = process.env.GRAFANA_USER;
    const pass = process.env.GRAFANA_PASS;
    if (user && pass) {
      // Wait for the login form. Grafana 12 uses data-testid attributes.
      const userInput = page.getByTestId("data-testid Username input field");
      if (await userInput.isVisible({ timeout: 5000 }).catch(() => false)) {
        await userInput.fill(user);
        await page.getByTestId("data-testid Password input field").fill(pass);
        await page.getByTestId("data-testid Login button").click();
        // Skip the "Change password" prompt if it appears.
        const skip = page.getByText("Skip", { exact: true });
        if (await skip.isVisible({ timeout: 3000 }).catch(() => false)) await skip.click();
      }
    }

    await expect(page).toHaveURL(/.*\/(?:\?orgId=1)?$|.*\/dashboards|.*\/d\/|.*\/explore.*/, { timeout: 15000 });
    await use(page);
  },

  // Grafana HTTP API client — uses the same auth as the browser context.
  grafana: async ({ request, grafanaUrl }, use) => {
    const auth = await buildAuth(request, grafanaUrl);
    const api: GrafanaAPI = {
      async get(path) {
        const r = await request.get(`${grafanaUrl}${path}`, { headers: auth });
        expect(r.ok(), `${path} → HTTP ${r.status()}`).toBeTruthy();
        return r.json();
      },
      async promQuery(query, dsUid = "prometheus") {
        const r = await request.get(`${grafanaUrl}/api/datasources/proxy/uid/${dsUid}/api/v1/query`, {
          headers: auth,
          params: { query },
        });
        expect(r.ok(), `promQuery(${query}) → HTTP ${r.status()}`).toBeTruthy();
        return r.json() as Promise<PromResult>;
      },
      async profileExists(query, dsUid = "pyroscope") {
        const now = Date.now();
        const r = await request.get(`${grafanaUrl}/api/datasources/proxy/uid/${dsUid}/api/v1/query`, {
          headers: auth,
          params: {
            query,
            from: String(now - 5 * 60_000),
            until: String(now),
          },
        });
        if (!r.ok()) return false;
        const body = await r.json();
        return (body?.flamebearer?.numTicks ?? 0) > 0;
      },
      async traceSearch(traceql, dsUid = "tempo") {
        const r = await request.get(`${grafanaUrl}/api/datasources/proxy/uid/${dsUid}/api/search`, {
          headers: auth,
          params: { q: traceql, limit: "20" },
        });
        if (!r.ok()) return { traces: [] };
        const body = await r.json();
        return { traces: body?.traces ?? [] };
      },
    };
    await use(api);
  },
});

async function buildAuth(request: APIRequestContext, grafanaUrl: string): Promise<Record<string, string>> {
  if (process.env.GRAFANA_TOKEN) return { Authorization: `Bearer ${process.env.GRAFANA_TOKEN}` };
  const user = process.env.GRAFANA_USER;
  const pass = process.env.GRAFANA_PASS;
  if (user && pass) return { Authorization: "Basic " + Buffer.from(`${user}:${pass}`).toString("base64") };
  // Anonymous (local dev)
  return {};
}

export { expect };
