import assert from "node:assert/strict";
import test from "node:test";
import { createStore } from "./store.ts";
import {
  ApiError,
  acceptCarrierShipment,
  bookShipment,
  publishAnchorTripAsPilotDriver,
  registerSoloOwnerOperatorDriver,
  startAnchorTripAsPilot,
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
