import { addTestPodPhoto, bookTestShipment, registerCompliantCarrier, startTestTrip } from "../test/fixtures.ts";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import test from "node:test";
import { createStore } from "./store.ts";
import { applyRazorpayWebhookPayload } from "./razorpayWebhook.ts";
import {
  attachRazorpayOrderForShipment,
  acceptCarrierShipment,

  confirmRazorpayCheckoutAuthorization,
  publishAnchorTripAsPilotDriver,

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
  const onboard = registerCompliantCarrier(store, {
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
    windowStart: "2099-04-24T00:00:00+05:30",
    windowEnd: "2099-04-25T23:59:59+05:30",
    vehicleClass: "MEDIUM",
    capacityKg: 1000,
  });

  const shipment = bookTestShipment(store, {
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
    (e: Error) => e.message === "shipment_not_deliverable",
  );

  const { payment } = confirmRazorpayCheckoutAuthorization(store, {
    shipmentId: shipment.id,
    razorpayOrderId: orderId,
    razorpayPaymentId: paymentId,
    razorpaySignature: checkoutSignature(orderId, paymentId),
  });
  assert.equal(payment.status, "AUTHORIZED");
  assert.equal(payment.razorpayPaymentId, paymentId);

  acceptCarrierShipment(store, { shipmentId: shipment.id, userId: onboard.user.id });

  startTestTrip(store, shipment.id);
  addTestPodPhoto(store, shipment.id);
  const updated = submitDriverPod(store, { shipmentId: shipment.id, userId: onboard.user.id });
  assert.equal(updated.status, "PENDING_RELEASE");
});

test("checkout confirm after a failed first attempt on the same order marks the booking paid", () => {
  const store = createStore();
  const onboard = registerCompliantCarrier(store, {
    fullName: "Retry Confirm",
    phone: "9876543211",
    orgDisplayName: "Retry Transport",
    vehicleRegistrationNumber: "HR26AB3211",
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
  const shipment = bookTestShipment(store, {
    anchorTripId: trip.id,
    customerOrgName: "Buyer",
    weightKg: 100,
    pickupAddress: "Gurugram",
    dropAddress: "Agra",
  });
  const orderId = "order_confirm_retry_1";
  const successPaymentId = "pay_confirm_retry_success";
  const pay = store.payments.get(shipment.paymentId)!;
  store.payments.set(pay.id, { ...pay, razorpayOrderId: orderId });

  applyRazorpayWebhookPayload(store, {
    event: "payment.failed",
    payload: { payment: { entity: { id: "pay_confirm_retry_failed", order_id: orderId, status: "failed" } } },
  });
  assert.equal(store.payments.get(pay.id)!.status, "FAILED");
  assert.equal(store.shipments.get(shipment.id)!.status, "PENDING_CARRIER_ACCEPT");
  assert.equal(store.anchorTrips.get(trip.id)!.reservedKg, 100);

  const { payment } = confirmRazorpayCheckoutAuthorization(store, {
    shipmentId: shipment.id,
    razorpayOrderId: orderId,
    razorpayPaymentId: successPaymentId,
    razorpaySignature: checkoutSignature(orderId, successPaymentId),
  });
  assert.equal(payment.status, "AUTHORIZED");
  assert.equal(payment.razorpayPaymentId, successPaymentId);
  assert.equal(store.shipments.get(shipment.id)!.status, "PENDING_CARRIER_ACCEPT");
  assert.equal(store.anchorTrips.get(trip.id)!.reservedKg, 100);
});

test("checkout confirm does not revive a refunded payment", () => {
  const store = createStore();
  const onboard = registerCompliantCarrier(store, {
    fullName: "Refund Confirm",
    phone: "9876543212",
    orgDisplayName: "Refund Transport",
    vehicleRegistrationNumber: "HR26AB3212",
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
  const shipment = bookTestShipment(store, {
    anchorTripId: trip.id,
    customerOrgName: "Buyer",
    weightKg: 100,
    pickupAddress: "Gurugram",
    dropAddress: "Agra",
  });
  const orderId = "order_confirm_refunded_1";
  const paymentId = "pay_confirm_refunded_1";
  const pay = store.payments.get(shipment.paymentId)!;
  store.payments.set(pay.id, { ...pay, status: "REFUNDED", razorpayOrderId: orderId, razorpayPaymentId: "pay_already_refunded" });

  assert.throws(
    () => confirmRazorpayCheckoutAuthorization(store, {
      shipmentId: shipment.id,
      razorpayOrderId: orderId,
      razorpayPaymentId: paymentId,
      razorpaySignature: checkoutSignature(orderId, paymentId),
    }),
    (e: Error & { extra?: Record<string, unknown> }) =>
      e.message === "payment_not_confirmable" && e.extra?.status === "REFUNDED",
  );
  assert.equal(store.payments.get(pay.id)!.status, "REFUNDED");
  assert.equal(store.payments.get(pay.id)!.razorpayPaymentId, "pay_already_refunded");
});
