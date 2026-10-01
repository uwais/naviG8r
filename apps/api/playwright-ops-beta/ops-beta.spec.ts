import { expect, test, type Page } from "@playwright/test";

// Accounts and data come from scripts/rbac-manual.mjs. It runs with OTP_DEBUG on, so Send code fills in the code.
const phones = { ops: "8000000005", finance: "8000000006", admin: "8000000007", carrierOwner: "8000000004" };

async function signIn(page: Page, phone: string): Promise<void> {
  await page.goto("/ops/beta");
  await page.getByLabel("Phone").fill(phone);
  await page.getByRole("button", { name: "Send code" }).click();
  await expect(page.getByLabel("Verification code")).toHaveValue(/^\d{6}$/);
  await expect(page.locator("#start")).toBeDisabled();
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(page.getByText("Signed in as")).toBeVisible();
}

test("a signed-out visitor sees only sign-in, and today's page still loads", async ({ page }) => {
  await page.goto("/ops/beta");
  await expect(page.getByRole("heading", { level: 1, name: "Operations" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Sign in" })).toBeVisible();
  await expect(page.locator("#workspace")).toBeHidden();

  await page.getByLabel("Phone").fill("8000009999");
  await page.getByRole("button", { name: "Send code" }).click();
  await expect(page.locator("#signinResult")).toHaveText("Couldn't send the code: no account uses that phone number.");
  await expect(page.getByRole("button", { name: "Send code" })).toBeEnabled();

  await page.getByLabel("Phone").fill(phones.admin);
  await page.getByRole("button", { name: "Send code" }).click();
  await expect(page.getByLabel("Verification code")).toHaveValue(/^\d{6}$/);
  await page.getByLabel("Phone").fill(phones.finance);
  await expect(page.getByLabel("Verification code")).toHaveValue("");
  await expect(page.getByRole("button", { name: "Send code" })).toBeEnabled();

  await page.goto("/ops");
  await expect(page.getByRole("heading", { level: 1, name: "Operations workspace" })).toBeVisible();
});

test("OPS: Approve or Reject first, then a reason from that action's list, recorded in the card", async ({ page }) => {
  await signIn(page, phones.ops);
  const card = page.getByRole("article", { name: "Synthetic Carrier B (carrier-b)" });
  await expect(card.getByText("Bank details submitted")).toBeVisible();
  await expect(page.locator("#countCarriers")).toHaveText("1");

  await card.getByRole("button", { name: "Reject" }).click();
  await expect(card.getByLabel("Reason for rejecting Synthetic Carrier B (carrier-b)", { exact: true }).locator("option")).toHaveText(
    ["Choose a reason", "Documents missing", "Bank account name doesn't match the carrier", "Duplicate account", "Not a carrier business"]);
  await card.getByRole("button", { name: "Cancel" }).click();
  await expect(card.getByRole("button", { name: "Reject" })).toBeFocused();

  await card.getByRole("button", { name: "Approve" }).click();
  const reason = card.getByLabel("Reason for approving Synthetic Carrier B (carrier-b)", { exact: true });
  await expect(reason).toBeFocused();
  await expect(reason.locator("option")).toHaveText(["Choose a reason", "Documents reviewed", "Bank details verified"]);
  await card.getByRole("button", { name: "Confirm approval" }).click();
  await expect(card.getByRole("alert")).toHaveText("Not approved yet. Choose a reason from the list.");
  await expect(reason).toHaveAttribute("aria-invalid", "true");

  await reason.selectOption({ label: "Documents reviewed" });
  await card.getByRole("button", { name: "Confirm approval" }).click();
  await expect(card.getByRole("status")).toContainText(/Approved by you at \d\d:\d\d IST: Documents reviewed\. Synthetic Carrier B can now accept shipments/);
  await expect(card.locator(".tag")).toHaveText("Approved");
  await expect(page.locator("#countCarriers")).toHaveText("0");

  const payments = page.locator("#payments");
  await expect(payments.getByText("Only FINANCE can release payments. You hold OPS.").first()).toBeVisible();
  await expect(payments.getByText("Amounts are shown to FINANCE only.")).toBeVisible();
  await expect(payments.getByRole("columnheader", { name: "Ledger credit" })).toHaveCount(0);
  for (const words of await page.locator(".tag").allTextContents()) expect(words).not.toContain("_");
});

test("review by ID: nothing chosen, and the reason list follows the decision", async ({ page }) => {
  await signIn(page, phones.ops);
  const form = page.locator("#byIdForm");
  const reason = form.getByLabel("Reason", { exact: true });
  await expect(form.getByRole("radio", { name: "Approve" })).not.toBeChecked();
  await expect(form.getByRole("radio", { name: "Reject" })).not.toBeChecked();
  await expect(reason).toBeDisabled();
  await form.getByLabel("Carrier ID").fill("carrier-b");
  await form.getByRole("button", { name: "Record review" }).click();
  await expect(form.getByRole("alert")).toHaveText("Not recorded yet. Pick Approve or Reject.");

  await form.getByRole("radio", { name: "Reject" }).check();
  await expect(reason).toBeEnabled();
  await expect(reason.locator("option")).toContainText(["Approval taken back"]);
  await form.getByRole("button", { name: "Record review" }).click();
  await expect(form.getByRole("alert")).toHaveText("Not recorded yet. Choose a reason from the list.");

  await reason.selectOption({ label: "Approval taken back" });
  await form.getByRole("button", { name: "Record review" }).click();
  const recorded = form.getByRole("status");
  await expect(recorded).toHaveText(/Review recorded by you at \d\d:\d\d IST: Approval taken back\. Synthetic Carrier B \(carrier-b\) now shows: Not approved\./);
  await expect(recorded).toBeFocused();
  await expect(form.getByRole("radio", { name: "Approve" })).not.toBeChecked();
  await expect(form.getByRole("radio", { name: "Reject" })).not.toBeChecked();
  await expect(reason).toBeDisabled();
  await expect(form.getByRole("button", { name: "Record review" })).toBeEnabled();
});

test("FINANCE: carrier review is off; release shows the ledger credit, Cancel and Esc close it, Release records it in the row", async ({ page }) => {
  await signIn(page, phones.finance);
  await expect(page.locator("#carriers").getByText("Only OPS can review carriers. You hold FINANCE.")).toBeVisible();
  await expect(page.locator("#byIdForm").getByText("Only OPS can review carriers. You hold FINANCE.")).toBeVisible();
  await expect(page.locator("#byIdForm").getByRole("button", { name: "Record review" })).toBeDisabled();
  await expect(page.locator("#byIdForm").getByLabel("Carrier ID")).toBeDisabled();

  await expect(page.getByRole("columnheader", { name: "Ledger credit" })).toBeVisible();
  const held = page.getByRole("row", { name: /load-a-hold/ });
  await expect(held.getByRole("button", { name: "Release payment" })).toBeDisabled();
  await expect(held).toContainText("Hold ends");

  const ready = page.getByRole("row", { name: /load-a-expired/ });
  await expect(ready).toContainText("Ready for payment release");
  await expect(ready).toContainText("₹45");
  const open = ready.getByRole("button", { name: "Release payment…" });
  await open.click();
  const dialog = page.getByRole("dialog", { name: "Release payment for shipment load-a-expired?" });
  await expect(dialog).toBeVisible();
  await expect(dialog).toContainText("₹45 is credited to the ledger balance of Synthetic Carrier A carrier-a. It is paid out in the first weekly payout batch (Wednesdays, 18:00 IST) at least 7 days after proof of delivery");
  await expect(dialog).toContainText("Shipper paid₹50");
  await expect(dialog).toContainText("NaviG8r commission− ₹5");
  await expect(dialog).toContainText("Credited to the ledger balance₹45");
  await expect(dialog.getByRole("button", { name: "Cancel" })).toBeFocused();

  await dialog.getByRole("button", { name: "Cancel" }).click();
  await expect(dialog).toBeHidden();
  await expect(open).toBeFocused();
  await open.click();
  await expect(dialog).toBeVisible();
  await page.keyboard.press("Escape");
  await expect(dialog).toBeHidden();
  await expect(open).toBeFocused();

  // A release the server is still holding: Esc twice may close the dialog, but the outcome must still show.
  let answerRelease = (): void => {};
  const serverHoldsRelease = new Promise<void>(resolve => { answerRelease = resolve; });
  await page.route("**/ops/shipments/load-a-expired/release", async route => {
    await serverHoldsRelease;
    await route.fulfill({ status: 500, contentType: "application/json", body: JSON.stringify({ error: "internal_error" }) });
  });
  await open.click();
  await dialog.getByRole("button", { name: "Release ₹45" }).click();
  await expect(dialog.getByText("Cancel is off until the server answers")).toBeVisible();
  await page.keyboard.press("Escape");
  await page.keyboard.press("Escape");
  answerRelease();
  await expect(page.getByText("Couldn't release the payment: the server hit an error. It may or may not have gone through.")).toBeVisible();
  await page.unroute("**/ops/shipments/load-a-expired/release");
  if (await dialog.isVisible()) await dialog.getByRole("button", { name: "Cancel" }).click();
  await expect(page.locator("#countPayments")).toHaveText("2");

  await open.click();
  await dialog.getByRole("button", { name: "Release ₹45" }).click();
  await expect(dialog).toBeHidden();
  await expect(ready.getByRole("status")).toContainText(/Payment released by you at \d\d:\d\d IST\. ₹45 is credited to the carrier's ledger balance and paid out in a later weekly payout batch/);
  await expect(page.locator("#countPayments")).toHaveText("1");
  await expect(ready.locator(".tag")).toHaveText("Payment released");
});

test("ADMIN gets the role form with nothing ticked and must pick a role", async ({ page }) => {
  await signIn(page, phones.admin);
  const team = page.locator("#team");
  for (const role of ["OPS", "FINANCE", "ADMIN", "SHIPPER", "CARRIER"]) await expect(team.getByRole("checkbox", { name: role })).not.toBeChecked();
  await team.getByLabel("User ID").fill("user-ops");
  await team.getByLabel("Organization ID").fill("platform");
  await team.getByRole("button", { name: "Save roles" }).click();
  await expect(team.getByRole("alert")).toHaveText("Not saved yet. Tick at least one role.");
});

test("someone without an operator role is told who to ask", async ({ page }) => {
  await signIn(page, phones.carrierOwner);
  await expect(page.getByText("You're signed in, but you don't have an operator role for Synthetic Carrier B.")).toBeVisible();
  await expect(page.locator("#sections")).toBeHidden();
});
