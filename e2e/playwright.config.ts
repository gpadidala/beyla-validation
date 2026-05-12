import { defineConfig, devices } from "@playwright/test";

// Default target = local docker-compose stack. Override for cluster runs:
//   GRAFANA_URL=https://grafana.example.com   GRAFANA_USER=admin   GRAFANA_PASS=... npm test
const GRAFANA_URL = process.env.GRAFANA_URL ?? "http://localhost:3000";

export default defineConfig({
  testDir: "./tests",
  fullyParallel: false,                 // dashboard tests share state; serial is safer
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : 2,
  timeout: 60_000,
  expect: {
    timeout: 15_000,
    toMatchSnapshot: { maxDiffPixelRatio: 0.02 },
  },
  reporter: [
    ["list"],
    ["html", { outputFolder: "reports/html", open: "never" }],
    ["json", { outputFile: "reports/results.json" }],
    ["junit", { outputFile: "reports/junit.xml" }],
  ],
  use: {
    baseURL: GRAFANA_URL,
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
    video: "retain-on-failure",
    actionTimeout: 15_000,
    navigationTimeout: 30_000,
    ignoreHTTPSErrors: true,
    extraHTTPHeaders: process.env.GRAFANA_TOKEN
      ? { Authorization: `Bearer ${process.env.GRAFANA_TOKEN}` }
      : {},
  },
  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"], viewport: { width: 1600, height: 1000 } },
    },
  ],
  // Bring up the docker-compose stack automatically if we're running locally.
  webServer: process.env.SKIP_WEBSERVER
    ? undefined
    : {
        command: "cd .. && docker compose up -d && bash e2e/scripts/wait-for-grafana.sh",
        url: `${GRAFANA_URL}/api/health`,
        reuseExistingServer: true,
        timeout: 180_000,
        stdout: "pipe",
        stderr: "pipe",
      },
});
