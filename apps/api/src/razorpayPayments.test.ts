import assert from "node:assert/strict";
import crypto from "node:crypto";
import test from "node:test";
import {
  isRazorpayAlreadyCapturedError,
  isRazorpayAlreadyRefundedError,
  verifyRazorpayWebhookSignature,
} from "./razorpayPayments.ts";

test("Razorpay webhook signature verification", () => {
  const secret = "whsec_unit_test";
  const payload = '{"event":"payment.authorized","payload":{}}';
  const good = crypto.createHmac("sha256", secret).update(payload).digest("hex");
  assert.equal(verifyRazorpayWebhookSignature(payload, good, secret), true);
  assert.equal(verifyRazorpayWebhookSignature(payload, "deadbeef", secret), false);
  assert.equal(verifyRazorpayWebhookSignature(payload, undefined, secret), false);
});

test("already-captured / already-refunded error classifiers", () => {
  assert.equal(isRazorpayAlreadyCapturedError("This payment has already been captured"), true);
  assert.equal(isRazorpayAlreadyRefundedError("payment already refunded"), true);
});
