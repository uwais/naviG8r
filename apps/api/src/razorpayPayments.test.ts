import assert from "node:assert/strict";
import crypto from "node:crypto";
import test from "node:test";
import { verifyRazorpayWebhookSignature } from "./razorpayPayments.ts";
import { applyRazorpayWebhookPayload } from "./razorpayWebhook.ts";
import { createStore } from "./store.ts";

test("Razorpay webhook signature verification", () => {
  const secret = "whsec_unit_test";
  const payload = '{"event":"payment.authorized","payload":{}}';
  const good = crypto.createHmac("sha256", secret).update(payload).digest("hex");
  assert.equal(verifyRazorpayWebhookSignature(payload, good, secret), true);
  assert.equal(verifyRazorpayWebhookSignature(payload, "deadbeef", secret), false);
  assert.equal(verifyRazorpayWebhookSignature(payload, undefined, secret), false);
});

test("Razorpay failed attempt webhook does not downgrade an authorized order payment", () => {
  const store = createStore();
  store.payments.set("pay_internal", {
    id: "pay_internal",
    shipmentId: "shp_1",
    amountPaise: 50000,
    status: "CREATED",
    provider: "RAZORPAY",
    providerRef: "order_1",
    razorpayOrderId: "order_1",
    createdAtUtcMs: 1,
    updatedAtUtcMs: 1,
  });

  applyRazorpayWebhookPayload(store, {
    event: "payment.authorized",
    payload: { payment: { entity: { id: "rzp_pay_success", order_id: "order_1" } } },
  });

  assert.equal(store.payments.get("pay_internal")?.status, "AUTHORIZED");
  assert.equal(store.payments.get("pay_internal")?.razorpayPaymentId, "rzp_pay_success");

  applyRazorpayWebhookPayload(store, {
    event: "payment.failed",
    payload: { payment: { entity: { id: "rzp_pay_failed_retry", order_id: "order_1" } } },
  });

  assert.equal(store.payments.get("pay_internal")?.status, "AUTHORIZED");
  assert.equal(store.payments.get("pay_internal")?.razorpayPaymentId, "rzp_pay_success");
});
