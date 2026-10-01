import { defineConfig } from "@playwright/test";

// The /ops/beta browser tests get their own seeded server. They approve a carrier and release the one
// ready shipment, which apps/api/playwright/dashboard.spec.ts also releases; on the shared server of
// playwright.config.ts the two files would race for it. One worker: these tests change the data in order.
export default defineConfig({
  testDir: "./apps/api/playwright-ops-beta",
  timeout: 30_000,
  workers: 1,
  use: {
    baseURL: "http://127.0.0.1:3143",
    headless: true,
    channel: process.env.PLAYWRIGHT_CHANNEL || undefined,
    viewport: { width: 1280, height: 1000 },
  },
  webServer: {
    command: "OTP_PHONE_START_LIMIT=1000 OTP_IP_START_LIMIT=1000 RBAC_MANUAL_PORT=3143 node --experimental-strip-types scripts/rbac-manual.mjs",
    url: "http://127.0.0.1:3143/health",
    reuseExistingServer: false,
    timeout: 30_000,
  },
});
