import assert from "node:assert/strict";
import test from "node:test";
import { createStore } from "./store.ts";
import { applyRazorpayWebhookPayload } from "./razorpayWebhook.ts";
import type { Payment } from "./types.ts";

function razorpayPayment(params: Partial<Payment> = {}): Payment {
  return {
    id: "pay_local_1",
    shipmentId: "shp_1",
    amountPaise: 10000,
    status: "CREATED",
    provider: "RAZORPAY",
    providerRef: "order_1",
    razorpayOrderId: "order_1",
    createdAtUtcMs: 1,
    updatedAtUtcMs: 1,
    ...params,
  };
}

function paymentWebhook(event: string, entity: Record<string, unknown>): Record<string, unknown> {
  return {
    event,
    payload: {
      payment: {
        entity,
      },
    },
  };
}

test("Razorpay failed webhook does not downgrade an authorized payment", () => {
  const store = createStore();
  const pay = razorpayPayment({ status: "AUTHORIZED", razorpayPaymentId: "pay_authorized_1" });
  store.payments.set(pay.id, pay);

  applyRazorpayWebhookPayload(
    store,
    paymentWebhook("payment.failed", {
      id: "pay_authorized_1",
      order_id: "order_1",
    }),
  );

  assert.equal(store.payments.get(pay.id)?.status, "AUTHORIZED");
});

test("Razorpay success webhooks do not reopen refunded payments", () => {
  const store = createStore();
  const pay = razorpayPayment({ status: "REFUNDED", razorpayPaymentId: "pay_refunded_1" });
  store.payments.set(pay.id, pay);

  applyRazorpayWebhookPayload(
    store,
    paymentWebhook("payment.authorized", {
      id: "pay_refunded_late_auth",
      order_id: "order_1",
    }),
  );
  assert.equal(store.payments.get(pay.id)?.status, "REFUNDED");
  assert.equal(store.payments.get(pay.id)?.razorpayPaymentId, "pay_refunded_1");

  applyRazorpayWebhookPayload(
    store,
    paymentWebhook("payment.captured", {
      id: "pay_refunded_1",
      order_id: "order_1",
    }),
  );
  assert.equal(store.payments.get(pay.id)?.status, "REFUNDED");
});
