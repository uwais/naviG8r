import test from "node:test";
import assert from "node:assert/strict";
import { httpFixture } from "../test/httpFixtures.ts";
import type { IntegrationWebhookDelivery } from "./types.ts";

test("a shipper admin cannot requeue another organisation's webhook delivery, and it stays unchanged", async t => {
  const f = await httpFixture(t);
  const delivery: IntegrationWebhookDelivery = {
    id: "whd_other_org",
    eventId: "evt_other_org",
    orgId: f.shipperB.org.id,
    connectionId: "conn_other_org",
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
  f.store.integrationWebhookDeliveries.set(delivery.id, { ...delivery });
  const out = await f.request(`/v1/pilot/customer/integrations/deliveries/${delivery.id}/retry?orgId=${f.shipperA.org.id}`, "POST", {}, f.tokens.shipperA);
  assert.equal(out.status, 404);
  assert.deepEqual(f.store.integrationWebhookDeliveries.get(delivery.id), delivery);
  const missing = await f.request(`/v1/pilot/customer/integrations/deliveries/whd_missing/retry?orgId=${f.shipperA.org.id}`, "POST", {}, f.tokens.shipperA);
  assert.equal(missing.status, 404);
});
