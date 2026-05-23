import assert from "node:assert/strict";
import test from "node:test";
import { createStore } from "./store.ts";
import type { Payment, PaymentStatus } from "./types.ts";
import { applyRazorpayWebhookPayload } from "./razorpayWebhook.ts";

function razorpayPayment(status: PaymentStatus, overrides: Partial<Payment> = {}): Payment {
  return {
    id: "pay_local_1",
    shipmentId: "shp_1",
    amountPaise: 100_00,
    status,
    provider: "RAZORPAY",
    providerRef: "order_1",
    razorpayOrderId: "order_1",
    createdAtUtcMs: 1,
    updatedAtUtcMs: 1,
    ...overrides,
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

test("payment.failed retry webhook does not downgrade an authorized Razorpay payment", () => {
  const store = createStore();
  const pay = razorpayPayment("AUTHORIZED", { razorpayPaymentId: "pay_success" });
  store.payments.set(pay.id, pay);

  applyRazorpayWebhookPayload(store, webhook("payment.failed", "pay_retry_failed"));

  const updated = store.payments.get(pay.id);
  assert.equal(updated?.status, "AUTHORIZED");
  assert.equal(updated?.razorpayPaymentId, "pay_success");
});

test("Razorpay success webhooks do not reopen refunded payments", () => {
  for (const event of ["payment.authorized", "payment.captured"]) {
    const store = createStore();
    const pay = razorpayPayment("REFUNDED", { razorpayPaymentId: "pay_refunded" });
    store.payments.set(pay.id, pay);

    applyRazorpayWebhookPayload(store, webhook(event, "pay_refunded"));

    assert.equal(store.payments.get(pay.id)?.status, "REFUNDED");
  }
});
