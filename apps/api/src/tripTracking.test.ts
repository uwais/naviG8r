import assert from "node:assert/strict";
import test from "node:test";
import { TRIP_TRACKING_STALE_MS } from "./config.ts";
import { createStore } from "./store.ts";
import {
  bookShipment,
  createCarrier,
  getShipmentTripTracking,
  isTripLocationLive,
  publishAnchorTrip,
  registerCustomerOrgAdmin,
  registerSoloOwnerOperatorDriver,
  reportAnchorTripLocation,
} from "./services.ts";

test("reportAnchorTripLocation stores ping on anchor trip", () => {
  const store = createStore();
  const driver = registerSoloOwnerOperatorDriver(store, {
    fullName: "Ravi",
    phone: "9100000010",
    orgDisplayName: "Ravi Transport",
    vehicleRegistrationNumber: "HR01",
    vehicleClass: "MEDIUM",
    vehicleCapacityKg: 500,
  });
  const trip = publishAnchorTrip(store, {
    carrierId: driver.org.id,
    originCity: "Gurugram",
    destCity: "Jaipur",
    windowStart: "2026-04-24T00:00:00+05:30",
    windowEnd: "2026-04-25T23:59:59+05:30",
    vehicleClass: "MEDIUM",
    capacityKg: 1000,
    origin: { lat: 28.46, lng: 77.03 },
    destination: { lat: 26.91, lng: 75.79 },
  });
  const now = 1_700_000_000_000;
  const updated = reportAnchorTripLocation(store, driver.user.id, trip.id, {
    lat: 28.5,
    lng: 77.1,
    recordedAtUtcMs: now,
    accuracyM: 12,
  });
  assert.equal(updated.lastLiveLocation?.lat, 28.5);
  assert.equal(updated.lastLiveLocation?.recordedAtUtcMs, now);
});

test("getShipmentTripTracking: customer sees live driver when BOOKED and ping is fresh", () => {
  const store = createStore();
  const driver = registerSoloOwnerOperatorDriver(store, {
    fullName: "Ravi",
    phone: "9100000011",
    orgDisplayName: "Ravi Transport",
    vehicleRegistrationNumber: "HR02",
    vehicleClass: "MEDIUM",
    vehicleCapacityKg: 500,
  });
  const trip = publishAnchorTrip(store, {
    carrierId: driver.org.id,
    originCity: "Gurugram",
    destCity: "Jaipur",
    windowStart: "2026-04-24T00:00:00+05:30",
    windowEnd: "2026-04-25T23:59:59+05:30",
    vehicleClass: "MEDIUM",
    capacityKg: 1000,
  });
  const cust = registerCustomerOrgAdmin(store, {
    fullName: "Buyer",
    phone: "9100000012",
    orgDisplayName: "ACME Buyer",
  });
  const shipment = bookShipment(store, {
    anchorTripId: trip.id,
    customerOrgName: cust.org.displayName,
    weightKg: 50,
    pickupAddress: "A",
    dropAddress: "B",
  });
  store.shipments.set(shipment.id, { ...shipment, customerOrgId: cust.org.id });

  const now = 1_700_000_000_000;
  reportAnchorTripLocation(store, driver.user.id, trip.id, {
    lat: 28.47,
    lng: 77.04,
    recordedAtUtcMs: now,
  });

  const out = getShipmentTripTracking(store, cust.user.id, shipment.id, { nowUtcMs: now });
  assert.equal(out.isLive, true);
  assert.equal(out.liveLocation?.lat, 28.47);
});

test("getShipmentTripTracking: stale ping is not live", () => {
  const store = createStore();
  const driver = registerSoloOwnerOperatorDriver(store, {
    fullName: "Ravi",
    phone: "9100000013",
    orgDisplayName: "Ravi Transport",
    vehicleRegistrationNumber: "HR03",
    vehicleClass: "MEDIUM",
    vehicleCapacityKg: 500,
  });
  const trip = publishAnchorTrip(store, {
    carrierId: driver.org.id,
    originCity: "Gurugram",
    destCity: "Jaipur",
    windowStart: "2026-04-24T00:00:00+05:30",
    windowEnd: "2026-04-25T23:59:59+05:30",
    vehicleClass: "MEDIUM",
    capacityKg: 1000,
  });
  const cust = registerCustomerOrgAdmin(store, {
    fullName: "Buyer",
    phone: "9100000014",
    orgDisplayName: "ACME Buyer",
  });
  const shipment = bookShipment(store, {
    anchorTripId: trip.id,
    customerOrgName: cust.org.displayName,
    weightKg: 50,
    pickupAddress: "A",
    dropAddress: "B",
  });
  store.shipments.set(shipment.id, { ...shipment, customerOrgId: cust.org.id });

  const pingAt = 1_700_000_000_000;
  reportAnchorTripLocation(store, driver.user.id, trip.id, {
    lat: 28.47,
    lng: 77.04,
    recordedAtUtcMs: pingAt,
  });

  const now = pingAt + TRIP_TRACKING_STALE_MS + 1;
  const out = getShipmentTripTracking(store, cust.user.id, shipment.id, { nowUtcMs: now });
  assert.equal(out.isLive, false);
  assert.equal(isTripLocationLive(out.liveLocation ?? undefined, now), false);
});

test("getShipmentTripTracking: other customer cannot see shipment", () => {
  const store = createStore();
  const carrier = createCarrier(store, "Carrier");
  const trip = publishAnchorTrip(store, {
    carrierId: carrier.id,
    originCity: "Gurugram",
    destCity: "Jaipur",
    windowStart: "2026-04-24T00:00:00+05:30",
    windowEnd: "2026-04-25T23:59:59+05:30",
    vehicleClass: "MEDIUM",
    capacityKg: 1000,
  });
  const shipment = bookShipment(store, {
    anchorTripId: trip.id,
    customerOrgName: "ACME",
    weightKg: 50,
    pickupAddress: "A",
    dropAddress: "B",
  });
  const other = registerCustomerOrgAdmin(store, {
    fullName: "Other",
    phone: "9100000015",
    orgDisplayName: "Other Co",
  });
  assert.throws(
    () => getShipmentTripTracking(store, other.user.id, shipment.id),
    (e: Error) => e.message === "shipment_not_found",
  );
});
