import { expect, test, type Page } from "@playwright/test";

async function semantics(page: Page) {
  const placeholder = page.locator("flt-semantics-placeholder");
  await placeholder.waitFor({ state: "attached" });
  await placeholder.evaluate((element: HTMLElement) => element.click());
}

async function signIn(page: Page, phone: string) {
  // Tests use local renderer assets and never contact maps/payment providers.
  await page.route(/https:\/\/(?!127\.0\.0\.1|localhost)/, (route) =>
    route.abort(),
  );
  await page.goto("/#/customer/login");
  await semantics(page);
  const phoneInput = page.getByRole("textbox", { name: "Mobile number" });
  await phoneInput.click();
  await expect(phoneInput).toBeFocused();
  // Flutter connects its editing state on the next rendered frame after focus.
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(() => resolve(null)))));
  await phoneInput.fill(phone);
  await expect(phoneInput).toHaveValue(phone);
  await Promise.all([
    page.waitForResponse(
      (response) =>
        response.url().endsWith("/v1/auth/otp/start") &&
        response.request().method() === "POST",
    ),
    page.getByRole("button", { name: "Send code", exact: true }).click(),
  ]);
  await expect(
    page.getByText("Debug OTP: 123456", { exact: true }),
  ).toBeVisible();
  await Promise.all([
    page.waitForResponse(response => response.url().endsWith("/v1/auth/me") && response.status() === 200),
    page.getByRole("button", { name: "Verify and continue", exact: true }).click(),
  ]);
  await expect(page.getByRole("button", { name: "Verify and continue", exact: true })).toHaveCount(0);
}

test("shipper accepts own POD from a mobile viewport", async ({ page }) => {
  await signIn(page, "8000000001");

  await page.goto("/#/customer/shipments/load-a-hold");
  await expect(page.getByRole("group", { name: /Payment on hold/ })).toBeVisible();
  await page
    .getByRole("button", { name: "Accept delivery", exact: true })
    .click();
  await page
    .getByRole("alertdialog")
    .getByRole("button", { name: "Accept delivery", exact: true })
    .click();
  await expect(page.getByText(/Delivery accepted/)).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Accept delivery", exact: true }),
  ).toHaveCount(0);
});

test("dual membership requires selection and keeps Finance out of shipper workspace", async ({
  page,
}) => {
  await signIn(page, "8000000008");
  await expect(
    page.getByText("Choose an organization above to continue.", {
      exact: true,
    }),
  ).toBeVisible();
  await page.getByRole("button", { name: /Choose organization/ }).click();
  await page
    .getByRole("menuitem", { name: "Synthetic Shipper A", exact: true })
    .click();
  await expect(
    page.getByRole("button", { name: /Synthetic Shipper A/ }),
  ).toBeVisible();
  await page.getByRole("button", { name: /Synthetic Shipper A/ }).click();
  await page
    .getByRole("menuitem", {
      name: "Synthetic NaviG8r Internal",
      exact: true,
    })
    .click();
  await expect(
    page.getByText("Internal workspace", { exact: true }),
  ).toBeVisible();
  await expect(page.getByText("My shipments", { exact: true })).toHaveCount(0);
});

test("driver cannot open owner payout form through a deep link", async ({
  page,
}) => {
  await signIn(page, "8000000009");
  await expect(
    page.getByRole("button", { name: "Synthetic Carrier A", exact: true }),
  ).toBeVisible();
  await page.goto("/#/driver/payout-setup");
  await expect(page).toHaveURL(/#\/driver$/);
  await expect(
    page.getByRole("textbox", { name: "Bank account number" }),
  ).toHaveCount(0);
});
