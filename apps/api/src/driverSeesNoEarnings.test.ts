// Owner decision, 15 Oct 2026: a driver never sees carrier earnings. Owners, owner-drivers and dispatchers keep them.
import test from "node:test";
import assert from "node:assert/strict";
import { httpFixture } from "../test/httpFixtures.ts";
import { authorizationContext, effectivePermissions, resolvePrincipal } from "./rbac.ts";
import { serializeResponse } from "./rbacResponses.ts";
import { inviteCarrierDriver, registerCustomerUser } from "./services.ts";

test("only a driver loses payment.read", () => {
  assert.equal(effectivePermissions(["CARRIER"], "DRIVER").includes("payment.read"), false);
  for (const subrole of ["OWNER_DRIVER", "OWNER", "DISPATCHER"]) {
    assert.equal(effectivePermissions(["CARRIER"], subrole).includes("payment.read"), true, subrole);
  }
  assert.equal(effectivePermissions(["SHIPPER"], "CUSTOMER_ADMIN").includes("payment.read"), true);
});

test("a driver gets 403 on earnings, ledger and payout batches, and no carrier money or payment event anywhere; the office keeps them", async t => {
  const f = await httpFixture(t);
  const orgId = f.carrierA.org.id;
  registerCustomerUser(f.store, { fullName: "Synthetic Driver", phone: "8000000013" });
  const driver = inviteCarrierDriver(f.store, f.carrierA.user.id, { orgId, phone: "8000000013", role: "DRIVER", vehicleRegistrationNumber: "KA02XY9999", vehicleClass: "MEDIUM", vehicleCapacityKg: 1000 });
  registerCustomerUser(f.store, { fullName: "Synthetic Dispatcher", phone: "8000000015" });
  inviteCarrierDriver(f.store, f.carrierA.user.id, { orgId, phone: "8000000015", role: "DISPATCHER" });
  // No route invites an OWNER; ops onboarding makes one, so the membership is written directly.
  const owner = registerCustomerUser(f.store, { fullName: "Synthetic Owner", phone: "8000000016" });
  f.store.memberships.set(`${owner.user.id}:${orgId}`, { userId: owner.user.id, orgId, role: "OWNER", createdAtUtcMs: Date.now() });
  const tokens = { driver: await f.login("8000000013"), dispatcher: await f.login("8000000015"), owner: await f.login("8000000016"), ownerDriver: f.tokens.carrierA };
  assert.equal((await f.request(`/v1/pilot/anchor-trips/${f.trip.id}/assignment`, "POST", { vehicleId: driver.vehicle.id, driverUserId: driver.user.id }, tokens.ownerDriver)).status, 200);

  const delivered = (await f.book()).body.shipment.id as string;
  const accepted = await f.request(`/v1/pilot/carrier/shipments/${delivered}/accept`, "POST", {}, tokens.driver);
  assert.equal(accepted.status, 200);
  const refunded = (await f.book()).body.shipment.id as string;
  assert.equal((await f.request(`/v1/pilot/carrier/shipments/${refunded}/accept`, "POST", {}, tokens.ownerDriver)).status, 200);
  const delivery = await f.request(`/shipments/${delivered}/driver-pod`, "POST", {}, tokens.driver);
  assert.equal(delivery.status, 200);
  assert.equal((await f.request(`/shipments/${refunded}/fail-refund`, "POST", {}, f.tokens.finance)).status, 200, "a payment status changes");

  for (const route of ["earnings", "ledger", "payout-batches"]) {
    const path = `/v1/pilot/carrier/${route}?orgId=${orgId}`;
    assert.equal((await f.request(path, "GET", undefined, tokens.driver)).status, 403, route);
    for (const [who, token] of Object.entries({ owner: tokens.owner, ownerDriver: tokens.ownerDriver, dispatcher: tokens.dispatcher })) {
      assert.equal((await f.request(path, "GET", undefined, token)).status, 200, `${who} ${route}`);
    }
  }

  const get = async (path: string, token: string) => {
    const response = await f.request(path, "GET", undefined, token);
    assert.equal(response.status, 200, path);
    return response.body;
  };
  assert.equal(((await get("/v1/pilot/carrier/shipments", tokens.driver)).shipments as unknown[]).length, 2, "the driver sees both shipments");
  const driverSees = [
    accepted.body, delivery.body,
    await get("/v1/pilot/carrier/shipments", tokens.driver),
    await get(`/v1/pilot/carrier/shipments?anchorTripId=${f.trip.id}`, tokens.driver),
    await get(`/shipments/${delivered}/tracking`, tokens.driver),
    await get("/v1/pilot/anchor-trips", tokens.driver),
    await get(`/v1/pilot/anchor-trips/${f.trip.id}`, tokens.driver),
    await get("/v1/pilot/me", tokens.driver),
    await get("/v1/notifications", tokens.driver),
    await get("/v1/notifications/shipments", tokens.driver),
    await get(`/v1/shipments/${refunded}/conversation/timeline`, tokens.driver),
  ];
  const driverText = JSON.stringify(driverSees);
  for (const money of ["Paise", "₹", "payment.status_changed", "Payment status"]) {
    assert.equal(driverText.includes(money), false, `${money} reached the driver`);
  }
  assert.ok(((await get("/v1/notifications", tokens.driver)).notifications as unknown[]).length > 0, "the driver still hears about the trip");

  for (const [who, token] of Object.entries({ owner: tokens.owner, ownerDriver: tokens.ownerDriver, dispatcher: tokens.dispatcher })) {
    const rows = (await get("/v1/pilot/carrier/shipments", token)).shipments as Array<{ id: string; netToCarrierPaise?: number }>;
    assert.equal(typeof rows.find((row) => row.id === delivered)?.netToCarrierPaise, "number", `${who} still sees net to carrier`);
    const heard = (await get("/v1/notifications", token)).notifications as Array<{ eventKey: string; shipmentId: string }>;
    assert.ok(heard.some((item) => item.eventKey === "payment.status_changed" && item.shipmentId === refunded), `${who} is told about the payment`);
  }
  const summary = (await get(`/v1/pilot/carrier/earnings?orgId=${orgId}`, tokens.ownerDriver)).summary as Record<string, unknown>;
  assert.equal(typeof summary.pendingAccruedPaise, "number");
});

test("money fields with no branch of their own are dropped for a driver and kept for the office", async t => {
  const f = await httpFixture(t);
  registerCustomerUser(f.store, { fullName: "Synthetic Driver", phone: "8000000013" });
  const driver = inviteCarrierDriver(f.store, f.carrierA.user.id, { orgId: f.carrierA.org.id, phone: "8000000013", role: "DRIVER", vehicleRegistrationNumber: "KA02XY9999", vehicleClass: "MEDIUM", vehicleCapacityKg: 1000 });
  const payouts = {
    summary: { pendingAccruedPaise: 100, paidPaise: 200, bookedCount: 1 },
    payoutBatches: [{ id: "batch-1", totalNetToCarrierPaise: 300, transfers: [{ carrierId: f.carrierA.org.id, netToCarrierPaise: 300 }] }],
  };
  const serializedFor = (userId: string) => JSON.stringify(authorizationContext.run({ principal: resolvePrincipal(f.store, userId), requestId: "synthetic" }, () => serializeResponse(payouts)));
  const forDriver = serializedFor(driver.user.id);
  assert.equal(forDriver.includes("Paise"), false, forDriver);
  assert.ok(forDriver.includes("bookedCount"), "everything else stays");
  assert.equal(serializedFor(f.carrierA.user.id), JSON.stringify(payouts), "the owner-driver gets it all");
});
