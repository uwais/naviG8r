import { httpFixture } from "../test/httpFixtures.ts";
import assert from "node:assert/strict";
import test, { type TestContext } from "node:test";
import { carrierRejection } from "./carrierRejection.ts";
import { inviteCarrierDriver, registerCustomerUser } from "./services.ts";
import { createStore } from "./store.ts";

async function rejectionFixture(t: TestContext) {
  const f = await httpFixture(t);
  const carrier = f.carrierA.org.id;
  // The fixture approves both carriers; start this one as a new carrier with no bank details, so a rejection takes back nothing.
  f.store.organizations.set(carrier, { ...f.store.organizations.get(carrier)!, kycStatus: "NOT_STARTED" });
  async function reject(code: string, org = carrier) {
    const out = await f.request(`/v1/organizations/${org}/kyc`, "POST", { status: "REJECTED" }, f.tokens.ops, { "x-reason-code": code });
    assert.equal(out.status, 200);
  }
  async function saveBankDetails() {
    const out = await f.request("/v1/pilot/carrier/payout-setup", "POST", { orgId: carrier, accountHolderName: "Ravi Kumar", ifsc: "HDFC0001234", accountNumber: "1234567890" }, f.tokens.carrierA);
    assert.equal(out.status, 200);
  }
  async function seenBy(token: string, org = carrier) {
    const me = await f.request("/v1/auth/me", "GET", undefined, token);
    return me.body.organizations.find((o: { id: string }) => o.id === org);
  }
  return { f, carrier, reject, saveBankDetails, seenBy };
}

test("only the owner reads the reason; drivers and dispatchers learn only that the carrier is rejected, or its approval taken back", async t => {
  const { f, carrier, reject, saveBankDetails, seenBy } = await rejectionFixture(t);
  const driverAndDispatcherTokens: string[] = [];
  for (const [phone, role] of [["8000000021", "DRIVER"], ["8000000022", "DISPATCHER"]] as const) {
    registerCustomerUser(f.store, { fullName: `Synthetic ${role}`, phone });
    inviteCarrierDriver(f.store, f.carrierA.user.id, { orgId: carrier, phone, role, vehicleRegistrationNumber: `TEST-${role}`, vehicleClass: "MEDIUM", vehicleCapacityKg: 1000 });
    driverAndDispatcherTokens.push(await f.login(phone));
  }
  // Never approved: the owner reads the reason, and nobody is told an approval was taken back.
  await reject("DOCUMENTS_MISSING");
  const ownerBefore = await seenBy(f.tokens.carrierA);
  assert.equal(ownerBefore.rejectionReasonCode, "DOCUMENTS_MISSING");
  assert.equal(ownerBefore.approvalTakenBack, undefined);
  for (const token of driverAndDispatcherTokens) {
    const org = await seenBy(token);
    assert.equal(org.kycStatus, "REJECTED");
    assert.equal(org.rejectionReasonCode, undefined);
    assert.equal(org.approvalTakenBack, undefined);
  }
  // Saved bank details let the bank reason through to the owner; the approval makes each rejection below a taken-back one.
  await saveBankDetails();
  const approve = await f.request(`/v1/organizations/${carrier}/kyc`, "POST", { status: "APPROVED" }, f.tokens.ops, { "x-reason-code": "BANK_DETAILS_VERIFIED" });
  assert.equal(approve.status, 200);
  for (const code of ["DOCUMENTS_MISSING", "BANK_DETAILS_MISMATCH", "DUPLICATE_ACCOUNT", "NOT_A_CARRIER"]) {
    await reject(code);
    const owner = await seenBy(f.tokens.carrierA);
    assert.equal(owner.rejectionReasonCode, code);
    assert.equal(owner.approvalTakenBack, true, code);
    for (const token of driverAndDispatcherTokens) {
      const org = await seenBy(token);
      assert.equal(org.kycStatus, "REJECTED", code);
      assert.equal(org.rejectionReasonCode, undefined, code);
      assert.equal(org.approvalTakenBack, true, code);
    }
  }
});

test("only the newest rejection counts, and a code outside the agreed four never reaches the carrier", async t => {
  const { f, reject, seenBy } = await rejectionFixture(t);
  await reject("NOT_A_CARRIER");
  assert.equal((await seenBy(f.tokens.carrierA)).rejectionReasonCode, "NOT_A_CARRIER");
  await reject("TYPED_ON_AN_OLDER_OPS_PAGE");
  assert.equal((await seenBy(f.tokens.carrierA)).rejectionReasonCode, undefined, "never falls back to an older reason");
  await reject("DUPLICATE_ACCOUNT");
  assert.equal((await seenBy(f.tokens.carrierA)).rejectionReasonCode, "DUPLICATE_ACCOUNT");
});

test("the bank reason reaches only a carrier that saved bank details before the rejection", async t => {
  const { f, reject, saveBankDetails, seenBy } = await rejectionFixture(t);
  await reject("BANK_DETAILS_MISMATCH");
  assert.equal((await seenBy(f.tokens.carrierA)).rejectionReasonCode, undefined);
  await saveBankDetails();
  await reject("BANK_DETAILS_MISMATCH");
  assert.equal((await seenBy(f.tokens.carrierA)).rejectionReasonCode, "BANK_DETAILS_MISMATCH");
});

test("a carrier waiting for review counts as having saved bank details, even from before saves were logged", async t => {
  const { f, carrier, reject, seenBy } = await rejectionFixture(t);
  // Saves before 16 Sep set SUBMITTED but wrote no BANK_ACCOUNT_CHANGED event.
  f.store.organizations.set(carrier, { ...f.store.organizations.get(carrier)!, kycStatus: "SUBMITTED" });
  await reject("DOCUMENTS_MISSING");
  await reject("BANK_DETAILS_MISMATCH");
  assert.equal((await seenBy(f.tokens.carrierA)).rejectionReasonCode, "BANK_DETAILS_MISMATCH");
});

test("the reason goes once the carrier is waiting for review again, or approved", async t => {
  const { f, carrier, reject, saveBankDetails, seenBy } = await rejectionFixture(t);
  await reject("DOCUMENTS_MISSING");
  await saveBankDetails();
  const waiting = await seenBy(f.tokens.carrierA);
  assert.equal(waiting.kycStatus, "SUBMITTED");
  assert.equal(waiting.rejectionReasonCode, undefined);
  const approve = await f.request(`/v1/organizations/${carrier}/kyc`, "POST", { status: "APPROVED" }, f.tokens.ops, { "x-reason-code": "DOCUMENTS_REVIEWED" });
  assert.equal(approve.status, 200);
  assert.equal((await seenBy(f.tokens.carrierA)).rejectionReasonCode, undefined);
});

test("taking back an approval says so, and 'Approval taken back' is not shown as a reason", async t => {
  const { f, reject, seenBy } = await rejectionFixture(t);
  const approvedCarrier = f.carrierB.org.id;
  await reject("APPROVAL_REVOKED", approvedCarrier);
  const org = await seenBy(f.tokens.carrierB, approvedCarrier);
  assert.equal(org.approvalTakenBack, true);
  assert.equal(org.rejectionReasonCode, undefined);
});

test("a taken-back approval stays called that when ops reject the carrier again with a reason", async t => {
  const { f, reject, seenBy } = await rejectionFixture(t);
  const approvedCarrier = f.carrierB.org.id;
  await reject("APPROVAL_REVOKED", approvedCarrier);
  await reject("DUPLICATE_ACCOUNT", approvedCarrier);
  const org = await seenBy(f.tokens.carrierB, approvedCarrier);
  assert.equal(org.approvalTakenBack, true);
  assert.equal(org.rejectionReasonCode, "DUPLICATE_ACCOUNT");
});

test("a rejected shipper organization gets no carrier reason, nor a taken-back approval", async t => {
  const { f, reject, seenBy } = await rejectionFixture(t);
  const shipper = f.shipperA.org.id;
  // Approved first, so only the carriers-only check keeps the taken-back flag from this shipper.
  const approve = await f.request(`/v1/organizations/${shipper}/kyc`, "POST", { status: "APPROVED" }, f.tokens.ops, { "x-reason-code": "DOCUMENTS_REVIEWED" });
  assert.equal(approve.status, 200);
  await reject("DOCUMENTS_MISSING", shipper);
  const org = await seenBy(f.tokens.shipperA, shipper);
  assert.equal(org.kycStatus, "REJECTED");
  assert.equal(org.rejectionReasonCode, undefined);
  assert.equal(org.approvalTakenBack, undefined);
});

test("taking back an approval for the bank reason shows that reason when bank details were saved first", async t => {
  const { f, carrier, reject, saveBankDetails, seenBy } = await rejectionFixture(t);
  await saveBankDetails();
  const approve = await f.request(`/v1/organizations/${carrier}/kyc`, "POST", { status: "APPROVED" }, f.tokens.ops, { "x-reason-code": "BANK_DETAILS_VERIFIED" });
  assert.equal(approve.status, 200);
  await reject("BANK_DETAILS_MISMATCH");
  const org = await seenBy(f.tokens.carrierA);
  assert.equal(org.rejectionReasonCode, "BANK_DETAILS_MISMATCH");
  assert.equal(org.approvalTakenBack, true);
});

test("each kind of proof of a bank save is enough on its own for the bank reason", () => {
  const org = { id: "carrier-x", kind: "CARRIER_FLEET" as const, displayName: "Carrier X", kycStatus: "REJECTED" as const, createdAtUtcMs: 0 };
  const owner = { userId: "owner-x", orgId: org.id, role: "OWNER" as const, createdAtUtcMs: 0 };
  const event = (id: string, timestamp: number, action: string, previousState?: string, newState?: string, reasonCode?: string) => ({
    id, actorUserId: "someone", actorOrganizationId: "some-org", action, resourceType: "organization", resourceId: org.id,
    previousState, newState, reasonCode, requestId: id, timestamp, source: "USER" as const,
  });
  // The rejection replaced an approval, so it says nothing itself about bank details.
  const bankRejection = event("rejection", 3000, "COMPLIANCE_STATUS_CHANGED", "APPROVED", "REJECTED", "BANK_DETAILS_MISMATCH");
  const withProof = (proof?: ReturnType<typeof event>, fundAccount?: string) => {
    const store = createStore();
    store.auditEvents.set(bankRejection.id, bankRejection);
    if (proof) store.auditEvents.set(proof.id, proof);
    return carrierRejection(store, { ...org, ...(fundAccount ? { payoutFundAccountId: fundAccount } : {}) }, owner).rejectionReasonCode;
  };
  assert.equal(withProof(), undefined, "no proof, no bank reason");
  assert.equal(withProof(event("save", 1000, "BANK_ACCOUNT_CHANGED")), "BANK_DETAILS_MISMATCH", "the save's own log entry");
  assert.equal(withProof(event("approval", 2000, "COMPLIANCE_STATUS_CHANGED", "SUBMITTED", "APPROVED")), "BANK_DETAILS_MISMATCH", "a review of a carrier waiting for review");
  assert.equal(withProof(undefined, "fa_older_save"), "BANK_DETAILS_MISMATCH", "a RazorpayX fund account");
});

test("the newest rejection is found by time, even when audit rows load newest first", () => {
  const store = createStore();
  const org = { id: "carrier-x", kind: "CARRIER_FLEET" as const, displayName: "Carrier X", kycStatus: "REJECTED" as const, createdAtUtcMs: 0 };
  const owner = { userId: "owner-x", orgId: org.id, role: "OWNER" as const, createdAtUtcMs: 0 };
  const rejection = (id: string, timestamp: number, reasonCode: string) => ({
    id, actorUserId: "ops", actorOrganizationId: "platform", action: "COMPLIANCE_STATUS_CHANGED", resourceType: "organization",
    resourceId: org.id, previousState: "SUBMITTED", newState: "REJECTED", reasonCode, requestId: id, timestamp, source: "USER" as const,
  });
  // A database reload can return the newer row before the older one.
  store.auditEvents.set("newer", rejection("newer", 2000, "DUPLICATE_ACCOUNT"));
  store.auditEvents.set("older", rejection("older", 1000, "NOT_A_CARRIER"));
  assert.deepEqual(carrierRejection(store, org, owner), { rejectionReasonCode: "DUPLICATE_ACCOUNT" });
});

test("owners are judged as the bank-details save judges them, so a member whose carrier role an admin removed gets no reason", () => {
  const store = createStore();
  const org = { id: "carrier-x", kind: "CARRIER_FLEET" as const, displayName: "Carrier X", kycStatus: "REJECTED" as const, createdAtUtcMs: 0 };
  store.auditEvents.set("rejection", {
    id: "rejection", actorUserId: "ops", actorOrganizationId: "platform", action: "COMPLIANCE_STATUS_CHANGED", resourceType: "organization",
    resourceId: org.id, previousState: "SUBMITTED", newState: "REJECTED", reasonCode: "DOCUMENTS_MISSING", requestId: "rejection", timestamp: 1000, source: "USER",
  });
  const owner = { userId: "owner-x", orgId: org.id, role: "OWNER" as const, createdAtUtcMs: 0 };
  assert.equal(carrierRejection(store, org, owner).rejectionReasonCode, "DOCUMENTS_MISSING");
  store.membershipRoles.set("owner-x:carrier-x", []);
  assert.equal(carrierRejection(store, org, owner).rejectionReasonCode, undefined, "without the carrier role the save route refuses this owner");
});

test("the reject captions on /ops, /ops/v1 and /ops/beta say exactly who sees each reason", async t => {
  const f = await httpFixture(t);
  const typedCodesCaption = "<p>If you reject with DOCUMENTS_MISSING, BANK_DETAILS_MISMATCH, DUPLICATE_ACCOUNT or NOT_A_CARRIER, only the carrier's owner sees that reason in their app, in plain words; BANK_DETAILS_MISMATCH only if the carrier has saved bank details. Dispatchers and drivers see no reason; they are told to ask the owner for details.</p>";
  const captionsByPage = {
    "/ops": [typedCodesCaption],
    "/ops/v1": [typedCodesCaption],
    "/ops/beta": [
      "<p class=\"caption\">For carriers not in the list, such as taking back an approval. The change and your reason are kept in the carrier's history. If you reject with Documents missing, Duplicate account, Not a carrier business or the bank reason, only the owner sees it in their app, in plain words; the bank reason only if the carrier has saved bank details. Dispatchers and drivers see no reason; they are told to ask the owner for details. If you take back an approval, everyone at the carrier reads that it was taken back.</p>",
      // Matched with the code that builds it, so the note must stay in the reject picker.
      "!approving && element('span', { id: cardId + '-reason-note', class: 'caption', text: \"Only the owner sees the reason you pick, in their app, in plain words; the bank reason only if the carrier has saved bank details. Dispatchers and drivers see no reason; they are told to ask the owner for details.\" })",
    ],
  };
  for (const [path, captions] of Object.entries(captionsByPage)) {
    const html = await (await fetch(f.base + path)).text();
    for (const caption of captions) assert.ok(html.includes(caption), `${path}: ${caption.slice(0, 60)}`);
  }
});

test("a carrier rejected as a duplicate stays an active carrier, so the other account cannot invite its owner", async t => {
  const { f, reject } = await rejectionFixture(t);
  await reject("DUPLICATE_ACCOUNT");
  const invited = await f.request("/v1/pilot/carrier/drivers/invite", "POST", { orgId: f.carrierB.org.id, phone: f.carrierA.user.phone, role: "DISPATCHER" }, f.tokens.carrierB);
  assert.equal(invited.status, 409);
  assert.equal(invited.body.error, "member_of_another_carrier");
});
