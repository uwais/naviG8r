import assert from "node:assert/strict";
import test from "node:test";
import { createStore } from "./store.ts";
import {
  ApiError,
  bookShipment,
  markPodDelivered,
  pilotListMyAnchorTrips,
  publishAnchorTripAsPilotDriver,
  registerSoloOwnerOperatorDriver,
} from "./services.ts";

test("pilot solo driver can register, publish trip, and shipments reference org id", () => {
  const store = createStore();
  const onboard = registerSoloOwnerOperatorDriver(store, {
    fullName: "Ravi Kumar",
    phone: "9876543210",
    orgDisplayName: "Ravi Transport",
    vehicleRegistrationNumber: "HR26AB1234",
    vehicleClass: "MEDIUM",
    vehicleCapacityKg: 5000,
  });

  const trip = publishAnchorTripAsPilotDriver(store, {
    userId: onboard.user.id,
    orgId: onboard.org.id,
    originCity: "Gurugram",
    destCity: "Jaipur",
    windowStart: "2026-04-24T00:00:00+05:30",
    windowEnd: "2026-04-25T23:59:59+05:30",
    vehicleClass: "MEDIUM",
    capacityKg: 1000,
  });

  assert.equal(trip.carrierId, onboard.org.id);

  const listed = pilotListMyAnchorTrips(store, onboard.user.id);
  assert.equal(listed.length, 1);
  assert.equal(listed[0]!.id, trip.id);

  const shipment = bookShipment(store, {
    anchorTripId: trip.id,
    customerOrgName: "ACME Manufacturing",
    weightKg: 200,
    pickupAddress: "Sector 44, Gurugram",
    dropAddress: "Sitapura, Jaipur",
  });
  assert.equal(shipment.carrierId, onboard.org.id);

  const pod = markPodDelivered(store, { shipmentId: shipment.id });
  assert.equal(pod.ledgerLine.carrierId, onboard.org.id);
});

test("bookShipment enforces Phase A when anchor trip has origin/destination geo", () => {
  const store = createStore();
  const onboard = registerSoloOwnerOperatorDriver(store, {
    fullName: "Ravi Kumar",
    phone: "9876543211",
    orgDisplayName: "Ravi Transport 2",
    vehicleRegistrationNumber: "HR26AB1235",
    vehicleClass: "MEDIUM",
    vehicleCapacityKg: 5000,
  });

  const trip = publishAnchorTripAsPilotDriver(store, {
    userId: onboard.user.id,
    orgId: onboard.org.id,
    originCity: "Agra",
    destCity: "Ajmer",
    origin: { lat: 27.1767, lng: 78.0081 },
    destination: { lat: 26.4499, lng: 74.6399 },
    windowStart: "2026-04-24T00:00:00+05:30",
    windowEnd: "2026-04-25T23:59:59+05:30",
    vehicleClass: "MEDIUM",
    capacityKg: 1000,
  });

  assert.throws(
    () =>
      bookShipment(store, {
        anchorTripId: trip.id,
        customerOrgName: "ACME Manufacturing",
        weightKg: 200,
        pickupAddress: "Gurugram",
        dropAddress: "Jaipur",
        pickup: { lat: 28.4595, lng: 77.0266 },
        drop: { lat: 26.9124, lng: 75.7873 },
      }),
    (e: unknown) => e instanceof ApiError && (e as ApiError).message === "phase_a_not_eligible",
  );

  const shipment = bookShipment(store, {
    anchorTripId: trip.id,
    customerOrgName: "ACME Manufacturing",
    weightKg: 200,
    pickupAddress: "Near Agra",
    dropAddress: "Near Ajmer",
    pickup: { lat: 27.18, lng: 78.01 },
    drop: { lat: 26.45, lng: 74.64 },
  });
  assert.equal(shipment.anchorTripId, trip.id);
});
