import test from "node:test";
import type { TestContext } from "node:test";
import assert from "node:assert/strict";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import http from "node:http";
import { join } from "node:path";
import { httpFixture } from "../test/httpFixtures.ts";
import { startTestTrip } from "../test/fixtures.ts";
import { loadStoreFromDisk } from "./persistence.ts";
import { inviteCarrierDriver, publishAnchorTrip, registerCustomerUser } from "./services.ts";
import { getIntegrationShipmentSnapshot, getIntegrationShipmentTracking } from "./integrationServices.ts";
import { POD_PHOTO_MAX_BYTES, podPhotoDisk } from "./podPhotos.ts";
import { FakePage, inlineScript } from "../test/fakePage.ts";

type Fixture = Awaited<ReturnType<typeof httpFixture>>;

/** The smallest layout the server reads as a JPEG: start, one scan, end. Nothing decodes it. */
const jpeg = (fill = 0x11) => Buffer.from([0xff, 0xd8, 0xff, 0xda, 0x00, 0x08, 1, 1, 0, 0, 0x3f, 0, fill, fill, 0xff, 0xd9]);
const moneyWords = /paise|gross|commission|netToCarrier|payout|amount/i;

async function hireDriver(f: Fixture, phone: string, fullName: string, registrationNumber: string) {
  registerCustomerUser(f.store, { fullName, phone });
  const hired = inviteCarrierDriver(f.store, f.carrierA.user.id, { orgId: f.carrierA.org.id, phone, role: "DRIVER", vehicleRegistrationNumber: registrationNumber, vehicleClass: "MEDIUM", vehicleCapacityKg: 1000 });
  return { userId: hired.user.id, vehicleId: hired.vehicle.id, token: await f.login(phone) };
}

/**
 * Shipper A's booking on carrier A's trip, accepted, with the trip's driver named and a second driver who is not.
 * The trip is on the way, since photos wait for the start.
 */
async function deliveryWaitingForPhotos(t: TestContext) {
  const f = await httpFixture(t);
  const driver = await hireDriver(f, "8000000013", "Synthetic Driver One", "KA01AB1234");
  const otherDriver = await hireDriver(f, "8000000014", "Synthetic Driver Two", "KA02XY9999");
  const assigned = await f.request(`/v1/pilot/anchor-trips/${f.trip.id}/assignment`, "POST", { vehicleId: driver.vehicleId, driverUserId: driver.userId }, f.tokens.carrierA);
  assert.equal(assigned.status, 200);
  const booking = await f.book();
  assert.equal(booking.status, 201);
  const id = booking.body.shipment.id as string;
  assert.equal((await f.request(`/v1/pilot/carrier/shipments/${id}/accept`, "POST", {}, f.tokens.carrierA)).status, 200);
  startTestTrip(f.store, id);
  return { f, id, driver, otherDriver };
}

async function upload(f: Fixture, shipmentId: string, body: Buffer | ReadableStream, token: string, contentType = "image/jpeg") {
  const response = await fetch(`${f.base}/v1/shipments/${shipmentId}/pod-photos`, {
    method: "POST", headers: { "content-type": contentType, authorization: `Bearer ${token}` }, body, ...(body instanceof ReadableStream ? { duplex: "half" } : {}),
  } as RequestInit);
  return { status: response.status, body: await response.json() };
}

/**
 * An upload that declares its length and sends only [first] of the body until finish is called, as a phone on a
 * weak signal does. The answer can come before the body is done.
 */
function partialUpload(f: Fixture, shipmentId: string, token: string | null, declaredLength: number, first: Buffer) {
  const { hostname, port } = new URL(f.base);
  const request = http.request({
    hostname, port, method: "POST", path: `/v1/shipments/${shipmentId}/pod-photos`,
    headers: { "content-type": "image/jpeg", "content-length": declaredLength, ...(token ? { authorization: `Bearer ${token}` } : {}) },
  });
  const answered = new Promise<{ status: number; body: Record<string, unknown> }>((resolve, reject) => {
    request.on("response", (response) => {
      const chunks: Buffer[] = [];
      response.on("data", (chunk: Buffer) => chunks.push(chunk));
      response.on("end", () => resolve({ status: response.statusCode!, body: JSON.parse(Buffer.concat(chunks).toString("utf8")) }));
    });
    request.on("error", reject);
  });
  const written = new Promise<void>((resolve) => request.write(first, () => resolve()));
  return { answered, written, finish: (rest: Buffer) => request.end(rest), close: () => request.destroy() };
}

async function photo(f: Fixture, shipmentId: string, photoId: string, token: string) {
  const response = await fetch(`${f.base}/v1/shipments/${shipmentId}/pod-photos/${photoId}`, { headers: { authorization: `Bearer ${token}` } });
  return { status: response.status, headers: response.headers, bytes: Buffer.from(await response.arrayBuffer()) };
}

test("the trip's driver sends a photo: the file goes on disk beside the data file, and only what is known about it goes in the store", async t => {
  const { f, id, driver } = await deliveryWaitingForPhotos(t);
  const sent = await upload(f, id, jpeg(), driver.token);
  assert.equal(sent.status, 201);
  const photoId = sent.body.photo.id as string;
  assert.match(photoId, /^[0-9a-f-]{36}$/);
  assert.deepEqual(Object.keys(sent.body.photo).sort(), ["contentType", "id", "uploadedAtUtcMs"]);
  assert.equal(moneyWords.test(JSON.stringify(sent.body)), false, "no money in the answer");

  const file = join(f.dir, "pod-photos", id, `${photoId}.jpg`);
  assert.deepEqual(readFileSync(file), jpeg());
  assert.deepEqual(readdirSync(join(f.dir, "pod-photos", id)), [`${photoId}.jpg`], "no temporary file is left behind");
  const saved = loadStoreFromDisk(f.dataFilePath!).shipments.get(id)!.podPhotos!;
  assert.deepEqual(saved.map(({ id: savedId, contentType, bytes, uploadedByUserId }) => ({ savedId, contentType, bytes, uploadedByUserId })), [{ savedId: photoId, contentType: "image/jpeg", bytes: 16, uploadedByUserId: driver.userId }]);
  assert.match(saved[0]!.sha256, /^[0-9a-f]{64}$/);
  assert.equal(readFileSync(f.dataFilePath!, "utf8").includes(jpeg().toString("base64")), false, "the data file holds no photo");
  const added = [...f.store.auditEvents.values()].filter((event) => event.action === "POD_PHOTO_ADDED");
  assert.equal(added.length, 1);
  assert.equal(added[0]!.newState, `photo ${photoId} sha256 ${saved[0]!.sha256}`, "the audit row names the photo and its checksum");
});

test("too large is 413, not a photo is 415, and a fourth photo is 409", async t => {
  const { f, id, driver } = await deliveryWaitingForPhotos(t);
  const tooLarge = Buffer.concat([jpeg(), Buffer.alloc(POD_PHOTO_MAX_BYTES)]);
  assert.deepEqual([(await upload(f, id, tooLarge, driver.token)).status, (await upload(f, id, tooLarge, driver.token)).body.error], [413, "pod_photo_too_large"]);
  const streamed = new ReadableStream({ start(controller) { controller.enqueue(tooLarge); controller.close(); } });
  assert.equal((await upload(f, id, streamed, driver.token)).status, 413, "a body sent without its length is cut off at the limit too");

  for (const [body, contentType] of [[Buffer.from("not a photo"), "image/jpeg"], [Buffer.from("<svg xmlns='http://www.w3.org/2000/svg'/>"), "image/png"], [jpeg(), "text/html"], [jpeg().subarray(0, 14), "image/jpeg"], [Buffer.alloc(0), "image/jpeg"]] as const) {
    const refused = await upload(f, id, body, driver.token, contentType);
    assert.deepEqual([refused.status, refused.body.error], [415, "pod_photo_wrong_type"], `${contentType} ${body.length}`);
  }
  for (const fill of [1, 2, 3]) assert.equal((await upload(f, id, jpeg(fill), driver.token)).status, 201);
  const fourth = await upload(f, id, jpeg(4), driver.token);
  assert.deepEqual([fourth.status, fourth.body.error], [409, "pod_photo_limit"]);
  assert.equal(f.store.shipments.get(id)!.podPhotos!.length, 3);
});

test("a photo still on its way does not hold up anyone else's request", async t => {
  const { f, id, driver } = await deliveryWaitingForPhotos(t);
  let finish!: () => void;
  const rest = new Promise<void>((resolve) => { finish = resolve; });
  const slow = new ReadableStream({
    async start(controller) {
      controller.enqueue(jpeg().subarray(0, 8));
      await rest;
      controller.enqueue(jpeg().subarray(8));
      controller.close();
    },
  });
  const sending = upload(f, id, slow, driver.token);
  const other = await f.request(`/shipments/${id}`, "GET", undefined, f.tokens.shipperA);
  assert.equal(other.status, 200, "answered while the photo is half sent");
  assert.equal(other.body.shipment.podPhotos, undefined);
  finish();
  assert.equal((await sending).status, 201);
});

test("who sees a photo: its shipper, its carrier, the trip's driver and NaviG8r staff; anyone else gets 404", async t => {
  const { f, id, driver, otherDriver } = await deliveryWaitingForPhotos(t);
  const photoId = (await upload(f, id, jpeg(), driver.token)).body.photo.id as string;
  for (const [who, token] of [["shipper", f.tokens.shipperA], ["carrier", f.tokens.carrierA], ["driver", driver.token], ["ops", f.tokens.ops], ["finance", f.tokens.finance], ["admin", f.tokens.admin]] as const) {
    const seen = await photo(f, id, photoId, token);
    assert.equal(seen.status, 200, who);
    assert.deepEqual(seen.bytes, jpeg(), who);
  }
  for (const [who, token] of [["another shipper", f.tokens.shipperB], ["another carrier", f.tokens.carrierB], ["a driver not on this trip", otherDriver.token]] as const) {
    assert.equal((await photo(f, id, photoId, token)).status, 404, who);
  }
  assert.equal((await fetch(`${f.base}/v1/shipments/${id}/pod-photos/${photoId}`)).status, 401);
  assert.equal((await upload(f, id, jpeg(), otherDriver.token)).status, 404, "a driver not on this trip cannot add one");
  assert.equal((await upload(f, id, jpeg(), f.tokens.shipperA)).status, 403, "a shipper cannot add one");

  const seen = await photo(f, id, photoId, f.tokens.shipperA);
  assert.deepEqual(
    [seen.headers.get("content-type"), seen.headers.get("cache-control"), seen.headers.get("x-content-type-options"), seen.headers.get("content-length"), seen.headers.get("content-security-policy"), seen.headers.get("cross-origin-resource-policy")],
    ["image/jpeg", "private, no-store", "nosniff", "16", "default-src 'none'", "same-origin"],
  );
});

test("shipment answers list the photos without who sent them, and ERP answers leave them out", async t => {
  const { f, id, driver } = await deliveryWaitingForPhotos(t);
  const photoId = (await upload(f, id, jpeg(), driver.token)).body.photo.id as string;
  for (const [route, token] of [[`/shipments/${id}`, f.tokens.shipperA], [`/ops/shipments/${id}`, f.tokens.ops]] as const) {
    const listed = (await f.request(route, "GET", undefined, token)).body.shipment.podPhotos;
    assert.deepEqual(listed.map((item: Record<string, unknown>) => Object.keys(item).sort()), [["contentType", "id", "uploadedAtUtcMs"]], route);
    assert.equal(listed[0].id, photoId);
  }
  const carrierList = (await f.request("/v1/pilot/carrier/shipments", "GET", undefined, driver.token)).body.shipments;
  assert.equal(carrierList.find((item: { id: string }) => item.id === id).podPhotos[0].id, photoId);
  const orgId = f.shipperA.org.id;
  assert.equal("podPhotos" in getIntegrationShipmentSnapshot(f.store, orgId, id).shipment, false);
  assert.equal("podPhotos" in getIntegrationShipmentTracking(f.store, orgId, id).shipment, false);
});

test("a photo can be removed before delivery is confirmed, not after; a driver cannot confirm without one, ops still can", async t => {
  const { f, id, driver } = await deliveryWaitingForPhotos(t);
  const refused = await f.request(`/shipments/${id}/driver-pod`, "POST", {}, driver.token);
  assert.deepEqual([refused.status, refused.body.error], [409, "pod_photo_required"]);
  assert.ok(/[.]$/.test(refused.body.detail), "detail is a sentence");

  const first = (await upload(f, id, jpeg(1), driver.token)).body.photo.id as string;
  const removed = await f.request(`/v1/shipments/${id}/pod-photos/${first}`, "DELETE", undefined, driver.token);
  assert.deepEqual([removed.status, removed.body], [200, { removed: true }]);
  const removal = [...f.store.auditEvents.values()].find((event) => event.action === "POD_PHOTO_REMOVED")!;
  assert.match(removal.previousState ?? "", new RegExp(`^photo ${first} sha256 [0-9a-f]{64}$`), "the audit row names the photo and its checksum");
  assert.equal(existsSync(join(f.dir, "pod-photos", id, `${first}.jpg`)), false);
  assert.equal((await photo(f, id, first, driver.token)).status, 404);
  assert.equal((await f.request(`/v1/shipments/${id}/pod-photos/${first}`, "DELETE", undefined, driver.token)).status, 404);

  const second = (await upload(f, id, jpeg(2), driver.token)).body.photo.id as string;
  assert.equal((await f.request(`/shipments/${id}/driver-pod`, "POST", {}, driver.token)).status, 200);
  const closed = await f.request(`/v1/shipments/${id}/pod-photos/${second}`, "DELETE", undefined, driver.token);
  assert.deepEqual([closed.status, closed.body.error], [409, "pod_photos_closed"]);
  assert.equal((await upload(f, id, jpeg(3), driver.token)).status, 409, "no photo is added after delivery is confirmed");
  assert.equal((await photo(f, id, second, f.tokens.shipperA)).status, 200, "the shipper sees it once delivery is confirmed");

  // On a trip of its own: the first trip has started, so it takes no more bookings.
  const secondTrip = publishAnchorTrip(f.store, { carrierId: f.carrierA.org.id, originCity: "A", destCity: "B", windowStart: "2026-09-16", windowEnd: "2026-09-17", vehicleClass: "MEDIUM", capacityKg: 1000 });
  const assisted = (await f.book(f.tokens.shipperA, { anchorTripId: secondTrip.id })).body.shipment.id as string;
  assert.equal((await f.request(`/v1/pilot/carrier/shipments/${assisted}/accept`, "POST", {}, f.tokens.carrierA)).status, 200);
  startTestTrip(f.store, assisted);
  const byOps = await f.request(`/shipments/${assisted}/driver-pod`, "POST", {}, f.tokens.ops, { "x-reason-code": "DRIVER_NO_SIGNAL", "x-effective-actor-id": f.carrierA.user.id });
  assert.equal(byOps.status, 200, "ops confirming for the carrier needs no photo; the owner has not decided that");
});

test("a photo id or shipment id that tries to leave the photos folder is not found", async t => {
  const { f, id, driver } = await deliveryWaitingForPhotos(t);
  await upload(f, id, jpeg(), driver.token);
  for (const path of [
    `/v1/shipments/${id}/pod-photos/..%2F..%2Fsynthetic.json`,
    `/v1/shipments/${id}/pod-photos/%2E%2E%2F%2E%2E%2Fsynthetic.json`,
    `/v1/shipments/..%2F..%2F/pod-photos/x`,
    `/v1/shipments/${id}/pod-photos/00000000-0000-0000-0000-000000000000`,
  ]) {
    const response = await fetch(f.base + path, { headers: { authorization: `Bearer ${f.tokens.ops}` } });
    assert.equal(response.status, 404, path);
    assert.match(response.headers.get("content-type") ?? "", /application\/json/, path);
  }
  const removal = await fetch(`${f.base}/v1/shipments/${id}/pod-photos/..%2F..%2Fsynthetic.json`, { method: "DELETE", headers: { authorization: `Bearer ${driver.token}` } });
  assert.equal(removal.status, 404);
  assert.ok(existsSync(f.dataFilePath!), "the data file is untouched");
});

test("/ops/beta offers View photo on a shipment waiting for release, and its policy allows only its own and in-memory images", async t => {
  const { f, id, driver } = await deliveryWaitingForPhotos(t);
  for (const fill of [1, 2]) await upload(f, id, jpeg(fill), driver.token);
  assert.equal((await f.request(`/shipments/${id}/driver-pod`, "POST", {}, driver.token)).status, 200);
  const served = await fetch(f.base + "/ops/beta");
  assert.match(served.headers.get("content-security-policy") ?? "", /(^|; )img-src 'self' blob:(;|$)/);
  const page = new FakePage(f.base);
  page.session.set("navig8r_access", f.tokens.finance);
  page.run(inlineScript(await served.text()));
  await page.settle();
  const row = page.byId("paymentsBody").querySelectorAll("tr").find((candidate) => candidate.textContent.includes(id));
  assert.ok(row, "the shipment is listed");
  assert.ok(page.visibleButton("View photo 1", row) && page.visibleButton("View photo 2", row), row.textContent);
});

test("an upload with no sign-in, or from someone who may not add photos, is answered before its body is read", async t => {
  const { f, id, otherDriver } = await deliveryWaitingForPhotos(t);
  // Under the 1.5 MB limit, so only the checks made before reading can answer while the body is still coming.
  for (const [token, status, error] of [[null, 401, "unauthorized"], ["not-a-token", 401, "unauthorized"], [otherDriver.token, 404, "not_found"], [f.tokens.shipperA, 403, "forbidden"]] as const) {
    const sending = partialUpload(f, id, token, 1_000_000, jpeg().subarray(0, 8));
    const answer = await Promise.race([sending.answered, new Promise<null>((resolve) => setTimeout(() => resolve(null), 2000))]);
    sending.close();
    assert.ok(answer, `${status} answered while 999,992 bytes were still to come`);
    assert.deepEqual([answer.status, answer.body.error], [status, error]);
  }
  const missing = partialUpload(f, "no-such-shipment", f.tokens.carrierA, 1_000_000, jpeg().subarray(0, 8));
  assert.equal((await missing.answered).status, 404);
  missing.close();
  assert.equal(f.store.shipments.get(id)!.podPhotos, undefined);
});

/** Four of carrier A's trips on the way, each with its own driver and one accepted booking of shipper A. */
async function fourDeliveriesWaitingForPhotos(t: TestContext) {
  const f = await httpFixture(t);
  const deliveries: { id: string; token: string }[] = [];
  for (const n of [1, 2, 3, 4]) {
    const driver = await hireDriver(f, `800000003${n}`, `Synthetic Driver ${n}`, `KA0${n}CD123${n}`);
    const trip = publishAnchorTrip(f.store, { carrierId: f.carrierA.org.id, originCity: "A", destCity: "B", windowStart: `2026-10-${10 + 2 * n}`, windowEnd: `2026-10-${11 + 2 * n}`, vehicleClass: "MEDIUM", capacityKg: 1000 });
    assert.equal((await f.request(`/v1/pilot/anchor-trips/${trip.id}/assignment`, "POST", { vehicleId: driver.vehicleId, driverUserId: driver.userId }, f.tokens.carrierA)).status, 200);
    const booking = await f.book(f.tokens.shipperA, { anchorTripId: trip.id });
    assert.equal(booking.status, 201);
    const id = booking.body.shipment.id as string;
    assert.equal((await f.request(`/v1/pilot/carrier/shipments/${id}/accept`, "POST", {}, f.tokens.carrierA)).status, 200);
    startTestTrip(f.store, id);
    deliveries.push({ id, token: driver.token });
  }
  return { f, deliveries };
}

test("a fifth upload while four logins each have one being read is told to try again, and the four finish", async t => {
  const { f, deliveries } = await fourDeliveriesWaitingForPhotos(t);
  const slow = deliveries.map(({ id, token }) => partialUpload(f, id, token, jpeg().length, jpeg().subarray(0, 8)));
  await Promise.all(slow.map((sending) => sending.written));
  // The four are on the wire; a moment more and the server has read their headers.
  await new Promise((resolve) => setTimeout(resolve, 100));
  const fifth = await upload(f, deliveries[0]!.id, jpeg(), f.tokens.carrierA);
  assert.deepEqual([fifth.status, fifth.body.error], [503, "busy_try_again"]);
  for (const sending of slow) sending.finish(jpeg().subarray(8));
  const statuses = (await Promise.all(slow.map((sending) => sending.answered))).map((answer) => answer.status);
  assert.deepEqual(statuses, [201, 201, 201, 201]);
  assert.equal((await upload(f, deliveries[0]!.id, jpeg(9), f.tokens.carrierA)).status, 201, "the slots were given back");
});

test("a login with an upload still being read is told to try again for a second one; another login's upload goes through", async t => {
  const { f, id, driver } = await deliveryWaitingForPhotos(t);
  const slow = partialUpload(f, id, driver.token, jpeg().length, jpeg().subarray(0, 8));
  await slow.written;
  await new Promise((resolve) => setTimeout(resolve, 100));
  const second = await upload(f, id, jpeg(2), driver.token);
  assert.deepEqual([second.status, second.body.error], [503, "busy_try_again"]);
  assert.equal((await upload(f, id, jpeg(3), f.tokens.carrierA)).status, 201, "the carrier office is not held up by its driver");
  slow.finish(jpeg().subarray(8));
  assert.equal((await slow.answered).status, 201);
  assert.equal((await upload(f, id, jpeg(4), driver.token)).status, 201, "the driver's slot was given back");
});

test("with under 200 MB free the photo is refused with 507 and nothing is written", async t => {
  const { f, id, driver } = await deliveryWaitingForPhotos(t);
  const realFreeBytes = podPhotoDisk.freeBytes;
  podPhotoDisk.freeBytes = () => 200 * 1024 * 1024 - 1;
  t.after(() => { podPhotoDisk.freeBytes = realFreeBytes; });
  const refused = await upload(f, id, jpeg(), driver.token);
  assert.deepEqual([refused.status, refused.body.error, refused.body.detail], [507, "storage_full", "The server cannot take photos right now. Try again later."]);
  assert.deepEqual(readdirSync(join(f.dir, "pod-photos", id)), []);
  assert.equal(f.store.shipments.get(id)!.podPhotos, undefined);
});

test("a write that fails part way leaves no temporary file and no photo", async t => {
  const { f, id, driver } = await deliveryWaitingForPhotos(t);
  const realRename = podPhotoDisk.rename;
  podPhotoDisk.rename = () => { throw new Error("synthetic_rename_failed"); };
  t.after(() => { podPhotoDisk.rename = realRename; });
  const failed = await upload(f, id, jpeg(), driver.token);
  assert.notEqual(failed.status, 201);
  assert.deepEqual(readdirSync(join(f.dir, "pod-photos", id)), [], "the .tmp file is removed");
  assert.equal(f.store.shipments.get(id)!.podPhotos, undefined);
  assert.equal([...f.store.auditEvents.values()].some((event) => event.action === "POD_PHOTO_ADDED"), false);
});

test("a refused upload still carries the CORS answer, so the app in a browser can read why", async t => {
  const { f, id } = await deliveryWaitingForPhotos(t);
  const response = await fetch(`${f.base}/v1/shipments/${id}/pod-photos`, { method: "POST", headers: { "content-type": "image/jpeg", origin: "http://localhost:5555" }, body: jpeg() });
  assert.equal(response.status, 401);
  assert.equal(response.headers.get("access-control-allow-origin"), "http://localhost:5555");
});

test("the server confirms delivery only with a photo of that shipment, for the carrier office as for a driver", async t => {
  const f = await httpFixture(t);
  const [withPhoto, withoutPhoto] = [(await f.book()).body.shipment.id as string, (await f.book()).body.shipment.id as string];
  for (const id of [withPhoto, withoutPhoto]) assert.equal((await f.request(`/v1/pilot/carrier/shipments/${id}/accept`, "POST", {}, f.tokens.carrierA)).status, 200);
  startTestTrip(f.store, withPhoto);
  assert.equal((await upload(f, withPhoto, jpeg(), f.tokens.carrierA)).status, 201);

  const refused = await f.request(`/shipments/${withoutPhoto}/driver-pod`, "POST", {}, f.tokens.carrierA);
  assert.deepEqual([refused.status, refused.body.error], [409, "pod_photo_required"], "a photo on another shipment does not count");
  assert.deepEqual([f.store.shipments.get(withoutPhoto)?.status, f.store.shipments.get(withoutPhoto)?.podAtUtcMs], ["BOOKED", null]);
  assert.equal((await f.request(`/shipments/${withPhoto}/driver-pod`, "POST", {}, f.tokens.carrierA)).status, 200);
});
