import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "./apps/api/playwright",
  timeout: 30_000,
  use: { baseURL: "http://127.0.0.1:3139", headless: true },
  webServer: {
    command: "AUTH_SECRET=synthetic-playwright-secret NODE_ENV=test DATA_FILE=/private/tmp/navig8r-playwright.json PORT=3139 node --experimental-strip-types apps/api/src/index.ts",
    url: "http://127.0.0.1:3139/health",
    reuseExistingServer: false,
    timeout: 30_000,
  },
});
