// Owner decision, 21 Oct 2026: "No need for their own action". The person who did something is not
// told about it; their teammates and the other company still are. An event with no person behind it
// (a webhook, the payment provider, a timer) still goes to everyone who may hear it.
import test from "node:test";
import type { TestContext } from "node:test";
import assert from "node:assert/strict";
import { httpFixture } from "../test/httpFixtures.ts";
import { authorizationContext } from "./rbac.ts";
import { inviteCarrierDriver, registerCustomerUser } from "./services.ts";

/** Carrier A with a dispatcher and a driver on the fixture's trip, all signed in. */
async function carrierWithStaff(t: TestContext) {
  const f = await httpFixture(t);
  const orgId = f.carrierA.org.id;
  registerCustomerUser(f.store, { fullName: "Synthetic Dispatcher", phone: "8000000015" });
  const dispatcher = inviteCarrierDriver(f.store, f.carrierA.user.id, { orgId, phone: "8000000015", role: "DISPATCHER" });
  registerCustomerUser(f.store, { fullName: "Synthetic Driver", phone: "8000000013" });
  const driver = inviteCarrierDriver(f.store, f.carrierA.user.id, { orgId, phone: "8000000013", role: "DRIVER", vehicleRegistrationNumber: "KA02XY9999", vehicleClass: "MEDIUM", vehicleCapacityKg: 1000 });
  const tokens = { dispatcher: await f.login("8000000015"), driver: await f.login("8000000013") };
  assert.equal((await f.request(`/v1/pilot/anchor-trips/${f.trip.id}/assignment`, "POST", { vehicleId: driver.vehicle.id, driverUserId: driver.user.id }, f.tokens.carrierA)).status, 200);
  return { f, orgId, dispatcher, driver, tokens };
}

function heard(f: Awaited<ReturnType<typeof httpFixture>>, userId: string, eventKey: string, shipmentId: string): boolean {
  return [...f.store.notifications.values()].some(n => n.recipientUserId === userId && n.eventKey === eventKey && n.shipmentId === shipmentId);
}

test("the person who accepts gets no notice; a teammate and the shipper do", async t => {
  const { f, dispatcher, tokens } = await carrierWithStaff(t);
  const shipmentId = (await f.book()).body.shipment.id as string;
  assert.equal((await f.request(`/v1/pilot/carrier/shipments/${shipmentId}/accept`, "POST", {}, tokens.dispatcher)).status, 200);

  // A push is queued only for a notice (createNotifications), so no notice means no push either.
  assert.equal(heard(f, dispatcher.user.id, "shipment.carrier_accepted", shipmentId), false, "the actor gets nothing");
  assert.equal(heard(f, f.carrierA.user.id, "shipment.carrier_accepted", shipmentId), true, "the owner hears about a dispatcher's Accept");
  assert.equal(heard(f, f.shipperA.user.id, "shipment.carrier_accepted", shipmentId), true, "the other company hears");

  const inbox = await f.request("/v1/notifications", "GET", undefined, tokens.dispatcher);
  assert.equal(inbox.body.notifications.some((n: { eventKey: string }) => n.eventKey === "shipment.carrier_accepted"), false, "no inbox row for the actor");
});

test("the shipper who books gets no notice of their own booking; the carrier does", async t => {
  const f = await httpFixture(t);
  const shipmentId = (await f.book()).body.shipment.id as string;
  assert.equal(heard(f, f.shipperA.user.id, "shipment.booked", shipmentId), false);
  assert.equal(heard(f, f.carrierA.user.id, "shipment.booked", shipmentId), true);
});

test("a payment change with no person behind it still goes to everyone who may hear it, drivers excepted", async t => {
  const { f, dispatcher, driver } = await carrierWithStaff(t);
  const booked = (await f.book()).body.shipment;
  const shipmentId = booked.id as string;
  await authorizationContext.run({ system: true, requestId: "synthetic-provider-event" }, async () => {
    const payment = [...f.store.payments.values()].find(p => p.shipmentId === shipmentId)!;
    f.store.payments.set(payment.id, { ...payment, status: "REFUNDED", updatedAtUtcMs: Date.now() });
    await f.persist();
  });
  for (const [who, userId] of [["the shipper", f.shipperA.user.id], ["the owner", f.carrierA.user.id], ["the dispatcher", dispatcher.user.id]] as const) {
    assert.equal(heard(f, userId, "payment.status_changed", shipmentId), true, who);
  }
  assert.equal(heard(f, driver.user.id, "payment.status_changed", shipmentId), false, "never a driver");
});
