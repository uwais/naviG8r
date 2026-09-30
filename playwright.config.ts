import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "./apps/api/playwright",
  timeout: 30_000,
  use: {
    baseURL: "http://127.0.0.1:3139",
    headless: true,
    channel: process.env.PLAYWRIGHT_CHANNEL || undefined,
  },
  webServer: {
    command:
      "OTP_PHONE_START_LIMIT=1000 OTP_IP_START_LIMIT=1000 RBAC_MANUAL_PORT=3139 node --experimental-strip-types scripts/rbac-manual.mjs",
    url: "http://127.0.0.1:3139/health",
    reuseExistingServer: false,
    timeout: 30_000,
  },
});
