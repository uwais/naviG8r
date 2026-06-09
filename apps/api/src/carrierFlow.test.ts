import assert from "node:assert/strict";
import test from "node:test";
import { createStore } from "./store.ts";
import {
  ApiError,
  acceptCarrierShipment,
  bookShipment,
  completeAnchorTripAsPilot,
  inviteCarrierDriver,
  publishAnchorTripAsPilotDriver,
  registerCustomerUser,
  registerSoloOwnerOperatorDriver,
  startAnchorTripAsPilot,
  submitDriverPod,
} from "./services.ts";

test("booking awaits carrier accept then trip start before live tracking", () => {
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

  const shipment = bookShipment(store, {
    anchorTripId: trip.id,
    customerOrgName: "ACME Manufacturing",
    weightKg: 200,
    pickupAddress: "Sector 44, Gurugram",
    dropAddress: "Sitapura, Jaipur",
  });
  assert.equal(shipment.status, "PENDING_CARRIER_ACCEPT");

  assert.throws(
    () => startAnchorTripAsPilot(store, { userId: onboard.user.id, tripId: trip.id }),
    (e: unknown) => e instanceof ApiError && (e as ApiError).message === "no_accepted_shipments",
  );

  const accepted = acceptCarrierShipment(store, {
    shipmentId: shipment.id,
    userId: onboard.user.id,
  });
  assert.equal(accepted.status, "BOOKED");
  assert.ok(accepted.acceptedAtUtcMs);

  const started = startAnchorTripAsPilot(store, { userId: onboard.user.id, tripId: trip.id });
  assert.equal(started.status, "IN_PROGRESS");
  assert.ok(started.startedAtUtcMs);
});

test("POD on last booking auto-completes IN_PROGRESS trip", () => {
  const store = createStore();
  const onboard = registerSoloOwnerOperatorDriver(store, {
    fullName: "Ravi Kumar",
    phone: "9876543220",
    orgDisplayName: "Ravi Transport",
    vehicleRegistrationNumber: "HR26AB9999",
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
  const shipment = bookShipment(store, {
    anchorTripId: trip.id,
    customerOrgName: "ACME",
    weightKg: 100,
    pickupAddress: "Gurugram",
    dropAddress: "Jaipur",
  });
  acceptCarrierShipment(store, { shipmentId: shipment.id, userId: onboard.user.id });
  startAnchorTripAsPilot(store, { userId: onboard.user.id, tripId: trip.id });

  submitDriverPod(store, { shipmentId: shipment.id, userId: onboard.user.id });

  const updatedTrip = store.anchorTrips.get(trip.id)!;
  assert.equal(updatedTrip.status, "COMPLETED");
  assert.ok(updatedTrip.completedAtUtcMs);
  assert.equal(updatedTrip.lastLiveLocation, undefined);
});

test("completeAnchorTripAsPilot requires all shipments POD'd", () => {
  const store = createStore();
  const onboard = registerSoloOwnerOperatorDriver(store, {
    fullName: "Ravi Kumar",
    phone: "9876543221",
    orgDisplayName: "Ravi Transport",
    vehicleRegistrationNumber: "HR26AB9998",
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
  const shipment = bookShipment(store, {
    anchorTripId: trip.id,
    customerOrgName: "ACME",
    weightKg: 100,
    pickupAddress: "Gurugram",
    dropAddress: "Jaipur",
  });
  acceptCarrierShipment(store, { shipmentId: shipment.id, userId: onboard.user.id });
  startAnchorTripAsPilot(store, { userId: onboard.user.id, tripId: trip.id });

  assert.throws(
    () => completeAnchorTripAsPilot(store, { userId: onboard.user.id, tripId: trip.id }),
    (e: unknown) => e instanceof ApiError && (e as ApiError).message === "shipments_still_active",
  );

  submitDriverPod(store, { shipmentId: shipment.id, userId: onboard.user.id });
  const done = completeAnchorTripAsPilot(store, { userId: onboard.user.id, tripId: trip.id });
  assert.equal(done.status, "COMPLETED");
});

test("dispatcher invite reuses carrier org primary vehicle", () => {
  const store = createStore();
  const onboard = registerSoloOwnerOperatorDriver(store, {
    fullName: "Owner",
    phone: "9876543211",
    orgDisplayName: "Fleet Co",
    vehicleRegistrationNumber: "HR26FLEET1",
    vehicleClass: "MEDIUM",
    vehicleCapacityKg: 5000,
  });
  const dispatcher = registerCustomerUser(store, {
    fullName: "Ops Lead",
    phone: "9876543212",
  });
  const ownerVehicleCount = [...store.vehicles.values()].filter((v) => v.orgId === onboard.org.id).length;

  const out = inviteCarrierDriver(store, onboard.user.id, {
    orgId: onboard.org.id,
    phone: dispatcher.user.phone,
    role: "DISPATCHER",
  });

  assert.equal(out.membership.role, "DISPATCHER");
  assert.equal(out.vehicle.registrationNumber, "HR26FLEET1");
  assert.equal(out.driverProfile.primaryVehicleId, onboard.vehicle.id);
  assert.equal(
    [...store.vehicles.values()].filter((v) => v.orgId === onboard.org.id).length,
    ownerVehicleCount,
  );
});
