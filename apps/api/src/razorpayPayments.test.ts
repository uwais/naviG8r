import assert from "node:assert/strict";
import crypto from "node:crypto";
import test from "node:test";
import { createStore } from "./store.ts";
import { applyRazorpayWebhookPayload } from "./razorpayWebhook.ts";
import { verifyRazorpayWebhookSignature } from "./razorpayPayments.ts";

test("Razorpay webhook signature verification", () => {
  const secret = "whsec_unit_test";
  const payload = '{"event":"payment.authorized","payload":{}}';
  const good = crypto.createHmac("sha256", secret).update(payload).digest("hex");
  assert.equal(verifyRazorpayWebhookSignature(payload, good, secret), true);
  assert.equal(verifyRazorpayWebhookSignature(payload, "deadbeef", secret), false);
  assert.equal(verifyRazorpayWebhookSignature(payload, undefined, secret), false);
});

test("Razorpay failed webhook does not downgrade an authorized payment for the same order", () => {
  const store = createStore();
  store.payments.set("payin_1", {
    id: "payin_1",
    shipmentId: "shp_1",
    amountPaise: 123_00,
    status: "AUTHORIZED",
    provider: "RAZORPAY",
    providerRef: "order_1",
    razorpayOrderId: "order_1",
    razorpayPaymentId: "pay_success",
    createdAtUtcMs: 1,
    updatedAtUtcMs: 2,
  });

  applyRazorpayWebhookPayload(store, {
    event: "payment.failed",
    payload: {
      payment: {
        entity: {
          id: "pay_failed_attempt",
          order_id: "order_1",
          status: "failed",
        },
      },
    },
  });

  const pay = store.payments.get("payin_1");
  assert.equal(pay?.status, "AUTHORIZED");
  assert.equal(pay?.razorpayPaymentId, "pay_success");
});

test("Razorpay authorization can recover an order after an earlier failed attempt", () => {
  const store = createStore();
  store.payments.set("payin_1", {
    id: "payin_1",
    shipmentId: "shp_1",
    amountPaise: 123_00,
    status: "CREATED",
    provider: "RAZORPAY",
    providerRef: "order_1",
    razorpayOrderId: "order_1",
    createdAtUtcMs: 1,
    updatedAtUtcMs: 1,
  });

  applyRazorpayWebhookPayload(store, {
    event: "payment.failed",
    payload: {
      payment: {
        entity: {
          id: "pay_failed_attempt",
          order_id: "order_1",
          status: "failed",
        },
      },
    },
  });
  applyRazorpayWebhookPayload(store, {
    event: "payment.authorized",
    payload: {
      payment: {
        entity: {
          id: "pay_success",
          order_id: "order_1",
          status: "authorized",
        },
      },
    },
  });

  const pay = store.payments.get("payin_1");
  assert.equal(pay?.status, "AUTHORIZED");
  assert.equal(pay?.razorpayPaymentId, "pay_success");
});
