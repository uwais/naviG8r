import assert from "node:assert/strict";
import test from "node:test";
import { createStore } from "./store.ts";
import { applyRazorpayWebhookPayload } from "./razorpayWebhook.ts";
import type { Payment } from "./types.ts";

function razorpayPayment(overrides: Partial<Payment> = {}): Payment {
  return {
    id: "payin_test",
    shipmentId: "shp_test",
    amountPaise: 12345,
    status: "CREATED",
    provider: "RAZORPAY",
    providerRef: "order_test",
    razorpayOrderId: "order_test",
    createdAtUtcMs: 1,
    updatedAtUtcMs: 1,
    ...overrides,
  };
}

function webhook(event: string, payment: { id: string; order_id: string; status?: string }) {
  return {
    event,
    payload: {
      payment: {
        entity: payment,
      },
    },
  };
}

test("payment.failed for another Razorpay attempt does not downgrade an authorized order", () => {
  const store = createStore();
  const pay = razorpayPayment({
    status: "AUTHORIZED",
    razorpayPaymentId: "pay_success",
  });
  store.payments.set(pay.id, pay);

  applyRazorpayWebhookPayload(
    store,
    webhook("payment.failed", {
      id: "pay_failed_attempt",
      order_id: pay.razorpayOrderId!,
      status: "failed",
    }),
  );

  const updated = store.payments.get(pay.id)!;
  assert.equal(updated.status, "AUTHORIZED");
  assert.equal(updated.razorpayPaymentId, "pay_success");
});

test("late Razorpay success webhooks do not reopen refunded payments", () => {
  for (const event of ["payment.authorized", "payment.captured"]) {
    const store = createStore();
    const pay = razorpayPayment({
      status: "REFUNDED",
      razorpayPaymentId: "pay_refunded",
    });
    store.payments.set(pay.id, pay);

    applyRazorpayWebhookPayload(
      store,
      webhook(event, {
        id: "pay_late_success",
        order_id: pay.razorpayOrderId!,
        status: event === "payment.captured" ? "captured" : "authorized",
      }),
    );

    const updated = store.payments.get(pay.id)!;
    assert.equal(updated.status, "REFUNDED");
    assert.equal(updated.razorpayPaymentId, "pay_refunded");
  }
});
