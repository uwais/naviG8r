import assert from "node:assert/strict";
import test from "node:test";
import { createStore } from "./store.ts";
import {
  ApiError,
  bookShipment,
  computeFreightGrossPaise,
  createCarrier,
  distanceBetweenGeoPointsKm,
  markPodDelivered,
  pilotListMyAnchorTrips,
  publishAnchorTrip,
  publishAnchorTripAsPilotDriver,
  registerCustomerOrgAdmin,
  registerSoloOwnerOperatorDriver,
  shipmentVisibleToCustomerUser,
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
  assert.equal(shipment.grossPaise, 200 * 500);
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
  const tripOrigin = { lat: 27.1767, lng: 78.0081 };
  const tripDest = { lat: 26.4499, lng: 74.6399 };
  const pickup = { lat: 27.18, lng: 78.01 };
  const drop = { lat: 26.45, lng: 74.64 };
  const { grossPaise: expected } = computeFreightGrossPaise({
    weightKg: 200,
    vehicleClass: "MEDIUM",
    laneKm: distanceBetweenGeoPointsKm(tripOrigin, tripDest),
    shipmentKm: distanceBetweenGeoPointsKm(pickup, drop),
  });
  assert.equal(shipment.grossPaise, expected);
  assert.equal(shipment.anchorTripId, trip.id);
});

test("bookShipment stores customerOrgId when customerOrg is provided", () => {
  const store = createStore();
  const carrier = createCarrier(store, "Carrier X");
  const trip = publishAnchorTrip(store, {
    carrierId: carrier.id,
    originCity: "A",
    destCity: "B",
    windowStart: "2026-04-24T00:00:00+05:30",
    windowEnd: "2026-04-25T23:59:59+05:30",
    vehicleClass: "MEDIUM",
    capacityKg: 1000,
  });
  const cust = registerCustomerOrgAdmin(store, {
    fullName: "Ops",
    phone: "9111223344",
    orgDisplayName: "ACME Logistics",
  });
  const shipment = bookShipment(store, {
    anchorTripId: trip.id,
    customerOrgName: "should be replaced",
    customerOrg: { id: cust.org.id, displayName: cust.org.displayName },
    weightKg: 50,
    pickupAddress: "p",
    dropAddress: "d",
  });
  assert.equal(shipment.customerOrgId, cust.org.id);
  assert.equal(shipment.customerOrgName, "ACME Logistics");
});

test("bookedByPhone links anonymous shipment to OTP user with same mobile", () => {
  const store = createStore();
  const onboard = registerSoloOwnerOperatorDriver(store, {
    fullName: "Ravi Kumar",
    phone: "9876543299",
    orgDisplayName: "Ravi Transport PhoneTest",
    vehicleRegistrationNumber: "HR26AB1299",
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
  const cust = registerCustomerOrgAdmin(store, {
    fullName: "Buyer",
    phone: "9123456700",
    orgDisplayName: "Retail Co",
  });
  const shipment = bookShipment(store, {
    anchorTripId: trip.id,
    customerOrgName: "Not Matching Org Name",
    bookedByPhoneRaw: "+91 9123456700",
    weightKg: 200,
    pickupAddress: "Sector 44, Gurugram",
    dropAddress: "Sitapura, Jaipur",
  });
  assert.equal(shipment.customerOrgId, undefined);
  assert.equal(shipment.bookedByPhone, "9123456700");
  assert.ok(shipmentVisibleToCustomerUser(store, shipment, cust.user.id));
});
