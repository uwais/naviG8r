import assert from "node:assert/strict";
import crypto from "node:crypto";
import test from "node:test";
import { createStore } from "./store.ts";
import { applyRazorpayWebhookPayload } from "./razorpayWebhook.ts";
import { verifyRazorpayWebhookSignature } from "./razorpayPayments.ts";
import type { Payment } from "./types.ts";

test("Razorpay webhook signature verification", () => {
  const secret = "whsec_unit_test";
  const payload = '{"event":"payment.authorized","payload":{}}';
  const good = crypto.createHmac("sha256", secret).update(payload).digest("hex");
  assert.equal(verifyRazorpayWebhookSignature(payload, good, secret), true);
  assert.equal(verifyRazorpayWebhookSignature(payload, "deadbeef", secret), false);
  assert.equal(verifyRazorpayWebhookSignature(payload, undefined, secret), false);
});

function razorpayPayment(overrides: Partial<Payment> = {}): Payment {
  return {
    id: "pay_local_1",
    shipmentId: "shp_1",
    amountPaise: 12345,
    status: "CREATED",
    provider: "RAZORPAY",
    providerRef: "order_1",
    razorpayOrderId: "order_1",
    createdAtUtcMs: 1,
    updatedAtUtcMs: 1,
    ...overrides,
  };
}

function paymentWebhook(event: string, id: string, orderId = "order_1"): Record<string, unknown> {
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

test("failed Razorpay attempt does not downgrade an authorized payment on the same order", () => {
  const store = createStore();
  store.payments.set("pay_local_1", razorpayPayment({
    status: "AUTHORIZED",
    razorpayPaymentId: "pay_success",
  }));

  applyRazorpayWebhookPayload(store, paymentWebhook("payment.failed", "pay_failed"));

  const pay = store.payments.get("pay_local_1");
  assert.equal(pay?.status, "AUTHORIZED");
  assert.equal(pay?.razorpayPaymentId, "pay_success");
});

test("late Razorpay webhooks do not overwrite refunded payments", () => {
  for (const event of ["payment.authorized", "payment.captured"]) {
    const store = createStore();
    store.payments.set("pay_local_1", razorpayPayment({
      status: "REFUNDED",
      razorpayPaymentId: "pay_success",
    }));

    applyRazorpayWebhookPayload(store, paymentWebhook(event, "pay_success"));

    assert.equal(store.payments.get("pay_local_1")?.status, "REFUNDED");
  }
});
