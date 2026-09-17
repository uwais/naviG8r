import { expect, test } from "@playwright/test";

test("operations shell does not embed sensitive data and explains authorization", async ({ page }) => {
  await page.goto("/ops");
  await expect(page).toHaveTitle("NaviG8r operations");
  await expect(page.getByRole("heading", { name: "NaviG8r operations" })).toBeVisible();
  const source = await page.content();
  expect(source).not.toContain("accountNumber");
  expect(source).not.toContain("payoutFundAccountId");
  expect(source).toContain("Payment releases require shipper acceptance or expiry");
});

test("shipment workflow shell keeps POD work available without admin controls", async ({ page }) => {
  await page.goto("/workflow");
  await expect(page).toHaveTitle("NaviG8r shipments");
  await expect(page.getByRole("heading", { name: "NaviG8r shipments" })).toBeVisible();
  const source = await page.content();
  expect(source).toContain("Accept POD");
  expect(source).toContain("const workflowOnly = true");
});
