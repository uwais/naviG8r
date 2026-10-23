// Owner, 22 Oct 2026: each message says who it is from, and the Messages screen names its shipment. A person's
// name stays inside their own company: the shipper reads the carrier's company name and "Driver" or "Office",
// never its driver's name.
import test from "node:test";
import type { TestContext } from "node:test";
import assert from "node:assert/strict";
import { httpFixture } from "../test/httpFixtures.ts";
import { inviteCarrierDriver, registerCustomerUser } from "./services.ts";

/** Carrier A's driver on the fixture's trip, signed in, with a booked shipment on that trip. */
async function shipmentWithDriver(t: TestContext) {
  const f = await httpFixture(t);
  registerCustomerUser(f.store, { fullName: "Synthetic Driver Ravi", phone: "8000000013" });
  const driver = inviteCarrierDriver(f.store, f.carrierA.user.id, { orgId: f.carrierA.org.id, phone: "8000000013", role: "DRIVER", vehicleRegistrationNumber: "KA02XY9999", vehicleClass: "MEDIUM", vehicleCapacityKg: 1000 });
  const driverToken = await f.login("8000000013");
  assert.equal((await f.request(`/v1/pilot/anchor-trips/${f.trip.id}/assignment`, "POST", { vehicleId: driver.vehicle.id, driverUserId: driver.user.id }, f.tokens.carrierA)).status, 200);
  const shipmentId = (await f.book()).body.shipment.id as string;
  return { f, driver, driverToken, shipmentId };
}

type TimelineMessage = { type: string; body: string; senderLabel?: string };
const labelOf = (items: TimelineMessage[], body: string) => items.find(item => item.type === "message" && item.body === body)?.senderLabel;

test("a shipper reads the carrier's company name and Driver for a driver's message, never the driver's name", async t => {
  const { f, driverToken, shipmentId } = await shipmentWithDriver(t);
  registerCustomerUser(f.store, { fullName: "Synthetic Dispatcher Meena", phone: "8000000015" });
  inviteCarrierDriver(f.store, f.carrierA.user.id, { orgId: f.carrierA.org.id, phone: "8000000015", role: "DISPATCHER" });
  const dispatcherToken = await f.login("8000000015");
  const messagesPath = `/v1/shipments/${shipmentId}/conversation/messages`;
  const timelinePath = `/v1/shipments/${shipmentId}/conversation/timeline`;
  assert.equal((await f.request(messagesPath, "POST", { body: "Reached the pickup.", clientRequestId: "driver-1" }, driverToken)).status, 201);
  assert.equal((await f.request(messagesPath, "POST", { body: "Truck is booked for 9.", clientRequestId: "dispatcher-1" }, dispatcherToken)).status, 201);
  assert.equal((await f.request(messagesPath, "POST", { body: "Invoice is with the driver.", clientRequestId: "owner-1" }, f.tokens.carrierA)).status, 201);
  assert.equal((await f.request(messagesPath, "POST", { body: "Gate 2, please.", clientRequestId: "shipper-1" }, f.tokens.shipperA)).status, 201);

  const shipperView = await f.request(timelinePath, "GET", undefined, f.tokens.shipperA);
  assert.equal(shipperView.status, 200);
  assert.equal(labelOf(shipperView.body.items, "Reached the pickup."), "Synthetic Carrier A · Driver");
  assert.equal(labelOf(shipperView.body.items, "Truck is booked for 9."), "Synthetic Carrier A · Office", "a dispatcher is the office");
  assert.equal(labelOf(shipperView.body.items, "Invoice is with the driver."), "Synthetic Carrier A · Office", "the owner is the office");
  assert.equal(labelOf(shipperView.body.items, "Gate 2, please."), "You");
  const shipperText = JSON.stringify(shipperView.body);
  assert.equal(shipperText.includes("Ravi") || shipperText.includes("Meena"), false, "no carrier person's name reaches the shipper anywhere in the response");

  const driverView = await f.request(timelinePath, "GET", undefined, driverToken);
  assert.equal(labelOf(driverView.body.items, "Gate 2, please."), "Synthetic Shipper A", "the other company's name, not the person's");
  assert.equal(labelOf(driverView.body.items, "Reached the pickup."), "You");

  // The carrier's own owner reads the driver's name: same company.
  const ownerView = await f.request(timelinePath, "GET", undefined, f.tokens.carrierA);
  assert.equal(labelOf(ownerView.body.items, "Reached the pickup."), "Synthetic Driver Ravi");
});

test("a teammate with no name on file reads as Your team", async t => {
  const { f, driver, driverToken, shipmentId } = await shipmentWithDriver(t);
  f.store.users.set(driver.user.id, { ...f.store.users.get(driver.user.id)!, fullName: "  " });
  assert.equal((await f.request(`/v1/shipments/${shipmentId}/conversation/messages`, "POST", { body: "On the way.", clientRequestId: "driver-2" }, driverToken)).status, 201);
  const ownerView = await f.request(`/v1/shipments/${shipmentId}/conversation/timeline`, "GET", undefined, f.tokens.carrierA);
  assert.equal(labelOf(ownerView.body.items, "On the way."), "Your team");
});

test("a NaviG8r support message reads as NaviG8r, not the staff member's name", async t => {
  const { f, shipmentId } = await shipmentWithDriver(t);
  const request = await f.request(`/v1/shipments/${shipmentId}/conversation/escalations`, "POST", {
    granteeUserId: f.ops.userId, reason: "Shipper asked for help with pickup", canRead: true, canSend: true, expiresAtUtcMs: Date.now() + 60_000,
  }, f.tokens.shipperA);
  assert.equal(request.status, 201);
  assert.equal((await f.request(`/v1/conversation-escalations/${request.body.grant.id}/approve`, "POST", {}, f.tokens.admin)).status, 200);
  assert.equal((await f.request(`/v1/shipments/${shipmentId}/conversation/messages`, "POST", { body: "We are on it.", clientRequestId: "ops-1" }, f.tokens.ops)).status, 201);
  const shipperView = await f.request(`/v1/shipments/${shipmentId}/conversation/timeline`, "GET", undefined, f.tokens.shipperA);
  assert.equal(labelOf(shipperView.body.items, "We are on it."), "NaviG8r");
  assert.equal(JSON.stringify(shipperView.body).includes(f.store.users.get(f.ops.userId)!.fullName), false);
});

test("the timeline names its shipment by route and leave date, with no ID and no money in it", async t => {
  const { f, driverToken, shipmentId } = await shipmentWithDriver(t);
  f.store.shipments.set(shipmentId, { ...f.store.shipments.get(shipmentId)!, externalLoadId: "LOAD-778" });
  for (const token of [f.tokens.shipperA, f.tokens.carrierA, driverToken]) {
    const timeline = await f.request(`/v1/shipments/${shipmentId}/conversation/timeline`, "GET", undefined, token);
    assert.equal(timeline.status, 200);
    assert.deepEqual(timeline.body.shipmentSummary, { originCity: "A", destCity: "B", windowStart: "2026-09-16" });
    assert.doesNotMatch(JSON.stringify(timeline.body), /Paise|commission|gross|amount|price|fee/i);
  }
});

test("an owner the carrier named as the trip's driver reads as Driver to the shipper", async t => {
  const { f, driver, shipmentId } = await shipmentWithDriver(t);
  assert.equal((await f.request(`/v1/pilot/anchor-trips/${f.trip.id}/assignment`, "POST", { vehicleId: driver.vehicle.id, driverUserId: f.carrierA.user.id }, f.tokens.carrierA)).status, 200);
  assert.equal((await f.request(`/v1/shipments/${shipmentId}/conversation/messages`, "POST", { body: "Driving this one myself.", clientRequestId: "owner-drives-1" }, f.tokens.carrierA)).status, 201);
  const shipperView = await f.request(`/v1/shipments/${shipmentId}/conversation/timeline`, "GET", undefined, f.tokens.shipperA);
  assert.equal(labelOf(shipperView.body.items, "Driving this one myself."), "Synthetic Carrier A · Driver");
});

test("a message keeps the Driver or Office it was sent as when the trip is given to someone else", async t => {
  const { f, driver, shipmentId } = await shipmentWithDriver(t);
  const messagesPath = `/v1/shipments/${shipmentId}/conversation/messages`;
  assert.equal((await f.request(`/v1/pilot/anchor-trips/${f.trip.id}/assignment`, "POST", { vehicleId: driver.vehicle.id, driverUserId: f.carrierA.user.id }, f.tokens.carrierA)).status, 200);
  assert.equal((await f.request(messagesPath, "POST", { body: "Driving this one myself.", clientRequestId: "owner-drives-2" }, f.tokens.carrierA)).status, 201);
  assert.equal((await f.request(`/v1/pilot/anchor-trips/${f.trip.id}/assignment`, "POST", { vehicleId: driver.vehicle.id, driverUserId: driver.user.id }, f.tokens.carrierA)).status, 200);
  assert.equal((await f.request(messagesPath, "POST", { body: "Ravi drives from here.", clientRequestId: "owner-office-1" }, f.tokens.carrierA)).status, 201);

  const items = (await f.request(`/v1/shipments/${shipmentId}/conversation/timeline`, "GET", undefined, f.tokens.shipperA)).body.items;
  assert.equal(labelOf(items, "Driving this one myself."), "Synthetic Carrier A · Driver", "sent while the owner drove");
  assert.equal(labelOf(items, "Ravi drives from here."), "Synthetic Carrier A · Office");

  // A message kept before the role was stored is worked out from today's trip, as before.
  const older = [...f.store.conversationMessages.values()].find((message) => message.body === "Driving this one myself.")!;
  const { senderRoleLabel: _dropped, ...withoutRole } = older;
  f.store.conversationMessages.set(older.id, withoutRole);
  const recomputed = (await f.request(`/v1/shipments/${shipmentId}/conversation/timeline`, "GET", undefined, f.tokens.shipperA)).body.items;
  assert.equal(labelOf(recomputed, "Driving this one myself."), "Synthetic Carrier A · Office");
});

test("a message from another company carries no sender id; one from your own company does", async t => {
  const { f, driverToken, shipmentId } = await shipmentWithDriver(t);
  const messagesPath = `/v1/shipments/${shipmentId}/conversation/messages`;
  assert.equal((await f.request(messagesPath, "POST", { body: "Reached the pickup.", clientRequestId: "driver-ids" }, driverToken)).status, 201);
  assert.equal((await f.request(messagesPath, "POST", { body: "Gate 2, please.", clientRequestId: "shipper-ids" }, f.tokens.shipperA)).status, 201);
  const byBody = (items: Array<{ body: string; senderUserId?: string }>, body: string) => items.find((item) => item.body === body)!;

  const shipperItems = (await f.request(`/v1/shipments/${shipmentId}/conversation/timeline`, "GET", undefined, f.tokens.shipperA)).body.items;
  assert.equal("senderUserId" in byBody(shipperItems, "Reached the pickup."), false, "the label is enough");
  assert.equal(byBody(shipperItems, "Gate 2, please.").senderUserId, f.shipperA.user.id, "the app marks your own messages by it");

  const ownerItems = (await f.request(`/v1/shipments/${shipmentId}/conversation/timeline`, "GET", undefined, f.tokens.carrierA)).body.items;
  assert.ok(byBody(ownerItems, "Reached the pickup.").senderUserId, "same company");
  assert.equal("senderUserId" in byBody(ownerItems, "Gate 2, please."), false);
});
