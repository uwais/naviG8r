import assert from "node:assert/strict";
import test from "node:test";
import { createStore } from "./store.ts";
import {
  ApiError,
  bookShipment,
  createCarrier,
  inviteCustomerMember,
  listCustomerOrgMembers,
  publishAnchorTrip,
  registerCustomerOrgAdmin,
  registerCustomerUser,
  shipmentVisibleToCustomerUser,
} from "./services.ts";

test("customer admin invites teammate who then sees org shipments", () => {
  const store = createStore();
  const carrier = createCarrier(store, "Carrier X");
  const trip = publishAnchorTrip(store, {
    carrierId: carrier.id,
    originCity: "Gurugram",
    destCity: "Jaipur",
    windowStart: "2026-04-24T00:00:00+05:30",
    windowEnd: "2026-04-25T23:59:59+05:30",
    vehicleClass: "MEDIUM",
    capacityKg: 1000,
  });

  const admin = registerCustomerOrgAdmin(store, {
    fullName: "ACME Admin",
    phone: "9111001100",
    orgDisplayName: "ACME Manufacturing",
  });
  const teammate = registerCustomerUser(store, {
    fullName: "ACME Buyer",
    phone: "9222002200",
  });

  const invited = inviteCustomerMember(store, admin.user.id, {
    orgId: admin.org.id,
    phone: teammate.user.phone,
  });
  assert.equal(invited.membership.role, "CUSTOMER_MEMBER");

  const shipment = bookShipment(store, {
    anchorTripId: trip.id,
    customerOrgName: admin.org.displayName,
    customerOrg: { id: admin.org.id, displayName: admin.org.displayName },
    bookedByUserId: admin.user.id,
    weightKg: 100,
    pickupAddress: "p",
    dropAddress: "d",
  });
  assert.equal(shipment.customerOrgId, admin.org.id);

  assert.ok(shipmentVisibleToCustomerUser(store, shipment, admin.user.id));
  assert.ok(shipmentVisibleToCustomerUser(store, shipment, teammate.user.id));

  const members = listCustomerOrgMembers(store, admin.user.id, admin.org.id);
  assert.equal(members.length, 2);
});

test("customer member cannot invite others", () => {
  const store = createStore();
  const admin = registerCustomerOrgAdmin(store, {
    fullName: "Admin",
    phone: "9111001101",
    orgDisplayName: "Retail Co",
  });
  const teammate = registerCustomerUser(store, {
    fullName: "Member",
    phone: "9222002201",
  });
  inviteCustomerMember(store, admin.user.id, {
    orgId: admin.org.id,
    phone: teammate.user.phone,
  });

  const other = registerCustomerUser(store, {
    fullName: "Other",
    phone: "9333003301",
  });

  assert.throws(
    () =>
      inviteCustomerMember(store, teammate.user.id, {
        orgId: admin.org.id,
        phone: other.user.phone,
      }),
    (e: unknown) => e instanceof Error && e.message === "forbidden",
  );
});

test("invite fails when user not registered", () => {
  const store = createStore();
  const admin = registerCustomerOrgAdmin(store, {
    fullName: "Admin",
    phone: "9111001102",
    orgDisplayName: "Factory",
  });

  assert.throws(
    () =>
      inviteCustomerMember(store, admin.user.id, {
        orgId: admin.org.id,
        phone: "9444004402",
      }),
    (e: unknown) => e instanceof ApiError && (e as ApiError).message === "user_not_found",
  );
});
