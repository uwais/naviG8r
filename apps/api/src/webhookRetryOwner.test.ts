import test from "node:test";
import assert from "node:assert/strict";
import { httpFixture } from "../test/httpFixtures.ts";
import type { IntegrationWebhookDelivery } from "./types.ts";

test("a shipper cannot retry another company's webhook delivery, and that delivery stays as it was", async t => {
  const f = await httpFixture(t);
  const otherCompanys: IntegrationWebhookDelivery = {
    id: "whd_other_company",
    eventId: "evt_other_company",
    orgId: f.shipperB.org.id,
    connectionId: "conn_other_company",
    webhookUrl: "https://erp.example.com/hook",
    payloadJson: "{}",
    status: "DEAD",
    attempts: 10,
    nextRetryAtUtcMs: 1,
    lastHttpStatus: 500,
    lastError: "delivery_failed",
    deliveredAtUtcMs: null,
    createdAtUtcMs: 1,
    updatedAtUtcMs: 1,
  };
  f.store.integrationWebhookDeliveries.set(otherCompanys.id, { ...otherCompanys });

  const refused = await f.request(`/v1/pilot/customer/integrations/deliveries/${otherCompanys.id}/retry?orgId=${f.shipperA.org.id}`, "POST", {}, f.tokens.shipperA);
  assert.equal(refused.status, 404);
  assert.equal(refused.body.error, "webhook_delivery_not_found");
  assert.deepEqual(f.store.integrationWebhookDeliveries.get(otherCompanys.id), otherCompanys);

  const owner = await f.request(`/v1/pilot/customer/integrations/deliveries/${otherCompanys.id}/retry?orgId=${f.shipperB.org.id}`, "POST", {}, f.tokens.shipperB);
  assert.equal(owner.status, 200);
  assert.equal(owner.body.delivery.status, "PENDING");
});
