import test from "node:test";
import assert from "node:assert/strict";
import { authorize, effectivePermissions, resolvePrincipal, paymentReady, migrateAuthorization, authorizationContext, type Role, type Principal } from "./rbac.ts";
import { createStore } from "./store.ts";
import { serializeResponse } from "./rbacResponses.ts";
import { internalUser } from "../test/fixtures.ts";

const cases: [string, Role[]][] = [
  ["load.create", ["SHIPPER", "OPS"]], ["trip.publish", ["CARRIER", "OPS"]],
  ["load.read", ["SHIPPER", "CARRIER", "OPS", "FINANCE", "ADMIN"]],
  ["pod.upload", ["CARRIER", "OPS"]], ["pod.accept", ["SHIPPER"]],
  ["carrier.offer_accept", ["CARRIER"]], ["load.status_update", ["CARRIER", "OPS"]],
  ["payment.capture", ["FINANCE"]], ["payment.refund", ["FINANCE"]],
  ["settlement.release", ["FINANCE"]], ["user.role_manage", ["ADMIN"]],
  ["kyc.verify", ["OPS"]], ["kyc.document_read", []], ["bank_account.sensitive_read", []],
  ["payment.checkout", ["SHIPPER"]], ["unknown", []],
];
function principal(role: Role): Principal { return { userId: "user", organizationId: "org-a", roles: [role], subrole: role === "SHIPPER" ? "CUSTOMER_ADMIN" : role === "CARRIER" ? "OWNER" : role, internal: !["SHIPPER", "CARRIER"].includes(role), permissions: effectivePermissions([role], role === "SHIPPER" ? "CUSTOMER_ADMIN" : role === "CARRIER" ? "OWNER" : role), membershipActive: true }; }
for (const role of ["SHIPPER", "CARRIER", "OPS", "FINANCE", "ADMIN"] as Role[]) for (const [action, allowed] of cases) {
  test(`${role}: ${action} ${allowed.includes(role) ? "allowed" : "denied"}`, () => {
    assert.equal(authorize(principal(role), action, { customerOrgId: "org-a", carrierId: "org-a", status: "PENDING_RELEASE", podAtUtcMs: 1, podAcceptedAtUtcMs: 2 }, 3), allowed.includes(role));
  });
}
test("missing and malformed principals/resources deny", () => {
  assert.equal(authorize(undefined, "load.read"), false);
  const p = principal("SHIPPER");
  for (const invalid of [{ ...p, membershipActive: false }, { ...p, organizationId: "" }, { ...p, roles: ["ROOT"] as unknown as Role[] }]) assert.equal(authorize(invalid, "load.read", { customerOrgId: "org-a" }), false);
  assert.equal(authorize(p, "load.read"), false);
  assert.equal(authorize(p, "load.read", {}), false);
  assert.equal(authorize(p, "load.read", { customerOrgId: "org-b" }), false);
  assert.equal(authorize(principal("CARRIER"), "pod.upload", { carrierId: "org-b" }), false);
});
test("owner/admin subroles retain only their intended extra rights", () => {
  assert.equal(effectivePermissions(["SHIPPER"], "CUSTOMER_MEMBER").includes("organization.member.invite"), false);
  for (const subrole of ["DRIVER", "DISPATCHER"]) assert.equal(effectivePermissions(["CARRIER"], subrole).includes("bank_account.create_token"), false);
  assert.equal(effectivePermissions(["CARRIER"], "DISPATCHER").includes("organization.member.invite"), true);
});
test("48-hour hold boundary and invalid dates", () => {
  const s = { status: "PENDING_RELEASE", podAtUtcMs: 1000 };
  const end = 1000 + 48 * 3600000;
  assert.equal(paymentReady(s, end - 1), false);
  assert.equal(paymentReady(s, end), true);
  assert.equal(paymentReady({ ...s, podAcceptedAtUtcMs: 1001 }, 1001), true);
  for (const podAtUtcMs of [NaN, Infinity, -1, undefined]) assert.equal(paymentReady({ ...s, podAtUtcMs }, end), false);
  assert.equal(paymentReady({ ...s, podAcceptedAtUtcMs: end + 1 }, 1001), false);
  assert.equal(paymentReady({ ...s, status: "BOOKED" }, end), false);
});
test("membership revocation, inactive organization and role compatibility", () => {
  const store = createStore(); const user = internalUser(store, "FINANCE");
  assert.deepEqual(resolvePrincipal(store, user.userId).roles, ["FINANCE"]);
  store.membershipRoles.set(`${user.userId}:${user.orgId}`, []);
  assert.deepEqual(resolvePrincipal(store, user.userId).roles, []);
  migrateAuthorization(store);
  assert.deepEqual(resolvePrincipal(store, user.userId).roles, []);
  store.organizations.get(user.orgId)!.inactiveAtUtcMs = 1;
  assert.throws(() => resolvePrincipal(store, user.userId), /membership_inactive/);
});
test("same user selects SHIPPER or FINANCE without cross-organization permission union", () => {
  const store = createStore(); const user = internalUser(store, "FINANCE");
  store.organizations.set("customer", { id: "customer", kind: "CUSTOMER", displayName: "Synthetic", kycStatus: "NOT_STARTED", createdAtUtcMs: 1 });
  store.memberships.set(`${user.userId}:customer`, { userId: user.userId, orgId: "customer", role: "CUSTOMER_ADMIN", createdAtUtcMs: 1 });
  assert.throws(() => resolvePrincipal(store, user.userId), /active_organization_required/);
  assert.equal(resolvePrincipal(store, user.userId, "customer").permissions.includes("payment.capture"), false);
  assert.equal(resolvePrincipal(store, user.userId, user.orgId).permissions.includes("load.create"), false);
  store.membershipRoles.set(`${user.userId}:customer`, ["SHIPPER", "FINANCE"]);
  assert.deepEqual(resolvePrincipal(store, user.userId, "customer").roles, ["SHIPPER"]);
});
test("serializer excludes raw and unexpected fields and public GPS", () => {
  const output = serializeResponse({ org: { id: "org", kind: "CUSTOMER", kycStatus: "APPROVED", payoutFundAccountId: "synthetic-private", accountNumber: "SYNTHETIC-NOT-A-BANK", addedSensitiveField: "private" }, trip: { id: "trip", originCity: "A", reservedKg: 1, lastLiveLocation: { lat: 1, lng: 2 } } });
  assert.equal(JSON.stringify(output).includes("private"), false);
  assert.equal(JSON.stringify(output).includes("lastLiveLocation"), false);
  const shipment = { id: "s", customerOrgName: "A", paymentId: "p", grossPaise: 1, commissionPaise: 2, netToCarrierPaise: 3, pickupAddress: "private", podNotes: "private" };
  const out = authorizationContext.run({ principal: principal("ADMIN"), requestId: "test" }, () => serializeResponse(shipment));
  assert.equal(JSON.stringify(out).includes("Paise"), false);
  assert.equal(JSON.stringify(out).includes("private"), false);
});
