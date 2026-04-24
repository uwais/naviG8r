import assert from "node:assert/strict";
import test from "node:test";
import { createStore } from "./store.ts";
import {
  bookShipment,
  markPodDelivered,
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
