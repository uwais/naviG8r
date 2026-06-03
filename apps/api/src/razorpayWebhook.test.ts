import assert from "node:assert/strict";
import test from "node:test";
import { applyRazorpayWebhookPayload } from "./razorpayWebhook.ts";
import { createStore } from "./store.ts";
import type { Payment } from "./types.ts";

function razorpayPayment(overrides: Partial<Payment> = {}): Payment {
  const now = Date.now();
  return {
    id: "payin_unit",
    shipmentId: "shp_unit",
    amountPaise: 123_45,
    status: "CREATED",
    provider: "RAZORPAY",
    providerRef: "order_unit",
    razorpayOrderId: "order_unit",
    createdAtUtcMs: now,
    updatedAtUtcMs: now,
    ...overrides,
  };
}

test("Razorpay failed webhook does not downgrade an authorized payment for the same order", () => {
  const store = createStore();
  store.payments.set(
    "payin_unit",
    razorpayPayment({
      status: "AUTHORIZED",
      razorpayPaymentId: "pay_authorized",
    }),
  );

  applyRazorpayWebhookPayload(store, {
    event: "payment.failed",
    payload: {
      payment: {
        entity: {
          id: "pay_failed_retry",
          order_id: "order_unit",
          status: "failed",
        },
      },
    },
  });

  const pay = store.payments.get("payin_unit");
  assert.equal(pay?.status, "AUTHORIZED");
  assert.equal(pay?.razorpayPaymentId, "pay_authorized");
});

test("Razorpay success webhooks do not reopen refunded payments", () => {
  const store = createStore();
  store.payments.set(
    "payin_unit",
    razorpayPayment({
      status: "REFUNDED",
      razorpayPaymentId: "pay_refunded",
    }),
  );

  applyRazorpayWebhookPayload(store, {
    event: "payment.captured",
    payload: {
      payment: {
        entity: {
          id: "pay_refunded",
          order_id: "order_unit",
          status: "captured",
        },
      },
    },
  });

  assert.equal(store.payments.get("payin_unit")?.status, "REFUNDED");

  applyRazorpayWebhookPayload(store, {
    event: "payment.authorized",
    payload: {
      payment: {
        entity: {
          id: "pay_refunded",
          order_id: "order_unit",
          status: "authorized",
        },
      },
    },
  });

  assert.equal(store.payments.get("payin_unit")?.status, "REFUNDED");
});
