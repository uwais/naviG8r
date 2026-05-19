import assert from "node:assert/strict";
import crypto from "node:crypto";
import test from "node:test";
import { verifyRazorpayWebhookSignature } from "./razorpayPayments.ts";
import { applyRazorpayWebhookPayload } from "./razorpayWebhook.ts";
import { createStore } from "./store.ts";
import type { Payment, PaymentStatus } from "./types.ts";

test("Razorpay webhook signature verification", () => {
  const secret = "whsec_unit_test";
  const payload = '{"event":"payment.authorized","payload":{}}';
  const good = crypto.createHmac("sha256", secret).update(payload).digest("hex");
  assert.equal(verifyRazorpayWebhookSignature(payload, good, secret), true);
  assert.equal(verifyRazorpayWebhookSignature(payload, "deadbeef", secret), false);
  assert.equal(verifyRazorpayWebhookSignature(payload, undefined, secret), false);
});

function razorpayPayment(status: PaymentStatus, overrides: Partial<Payment> = {}): Payment {
  return {
    id: "pay_local_1",
    shipmentId: "shp_1",
    amountPaise: 12345,
    status,
    provider: "RAZORPAY",
    providerRef: "order_1",
    razorpayOrderId: "order_1",
    razorpayPaymentId: "pay_rzp_1",
    createdAtUtcMs: 1,
    updatedAtUtcMs: 1,
    ...overrides,
  };
}

function webhook(event: string, payment: { id?: string; order_id?: string; status?: string }): Record<string, unknown> {
  return {
    event,
    payload: {
      payment: {
        entity: payment,
      },
    },
  };
}

test("Razorpay failed webhook does not downgrade an authorized payment", () => {
  const store = createStore();
  store.payments.set("pay_local_1", razorpayPayment("AUTHORIZED"));

  applyRazorpayWebhookPayload(
    store,
    webhook("payment.failed", { id: "pay_retry_failed", order_id: "order_1", status: "failed" }),
  );

  const pay = store.payments.get("pay_local_1");
  assert.equal(pay?.status, "AUTHORIZED");
  assert.equal(pay?.razorpayPaymentId, "pay_rzp_1");
});

test("Razorpay late success webhooks do not reopen refunded payments", () => {
  const store = createStore();
  store.payments.set("pay_local_1", razorpayPayment("REFUNDED"));

  applyRazorpayWebhookPayload(
    store,
    webhook("payment.captured", { id: "pay_rzp_1", order_id: "order_1", status: "captured" }),
  );
  assert.equal(store.payments.get("pay_local_1")?.status, "REFUNDED");

  applyRazorpayWebhookPayload(
    store,
    webhook("payment.authorized", { id: "pay_rzp_2", order_id: "order_1", status: "authorized" }),
  );
  const pay = store.payments.get("pay_local_1");
  assert.equal(pay?.status, "REFUNDED");
  assert.equal(pay?.razorpayPaymentId, "pay_rzp_1");
});
