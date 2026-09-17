import test from "node:test";
import assert from "node:assert/strict";
import { httpFixture } from "../test/httpFixtures.ts";
import { loadStoreFromDisk } from "./persistence.ts";
import { resolvePrincipal } from "./rbac.ts";

test("HTTP authenticates protected routes and ignores demo/header bypasses", async t => {
  const f = await httpFixture(t);
  process.env.ALLOW_X_USER_ID = "1"; process.env.ENABLE_LEGACY_DEMO_SURFACE = "1";
  for (const path of ["/shipments", "/v1/users", "/payout-batches", "/ops/shipments/pending-release"]) {
    assert.equal((await f.request(path)).status, 401);
    assert.equal((await f.request(path, "GET", undefined, "invalid")).status, 401);
    assert.equal((await f.request(path, "GET", undefined, undefined, { "x-user-id": f.admin.userId })).status, 401);
  }
  assert.equal((await f.book("")).status, 401);
  assert.equal((await f.book(f.tokens.carrierA)).status, 403);
  assert.equal((await f.request("/shipments/x/pod", "POST", {}, f.tokens.admin)).status, 410);
  f.store.users.get(f.shipperA.user.id)!.inactiveAtUtcMs = 1;
  assert.equal((await f.book()).status, 401);
});

test("HTTP tenant isolation covers path, query, body, collection and inactive membership", async t => {
  const f = await httpFixture(t); const booking = await f.book(); assert.equal(booking.status, 201);
  const id = booking.body.shipment.id;
  assert.equal((await f.request(`/shipments/${id}`, "GET", undefined, f.tokens.shipperA)).status, 200);
  for (const suffix of ["", "/tracking"]) assert.equal((await f.request(`/shipments/${id}${suffix}`, "GET", undefined, f.tokens.shipperB)).status, 404);
  assert.equal((await f.request(`/shipments/${id}/accept-pod`, "POST", {}, f.tokens.shipperB)).status, 404);
  assert.equal((await f.request(`/v1/pilot/carrier/shipments/${id}/accept`, "POST", {}, f.tokens.carrierB)).status, 404);
  assert.equal((await f.request("/shipments", "GET", undefined, f.tokens.shipperB)).body.shipments.length, 0);
  assert.equal((await f.request(`/v1/pilot/carrier/earnings?orgId=${f.carrierB.org.id}`, "GET", undefined, f.tokens.carrierA)).status, 404);
  assert.equal((await f.book(f.tokens.shipperA, { customerOrgId: f.shipperB.org.id })).status, 404);
  f.store.memberships.get(`${f.shipperA.user.id}:${f.shipperA.org.id}`)!.inactiveAtUtcMs = 1;
  assert.equal((await f.request(`/shipments/${id}`, "GET", undefined, f.tokens.shipperA)).status, 403);
});

test("HTTP compliance, POD acceptance, finance separation and safe audits persist", async t => {
  const f = await httpFixture(t); const booking = await f.book(); const id = booking.body.shipment.id;
  f.store.organizations.get(f.carrierA.org.id)!.kycStatus = "SUBMITTED";
  const accept = `/v1/pilot/carrier/shipments/${id}/accept`;
  assert.equal((await f.request(accept, "POST", {}, f.tokens.carrierA)).status, 409);
  const kyc = `/v1/organizations/${f.carrierA.org.id}/kyc`;
  assert.equal((await f.request(kyc, "POST", { status: "APPROVED" }, f.tokens.carrierA)).status, 403);
  assert.equal((await f.request(kyc, "POST", { status: "APPROVED" }, f.tokens.ops, { "x-reason-code": "DOCUMENTS_REVIEWED" })).status, 200);
  assert.equal((await f.request(accept, "POST", {}, f.tokens.carrierA)).status, 200);
  assert.equal((await f.request(`/v1/pilot/anchor-trips/${f.trip.id}/start`, "POST", {}, f.tokens.finance)).status, 403);
  assert.equal((await f.request(`/shipments/${id}/driver-pod`, "POST", { notes: "SYNTHETIC PRIVATE NOTE" }, f.tokens.carrierA)).status, 200);
  const release = `/ops/shipments/${id}/release`;
  for (const role of ["ops", "admin", "carrierA", "shipperA"] as const) assert.equal((await f.request(release, "POST", {}, f.tokens[role])).status, 403);
  assert.equal((await f.request(release, "POST", {}, f.tokens.finance)).status, 403);
  assert.equal((await f.request(`/shipments/${id}/accept-pod`, "POST", {}, f.tokens.shipperA)).status, 200);
  const results = await Promise.all([f.request(release, "POST", {}, f.tokens.finance), f.request(release, "POST", {}, f.tokens.finance)]);
  assert.equal(results.filter(r => r.status === 200).length, 1);
  assert.equal(f.store.ledgerLines.size, 1);
  const restored = loadStoreFromDisk(f.dataFilePath!);
  assert.ok(restored.shipments.get(id)?.podAcceptedAtUtcMs);
  for (const action of ["COMPLIANCE_STATUS_CHANGED", "POD_UPLOADED", "POD_ACCEPTED", "PAYMENT_CAPTURED"]) assert.ok([...restored.auditEvents.values()].some(e => e.action === action));
  assert.equal(JSON.stringify([...restored.auditEvents.values()]).includes("SYNTHETIC PRIVATE NOTE"), false);
  const support = await f.request(`/ops/shipments/${id}`, "GET", undefined, f.tokens.admin);
  assert.equal(support.status, 200); assert.equal(support.body.shipment.grossPaise, undefined); assert.equal(support.body.shipment.pickupAddress, undefined);
});

test("HTTP role management rejects unknown roles; revocation takes effect immediately and after restart", async t => {
  const f = await httpFixture(t);
  const payload = { userId: f.finance.userId, orgId: f.finance.orgId, roles: ["ROOT"] };
  assert.equal((await f.request("/v1/roles", "POST", payload, f.tokens.admin)).status, 400);
  assert.equal((await f.request("/v1/roles", "POST", { ...payload, roles: [] }, f.tokens.ops)).status, 403);
  assert.equal((await f.request("/v1/roles", "POST", { ...payload, roles: [] }, f.tokens.admin)).status, 200);
  assert.equal((await f.request("/payout-batches/run", "POST", {}, f.tokens.finance)).status, 403);
  const restored = loadStoreFromDisk(f.dataFilePath!);
  assert.deepEqual(resolvePrincipal(restored, f.finance.userId).roles, []);
  assert.ok([...restored.auditEvents.values()].some(e => e.action === "ROLE_REMOVED"));
});

test("HTTP multiple memberships require explicit organization and prevent Finance/SHIPPER union", async t => {
  const f = await httpFixture(t);
  f.store.memberships.set(`${f.shipperA.user.id}:${f.finance.orgId}`, { userId: f.shipperA.user.id, orgId: f.finance.orgId, role: "FINANCE", createdAtUtcMs: 1 });
  assert.equal((await f.book()).status, 400);
  assert.equal((await f.request("/payout-batches", "GET", undefined, f.tokens.shipperA, { "x-organization-id": f.shipperA.org.id })).status, 403);
  assert.equal((await f.request("/payout-batches", "GET", undefined, f.tokens.shipperA, { "x-organization-id": f.finance.orgId })).status, 200);
  assert.equal((await f.request("/payout-batches", "GET", undefined, f.tokens.shipperA, { "x-organization-id": f.shipperB.org.id })).status, 403);
});
