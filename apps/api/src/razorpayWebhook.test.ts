import assert from "node:assert/strict";
import test from "node:test";
import { applyRazorpayWebhookPayload } from "./razorpayWebhook.ts";
import { createStore } from "./store.ts";
import type { Payment, PaymentStatus } from "./types.ts";

function razorpayPayment(status: PaymentStatus): Payment {
  return {
    id: "payin_1",
    shipmentId: "shp_1",
    amountPaise: 12345,
    status,
    provider: "RAZORPAY",
    providerRef: "order_1",
    razorpayOrderId: "order_1",
    razorpayPaymentId: "rzp_pay_1",
    createdAtUtcMs: 1000,
    updatedAtUtcMs: 1000,
  };
}

function paymentEvent(event: string): Record<string, unknown> {
  return {
    event,
    payload: {
      payment: {
        entity: {
          id: "rzp_pay_1",
          order_id: "order_1",
        },
      },
    },
  };
}

test("Razorpay failed webhook does not downgrade an authorized payment", () => {
  const store = createStore();
  store.payments.set("payin_1", razorpayPayment("AUTHORIZED"));

  applyRazorpayWebhookPayload(store, paymentEvent("payment.failed"));

  assert.equal(store.payments.get("payin_1")?.status, "AUTHORIZED");
});

test("Razorpay success webhooks do not reopen refunded payments", () => {
  const store = createStore();
  store.payments.set("payin_1", razorpayPayment("REFUNDED"));

  applyRazorpayWebhookPayload(store, paymentEvent("payment.authorized"));
  assert.equal(store.payments.get("payin_1")?.status, "REFUNDED");

  applyRazorpayWebhookPayload(store, paymentEvent("payment.captured"));
  assert.equal(store.payments.get("payin_1")?.status, "REFUNDED");
});
