import { test, expect, type Page } from "@playwright/test";

test.describe.configure({ mode: "serial" });
async function sendOtp(page: Page, expectDebugCode = true) {
  const started = page.waitForResponse(
    (response) =>
      response.url().endsWith("/v1/auth/otp/start") &&
      response.request().method() === "POST",
  );
  await page.locator("#send-otp, #start").first().click();
  const challenge = await (await started).json();
  expect(challenge.challengeId).toEqual(expect.any(String));
  if (expectDebugCode) expect(challenge.debugCode).toMatch(/^\d{6}$/);
  if (challenge.debugCode === undefined) {
    await expect(page.locator("#code")).toHaveValue("");
  } else {
    await expect(page.locator("#code")).toHaveValue(challenge.debugCode);
  }
  return challenge;
}
async function login(page: Page, phone: string, path = "/admin/v1") {
  await page.goto(path);
  await page.getByLabel("Phone number", { exact: true }).fill(phone);
  await sendOtp(page);
  await page.getByRole("button", { name: "Sign in", exact: true }).click();
  await expect(page.locator("#protected")).toBeVisible();
}
async function screenshot(page: Page, name: string, fullPage = true) {
  const path = test.info().outputPath(name + ".png");
  await page.screenshot({ path, fullPage });
  await test.info().attach(name, { path, contentType: "image/png" });
}
function action(page: Page, name: string) {
  return page
    .locator("form")
    .filter({ has: page.getByRole("heading", { name, exact: true }) });
}

for (const width of [1440, 390, 320]) {
  test(`V2 shares the blue dashboard header at ${width}px before and after login`, async ({
    page,
  }) => {
    await page.setViewportSize({ width, height: 844 });
    await page.goto("/admin/v1");
    const v1Header = page.getByRole("banner");
    const background = await v1Header.evaluate(
      (element) => getComputedStyle(element).backgroundColor,
    );
    const headingFontSize = await page
      .locator("#workspace h1")
      .evaluate((element) => getComputedStyle(element).fontSize);
    await screenshot(page, "header-v1-login", false);

    async function checkHeader(workspace: "admin" | "ops") {
      const heading =
        workspace === "ops" ? "Operations workspace" : "Full dashboard";
      await expect(page.getByRole("heading", { level: 1 })).toHaveText(heading);
      await expect(page.getByRole("heading", { level: 1 })).toHaveCSS(
        "font-size",
        headingFontSize,
      );
      await expect(page).toHaveTitle(`NaviG8r · ${heading}`);
      const header = page.getByRole("banner");
      await expect(header).toHaveCSS("background-color", background);
      await expect(header.locator("strong")).toHaveText("NaviG8r");
      await expect(header).toContainText("Operations & administration · V2");
      const links = header.getByRole("link");
      await expect(links).toHaveCount(2);
      await expect(links.nth(0)).toHaveAttribute("href", `/${workspace}/v1`);
      await expect(links.nth(1)).toHaveAttribute("href", "/workflow");
      await expect(links.nth(0)).toHaveCSS("color", "rgb(213, 233, 255)");
      const bounds = await header.boundingBox();
      expect(bounds?.x).toBe(0);
      expect(bounds?.y).toBe(0);
      expect(bounds?.width).toBe(
        await page.evaluate(() => document.documentElement.clientWidth),
      );
      for (const link of await links.all()) {
        await expect(link).toBeVisible();
        const box = await link.boundingBox();
        expect(box!.x).toBeGreaterThanOrEqual(0);
        expect(box!.x + box!.width).toBeLessThanOrEqual(width);
      }
      expect(
        await page.evaluate(
          () => document.documentElement.scrollWidth <= innerWidth,
        ),
      ).toBe(true);
    }

    for (const path of ["/admin", "/ops", "/admin/v2", "/ops/v2"]) {
      await page.goto(path);
      await expect(page.locator("#login")).toBeVisible();
      await checkHeader(path.startsWith("/ops") ? "ops" : "admin");
    }
    await screenshot(page, "header-v2-login", false);
    await page.locator("#phone").fill("8000000011");
    await sendOtp(page);
    await page.getByRole("button", { name: "Sign in", exact: true }).click();
    await expect(page.locator("#workspace")).toBeVisible();
    await expect(page.locator("#roles")).toContainText("FINANCE");
    await expect(page.locator("#roleManagement")).toBeVisible();
    await expect(page.locator("#compliance")).toBeVisible();
    await page.evaluate(() => scrollTo(0, 0));
    await checkHeader("ops");
    await screenshot(page, "header-v2-signed-in", false);
    await screenshot(page, "header-v2-full-page");
    for (const workspace of ["ops", "admin"] as const) {
      await page.goto(`/${workspace}/v2`);
      await expect(page.locator("#roles")).toContainText("FINANCE");
      await checkHeader(workspace);
      await screenshot(page, `headings-${workspace}-v2`, false);
      await page
        .getByRole("link", { name: "Open full dashboard (V1)" })
        .click();
      await expect(page).toHaveURL(`/${workspace}/v1`);
      await expect(page.locator("#protected")).toBeVisible();
      await expect(
        page.getByRole("heading", {
          level: 1,
          name: workspace === "ops" ? "Operations workspace" : "Full dashboard",
          exact: true,
        }),
      ).toBeVisible();
      await expect(page.locator("#organization")).toHaveValue("platform");
      await expect(page.locator("#roles")).toContainText("FINANCE");
      await screenshot(page, `headings-${workspace}-v1`, false);
      await page.getByRole("link", { name: "Compact dashboard (V2)" }).click();
      await expect(page).toHaveURL(`/${workspace}/v2`);
      await expect(page.locator("#organization")).toHaveValue("platform");
      await expect(page.locator("#roles")).toContainText("FINANCE");
      await checkHeader(workspace);
    }
  });
}

test("V1 full layout restores all sections for combined roles and retains V2", async ({
  page,
}) => {
  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.goto("/admin/v1");
  await screenshot(page, "01-v1-login");
  await login(page, "8000000011");
  for (const name of [
    "Carriers",
    "Organizations",
    "Users",
    "Memberships",
    "Vehicles",
    "Driver profiles",
    "Anchor trips",
    "Shipments",
    "Ledger lines",
    "Payout batches",
  ]) {
    await page.getByRole("button", { name, exact: true }).click();
    await expect(page.locator("#table-title")).toHaveText(name);
    await screenshot(page, "02-section-" + name.replaceAll(" ", "-"));
  }
  await page.getByRole("button", { name: "Carriers", exact: true }).click();
  await expect(
    page.getByRole("button", { name: "Previous", exact: true }),
  ).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Next", exact: true }),
  ).toBeVisible();
  await page.getByLabel("Search records").fill("Synthetic Carrier A");
  await page.getByRole("button", { name: "Search", exact: true }).click();
  await expect(page.locator("#count")).toHaveText("1 records");
  await page.getByRole("button", { name: "View", exact: true }).click();
  await expect(page.locator("#record")).toContainText("carrier-a");
  await page
    .getByRole("button", { name: "Assistance members", exact: true })
    .click();
  await page
    .getByLabel("Target organization ID", { exact: true })
    .first()
    .fill("shipper-a");
  await page.getByRole("button", { name: "Search", exact: true }).click();
  await expect(page.locator("#table")).toContainText("user-shipper-a");
  await page.getByRole("button", { name: "Carriers", exact: true }).click();
  for (const label of [
    "Origin latitude",
    "Origin longitude",
    "Destination latitude",
    "Destination longitude",
  ])
    await expect(
      action(page, "Publish trip").getByLabel(label, { exact: true }),
    ).toBeVisible();
  for (const label of [
    "Pickup latitude",
    "Pickup longitude",
    "Drop latitude",
    "Drop longitude",
  ])
    await expect(
      action(page, "Book shipment").getByLabel(label, { exact: true }),
    ).toBeVisible();
  await screenshot(page, "03-v1-desktop-full");
  await page.getByRole("link", { name: "Compact dashboard (V2)" }).click();
  await expect(
    page.getByRole("heading", { name: "Full dashboard", exact: true }),
  ).toBeVisible();
  await expect(page.locator("#roles")).toContainText("FINANCE");
  await expect(
    page.getByRole("heading", { name: "Carrier compliance review" }),
  ).toBeVisible();
  await screenshot(page, "04-v2-preserved");
  await page.getByRole("link", { name: "Open full dashboard (V1)" }).click();
  await expect(page.locator("#roles")).toContainText("ADMIN");
  await page.setViewportSize({ width: 390, height: 844 });
  await screenshot(page, "05-v1-mobile");
  await screenshot(page, "05-v1-mobile-viewport", false);
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  ).toBe(true);
});

test("single roles and cross-organization sessions expose only authorized tools", async ({
  page,
}) => {
  for (const [phone, present, absent] of [
    ["8000000007", "Set internal roles", "Release payment"],
    ["8000000005", "Publish trip", "Set internal roles"],
    ["8000000006", "Release payment", "Publish trip"],
  ]) {
    await page.goto("/admin/v1");
    await page.evaluate(() => sessionStorage.clear());
    await login(page, phone);
    await expect(action(page, present)).toBeVisible();
    await expect(action(page, absent)).toHaveCount(0);
    await screenshot(page, "06-role-" + phone.slice(-1));
  }
  await page.evaluate(() => sessionStorage.clear());
  await page.goto("/admin/v1");
  await page.getByLabel("Phone number", { exact: true }).fill("8000000008");
  await sendOtp(page);
  await page.getByRole("button", { name: "Sign in", exact: true }).click();
  await page.getByLabel("Acting organization").selectOption("platform");
  await expect(action(page, "Release payment")).toBeVisible();
  await page.getByLabel("Acting organization").selectOption("shipper-a");
  await expect(page.locator("#protected")).toBeHidden();
  await expect(page.locator("#table")).toBeEmpty();
  await screenshot(page, "07-external-membership");
});

test("V1 onboarding and compliance persist into V2 with explicit review", async ({
  page,
}) => {
  await login(page, "8000000011");
  page.on("dialog", (d) => d.accept());
  const f = action(page, "Create carrier");
  await f.getByLabel("Carrier name").fill("Synthetic Dashboard Fleet <test>");
  await f.getByLabel("Existing owner user ID").fill("user-carrier-a");
  await f.getByLabel("Reason code").fill("PILOT_ONBOARDING");
  await f.getByRole("button").click();
  await expect(page.locator("#notice")).toContainText(
    "Create carrier completed",
  );
  await expect(page.locator("#queue")).toContainText(
    "Synthetic Dashboard Fleet <test>",
  );
  await screenshot(page, "08-carrier-created");
  await page.getByLabel("Review reason code").fill("DOCUMENTS_REVIEWED");
  const row = page
    .locator(".review-row")
    .filter({ hasText: "Synthetic Dashboard Fleet <test>" });
  await row.getByRole("button", { name: "Approve", exact: true }).click();
  await expect(page.locator("#notice")).toContainText("is now APPROVED");
  await expect(row).toHaveCount(0);
  await screenshot(page, "09-carrier-approved");
  await page.goto("/ops/v2");
  await expect(page.locator("#kycQueue")).not.toContainText(
    "Synthetic Dashboard Fleet <test>",
  );
  await expect(page.locator("#kycQueue")).toContainText("Synthetic Carrier B");
  await screenshot(page, "10-v2-compliance");
});

test("POD hold is enforced in V1 and release appears in the delivered view", async ({
  page,
}) => {
  await login(page, "8000000006", "/ops/v1");
  page.on("dialog", (d) => d.accept());
  const f = action(page, "Release payment");
  await f.getByLabel("Shipment ID").fill("load-a-hold");
  await f.getByLabel("Reason code").fill("POD_REVIEWED");
  await f.getByRole("button").click();
  await expect(page.locator("#error")).toContainText("payment_hold_active");
  await screenshot(page, "11-payment-hold");
  // The API returns 403 for an active hold; refresh the principal before retrying.
  await page.getByRole("button", { name: "Refresh access" }).click();
  await f.getByLabel("Shipment ID").fill("load-a-expired");
  await f.getByLabel("Reason code").fill("HOLD_EXPIRED");
  await f.getByRole("button").click();
  await expect(page.locator("#notice")).toContainText(
    "Release payment completed",
  );
  await page.getByRole("button", { name: "Recently delivered" }).click();
  await expect(page.locator("#table")).toContainText("load-a-expired");
  await screenshot(page, "12-recently-delivered");
});

test("V1 assisted publish, booking and POD forms execute with attribution", async ({
  page,
}) => {
  await login(page, "8000000005");
  page.on("dialog", (d) => d.accept());
  const publish = action(page, "Publish trip");
  for (const [label, value] of [
    ["Carrier organization ID", "carrier-a"],
    ["Represented member user ID", "user-carrier-a"],
    ["Origin city", "Synthetic A"],
    ["Destination city", "Synthetic B"],
    ["Window start (ISO)", "2026-10-01T09:00:00+05:30"],
    ["Window end (ISO)", "2026-10-02T09:00:00+05:30"],
    ["Capacity (kg)", "500"],
    ["Reason code", "CARRIER_REQUEST"],
  ])
    await publish.getByLabel(label, { exact: true }).fill(value);
  await publish.getByRole("button").click();
  await expect(page.locator("#notice")).toContainText("Publish trip completed");
  const tripId = (await page.locator("#notice").innerText())
    .trim()
    .split(" ")
    .at(-1)!;
  await screenshot(page, "13-trip-published");
  const booking = action(page, "Book shipment");
  for (const [label, value] of [
    ["Customer organization ID", "shipper-a"],
    ["Represented member user ID", "user-shipper-a"],
    ["Anchor trip ID", tripId],
    ["Weight (kg)", "10"],
    ["Pickup address", "Synthetic pickup"],
    ["Drop address", "Synthetic drop"],
    ["Reason code", "CUSTOMER_REQUEST"],
  ])
    await booking.getByLabel(label, { exact: true }).fill(value);
  await booking.getByRole("button").click();
  await expect(page.locator("#notice")).toContainText(
    "Book shipment completed",
  );
  await screenshot(page, "14-assisted-booking");
  const pod = action(page, "Submit POD");
  await pod.getByLabel("Shipment ID").fill("load-a-booked");
  await pod.getByLabel("Represented member user ID").fill("user-carrier-a");
  await pod.getByLabel("Reason code").fill("DELIVERY_CONFIRMED");
  await pod.getByRole("button").click();
  await expect(page.locator("#notice")).toContainText("Submit POD completed");
  await screenshot(page, "15-assisted-pod");
});

test("V2 shipper POD acceptance and finance release still work after V1 submission", async ({
  page,
}) => {
  await page.goto("/workflow");
  await page.getByLabel("Phone", { exact: true }).fill("8000000001");
  await sendOtp(page);
  await page.getByRole("button", { name: "Sign in", exact: true }).click();
  const row = page.locator("article").filter({ hasText: "load-a-booked" });
  await row.getByRole("button", { name: "Accept POD" }).click();
  await expect(row).toContainText("Ready for payment release");
  await screenshot(page, "16-shipper-acceptance");
  await page.evaluate(() => sessionStorage.clear());
  await page.goto("/ops/v2");
  await page.getByLabel("Phone", { exact: true }).fill("8000000006");
  await sendOtp(page);
  await page.getByRole("button", { name: "Sign in", exact: true }).click();
  const financeRow = page
    .locator("article")
    .filter({ hasText: "load-a-booked" });
  await financeRow.getByRole("button", { name: "Release payment" }).click();
  await expect(financeRow).toHaveCount(0);
  await screenshot(page, "17-v2-payment-release");
});

test("V1 administration, refund and payout forms preserve their role boundaries", async ({
  page,
}) => {
  await login(page, "8000000011");
  page.on("dialog", (d) => d.accept());
  const access = action(page, "Set internal roles");
  await access.getByLabel("Registered user ID").fill("user-member");
  await access.getByLabel("Roles (comma separated)").fill("OPS");
  await access.getByLabel("Reason code").fill("ACCESS_REVIEW");
  await access.getByRole("button").click();
  await expect(page.locator("#notice")).toContainText(
    "Set internal roles completed",
  );
  await screenshot(page, "18-internal-role-grant");
  const roles = action(page, "Set membership roles");
  await roles.getByLabel("User ID", { exact: true }).fill("user-member");
  await roles.getByLabel("Target organization ID").fill("platform");
  await roles.getByLabel("Reason code").fill("ACCESS_REVOKED");
  await roles.getByRole("button").click();
  await expect(page.locator("#notice")).toContainText(
    "Set membership roles completed",
  );
  const deactivate = action(page, "Deactivate user");
  await deactivate.getByLabel("User ID", { exact: true }).fill("user-member");
  await deactivate.getByLabel("Reason code").fill("ACCOUNT_CLOSED");
  await deactivate.getByRole("button").click();
  await expect(page.locator("#notice")).toContainText(
    "Deactivate user completed",
  );
  await screenshot(page, "19-user-deactivated");
  const refund = action(page, "Fail and refund");
  await refund.getByLabel("Shipment ID").fill("load-b-pending");
  await refund.getByLabel("Reason code").fill("CARRIER_FAILED");
  await refund.getByRole("button").click();
  await expect(page.locator("#notice")).toContainText(
    "Fail and refund completed",
  );
  await screenshot(page, "20-refund-completed");
  const payout = action(page, "Run payout batch");
  await payout.getByLabel("Reason code").fill("SETTLEMENT_REVIEWED");
  await payout.getByRole("button").click();
  await expect(page.locator("#notice")).toContainText(
    "Run payout batch completed",
  );
  await page
    .getByRole("button", { name: "Payout batches", exact: true })
    .click();
  await expect(page.locator("#count")).toContainText("BOOKKEEPING");
  await screenshot(page, "21-payout-history");
});

test("revocation clears an open V1 session and blocks direct actions", async ({
  page,
  browser,
}) => {
  await login(page, "8000000005");
  const adminContext = await browser.newContext();
  const adminPage = await adminContext.newPage();
  try {
    await login(adminPage, "8000000011");
    adminPage.on("dialog", (d) => d.accept());
    const roles = action(adminPage, "Set membership roles");
    await roles.getByLabel("User ID", { exact: true }).fill("user-ops");
    await roles.getByLabel("Target organization ID").fill("platform");
    await roles.getByLabel("Reason code").fill("ACCESS_REVOKED");
    await roles.getByRole("button").click();
    await expect(adminPage.locator("#notice")).toContainText(
      "Set membership roles completed",
    );
    const status = await page.evaluate(
      async () =>
        (
          await fetch("/v1/ops/dashboard/carriers", {
            headers: {
              authorization:
                "Bearer " + sessionStorage.getItem("navig8r_access"),
              "x-organization-id": "platform",
            },
          })
        ).status,
    );
    expect(status).toBe(403);
    await page.getByRole("button", { name: "Refresh access" }).click();
    await expect(page.locator("#protected")).toBeHidden();
    await expect(page.locator("#table")).toBeEmpty();
    await screenshot(page, "22-revoked-session");
  } finally {
    await adminContext.close();
  }
});

test("V1 accepts generated OTP codes and clears stale delivery on resend", async ({
  page,
}) => {
  let starts = 0;
  let verified: unknown;
  await page.route("**/v1/auth/otp/start", async (route) => {
    starts += 1;
    await route.fulfill({
      json: {
        challengeId: `otp_v1_${starts}`,
        expiresAtUtcMs: Date.now() + 600000,
        ...(starts === 1 ? { debugCode: "000042" } : {}),
      },
    });
  });
  await page.route("**/v1/auth/otp/verify", async (route) => {
    verified = JSON.parse(route.request().postData() || "{}");
    await route.fulfill({ status: 400, json: { error: "otp_expired" } });
  });
  await page.goto("/admin/v1");
  await page.getByLabel("Phone number", { exact: true }).fill("8000000005");
  const first = await sendOtp(page);
  expect(first.debugCode).toBe("000042");
  await page.locator("#code").fill("111111");
  const second = await sendOtp(page, false);
  expect(second.challengeId).not.toBe(first.challengeId);
  await expect(page.locator("#code")).toHaveValue("");
  await page.locator("#code").fill("987654");
  await page.getByRole("button", { name: "Sign in", exact: true }).click();
  await expect(page.locator("#error")).toContainText("expired");
  expect(verified).toEqual({
    phone: "8000000005",
    challengeId: second.challengeId,
    code: "987654",
  });
});

test("V1 OTP cooldown disables resend and phone changes clear the challenge", async ({ page }) => {
  let starts = 0;
  await page.route("**/v1/auth/otp/start", async (route) => {
    starts += 1;
    await route.fulfill({ json: {
      challengeId: `otp_cooldown_${starts}`,
      expiresAtUtcMs: Date.now() + 600000,
      retryAfterMs: 30000,
      debugCode: "001234",
    } });
  });
  await page.goto("/admin/v1");
  await page.getByLabel("Phone number", { exact: true }).fill("8000000005");
  await page.getByRole("button", { name: "Send code", exact: true }).click();
  await expect(page.locator("#send-otp")).toHaveText("Resend code (30s)");
  await expect(page.locator("#send-otp")).toBeDisabled();
  await expect(page.locator("#code")).toHaveValue("001234");
  await page.getByLabel("Phone number", { exact: true }).fill("8000000006");
  await expect(page.locator("#send-otp")).toHaveText("Send code");
  await expect(page.locator("#send-otp")).toBeEnabled();
  await expect(page.locator("#code")).toHaveValue("");
  expect(starts).toBe(1);
});
