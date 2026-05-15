import assert from "node:assert/strict";
import test from "node:test";
import { createStore } from "./store.ts";
import { applyRazorpayWebhookPayload } from "./razorpayWebhook.ts";
import type { Payment } from "./types.ts";

function razorpayPayload(event: string, entity: Record<string, unknown>): Record<string, unknown> {
  return { event, payload: { payment: { entity } } };
}

test("late Razorpay webhooks do not resurrect refunded payments", () => {
  const store = createStore();
  const payment: Payment = {
    id: "payin_1",
    shipmentId: "shp_1",
    amountPaise: 100_00,
    status: "REFUNDED",
    provider: "RAZORPAY",
    providerRef: "order_1",
    razorpayOrderId: "order_1",
    razorpayPaymentId: "pay_1",
    createdAtUtcMs: 1,
    updatedAtUtcMs: 2,
  };
  store.payments.set(payment.id, payment);

  applyRazorpayWebhookPayload(
    store,
    razorpayPayload("payment.authorized", { id: "pay_1", order_id: "order_1", status: "authorized" }),
  );
  assert.equal(store.payments.get(payment.id)?.status, "REFUNDED");
  assert.equal(store.payments.get(payment.id)?.razorpayPaymentId, "pay_1");

  applyRazorpayWebhookPayload(
    store,
    razorpayPayload("payment.captured", { id: "pay_1", order_id: "order_1", status: "captured" }),
  );
  assert.equal(store.payments.get(payment.id)?.status, "REFUNDED");
  assert.equal(store.payments.get(payment.id)?.razorpayPaymentId, "pay_1");
});
