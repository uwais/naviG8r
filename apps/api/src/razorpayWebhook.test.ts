import assert from "node:assert/strict";
import test from "node:test";
import { applyRazorpayWebhookPayload } from "./razorpayWebhook.ts";
import { createStore } from "./store.ts";
import type { Payment } from "./types.ts";

function razorpayPayment(overrides: Partial<Payment> = {}): Payment {
  return {
    id: "pay_1",
    shipmentId: "shp_1",
    amountPaise: 100_00,
    status: "CREATED",
    provider: "RAZORPAY",
    providerRef: "order_1",
    razorpayOrderId: "order_1",
    createdAtUtcMs: 1,
    updatedAtUtcMs: 1,
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

test("Razorpay success webhooks do not reopen refunded payments", () => {
  const store = createStore();
  store.payments.set(
    "pay_1",
    razorpayPayment({
      status: "REFUNDED",
      razorpayPaymentId: "pay_rzp_1",
    }),
  );

  applyRazorpayWebhookPayload(
    store,
    webhook("payment.authorized", { id: "pay_rzp_2", order_id: "order_1", status: "authorized" }),
  );
  assert.equal(store.payments.get("pay_1")?.status, "REFUNDED");
  assert.equal(store.payments.get("pay_1")?.razorpayPaymentId, "pay_rzp_1");

  applyRazorpayWebhookPayload(
    store,
    webhook("payment.captured", { id: "pay_rzp_1", order_id: "order_1", status: "captured" }),
  );
  assert.equal(store.payments.get("pay_1")?.status, "REFUNDED");
});

test("Razorpay failed webhooks do not downgrade authorized payments", () => {
  const store = createStore();
  store.payments.set(
    "pay_1",
    razorpayPayment({
      status: "AUTHORIZED",
      razorpayPaymentId: "pay_rzp_authorized",
    }),
  );

  applyRazorpayWebhookPayload(
    store,
    webhook("payment.failed", { id: "pay_rzp_failed_retry", order_id: "order_1", status: "failed" }),
  );

  const pay = store.payments.get("pay_1");
  assert.equal(pay?.status, "AUTHORIZED");
  assert.equal(pay?.razorpayPaymentId, "pay_rzp_authorized");
});

test("Razorpay success webhooks can recover from a failed retry attempt", () => {
  const store = createStore();
  store.payments.set(
    "pay_1",
    razorpayPayment({
      status: "FAILED",
      razorpayPaymentId: "pay_rzp_failed",
    }),
  );

  applyRazorpayWebhookPayload(
    store,
    webhook("payment.authorized", { id: "pay_rzp_success", order_id: "order_1", status: "authorized" }),
  );

  const pay = store.payments.get("pay_1");
  assert.equal(pay?.status, "AUTHORIZED");
  assert.equal(pay?.razorpayPaymentId, "pay_rzp_success");
});
