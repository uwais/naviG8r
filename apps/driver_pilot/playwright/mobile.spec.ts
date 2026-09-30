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
  await page.evaluate(
    () =>
      new Promise((resolve) =>
        requestAnimationFrame(() => requestAnimationFrame(() => resolve(null))),
      ),
  );
  await phoneInput.fill(phone);
  await expect(phoneInput).toHaveValue(phone);
  const otpResponse = await Promise.all([
    page.waitForResponse(
      (response) =>
        response.url().endsWith("/v1/auth/otp/start") &&
        response.request().method() === "POST",
    ),
    page
      .getByRole("button", { name: "Send code", exact: true })
      .evaluate((element: HTMLElement) => element.click()),
  ]);
  const otp = await otpResponse[0].json();
  expect(otp.debugCode).toMatch(/^\d{6}$/);
  if (otp.debugCode) {
    await expect(
      page
        .locator("flt-semantics-host")
        .getByText(`Debug OTP: ${otp.debugCode}`, { exact: true }),
    ).toBeVisible();
  }
  await page.waitForTimeout(1400);
  await page.screenshot({
    path: test.info().outputPath("otp-customer-login.png"),
  });
  await Promise.all([
    page.waitForResponse(
      (response) =>
        response.url().endsWith("/v1/auth/me") && response.status() === 200,
    ),
    page
      .getByRole("button", { name: "Verify and continue", exact: true })
      .evaluate((element: HTMLElement) => element.click()),
  ]);
  await expect(
    page.getByRole("button", { name: "Verify and continue", exact: true }),
  ).toHaveCount(0);
}

test("shipper accepts own POD from a mobile viewport", async ({ page }) => {
  await signIn(page, "8000000001");

  await page.goto("/#/customer/shipments/load-a-hold");
  await expect(
    page.getByRole("group", { name: /Payment on hold/ }),
  ).toBeVisible();
  await page
    .getByRole("button", { name: "Accept delivery", exact: true })
    .evaluate((element: HTMLElement) => element.click());
  await page
    .getByRole("alertdialog")
    .getByRole("button", { name: "Accept delivery", exact: true })
    .evaluate((element: HTMLElement) => element.click());
  await expect(
    page.locator("flt-semantics-host").getByText(/Delivery accepted/),
  ).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Accept delivery", exact: true }),
  ).toHaveCount(0);
});

test("dual membership requires selection and keeps Finance out of shipper workspace", async ({
  page,
}) => {
  await signIn(page, "8000000008");
  await expect(
    page
      .locator("flt-semantics-host")
      .getByText("Choose an organization above to continue.", {
        exact: true,
      }),
  ).toBeVisible();
  await page
    .getByRole("button", { name: /Choose organization/ })
    .evaluate((element: HTMLElement) => element.click());
  await page
    .getByRole("menuitem", { name: "Synthetic Shipper A", exact: true })
    .evaluate((element: HTMLElement) => element.click());
  await expect(
    page.getByRole("button", { name: /Synthetic Shipper A/ }),
  ).toBeVisible();
  await page
    .getByRole("button", { name: /Synthetic Shipper A/ })
    .evaluate((element: HTMLElement) => element.click());
  await page
    .getByRole("menuitem", {
      name: "Synthetic NaviG8r Internal",
      exact: true,
    })
    .evaluate((element: HTMLElement) => element.click());
  await expect(
    page
      .locator("flt-semantics-host")
      .getByText("Internal workspace", { exact: true }),
  ).toBeVisible();
  await expect(
    page
      .locator("flt-semantics-host")
      .getByText("My shipments", { exact: true }),
  ).toHaveCount(0);
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

test("driver starts one generated challenge without exposing it in the URL", async ({
  page,
}, info) => {
  await page.route(/https:\/\/(?!127\.0\.0\.1|localhost)/, (route) =>
    route.abort(),
  );
  let starts = 0;
  page.on("request", (request) => {
    if (
      request.url().endsWith("/v1/auth/otp/start") &&
      request.method() === "POST"
    )
      starts++;
  });
  await page.goto("/#/driver/onboarding/phone");
  await semantics(page);
  const phone = page.getByRole("textbox", { name: "Mobile number" });
  await phone.click();
  await page.evaluate(
    () =>
      new Promise((resolve) =>
        requestAnimationFrame(() => requestAnimationFrame(() => resolve(null))),
      ),
  );
  await phone.fill("8000000003");
  const started = page.waitForResponse(
    (r) =>
      r.url().endsWith("/v1/auth/otp/start") && r.request().method() === "POST",
  );
  await page
    .getByRole("button", { name: "Send code", exact: true })
    .evaluate((e: HTMLElement) => e.click());
  const challenge = await (await started).json();
  expect(challenge.debugCode).toMatch(/^\d{6}$/);
  await expect(page).toHaveURL(/#\/driver\/onboarding\/otp\?phone=8000000003$/);
  expect(starts).toBe(1);
  expect(page.url()).not.toContain(challenge.challengeId);
  expect(page.url()).not.toContain("debugCode");
  await page.waitForTimeout(1200);
  await page.screenshot({ path: info.outputPath("otp-driver-challenge.png") });
});
