import assert from "node:assert/strict";
import crypto from "node:crypto";
import test from "node:test";
import { createStore } from "./store.ts";
import { verifyRazorpayWebhookSignature } from "./razorpayPayments.ts";
import { applyRazorpayWebhookPayload } from "./razorpayWebhook.ts";
import type { Payment } from "./types.ts";

test("Razorpay webhook signature verification", () => {
  const secret = "whsec_unit_test";
  const payload = '{"event":"payment.authorized","payload":{}}';
  const good = crypto.createHmac("sha256", secret).update(payload).digest("hex");
  assert.equal(verifyRazorpayWebhookSignature(payload, good, secret), true);
  assert.equal(verifyRazorpayWebhookSignature(payload, "deadbeef", secret), false);
  assert.equal(verifyRazorpayWebhookSignature(payload, undefined, secret), false);
});

test("Razorpay failed webhook does not clobber an authorized payment for the same order", () => {
  const store = createStore();
  const payment: Payment = {
    id: "pay_internal_1",
    shipmentId: "ship_1",
    amountPaise: 12345,
    status: "AUTHORIZED",
    provider: "RAZORPAY",
    providerRef: "order_1",
    razorpayOrderId: "order_1",
    razorpayPaymentId: "pay_success",
    createdAtUtcMs: 1,
    updatedAtUtcMs: 2,
  };
  store.payments.set(payment.id, payment);

  applyRazorpayWebhookPayload(store, {
    event: "payment.failed",
    payload: {
      payment: {
        entity: {
          id: "pay_failed_retry",
          order_id: "order_1",
          status: "failed",
        },
      },
    },
  });

  const updated = store.payments.get(payment.id);
  assert.equal(updated?.status, "AUTHORIZED");
  assert.equal(updated?.razorpayPaymentId, "pay_success");
});
