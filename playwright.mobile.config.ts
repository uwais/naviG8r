import { existsSync } from "node:fs";
import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "./apps/driver_pilot/playwright",
  outputDir: "/private/tmp/navig8r-mobile-rbac-results",
  workers: 1,
  timeout: 60_000,
  use: {
    baseURL: "http://127.0.0.1:8087",
    channel:
      process.env.RBAC_BROWSER_CHANNEL ??
      (existsSync(
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
      )
        ? "chrome"
        : "chromium"),
    viewport: { width: 390, height: 844 },
  },
  webServer: [
    {
      command:
        "RBAC_MANUAL_PORT=3140 node --experimental-strip-types scripts/rbac-manual.mjs",
      url: "http://127.0.0.1:3140/health",
      reuseExistingServer: false,
    },
    {
      command: "node scripts/serve-mobile-rbac.mjs",
      url: "http://127.0.0.1:8087",
      reuseExistingServer: false,
    },
  ],
});
