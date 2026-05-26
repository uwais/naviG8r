import assert from "node:assert/strict";
import test from "node:test";
import { createStore } from "./store.ts";
import type { Payment, PaymentStatus } from "./types.ts";
import { applyRazorpayWebhookPayload } from "./razorpayWebhook.ts";

function addRazorpayPayment(status: PaymentStatus): Payment {
  return {
    id: "pay_local",
    shipmentId: "shp_1",
    amountPaise: 10_000,
    status,
    provider: "RAZORPAY",
    providerRef: "order_1",
    razorpayOrderId: "order_1",
    razorpayPaymentId: status === "CREATED" ? undefined : "rzp_pay_1",
    createdAtUtcMs: 1,
    updatedAtUtcMs: 1,
  };
}

function webhook(event: string, id: string, orderId = "order_1"): Record<string, unknown> {
  return {
    event,
    payload: {
      payment: {
        entity: {
          id,
          order_id: orderId,
        },
      },
    },
  };
}

test("Razorpay webhooks do not reopen refunded payments", () => {
  const store = createStore();
  const payment = addRazorpayPayment("REFUNDED");
  store.payments.set(payment.id, payment);

  applyRazorpayWebhookPayload(store, webhook("payment.authorized", "rzp_pay_1"));
  assert.equal(store.payments.get(payment.id)?.status, "REFUNDED");

  applyRazorpayWebhookPayload(store, webhook("payment.captured", "rzp_pay_1"));
  assert.equal(store.payments.get(payment.id)?.status, "REFUNDED");
});

test("Razorpay failed retries do not downgrade an authorized payment", () => {
  const store = createStore();
  const payment = addRazorpayPayment("AUTHORIZED");
  store.payments.set(payment.id, payment);

  applyRazorpayWebhookPayload(store, webhook("payment.failed", "rzp_failed_retry"));

  const updated = store.payments.get(payment.id);
  assert.equal(updated?.status, "AUTHORIZED");
  assert.equal(updated?.razorpayPaymentId, "rzp_pay_1");
});
