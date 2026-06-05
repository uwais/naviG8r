import assert from "node:assert/strict";
import crypto from "node:crypto";
import test from "node:test";
import { createStore } from "./store.ts";
import {
  attachRazorpayOrderForShipment,
  bookShipment,
  confirmRazorpayCheckoutAuthorization,
  publishAnchorTripAsPilotDriver,
  registerSoloOwnerOperatorDriver,
  submitDriverPod,
} from "./services.ts";

process.env.PAYMENT_PROVIDER = "RAZORPAY";
process.env.RAZORPAY_KEY_ID = "rzp_test_confirm";
process.env.RAZORPAY_KEY_SECRET = "confirm_test_secret";

function checkoutSignature(orderId: string, paymentId: string): string {
  return crypto.createHmac("sha256", process.env.RAZORPAY_KEY_SECRET!)
    .update(`${orderId}|${paymentId}`)
    .digest("hex");
}

test("confirmRazorpayCheckoutAuthorization moves CREATED to AUTHORIZED for driver POD", async (t) => {
  const store = createStore();
  const onboard = registerSoloOwnerOperatorDriver(store, {
    fullName: "Driver Confirm",
    phone: "9876543210",
    orgDisplayName: "Confirm Transport",
    vehicleRegistrationNumber: "HR26AB3210",
    vehicleClass: "MEDIUM",
    vehicleCapacityKg: 5000,
  });
  const trip = publishAnchorTripAsPilotDriver(store, {
    userId: onboard.user.id,
    orgId: onboard.org.id,
    originCity: "Gurugram",
    destCity: "Agra",
    windowStart: "2026-04-24T00:00:00+05:30",
    windowEnd: "2026-04-25T23:59:59+05:30",
    vehicleClass: "MEDIUM",
    capacityKg: 1000,
  });

  const shipment = bookShipment(store, {
    anchorTripId: trip.id,
    customerOrgName: "Buyer",
    weightKg: 100,
    pickupAddress: "Gurugram",
    dropAddress: "Agra",
  });

  const orderId = "order_confirm_test_1";
  const paymentId = "pay_confirm_test_1";
  const pay = store.payments.get(shipment.paymentId)!;
  store.payments.set(pay.id, { ...pay, razorpayOrderId: orderId });

  assert.throws(
    () => submitDriverPod(store, { shipmentId: shipment.id, userId: onboard.user.id }),
    (e: Error) => e.message.includes("checkout_not_completed_for_pod"),
  );

  const { payment } = confirmRazorpayCheckoutAuthorization(store, {
    shipmentId: shipment.id,
    razorpayOrderId: orderId,
    razorpayPaymentId: paymentId,
    razorpaySignature: checkoutSignature(orderId, paymentId),
  });
  assert.equal(payment.status, "AUTHORIZED");
  assert.equal(payment.razorpayPaymentId, paymentId);

  const updated = submitDriverPod(store, { shipmentId: shipment.id, userId: onboard.user.id });
  assert.equal(updated.status, "PENDING_RELEASE");
});
