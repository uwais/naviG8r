import assert from "node:assert/strict";
import test from "node:test";
import { createStore } from "./store.ts";
import { applyRazorpayWebhookPayload } from "./razorpayWebhook.ts";
import type { Payment, PaymentStatus } from "./types.ts";

function razorpayPayment(status: PaymentStatus): Payment {
  return {
    id: "payin_1",
    shipmentId: "shp_1",
    amountPaise: 10000,
    status,
    provider: "RAZORPAY",
    providerRef: "order_1",
    razorpayOrderId: "order_1",
    razorpayPaymentId: status === "CREATED" ? undefined : "pay_1",
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

test("Razorpay success webhooks do not reopen refunded payments", () => {
  const store = createStore();
  store.payments.set("payin_1", razorpayPayment("REFUNDED"));

  applyRazorpayWebhookPayload(store, webhook("payment.authorized", "pay_1"));
  assert.equal(store.payments.get("payin_1")?.status, "REFUNDED");

  applyRazorpayWebhookPayload(store, webhook("payment.captured", "pay_1"));
  assert.equal(store.payments.get("payin_1")?.status, "REFUNDED");
});

test("Razorpay failed webhook does not downgrade authorized payments", () => {
  const store = createStore();
  store.payments.set("payin_1", razorpayPayment("AUTHORIZED"));

  applyRazorpayWebhookPayload(store, webhook("payment.failed", "pay_2"));

  const pay = store.payments.get("payin_1");
  assert.equal(pay?.status, "AUTHORIZED");
  assert.equal(pay?.razorpayPaymentId, "pay_1");
});
