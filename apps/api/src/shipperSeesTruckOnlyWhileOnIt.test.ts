// A shipper sees where the truck is only while its own goods are on it: shipment BOOKED and trip IN_PROGRESS.
// The same rule holds in the app, the ERP API and the ERP webhooks.
import test from "node:test";
import type { TestContext } from "node:test";
import assert from "node:assert/strict";
import { httpFixture } from "../test/httpFixtures.ts";
import { addFinalTestEwayBill, addTestPodPhoto } from "../test/fixtures.ts";
import { reportAnchorTripLocation, startAnchorTripAsPilot } from "./services.ts";
import { getIntegrationShipmentSnapshot, getIntegrationShipmentTracking } from "./integrationServices.ts";
import { buildIntegrationEventPayload } from "./integrationWebhooks.ts";

const truckLat = 12.3456;

/**
 * Shipper A has two shipments on the moving truck; the first is then delivered while the second keeps the trip going.
 * Shipper B's booking was not paid, so the trip left without it.
 */
async function truckOnTheWay(t: TestContext) {
  const f = await httpFixture(t);
  const delivered = (await f.book(f.tokens.shipperA)).body.shipment.id as string;
  const stillOnTruck = (await f.book(f.tokens.shipperA)).body.shipment.id as string;
  const leftBehind = (await f.book(f.tokens.shipperB)).body.shipment.id as string;
  const unpaid = f.store.payments.get(f.store.shipments.get(leftBehind)!.paymentId)!;
  f.store.payments.set(unpaid.id, { ...unpaid, status: "CREATED" });
  for (const id of [delivered, stillOnTruck]) {
    assert.equal((await f.request(`/v1/pilot/carrier/shipments/${id}/accept`, "POST", {}, f.tokens.carrierA)).status, 200);
    addFinalTestEwayBill(f.store, id);
  }
  startAnchorTripAsPilot(f.store, { userId: f.carrierA.user.id, tripId: f.trip.id });
  reportAnchorTripLocation(f.store, f.carrierA.user.id, f.trip.id, { lat: truckLat, lng: 76.5432, recordedAtUtcMs: Date.now() });
  assert.equal(f.store.shipments.get(leftBehind)!.status, "FAILED_CARRIER_REFUNDED");
  async function deliverFirst() {
    addTestPodPhoto(f.store, delivered);
    assert.equal((await f.request(`/shipments/${delivered}/driver-pod`, "POST", {}, f.tokens.carrierA)).status, 200);
    assert.equal(f.store.anchorTrips.get(f.trip.id)!.status, "IN_PROGRESS", "the other shipment keeps the truck moving");
  }
  return { f, delivered, stillOnTruck, leftBehind, deliverFirst };
}

const showsTruck = (body: unknown) => JSON.stringify(body).includes(String(truckLat));

test("the app tracking route shows the truck to a shipper only while its goods are on the moving truck", async t => {
  const { f, delivered, stillOnTruck, leftBehind, deliverFirst } = await truckOnTheWay(t);
  const track = (id: string, token: string) => f.request(`/shipments/${id}/tracking`, "GET", undefined, token);
  assert.equal((await track(delivered, f.tokens.shipperA)).body.liveLocation.lat, truckLat);
  const other = await track(leftBehind, f.tokens.shipperB);
  assert.equal(other.status, 200);
  assert.equal(showsTruck(other.body), false, "a shipment not on the truck");

  await deliverFirst();
  const afterDelivery = await track(delivered, f.tokens.shipperA);
  assert.equal(afterDelivery.status, 200);
  assert.equal(showsTruck(afterDelivery.body), false, "a delivered shipment");
  assert.equal((await track(stillOnTruck, f.tokens.shipperA)).body.liveLocation.lat, truckLat, "a shipment still on the truck");
  assert.equal((await track(delivered, f.tokens.carrierA)).body.liveLocation.lat, truckLat, "the carrier still sees its truck");
});

test("the ERP tracking and shipment routes show the truck only while the shipper's goods are on the moving truck", async t => {
  const { f, delivered, stillOnTruck, leftBehind, deliverFirst } = await truckOnTheWay(t);
  assert.equal(getIntegrationShipmentTracking(f.store, f.shipperA.org.id, delivered).liveLocation?.lat, truckLat);
  assert.equal(showsTruck(getIntegrationShipmentTracking(f.store, f.shipperB.org.id, leftBehind)), false, "tracking, not on the truck");
  const snapshot = getIntegrationShipmentSnapshot(f.store, f.shipperB.org.id, leftBehind);
  assert.equal(showsTruck(snapshot), false, "shipment, not on the truck");
  assert.equal(JSON.stringify(snapshot).includes(f.carrierA.user.id), false, "the driver's user id stays with the carrier");

  await deliverFirst();
  assert.equal(showsTruck(getIntegrationShipmentTracking(f.store, f.shipperA.org.id, delivered)), false, "tracking, delivered");
  assert.equal(showsTruck(getIntegrationShipmentSnapshot(f.store, f.shipperA.org.id, delivered)), false, "shipment, delivered");
  assert.equal(getIntegrationShipmentTracking(f.store, f.shipperA.org.id, stillOnTruck).liveLocation?.lat, truckLat, "tracking, still on the truck");
});

test("an ERP webhook carries the truck's position only while the shipper's goods are on the moving truck", async t => {
  const { f, delivered, stillOnTruck, leftBehind, deliverFirst } = await truckOnTheWay(t);
  const payloadFor = (shipmentId: string) =>
    buildIntegrationEventPayload(f.store, { eventType: "load.location_updated", shipment: f.store.shipments.get(shipmentId)!, sequence: 1 });
  const lastLocationLat = (shipmentId: string) => (payloadFor(shipmentId).tracking as { lastLocation: { lat: number } | null }).lastLocation?.lat;
  assert.equal(lastLocationLat(delivered), truckLat);
  assert.equal(showsTruck(payloadFor(leftBehind)), false, "not on the truck");

  await deliverFirst();
  assert.equal(showsTruck(payloadFor(delivered)), false, "delivered");
  assert.equal(lastLocationLat(stillOnTruck), truckLat, "still on the truck");
});
