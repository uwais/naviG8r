import assert from "node:assert/strict";
import test from "node:test";
import { createStore } from "./store.ts";
import {
  ApiError,
  bookShipment,
  grantOpsAdmin,
  inviteCarrierDriver,
  opsDeleteUser,
  publishAnchorTripAsPilotDriver,
  registerCustomerUser,
  registerSoloOwnerOperatorDriver,
  customerEligibleAnchorTripsPhaseA,
} from "./services.ts";
import { isActiveEntity } from "./softDelete.ts";

function grantOps(store: ReturnType<typeof createStore>, phone: string) {
  registerCustomerUser(store, { fullName: "Ops " + phone.slice(-4), phone });
  return grantOpsAdmin(store, { phone });
}

test("opsDeleteUser soft-deactivates sole-owned carrier org (audit retained)", () => {
  const store = createStore();
  const ops = grantOps(store, "9000000001");
  const driver = registerSoloOwnerOperatorDriver(store, {
    fullName: "Delete Me",
    phone: "9000000002",
    orgDisplayName: "Doomed Cargo",
    vehicleRegistrationNumber: "HR26DEL1",
    vehicleClass: "MEDIUM",
    vehicleCapacityKg: 4000,
  });
  const trip = publishAnchorTripAsPilotDriver(store, {
    userId: driver.user.id,
    orgId: driver.org.id,
    originCity: "Gurugram",
    destCity: "Jaipur",
    windowStart: "2026-04-24T00:00:00+05:30",
    windowEnd: "2026-04-25T23:59:59+05:30",
    vehicleClass: "MEDIUM",
    capacityKg: 1000,
  });

  const out = opsDeleteUser(store, { actingUserId: ops.userId, userId: driver.user.id });

  assert.equal(out.deactivatedUserId, driver.user.id);
  assert.ok(out.cascadedOrgIds.includes(driver.org.id));
  assert.ok(out.deactivatedTripIds.includes(trip.id));

  // Rows retained for audit
  assert.equal(store.users.has(driver.user.id), true);
  assert.equal(store.organizations.has(driver.org.id), true);
  assert.equal(store.vehicles.has(driver.vehicle.id), true);
  assert.equal(store.anchorTrips.has(trip.id), true);

  assert.equal(isActiveEntity(store.users.get(driver.user.id)), false);
  assert.equal(isActiveEntity(store.organizations.get(driver.org.id)), false);
  assert.equal(isActiveEntity(store.vehicles.get(driver.vehicle.id)), false);
  assert.equal(isActiveEntity(store.anchorTrips.get(trip.id)), false);
  assert.equal(store.users.get(driver.user.id)?.inactiveReason, "ops_user_deactivate");

  // Tombstone must actually take the lane off the marketplace (status stays OPEN for audit).
  assert.equal(store.anchorTrips.get(trip.id)?.status, "OPEN");
  assert.throws(
    () =>
      bookShipment(store, {
        anchorTripId: trip.id,
        customerOrgName: "Acme",
        weightKg: 100,
        pickupAddress: "A",
        dropAddress: "B",
      }),
    (e: unknown) => e instanceof Error && e.message === "anchor_trip_not_open",
  );
});

test("opsDeleteUser blocks active shipments without force", () => {
  const store = createStore();
  const ops = grantOps(store, "9000000011");
  const driver = registerSoloOwnerOperatorDriver(store, {
    fullName: "Active Driver",
    phone: "9000000012",
    orgDisplayName: "Active Cargo",
    vehicleRegistrationNumber: "HR26ACT1",
    vehicleClass: "MEDIUM",
    vehicleCapacityKg: 4000,
  });
  const trip = publishAnchorTripAsPilotDriver(store, {
    userId: driver.user.id,
    orgId: driver.org.id,
    originCity: "Gurugram",
    destCity: "Jaipur",
    windowStart: "2026-04-24T00:00:00+05:30",
    windowEnd: "2026-04-25T23:59:59+05:30",
    vehicleClass: "MEDIUM",
    capacityKg: 1000,
  });
  bookShipment(store, {
    anchorTripId: trip.id,
    customerOrgName: "Acme",
    weightKg: 100,
    pickupAddress: "A",
    dropAddress: "B",
  });

  assert.throws(
    () => opsDeleteUser(store, { actingUserId: ops.userId, userId: driver.user.id }),
    (e: unknown) => e instanceof ApiError && e.message === "active_work_exists",
  );

  const out = opsDeleteUser(store, { actingUserId: ops.userId, userId: driver.user.id, force: true });
  assert.equal(out.force, true);
  assert.equal(isActiveEntity(store.users.get(driver.user.id)), false);
  assert.equal(isActiveEntity(store.organizations.get(driver.org.id)), false);
  assert.equal(store.shipments.size >= 1, true);
});

test("opsDeleteUser deactivates membership only for shared fleet org", () => {
  const store = createStore();
  const ops = grantOps(store, "9000000021");
  const owner = registerSoloOwnerOperatorDriver(store, {
    fullName: "Owner",
    phone: "9000000022",
    orgDisplayName: "Fleet Co",
    vehicleRegistrationNumber: "HR26FLT1",
    vehicleClass: "MEDIUM",
    vehicleCapacityKg: 5000,
  });
  const staff = registerCustomerUser(store, { fullName: "Staff Driver", phone: "9000000023" });
  inviteCarrierDriver(store, owner.user.id, {
    orgId: owner.org.id,
    phone: staff.user.phone,
    role: "DRIVER",
    vehicleRegistrationNumber: "HR26FLT2",
    vehicleClass: "SMALL",
    vehicleCapacityKg: 1000,
  });

  const out = opsDeleteUser(store, { actingUserId: ops.userId, userId: staff.user.id });

  assert.equal(out.cascadedOrgIds.length, 0);
  assert.ok(out.deactivatedMembershipOrgIds.includes(owner.org.id));
  assert.equal(isActiveEntity(store.organizations.get(owner.org.id)), true);
  assert.equal(isActiveEntity(store.users.get(owner.user.id)), true);
  assert.equal(isActiveEntity(store.users.get(staff.user.id)), false);
});

test("opsDeleteUser cannot delete self", () => {
  const store = createStore();
  const ops = grantOps(store, "9000000031");
  assert.throws(
    () => opsDeleteUser(store, { actingUserId: ops.userId, userId: ops.userId }),
    (e: unknown) => e instanceof ApiError && e.message === "cannot_delete_self",
  );
});

test("opsDeleteUser removes OPEN trips from marketplace match and blocks new publish", () => {
  const store = createStore();
  const ops = grantOps(store, "9000000041");
  const driver = registerSoloOwnerOperatorDriver(store, {
    fullName: "Lane Driver",
    phone: "9000000042",
    orgDisplayName: "Lane Cargo",
    vehicleRegistrationNumber: "HR26LAN1",
    vehicleClass: "MEDIUM",
    vehicleCapacityKg: 4000,
  });
  const origin = { lat: 28.46, lng: 77.03 };
  const destination = { lat: 26.91, lng: 75.79 };
  publishAnchorTripAsPilotDriver(store, {
    userId: driver.user.id,
    orgId: driver.org.id,
    originCity: "Gurugram",
    destCity: "Jaipur",
    origin,
    destination,
    windowStart: "2026-04-24T00:00:00+05:30",
    windowEnd: "2026-04-25T23:59:59+05:30",
    vehicleClass: "MEDIUM",
    capacityKg: 1000,
  });

  const before = customerEligibleAnchorTripsPhaseA(store, {
    pickup: origin,
    drop: destination,
    weightKg: 100,
  }).filter((r) => r.eligibility.eligible);
  assert.equal(before.length, 1);

  opsDeleteUser(store, { actingUserId: ops.userId, userId: driver.user.id });

  const after = customerEligibleAnchorTripsPhaseA(store, {
    pickup: origin,
    drop: destination,
    weightKg: 100,
  }).filter((r) => r.eligibility.eligible);
  assert.equal(after.length, 0);

  assert.throws(
    () =>
      publishAnchorTripAsPilotDriver(store, {
        userId: driver.user.id,
        orgId: driver.org.id,
        originCity: "Gurugram",
        destCity: "Jaipur",
        windowStart: "2026-04-26T00:00:00+05:30",
        windowEnd: "2026-04-27T23:59:59+05:30",
        vehicleClass: "MEDIUM",
        capacityKg: 1000,
      }),
    (e: unknown) => e instanceof Error && e.message === "org_inactive",
  );
});
