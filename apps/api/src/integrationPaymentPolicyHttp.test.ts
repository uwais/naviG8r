import assert from "node:assert/strict";
import test from "node:test";
import { httpFixture } from "../test/httpFixtures.ts";

const route = (orgId: string) => `/v1/ops/organizations/${orgId}/integration-payment-policy`;
const REASON = { "x-reason-code": "PAYMENT_AGREEMENT_SIGNED" };

test("platform OPS or ADMIN sets an organisation's ERP payment policy, and it is in the audit log", async (t) => {
  const f = await httpFixture(t);
  const orgId = f.shipperA.org.id;

  const byOps = await f.request(route(orgId), "PUT", { paymentPolicy: "erp_preauthorized" }, f.tokens.ops, REASON);
  assert.equal(byOps.status, 200);
  assert.equal(byOps.body.connection.paymentPolicy, "erp_preauthorized");
  assert.equal(byOps.body.connection.orgId, orgId);
  assert.equal(byOps.body.connection.webhookSecret, undefined);

  const byAdmin = await f.request(route(orgId), "PUT", { paymentPolicy: "portal_checkout" }, f.tokens.admin, REASON);
  assert.equal(byAdmin.status, 200);
  assert.equal(byAdmin.body.connection.paymentPolicy, "portal_checkout");

  const audit = [...f.store.auditEvents.values()].filter((e) => e.action === "INTEGRATION_PAYMENT_POLICY_CHANGED");
  assert.deepEqual(
    audit.map((e) => [e.actorUserId, e.resourceType, e.resourceId, e.previousState, e.newState, e.reasonCode]),
    [
      [f.ops.userId, "organization", orgId, "portal_checkout", "erp_preauthorized", "PAYMENT_AGREEMENT_SIGNED"],
      [f.admin.userId, "organization", orgId, "erp_preauthorized", "portal_checkout", "PAYMENT_AGREEMENT_SIGNED"],
    ],
  );
});

test("a shipper or finance user cannot set the payment policy", async (t) => {
  const f = await httpFixture(t);
  const orgId = f.shipperA.org.id;

  const byShipper = await f.request(route(orgId), "PUT", { paymentPolicy: "erp_preauthorized" }, f.tokens.shipperA, REASON);
  assert.equal(byShipper.status, 403);
  const byFinance = await f.request(route(orgId), "PUT", { paymentPolicy: "erp_preauthorized" }, f.tokens.finance, REASON);
  assert.equal(byFinance.status, 403);
  assert.equal(byFinance.body.error, "payment_policy_staff_only");

  const connection = [...f.store.integrationConnections.values()].find((c) => c.orgId === orgId);
  assert.notEqual(connection?.paymentPolicy, "erp_preauthorized");
  assert.equal([...f.store.auditEvents.values()].some((e) => e.action === "INTEGRATION_PAYMENT_POLICY_CHANGED"), false);
});

test("the payment policy route needs a reason, a known policy and a shipper organisation", async (t) => {
  const f = await httpFixture(t);
  const orgId = f.shipperA.org.id;

  const noReason = await f.request(route(orgId), "PUT", { paymentPolicy: "erp_preauthorized" }, f.tokens.ops);
  assert.equal(noReason.status, 400);
  assert.equal(noReason.body.error, "reason_required");

  const unknown = await f.request(route(orgId), "PUT", { paymentPolicy: "pay_later" }, f.tokens.ops, REASON);
  assert.equal(unknown.status, 400);
  assert.equal(unknown.body.error, "invalid_payment_policy");

  const carrierOrg = await f.request(route(f.carrierA.org.id), "PUT", { paymentPolicy: "erp_preauthorized" }, f.tokens.ops, REASON);
  assert.equal(carrierOrg.status, 404);
  assert.equal(carrierOrg.body.error, "not_found");
});
