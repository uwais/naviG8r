import assert from "node:assert/strict";
import test from "node:test";
import { pilotOtpStart, pilotOtpVerify } from "./auth.ts";
import { createStore } from "./store.ts";
import {
  bookShipment,
  createCarrier,
  failCarrierAndRefund,
  publishAnchorTrip,
  registerCustomerOrgAdmin,
  registerCustomerUser,
  registerSoloOwnerOperatorDriver,
  rollbackBooking,
} from "./services.ts";

function openTrip(store: ReturnType<typeof createStore>, capacityKg = 1000) {
  const c = createCarrier(store, "Acme Haul");
  return publishAnchorTrip(store, {
    carrierId: c.id,
    originCity: "Gurugram",
    destCity: "Jaipur",
    windowStart: "2026-08-10T00:00:00+05:30",
    windowEnd: "2026-08-11T23:59:59+05:30",
    vehicleClass: "MEDIUM",
    capacityKg,
  });
}

test("rejects NaN/Infinity weightKg and capacityKg before capacity math is poisoned", () => {
  const store = createStore();
  const trip = openTrip(store, 1000);

  assert.throws(
    () =>
      bookShipment(store, {
        anchorTripId: trip.id,
        customerOrgName: "Factory",
        weightKg: Number("abc"),
        pickupAddress: "A",
        dropAddress: "B",
      }),
    /invalid_weightKg/,
  );
  assert.equal(trip.reservedKg, 0);

  assert.throws(
    () =>
      bookShipment(store, {
        anchorTripId: trip.id,
        customerOrgName: "Factory",
        weightKg: Number.POSITIVE_INFINITY,
        pickupAddress: "A",
        dropAddress: "B",
      }),
    /invalid_weightKg/,
  );

  const c = createCarrier(store, "Other");
  assert.throws(
    () =>
      publishAnchorTrip(store, {
        carrierId: c.id,
        originCity: "A",
        destCity: "B",
        windowStart: "2026-08-10T00:00:00+05:30",
        windowEnd: "2026-08-11T23:59:59+05:30",
        vehicleClass: "MEDIUM",
        capacityKg: Number("nope"),
      }),
    /invalid_capacityKg/,
  );
  assert.throws(
    () =>
      publishAnchorTrip(store, {
        carrierId: c.id,
        originCity: "A",
        destCity: "B",
        windowStart: "2026-08-10T00:00:00+05:30",
        windowEnd: "2026-08-11T23:59:59+05:30",
        vehicleClass: "MEDIUM",
        capacityKg: Number.POSITIVE_INFINITY,
      }),
    /invalid_capacityKg/,
  );
});

test("rollbackBooking does not leave NaN reservedKg if a corrupt shipment is rolled back", () => {
  const store = createStore();
  const trip = openTrip(store, 1000);
  const s = bookShipment(store, {
    anchorTripId: trip.id,
    customerOrgName: "Factory",
    weightKg: 200,
    pickupAddress: "A",
    dropAddress: "B",
  });
  // Simulate a historically-poisoned reservedKg (pre-fix) plus NaN weight on the shipment.
  trip.reservedKg = Number.NaN;
  store.anchorTrips.set(trip.id, trip);
  store.shipments.set(s.id, { ...s, weightKg: Number.NaN });

  rollbackBooking(store, s.id);
  assert.equal(trip.reservedKg, 0);
  assert.equal(Number.isFinite(trip.reservedKg), true);
});

test("unverified phone registration can be reclaimed; verified phone cannot", (t) => {
  const prev = {
    AUTH_SECRET: process.env.AUTH_SECRET,
    OTP_DEBUG: process.env.OTP_DEBUG,
    OTP_FIXED_CODE: process.env.OTP_FIXED_CODE,
  };
  t.after(() => {
    process.env.AUTH_SECRET = prev.AUTH_SECRET;
    process.env.OTP_DEBUG = prev.OTP_DEBUG;
    process.env.OTP_FIXED_CODE = prev.OTP_FIXED_CODE;
  });
  process.env.AUTH_SECRET = "test_secret_minimum_16_chars";
  process.env.OTP_DEBUG = "1";
  process.env.OTP_FIXED_CODE = "123456";

  const store = createStore();
  const squat = registerCustomerUser(store, { fullName: "Squatter", phone: "9000011111" });
  assert.ok(store.users.get(squat.user.id));

  const reclaim = registerCustomerOrgAdmin(store, {
    fullName: "Real Owner",
    phone: "9000011111",
    orgDisplayName: "Real Co",
  });
  assert.equal(reclaim.user.phone, "9000011111");
  assert.equal(reclaim.user.fullName, "Real Owner");
  assert.equal(store.users.has(squat.user.id), false);

  const start = pilotOtpStart(store, { phone: "9000011111" });
  pilotOtpVerify(store, {
    phone: "9000011111",
    challengeId: start.challengeId,
    code: "123456",
  });

  assert.throws(
    () =>
      registerCustomerUser(store, {
        fullName: "Attacker",
        phone: "9000011111",
      }),
    /phone_already_registered/,
  );
});

test("OTP verify locks after too many wrong attempts", (t) => {
  const prev = {
    AUTH_SECRET: process.env.AUTH_SECRET,
    OTP_DEBUG: process.env.OTP_DEBUG,
    OTP_FIXED_CODE: process.env.OTP_FIXED_CODE,
    OTP_MAX_ATTEMPTS: process.env.OTP_MAX_ATTEMPTS,
  };
  t.after(() => {
    process.env.AUTH_SECRET = prev.AUTH_SECRET;
    process.env.OTP_DEBUG = prev.OTP_DEBUG;
    process.env.OTP_FIXED_CODE = prev.OTP_FIXED_CODE;
    if (prev.OTP_MAX_ATTEMPTS === undefined) delete process.env.OTP_MAX_ATTEMPTS;
    else process.env.OTP_MAX_ATTEMPTS = prev.OTP_MAX_ATTEMPTS;
  });
  process.env.AUTH_SECRET = "test_secret_minimum_16_chars";
  process.env.OTP_DEBUG = "1";
  process.env.OTP_FIXED_CODE = "123456";
  process.env.OTP_MAX_ATTEMPTS = "3";

  const store = createStore();
  registerSoloOwnerOperatorDriver(store, {
    fullName: "Ravi",
    phone: "9876500000",
    orgDisplayName: "Ravi Transport",
    vehicleRegistrationNumber: "HR26AB0001",
    vehicleClass: "MEDIUM",
    vehicleCapacityKg: 5000,
  });

  const start = pilotOtpStart(store, { phone: "9876500000" });
  assert.throws(
    () =>
      pilotOtpVerify(store, {
        phone: "9876500000",
        challengeId: start.challengeId,
        code: "000000",
      }),
    /otp_incorrect/,
  );
  assert.throws(
    () =>
      pilotOtpVerify(store, {
        phone: "9876500000",
        challengeId: start.challengeId,
        code: "000001",
      }),
    /otp_incorrect/,
  );
  assert.throws(
    () =>
      pilotOtpVerify(store, {
        phone: "9876500000",
        challengeId: start.challengeId,
        code: "000002",
      }),
    /otp_locked/,
  );
  // Even the correct code is rejected after lockout.
  assert.throws(
    () =>
      pilotOtpVerify(store, {
        phone: "9876500000",
        challengeId: start.challengeId,
        code: "123456",
      }),
    /otp_challenge_invalid/,
  );
});

test("concurrent failCarrierAndRefund claims once and does not double-free capacity", async () => {
  const store = createStore();
  const trip = openTrip(store, 1000);
  const s1 = bookShipment(store, {
    anchorTripId: trip.id,
    customerOrgName: "A",
    weightKg: 400,
    pickupAddress: "A",
    dropAddress: "B",
  });
  bookShipment(store, {
    anchorTripId: trip.id,
    customerOrgName: "B",
    weightKg: 400,
    pickupAddress: "A",
    dropAddress: "B",
  });
  assert.equal(trip.reservedKg, 800);

  const pay = store.payments.get(s1.paymentId)!;
  // Keep MOCK CAPTURED so refund path stays local (no gateway).
  assert.equal(pay.provider, "MOCK");
  assert.equal(pay.status, "CAPTURED");

  const results = await Promise.allSettled([
    failCarrierAndRefund(store, { shipmentId: s1.id }),
    failCarrierAndRefund(store, { shipmentId: s1.id }),
  ]);

  const fulfilled = results.filter((r) => r.status === "fulfilled");
  const rejected = results.filter((r) => r.status === "rejected");
  assert.equal(fulfilled.length, 1);
  assert.equal(rejected.length, 1);
  assert.match(String((rejected[0] as PromiseRejectedResult).reason?.message ?? ""), /shipment_not_refundable/);
  // Sibling 400kg booking must still be reserved.
  assert.equal(trip.reservedKg, 400);
});
