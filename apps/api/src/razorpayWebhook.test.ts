import assert from "node:assert/strict";
import test from "node:test";
import { createStore } from "./store.ts";
import { applyRazorpayWebhookPayload } from "./razorpayWebhook.ts";
import type { Payment } from "./types.ts";

function razorpayPayment(overrides: Partial<Payment>): Payment {
  const now = Date.now();
  return {
    id: "payin_1",
    shipmentId: "shp_1",
    amountPaise: 10000,
    status: "CREATED",
    provider: "RAZORPAY",
    providerRef: "order_1",
    razorpayOrderId: "order_1",
    createdAtUtcMs: now,
    updatedAtUtcMs: now,
    ...overrides,
  };
}

function webhook(event: string, entity: Record<string, unknown>): Record<string, unknown> {
  return {
    event,
    payload: {
      payment: {
        entity,
      },
    },
  };
}

test("Razorpay failed retry does not downgrade an authorized payment for the same order", () => {
  const store = createStore();
  store.payments.set(
    "payin_1",
    razorpayPayment({
      status: "AUTHORIZED",
      razorpayPaymentId: "pay_success",
    }),
  );

  applyRazorpayWebhookPayload(
    store,
    webhook("payment.failed", {
      id: "pay_failed_retry",
      order_id: "order_1",
      status: "failed",
    }),
  );

  const pay = store.payments.get("payin_1");
  assert.equal(pay?.status, "AUTHORIZED");
  assert.equal(pay?.razorpayPaymentId, "pay_success");
});

test("late Razorpay success webhooks do not reopen refunded payments", () => {
  const store = createStore();
  store.payments.set(
    "payin_1",
    razorpayPayment({
      status: "REFUNDED",
      razorpayPaymentId: "pay_refunded",
    }),
  );

  applyRazorpayWebhookPayload(
    store,
    webhook("payment.authorized", {
      id: "pay_refunded",
      order_id: "order_1",
      status: "authorized",
    }),
  );
  assert.equal(store.payments.get("payin_1")?.status, "REFUNDED");

  applyRazorpayWebhookPayload(
    store,
    webhook("payment.captured", {
      id: "pay_refunded",
      order_id: "order_1",
      status: "captured",
    }),
  );
  assert.equal(store.payments.get("payin_1")?.status, "REFUNDED");
});
