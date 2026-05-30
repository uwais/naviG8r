import assert from "node:assert/strict";
import test from "node:test";
import { applyRazorpayWebhookPayload } from "./razorpayWebhook.ts";
import { createStore } from "./store.ts";
import type { Payment } from "./types.ts";

function razorpayPayment(overrides: Partial<Payment> = {}): Payment {
  const now = Date.now();
  return {
    id: "pay_internal",
    shipmentId: "shp_1",
    amountPaise: 12345,
    status: "CREATED",
    provider: "RAZORPAY",
    providerRef: "order_1",
    razorpayOrderId: "order_1",
    createdAtUtcMs: now,
    updatedAtUtcMs: now,
    ...overrides,
  };
}

function webhook(event: string, entity: Record<string, unknown>) {
  return {
    event,
    payload: {
      payment: {
        entity,
      },
    },
  };
}

test("Razorpay payment.failed does not downgrade an authorized payment by order id", () => {
  const store = createStore();
  store.payments.set("pay_internal", razorpayPayment({
    status: "AUTHORIZED",
    razorpayPaymentId: "pay_success",
  }));

  applyRazorpayWebhookPayload(store, webhook("payment.failed", {
    id: "pay_failed_retry",
    order_id: "order_1",
    status: "failed",
  }));

  const pay = store.payments.get("pay_internal");
  assert.equal(pay?.status, "AUTHORIZED");
  assert.equal(pay?.razorpayPaymentId, "pay_success");
});

test("Razorpay success webhooks do not reopen refunded payments", () => {
  const store = createStore();
  store.payments.set("pay_internal", razorpayPayment({
    status: "REFUNDED",
    razorpayPaymentId: "pay_success",
  }));

  applyRazorpayWebhookPayload(store, webhook("payment.authorized", {
    id: "pay_success",
    order_id: "order_1",
    status: "authorized",
  }));
  assert.equal(store.payments.get("pay_internal")?.status, "REFUNDED");

  applyRazorpayWebhookPayload(store, webhook("payment.captured", {
    id: "pay_success",
    order_id: "order_1",
    status: "captured",
  }));
  assert.equal(store.payments.get("pay_internal")?.status, "REFUNDED");
});
