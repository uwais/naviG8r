// An e-way bill cannot be removed once its trip has started (owner, 23 Oct 2026): the truck is on the road with it.
// Editing it stays allowed.
import assert from "node:assert/strict";
import test from "node:test";
import { httpFixture } from "../test/httpFixtures.ts";

const bill = { kind: "BILL", billNumber: "123456789012", billDate: "2026-10-01", makerGstin: "29ABCDE1234F1Z5", invoiceNumber: "INV/1" };

async function shipmentWithBill(t: Parameters<typeof httpFixture>[0], tripStatus: "OPEN" | "IN_PROGRESS" | "COMPLETED") {
  const f = await httpFixture(t);
  const id = (await f.book()).body.shipment.id as string;
  assert.equal((await f.request(`/shipments/${id}/eway-bill`, "POST", bill, f.tokens.shipperA)).status, 200);
  f.store.anchorTrips.set(f.trip.id, { ...f.store.anchorTrips.get(f.trip.id)!, status: tripStatus });
  return { f, id };
}

for (const tripStatus of ["IN_PROGRESS", "COMPLETED"] as const) {
  test(`a trip ${tripStatus}: removal is refused and the bill stays; an edit still goes through`, async t => {
    const { f, id } = await shipmentWithBill(t, tripStatus);
    const removal = await f.request(`/shipments/${id}/eway-bill/remove`, "POST", {}, f.tokens.shipperA);
    assert.equal(removal.status, 409);
    assert.deepEqual({ error: removal.body.error, detail: removal.body.detail },
      { error: "trip_started", detail: "The trip has started, so the e-way bill cannot be removed." });
    assert.equal(f.store.shipments.get(id)!.ewayBill?.kind, "BILL", "the bill is still there");

    const edit = await f.request(`/shipments/${id}/eway-bill`, "POST", { ...bill, invoiceNumber: "INV/2" }, f.tokens.shipperA);
    assert.equal(edit.status, 200);
  });
}

test("before the start the bill can still be removed", async t => {
  const { f, id } = await shipmentWithBill(t, "OPEN");
  assert.equal((await f.request(`/shipments/${id}/eway-bill/remove`, "POST", {}, f.tokens.shipperA)).status, 200);
  assert.equal(f.store.shipments.get(id)!.ewayBill, undefined);
});
