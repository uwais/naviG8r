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
