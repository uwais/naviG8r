// Proof of delivery waits for the trip to start (owner, 23 Oct 2026): before the start, delivery cannot be
// confirmed and no delivery photo can be sent. A finished trip still takes a retry.
import assert from "node:assert/strict";
import test from "node:test";
import { httpFixture } from "../test/httpFixtures.ts";
import { addTestPodPhoto } from "../test/fixtures.ts";

const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xda, 0x00, 0x08, 1, 1, 0, 0, 0x3f, 0, 0x11, 0x11, 0xff, 0xd9]);
const refusal = { error: "trip_not_started", detail: "Start the trip first." };

async function acceptedBooking(f: Awaited<ReturnType<typeof httpFixture>>) {
  const id = (await f.book()).body.shipment.id as string;
  assert.equal((await f.request(`/v1/pilot/carrier/shipments/${id}/accept`, "POST", {}, f.tokens.carrierA)).status, 200);
  return id;
}

async function sendPhoto(f: Awaited<ReturnType<typeof httpFixture>>, id: string) {
  const response = await fetch(`${f.base}/v1/shipments/${id}/pod-photos`, {
    method: "POST", headers: { "content-type": "image/jpeg", authorization: `Bearer ${f.tokens.carrierA}` }, body: jpeg,
  });
  return { status: response.status, body: await response.json() };
}

function setTripStatus(f: Awaited<ReturnType<typeof httpFixture>>, status: "OPEN" | "FULL" | "IN_PROGRESS" | "COMPLETED") {
  f.store.anchorTrips.set(f.trip.id, { ...f.store.anchorTrips.get(f.trip.id)!, status });
}

for (const status of ["OPEN", "FULL"] as const) {
  test(`a trip still ${status}, not started, refuses delivery and photos, and changes nothing`, async t => {
    const f = await httpFixture(t);
    const id = await acceptedBooking(f);
    setTripStatus(f, status);
    addTestPodPhoto(f.store, id);
    const delivery = await f.request(`/shipments/${id}/driver-pod`, "POST", {}, f.tokens.carrierA);
    assert.equal(delivery.status, 409);
    assert.deepEqual({ error: delivery.body.error, detail: delivery.body.detail }, refusal);
    assert.equal(f.store.shipments.get(id)!.status, "BOOKED", "delivery is not confirmed");

    const photo = await sendPhoto(f, id);
    assert.equal(photo.status, 409);
    assert.deepEqual({ error: photo.body.error, detail: photo.body.detail }, refusal);
    assert.equal(f.store.shipments.get(id)!.podPhotos!.length, 1, "no photo is added");
  });
}

test("a trip on the way takes the photo and the delivery", async t => {
  const f = await httpFixture(t);
  const id = await acceptedBooking(f);
  setTripStatus(f, "IN_PROGRESS");
  assert.equal((await sendPhoto(f, id)).status, 201);
  assert.equal((await f.request(`/shipments/${id}/driver-pod`, "POST", {}, f.tokens.carrierA)).status, 200);
});

test("a finished trip still takes a retry", async t => {
  const f = await httpFixture(t);
  const id = await acceptedBooking(f);
  setTripStatus(f, "COMPLETED");
  assert.equal((await sendPhoto(f, id)).status, 201);
  assert.equal((await f.request(`/shipments/${id}/driver-pod`, "POST", {}, f.tokens.carrierA)).status, 200);
});
