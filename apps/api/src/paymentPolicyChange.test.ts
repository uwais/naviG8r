import test from "node:test";
import assert from "node:assert/strict";
import { httpFixture } from "../test/httpFixtures.ts";
import { getOrCreateIntegrationConnection, updateIntegrationConnection } from "./integrationServices.ts";

test("a shipper keeps its webhook and name settings but cannot change how its ERP connection pays", async t => {
  const f = await httpFixture(t);
  const route = `/v1/pilot/customer/integrations/connection?orgId=${f.shipperA.org.id}`;

  const refused = await f.request(route, "PATCH", { webhookUrl: "https://erp.example.com/a", paymentPolicy: "erp_preauthorized" }, f.tokens.shipperA);
  assert.deepEqual([refused.status, refused.body.error], [403, "forbidden"]);
  const unchanged = getOrCreateIntegrationConnection(f.store, f.shipperA.org.id);
  assert.equal(unchanged.paymentPolicy, "portal_checkout");
  assert.equal(unchanged.webhookUrl, undefined, "nothing in the refused request is saved");

  const unknown = await f.request(route, "PATCH", { paymentPolicy: "pay_later" }, f.tokens.shipperA);
  assert.deepEqual([unknown.status, unknown.body.error], [400, "invalid_payment_policy"]);

  // The app sends the policy it read back with every save.
  const saved = await f.request(route, "PATCH", { webhookUrl: "https://erp.example.com/b", displayName: "Main ERP", paymentPolicy: "portal_checkout" }, f.tokens.shipperA);
  assert.equal(saved.status, 200);
  assert.deepEqual([saved.body.connection.webhookUrl, saved.body.connection.displayName, saved.body.connection.paymentPolicy], ["https://erp.example.com/b", "Main ERP", "portal_checkout"]);
});

test("platform OPS and ADMIN can change an ERP connection's payment policy; FINANCE and the shipper cannot", async t => {
  const f = await httpFixture(t);
  const orgId = f.shipperA.org.id;
  for (const userId of [f.finance.userId, f.shipperA.user.id, undefined]) {
    assert.throws(() => updateIntegrationConnection(f.store, orgId, { paymentPolicy: "erp_preauthorized", changedByUserId: userId }), /forbidden/);
    assert.equal(getOrCreateIntegrationConnection(f.store, orgId).paymentPolicy, "portal_checkout");
  }
  assert.equal(updateIntegrationConnection(f.store, orgId, { paymentPolicy: "erp_preauthorized", changedByUserId: f.ops.userId }).paymentPolicy, "erp_preauthorized");
  assert.equal(updateIntegrationConnection(f.store, orgId, { paymentPolicy: "portal_checkout", changedByUserId: f.admin.userId }).paymentPolicy, "portal_checkout");
});

test("NaviG8r staff set an organisation's ERP payment policy through the ops route, and each change is in the audit log", async t => {
  const f = await httpFixture(t);
  const orgId = f.shipperA.org.id;
  const route = (id: string) => `/v1/ops/organizations/${id}/erp-payment-policy`;

  const byOps = await f.request(route(orgId), "POST", { paymentPolicy: "erp_preauthorized" }, f.tokens.ops);
  assert.deepEqual([byOps.status, byOps.body], [200, { orgId, paymentPolicy: "erp_preauthorized" }]);
  assert.equal(getOrCreateIntegrationConnection(f.store, orgId).paymentPolicy, "erp_preauthorized");
  const byAdmin = await f.request(route(orgId), "POST", { paymentPolicy: "portal_checkout" }, f.tokens.admin);
  assert.deepEqual([byAdmin.status, byAdmin.body.paymentPolicy], [200, "portal_checkout"]);
  assert.deepEqual([...f.store.auditEvents.values()].filter((row) => row.action === "ERP_PAYMENT_POLICY_CHANGED").map((row) => [row.resourceType, row.resourceId, row.previousState, row.newState, row.actorUserId]),
    [["organization", orgId, "portal_checkout", "erp_preauthorized", f.ops.userId], ["organization", orgId, "erp_preauthorized", "portal_checkout", f.admin.userId]]);

  for (const token of [f.tokens.finance, f.tokens.shipperA, f.tokens.carrierA]) {
    const refused = await f.request(route(orgId), "POST", { paymentPolicy: "erp_preauthorized" }, token);
    assert.deepEqual([refused.status, refused.body.error], [403, "forbidden"]);
  }
  assert.equal((await f.request(route(orgId), "POST", { paymentPolicy: "erp_preauthorized" })).status, 401);
  assert.equal(getOrCreateIntegrationConnection(f.store, orgId).paymentPolicy, "portal_checkout", "no refused request changed it");

  const unknown = await f.request(route(orgId), "POST", { paymentPolicy: "pay_later" }, f.tokens.ops);
  assert.deepEqual([unknown.status, unknown.body.error], [400, "invalid_payment_policy"]);
  for (const id of ["org_missing", f.carrierA.org.id]) {
    assert.deepEqual([(await f.request(route(id), "POST", { paymentPolicy: "erp_preauthorized" }, f.tokens.ops)).status], [404], id);
  }
  assert.equal([...f.store.auditEvents.values()].filter((row) => row.action === "ERP_PAYMENT_POLICY_CHANGED").length, 2);
});
