import test from "node:test";
import assert from "node:assert/strict";
import { httpFixture } from "../test/httpFixtures.ts";
import type { IntegrationWebhookDelivery } from "./types.ts";

function deadDelivery(orgId: string): IntegrationWebhookDelivery {
  return {
    id: "whd_synthetic_retry",
    eventId: "evt_synthetic_retry",
    orgId,
    connectionId: "conn_synthetic_retry",
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
}

test("a shipper cannot retry another organisation's webhook delivery, and that delivery stays as it was", async t => {
  const f = await httpFixture(t);
  const delivery = deadDelivery(f.shipperB.org.id);
  f.store.integrationWebhookDeliveries.set(delivery.id, { ...delivery });
  const retried = await f.request(`/v1/pilot/customer/integrations/deliveries/${delivery.id}/retry?orgId=${f.shipperA.org.id}`, "POST", {}, f.tokens.shipperA);
  assert.equal(retried.status, 404);
  assert.equal(retried.body.error, "webhook_delivery_not_found");
  assert.deepEqual(f.store.integrationWebhookDeliveries.get(delivery.id), delivery);
});

test("a shipper still retries its own webhook delivery", async t => {
  const f = await httpFixture(t);
  const delivery = deadDelivery(f.shipperA.org.id);
  f.store.integrationWebhookDeliveries.set(delivery.id, { ...delivery });
  const retried = await f.request(`/v1/pilot/customer/integrations/deliveries/${delivery.id}/retry?orgId=${f.shipperA.org.id}`, "POST", {}, f.tokens.shipperA);
  assert.equal(retried.status, 200);
  assert.deepEqual([retried.body.delivery.status, retried.body.delivery.attempts], ["PENDING", 0]);
});
