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
    const out = await f.request("/v1/pilot/carrier/payout-setup", "POST", { orgId: carrier, accountHolderName: "Ravi Kumar", ifsc: "HDFC0001234" }, f.tokens.carrierA);
    assert.equal(out.status, 200);
  }
  async function seenBy(token: string, org = carrier) {
    const me = await f.request("/v1/auth/me", "GET", undefined, token);
    return me.body.organizations.find((o: { id: string }) => o.id === org);
  }
  return { f, carrier, reject, saveBankDetails, seenBy };
}

test("a rejected carrier's owner and drivers both read the reason ops picked", async t => {
  const { f, carrier, reject, seenBy } = await rejectionFixture(t);
  registerCustomerUser(f.store, { fullName: "Synthetic Driver", phone: "8000000021" });
  inviteCarrierDriver(f.store, f.carrierA.user.id, { orgId: carrier, phone: "8000000021", role: "DRIVER", vehicleRegistrationNumber: "TEST-D", vehicleClass: "MEDIUM", vehicleCapacityKg: 1000 });
  const driver = await f.login("8000000021");
  await reject("DOCUMENTS_MISSING");
  for (const token of [f.tokens.carrierA, driver]) {
    const org = await seenBy(token);
    assert.equal(org.kycStatus, "REJECTED");
    assert.equal(org.rejectionReasonCode, "DOCUMENTS_MISSING");
    assert.equal(org.approvalTakenBack, undefined);
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

test("the bank reason reaches only members who can save bank details; drivers and dispatchers get no reason", async t => {
  const { f, carrier, reject, saveBankDetails, seenBy } = await rejectionFixture(t);
  const others: string[] = [];
  for (const [phone, role] of [["8000000021", "DRIVER"], ["8000000022", "DISPATCHER"]] as const) {
    registerCustomerUser(f.store, { fullName: `Synthetic ${role}`, phone });
    inviteCarrierDriver(f.store, f.carrierA.user.id, { orgId: carrier, phone, role, vehicleRegistrationNumber: `TEST-${role}`, vehicleClass: "MEDIUM", vehicleCapacityKg: 1000 });
    others.push(await f.login(phone));
  }
  await saveBankDetails();
  await reject("BANK_DETAILS_MISMATCH");
  assert.equal((await seenBy(f.tokens.carrierA)).rejectionReasonCode, "BANK_DETAILS_MISMATCH");
  for (const token of others) {
    const org = await seenBy(token);
    assert.equal(org.kycStatus, "REJECTED");
    assert.equal(org.rejectionReasonCode, undefined);
  }
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

test("a rejected shipper organization gets no carrier reason", async t => {
  const { f, reject, seenBy } = await rejectionFixture(t);
  const shipper = f.shipperA.org.id;
  await reject("DOCUMENTS_MISSING", shipper);
  const org = await seenBy(f.tokens.shipperA, shipper);
  assert.equal(org.kycStatus, "REJECTED");
  assert.equal(org.rejectionReasonCode, undefined);
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
  const member = { userId: "member-x", orgId: org.id, role: "DRIVER" as const, createdAtUtcMs: 0 };
  const rejection = (id: string, timestamp: number, reasonCode: string) => ({
    id, actorUserId: "ops", actorOrganizationId: "platform", action: "COMPLIANCE_STATUS_CHANGED", resourceType: "organization",
    resourceId: org.id, previousState: "SUBMITTED", newState: "REJECTED", reasonCode, requestId: id, timestamp, source: "USER" as const,
  });
  // A database reload can return the newer row before the older one.
  store.auditEvents.set("newer", rejection("newer", 2000, "DUPLICATE_ACCOUNT"));
  store.auditEvents.set("older", rejection("older", 1000, "NOT_A_CARRIER"));
  assert.deepEqual(carrierRejection(store, org, member), { rejectionReasonCode: "DUPLICATE_ACCOUNT" });
});

test("the bank reason follows who can save bank details, including a role an admin removed", () => {
  const store = createStore();
  const org = { id: "carrier-x", kind: "CARRIER_FLEET" as const, displayName: "Carrier X", kycStatus: "REJECTED" as const, createdAtUtcMs: 0, payoutFundAccountId: "fa_saved" };
  store.auditEvents.set("rejection", {
    id: "rejection", actorUserId: "ops", actorOrganizationId: "platform", action: "COMPLIANCE_STATUS_CHANGED", resourceType: "organization",
    resourceId: org.id, previousState: "SUBMITTED", newState: "REJECTED", reasonCode: "BANK_DETAILS_MISMATCH", requestId: "rejection", timestamp: 1000, source: "USER",
  });
  const owner = { userId: "owner-x", orgId: org.id, role: "OWNER" as const, createdAtUtcMs: 0 };
  assert.equal(carrierRejection(store, org, owner).rejectionReasonCode, "BANK_DETAILS_MISMATCH");
  store.membershipRoles.set("owner-x:carrier-x", []);
  assert.equal(carrierRejection(store, org, owner).rejectionReasonCode, undefined, "without the carrier role the save route refuses this owner");
});
