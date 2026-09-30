import { expect, test } from "@playwright/test";

test("operations shell does not embed sensitive data and explains authorization", async ({
  page,
}) => {
  await page.goto("/ops");
  await expect(page).toHaveTitle("NaviG8r · Operations workspace");
  await expect(
    page.getByRole("heading", { name: "Operations workspace" }),
  ).toBeVisible();
  const source = await page.content();
  expect(source).not.toContain("accountNumber");
  expect(source).not.toContain("payoutFundAccountId");
  expect(source).toContain(
    "Payment releases require shipper acceptance or expiry",
  );
});

test("shipment workflow shell keeps POD work available without admin controls", async ({
  page,
}) => {
  await page.goto("/workflow");
  await expect(page).toHaveTitle("NaviG8r shipments");
  await expect(
    page.getByRole("heading", { name: "NaviG8r shipments" }),
  ).toBeVisible();
  const source = await page.content();
  expect(source).toContain("Accept POD");
  expect(source).toContain("const workflowOnly = true");
});

test("OTP start replaces stale code and accepts generated leading-zero debug codes", async ({
  page,
}) => {
  let starts = 0;
  await page.route("**/v1/auth/otp/start", async (route) => {
    starts += 1;
    await route.fulfill({
      json: {
        challengeId: `otp_${starts}`,
        expiresAtUtcMs: Date.now() + 600000,
        ...(starts === 1 ? { debugCode: "012304" } : {}),
      },
    });
  });
  await page.goto("/ops");
  await page.locator("#phone").fill("9111009900");
  await page.locator("#start").click();
  await expect(page.locator("#code")).toHaveValue("012304");
  await page.locator("#start").click();
  await expect(page.locator("#code")).toHaveValue("");
});

test("OTP start preserves a manually entered code when the challenge is unchanged", async ({ page }) => {
  await page.route("**/v1/auth/otp/start", (route) =>
    route.fulfill({
      json: { challengeId: "otp_same", expiresAtUtcMs: Date.now() + 600000, retryAfterMs: 0 },
    }),
  );
  await page.goto("/ops");
  await page.locator("#phone").fill("9111009900");
  await page.locator("#start").click();
  await expect(page.locator("#start")).toHaveText("Resend code");
  await page.locator("#code").fill("654321");
  await page.locator("#start").click();
  await expect(page.locator("#code")).toHaveValue("654321");
});

test("OTP start throttling preserves the current challenge and code and shows a countdown", async ({ page }) => {
  let starts = 0;
  await page.route("**/v1/auth/otp/start", (route) =>
    route.fulfill(starts++ === 0
      ? { json: { challengeId: "otp_current", expiresAtUtcMs: Date.now() + 600000, debugCode: "012304" } }
      : { status: 429, json: { error: "otp_rate_limited", retryAfterMs: 30000 } }),
  );
  await page.goto("/ops");
  await page.locator("#phone").fill("9111009900");
  await page.locator("#start").click();
  await expect(page.locator("#start")).toHaveText("Resend code");
  await page.locator("#start").click({ force: true });
  await expect(page.locator("#code")).toHaveValue("012304");
  await expect(page.locator("#error")).toContainText("30 seconds");
  await expect(page.locator("#start")).toHaveText(/Resend code \(30s\)/);
  await expect(page.locator("#start")).toBeDisabled();
});

test("changing the OTP phone resets the challenge and countdown", async ({ page }) => {
  let releaseResponse!: () => void;
  const responseGate = new Promise<void>((resolve) => { releaseResponse = resolve; });
  await page.route("**/v1/auth/otp/start", async (route) => {
    await responseGate;
    await route.fulfill({ status: 429, json: { error: "otp_rate_limited", retryAfterMs: 30000 } });
  });
  await page.goto("/ops");
  await page.locator("#phone").fill("9111009900");
  await page.locator("#start").click();
  await page.locator("#phone").fill("9111009901");
  releaseResponse();
  await expect(page.locator("#start")).toHaveText("Send code");
  await expect(page.locator("#start")).toBeEnabled();
  await expect(page.locator("#error")).toBeEmpty();
});

test("OTP verify sends the current leading-zero code and explains expired or incorrect responses", async ({
  page,
}) => {
  let submitted: unknown;
  await page.route("**/v1/auth/otp/start", (route) =>
    route.fulfill({
      json: {
        challengeId: "otp_current",
        expiresAtUtcMs: Date.now() + 600000,
        debugCode: "012304",
      },
    }),
  );
  await page.route("**/v1/auth/otp/verify", async (route) => {
    submitted = JSON.parse(route.request().postData() || "{}");
    await route.fulfill({ status: 400, json: { error: "otp_expired" } });
  });
  await page.goto("/ops");
  await page.locator("#phone").fill("9111009900");
  await page.locator("#start").click();
  await page.locator("#verify").click();
  await expect(page.locator("#error")).toContainText("expired");
  expect(submitted).toEqual({
    phone: "9111009900",
    challengeId: "otp_current",
    code: "012304",
  });

  await page.unroute("**/v1/auth/otp/verify");
  await page.route("**/v1/auth/otp/verify", (route) =>
    route.fulfill({ status: 400, json: { error: "otp_incorrect" } }),
  );
  await page.locator("#verify").click();
  await expect(page.locator("#error")).toContainText("incorrect");
});

for (const viewport of [
  { width: 1280, height: 900 },
  { width: 390, height: 844 },
]) {
  test(`generated OTP signs in through the real API at ${viewport.width}px`, async ({
    page,
  }, info) => {
    await page.setViewportSize(viewport);
    await page.goto("/ops");
    await page.locator("#phone").fill("8000000005");
    const response = page.waitForResponse(
      (r) =>
        r.url().endsWith("/v1/auth/otp/start") &&
        r.request().method() === "POST",
    );
    await page.locator("#start").click();
    const challenge = await (await response).json();
    expect(challenge.debugCode).toMatch(/^\d{6}$/);
    await expect(page.locator("#code")).toHaveValue(challenge.debugCode);
    await page.screenshot({
      path: info.outputPath("generated-otp-login.png"),
      fullPage: true,
    });
    await page.locator("#verify").click();
    await expect(page.locator("#workspace")).toBeVisible();
    await expect(page.locator("#roles")).toContainText("OPS");
    await expect(page.locator("#error")).toBeEmpty();
    await page.screenshot({
      path: info.outputPath("generated-otp-signed-in.png"),
      fullPage: true,
    });
  });
}
