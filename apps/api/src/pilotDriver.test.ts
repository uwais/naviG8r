import { bookTestShipment, registerCompliantCarrier, deliverTestShipment } from "../test/fixtures.ts";
import assert from "node:assert/strict";
import test from "node:test";
import { createStore } from "./store.ts";
import {
  acceptCarrierShipment,
  ApiError,

  computeFreightGrossPaise,
  createCarrier,
  distanceBetweenGeoPointsKm,

  pilotCarrierEarningsSummary,
  pilotListCarrierShipments,
  pilotListMyAnchorTrips,
  pilotSubmitPayoutSetup,
  publishAnchorTrip,
  publishAnchorTripAsPilotDriver,
  registerCustomerOrgAdmin,

  shipmentVisibleToCarrierPilot,
  shipmentVisibleToCustomerUser,
} from "./services.ts";

test("pilot solo driver can register, publish trip, and shipments reference org id", async () => {
  const store = createStore();
  const onboard = registerCompliantCarrier(store, {
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

  const shipment = bookTestShipment(store, {
    anchorTripId: trip.id,
    customerOrgName: "ACME Manufacturing",
    weightKg: 200,
    pickupAddress: "Sector 44, Gurugram",
    dropAddress: "Sitapura, Jaipur",
  });
  assert.equal(shipment.grossPaise, 200 * 500);
  assert.equal(shipment.carrierId, onboard.org.id);
  assert.equal(shipment.status, "PENDING_CARRIER_ACCEPT");

  acceptCarrierShipment(store, { shipmentId: shipment.id, userId: onboard.user.id });
  const pod = await deliverTestShipment(store, { shipmentId: shipment.id });
  assert.equal(pod.ledgerLine.carrierId, onboard.org.id);
});

test("bookShipment enforces Phase A when anchor trip has origin/destination geo", () => {
  const store = createStore();
  const onboard = registerCompliantCarrier(store, {
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
      bookTestShipment(store, {
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

  const shipment = bookTestShipment(store, {
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
  const shipment = bookTestShipment(store, {
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

test("phone matches do not grant access to historical unowned shipments", () => {
  const store = createStore();
  const onboard = registerCompliantCarrier(store, {
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
  const shipment = bookTestShipment(store, {
    anchorTripId: trip.id,
    customerOrgName: "Not Matching Org Name",
    bookedByPhoneRaw: "+91 9123456700",
    weightKg: 200,
    pickupAddress: "Sector 44, Gurugram",
    dropAddress: "Sitapura, Jaipur",
  });
  delete shipment.customerOrgId;
  assert.equal(shipment.customerOrgId, undefined);
  assert.equal(shipment.bookedByPhone, "9123456700");
  assert.equal(shipmentVisibleToCustomerUser(store, shipment, cust.user.id), false);
});

test("booking user IDs do not grant access without shipper membership", () => {
  const store = createStore();
  const onboard = registerCompliantCarrier(store, {
    fullName: "Ravi Kumar",
    phone: "9876543298",
    orgDisplayName: "Ravi Transport UserIdTest",
    vehicleRegistrationNumber: "HR26AB1298",
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
  const shipment = bookTestShipment(store, {
    anchorTripId: trip.id,
    customerOrgName: "Walk-in buyer",
    bookedByUserId: onboard.user.id,
    weightKg: 150,
    pickupAddress: "Gurugram",
    dropAddress: "Jaipur",
  });
  delete shipment.customerOrgId;
  assert.equal(shipment.customerOrgId, undefined);
  assert.equal(shipment.bookedByPhone, undefined);
  shipment.bookedByUserId = onboard.user.id;
  assert.equal(shipmentVisibleToCustomerUser(store, shipment, onboard.user.id), false);
});

test("carrier pilot can list org shipments, mark POD visibility, and submit payout setup", async () => {
  const store = createStore();
  const onboard = registerCompliantCarrier(store, {
    fullName: "Ravi Kumar",
    phone: "9876543212",
    orgDisplayName: "Ravi Transport 3",
    vehicleRegistrationNumber: "HR26AB1236",
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
  const shipment = bookTestShipment(store, {
    anchorTripId: trip.id,
    customerOrgName: "ACME",
    weightKg: 100,
    pickupAddress: "Gurugram",
    dropAddress: "Jaipur",
  });
  assert.ok(shipmentVisibleToCarrierPilot(store, shipment, onboard.user.id));
  const listed = pilotListCarrierShipments(store, onboard.user.id, { anchorTripId: trip.id });
  assert.equal(listed.length, 1);
  assert.equal(listed[0]!.id, shipment.id);

  const setup = await pilotSubmitPayoutSetup(store, onboard.user.id, {
    orgId: onboard.org.id,
    accountHolderName: "Ravi Kumar",
    ifsc: "HDFC0001234",
  });
  assert.equal(setup.org.kycStatus, "SUBMITTED");

  const summary = pilotCarrierEarningsSummary(store, onboard.user.id, onboard.org.id);
  assert.equal(summary.bookedCount, 1);
});

// The format rules themselves live in bankAccountValidation.test.ts. This one
// exists so that deleting the validation CALL from pilotSubmitPayoutSetup turns
// something red - without it, the rules could be wired out and every unit test
// would still pass.
test("pilotSubmitPayoutSetup refuses a malformed IFSC before it reaches the payout provider", async () => {
  const store = createStore();
  const onboard = registerCompliantCarrier(store, {
    fullName: "Ravi Kumar",
    phone: "9876500011",
    orgDisplayName: "Ravi Transport",
    vehicleRegistrationNumber: "HR26AB9999",
    vehicleClass: "MEDIUM",
    vehicleCapacityKg: 5000,
  });

  await assert.rejects(
    () =>
      pilotSubmitPayoutSetup(store, onboard.user.id, {
        orgId: onboard.org.id,
        accountHolderName: "Ravi Kumar",
        // Fifth character must be zero. This is the single most common typo and
        // the provider only reports it on payout day.
        ifsc: "HDFC1001234",
      }),
    /invalid_payout_profile/,
  );

  assert.notEqual(
    store.organizations.get(onboard.org.id)?.kycStatus,
    "SUBMITTED",
    "a rejected profile must not advance the organization's KYC status",
  );
});
