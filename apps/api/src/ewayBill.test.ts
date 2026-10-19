import test from "node:test";
import assert from "node:assert/strict";
import { httpFixture } from "../test/httpFixtures.ts";
import { loadStoreFromDisk } from "./persistence.ts";
import { inviteCarrierDriver, registerCustomerUser } from "./services.ts";
import { getIntegrationShipmentSnapshot, getIntegrationShipmentTracking } from "./integrationServices.ts";
import { checkEwayBillDetails, checkEwayBillStatement, indiaDateString } from "./ewayBillValidation.ts";

const goodBill = { kind: "BILL", billNumber: "1234 5678 9012", billDate: "2026-10-01", makerGstin: "29abcde1234f1z5", invoiceNumber: "INV/2026/001" };

async function bookedShipment(f: Awaited<ReturnType<typeof httpFixture>>) {
  const booking = await f.book(); assert.equal(booking.status, 201);
  const id = booking.body.shipment.id as string;
  assert.equal((await f.request(`/v1/pilot/carrier/shipments/${id}/accept`, "POST", {}, f.tokens.carrierA)).status, 200);
  return id;
}

test("the shipper adds a bill; format typos are refused with a plain sentence and the field", async t => {
  const f = await httpFixture(t); const id = await bookedShipment(f); const route = `/shipments/${id}/eway-bill`;
  for (const change of [{ billNumber: "12345" }, { billDate: "2026-02-31" }, { billDate: "2999-01-01" }, { makerGstin: "NOPE" }, { invoiceNumber: "" }]) {
    const refused = await f.request(route, "POST", { ...goodBill, ...change }, f.tokens.shipperA);
    assert.equal(refused.status, 400); assert.equal(refused.body.field, Object.keys(change)[0]); assert.ok(/[.]$/.test(refused.body.detail), "detail is a sentence");
  }
  assert.equal((await f.request(route, "POST", { kind: "SOMETHING" }, f.tokens.shipperA)).body.field, "kind");
  const saved = await f.request(route, "POST", goodBill, f.tokens.shipperA);
  assert.equal(saved.status, 200);
  assert.deepEqual(
    { number: saved.body.shipment.ewayBill.billNumber, gstin: saved.body.shipment.ewayBill.makerGstin, check: saved.body.shipment.ewayBill.check },
    { number: "123456789012", gstin: "29ABCDE1234F1Z5", check: undefined },
  );
  assert.equal(saved.body.shipment.ewayBill.enteredByUserId, undefined, "user ids stay on the server");
  const restored = loadStoreFromDisk(f.dataFilePath!);
  assert.equal(restored.shipments.get(id)?.ewayBill?.billNumber, "123456789012", "the bill survives a restart");
});

test("a statement that no bill is needed needs a reason, and 'Other' needs words", () => {
  assert.equal(checkEwayBillStatement({}).ok, false);
  assert.equal(checkEwayBillStatement({ reason: "OTHER" }).ok, false);
  assert.equal(checkEwayBillStatement({ reason: "OTHER", note: "ab" }).ok, false);
  assert.deepEqual(checkEwayBillStatement({ reason: "GOODS_EXEMPT", note: "ignored" }), { ok: true, value: { reason: "GOODS_EXEMPT" } });
  assert.equal(checkEwayBillDetails(goodBill, Date.UTC(2026, 9, 14)).ok, true);
  assert.equal(indiaDateString(Date.UTC(2026, 9, 14, 19, 0)), "2026-10-15", "19:00 UTC is already the next day in India");
});

test("each role gets its own cut of the bill; finance, admin and other shippers get none", async t => {
  const f = await httpFixture(t); const id = await bookedShipment(f);
  assert.equal((await f.request(`/shipments/${id}/eway-bill`, "POST", goodBill, f.tokens.shipperA)).status, 200);
  registerCustomerUser(f.store, { fullName: "Synthetic Driver", phone: "8000000013" });
  const driver = inviteCarrierDriver(f.store, f.carrierA.user.id, { orgId: f.carrierA.org.id, phone: "8000000013", role: "DRIVER", vehicleRegistrationNumber: "TEST-D", vehicleClass: "MEDIUM", vehicleCapacityKg: 1000 });
  assert.equal((await f.request(`/v1/pilot/anchor-trips/${f.trip.id}/assignment`, "POST", { vehicleId: driver.vehicle.id, driverUserId: driver.user.id }, f.tokens.carrierA)).status, 200, "a driver sees only a trip naming them");
  const driverToken = await f.login("8000000013");
  const shipperView = (await f.request(`/shipments/${id}`, "GET", undefined, f.tokens.shipperA)).body.shipment.ewayBill;
  assert.equal(shipperView.invoiceNumber, "INV/2026/001"); assert.equal(shipperView.billDate, "2026-10-01");
  const opsView = (await f.request(`/ops/shipments/${id}`, "GET", undefined, f.tokens.ops)).body.shipment.ewayBill;
  assert.equal(opsView.makerGstin, "29ABCDE1234F1Z5");
  for (const token of [f.tokens.carrierA, driverToken]) {
    const list = await f.request("/v1/pilot/carrier/shipments", "GET", undefined, token);
    const seen = (list.body.shipments as Array<{ id: string; ewayBill?: Record<string, unknown> }>).find(s => s.id === id)!.ewayBill!;
    assert.equal(seen.billNumber, "123456789012");
    for (const hidden of ["billDate", "makerGstin", "invoiceNumber", "enteredAtUtcMs", "enteredByUserId"]) assert.equal(seen[hidden], undefined, `${hidden} is not for carriers`);
    assert.equal(JSON.stringify(list.body).includes("INV/2026"), false);
    assert.equal(JSON.stringify(list.body).includes("29ABCDE"), false);
  }
  assert.equal(driver.user.id.length > 0, true);
  assert.equal((await f.request(`/shipments/${id}`, "GET", undefined, f.tokens.shipperB)).status, 404);
  // No response for any role may carry who entered or checked a bill.
  await f.request(`/ops/eway-bills/${id}/check`, "POST", { result: "FOUND", billNumber: "123456789012" }, f.tokens.ops);
  for (const [path, token] of [[`/shipments/${id}`, f.tokens.shipperA], ["/shipments", f.tokens.shipperA], ["/v1/pilot/carrier/shipments", f.tokens.carrierA], ["/v1/pilot/carrier/shipments", driverToken], [`/ops/shipments/${id}`, f.tokens.ops], ["/ops/eway-bills", f.tokens.ops]] as const) {
    const text = JSON.stringify((await f.request(path, "GET", undefined, token)).body);
    assert.equal(text.includes("enteredByUserId") || text.includes("checkedByUserId"), false, `user ids leaked on ${path}`);
  }
  for (const token of [f.tokens.finance, f.tokens.admin]) {
    const view = await f.request(`/ops/shipments/${id}`, "GET", undefined, token);
    assert.equal(view.body.shipment?.ewayBill, undefined);
    assert.equal(JSON.stringify(view.body).includes("123456789012"), false);
  }
});

test("only the shipper who owns the shipment can write; carriers, ops and other shippers cannot", async t => {
  const f = await httpFixture(t); const id = await bookedShipment(f); const route = `/shipments/${id}/eway-bill`;
  assert.equal((await f.request(route, "POST", goodBill)).status, 401);
  assert.equal((await f.request(route, "POST", goodBill, f.tokens.shipperB)).status, 404);
  for (const role of ["carrierA", "carrierB", "ops", "finance", "admin"] as const) assert.equal((await f.request(route, "POST", goodBill, f.tokens[role])).status, role === "carrierB" ? 404 : 403, role);
  assert.equal((await f.request(`${route}/remove`, "POST", {}, f.tokens.carrierA)).status, 403);
  assert.equal(loadStoreFromDisk(f.dataFilePath!).shipments.get(id)?.ewayBill, undefined);
});

test("ops lists, checks and reports a problem; any edit clears the check; typed text never reaches the audit log", async t => {
  const f = await httpFixture(t); const id = await bookedShipment(f); const second = (await f.book()).body.shipment.id as string;
  const lists = async () => (await f.request("/ops/eway-bills", "GET", undefined, f.tokens.ops)).body as { toCheck: Array<{ id: string }>; missing: Array<{ id: string }>; notNeeded: Array<{ id: string }> };
  assert.deepEqual((await lists()).missing.map(s => s.id), [id, second].sort((a, b) => (f.store.shipments.get(a)!.createdAtUtcMs - f.store.shipments.get(b)!.createdAtUtcMs) || a.localeCompare(b)));
  await f.request(`/shipments/${id}/eway-bill`, "POST", goodBill, f.tokens.shipperA);
  await f.request(`/shipments/${second}/eway-bill`, "POST", { kind: "NOT_NEEDED", reason: "OTHER", note: "SYNTHETIC PRIVATE REASON" }, f.tokens.shipperA);
  let seen = await lists();
  assert.deepEqual([seen.toCheck.map(s => s.id), seen.missing.length, seen.notNeeded.map(s => s.id)], [[id], 0, [second]]);
  const check = `/ops/eway-bills/${id}/check`;
  for (const role of ["shipperA", "carrierA", "finance", "admin"] as const) {
    assert.equal((await f.request(check, "POST", { result: "FOUND" }, f.tokens[role])).status, 403, role);
    assert.equal((await f.request("/ops/eway-bills", "GET", undefined, f.tokens[role])).status, 403, role);
  }
  assert.equal((await f.request("/ops/eway-bills")).status, 401);
  assert.equal((await f.request(check, "POST", { result: "PROBLEM" }, f.tokens.ops)).body.field, "problemReason");
  assert.equal((await f.request(check, "POST", { result: "MAYBE" }, f.tokens.ops)).body.field, "result");
  assert.equal((await f.request(`/ops/eway-bills/${second}/check`, "POST", { result: "FOUND" }, f.tokens.ops)).status, 409);
  const stale = await f.request(check, "POST", { result: "FOUND", billNumber: "999999999999" }, f.tokens.ops);
  assert.deepEqual([stale.status, stale.body.error], [409, "eway_bill_changed"], "a check for a bill the shipper replaced is refused");
  assert.equal(f.store.shipments.get(id)?.ewayBill?.check, undefined, "and nothing is stamped on the new bill");
  const problem = await f.request(check, "POST", { result: "PROBLEM", problemReason: "NOT_FOUND", billNumber: "123456789012" }, f.tokens.ops);
  assert.equal(problem.status, 200); assert.equal(problem.body.shipment.ewayBill.check.problemReason, "NOT_FOUND");
  assert.equal(problem.body.shipment.ewayBill.check.checkedByUserId, undefined);
  const carrierSees = (await f.request("/v1/pilot/carrier/shipments", "GET", undefined, f.tokens.carrierA)).body.shipments.find((s: { id: string }) => s.id === id).ewayBill;
  assert.equal(carrierSees.check.result, "PROBLEM");
  assert.equal((await lists()).toCheck.length, 0, "a checked bill leaves the to-check list");
  const found = await f.request(check, "POST", { result: "FOUND", billNumber: "123456789012" }, f.tokens.ops);
  assert.equal(found.body.shipment.ewayBill.check.result, "FOUND");
  const edited = await f.request(`/shipments/${id}/eway-bill`, "POST", { ...goodBill, invoiceNumber: "INV/2026/002" }, f.tokens.shipperA);
  assert.equal(edited.body.shipment.ewayBill.check, undefined, "editing clears what ops saw");
  assert.deepEqual((await lists()).toCheck.map(s => s.id), [id]);
  const restored = loadStoreFromDisk(f.dataFilePath!);
  const actions = [...restored.auditEvents.values()].map(e => e.action);
  for (const action of ["EWAY_BILL_ENTERED", "EWAY_BILL_NOT_NEEDED_STATED", "EWAY_BILL_CHECKED"]) assert.ok(actions.includes(action), action);
  const auditText = JSON.stringify([...restored.auditEvents.values()]);
  for (const typed of ["SYNTHETIC PRIVATE REASON", "123456789012", "INV/2026", "29ABCDE"]) assert.equal(auditText.includes(typed), false, typed);
});

test("removing returns to 'nothing added' and stays removed after a restart; delivered shipments are locked", async t => {
  const f = await httpFixture(t); const id = await bookedShipment(f); const route = `/shipments/${id}/eway-bill`;
  await f.request(route, "POST", goodBill, f.tokens.shipperA);
  const removed = await f.request(`${route}/remove`, "POST", {}, f.tokens.shipperA);
  assert.equal(removed.status, 200); assert.equal(removed.body.shipment.ewayBill, undefined);
  assert.equal(loadStoreFromDisk(f.dataFilePath!).shipments.get(id)?.ewayBill, undefined);
  assert.equal((await f.request(`${route}/remove`, "POST", {}, f.tokens.shipperA)).status, 200, "removing twice is harmless");
  assert.ok([...loadStoreFromDisk(f.dataFilePath!).auditEvents.values()].some(e => e.action === "EWAY_BILL_REMOVED"));
  f.store.shipments.set(id, { ...f.store.shipments.get(id)!, status: "DELIVERED" });
  const locked = await f.request(route, "POST", goodBill, f.tokens.shipperA);
  assert.equal(locked.status, 409); assert.equal(locked.body.error, "eway_bill_locked");
});

test("ERP snapshot and tracking never carry the bill", async t => {
  const f = await httpFixture(t); const id = await bookedShipment(f);
  await f.request(`/shipments/${id}/eway-bill`, "POST", goodBill, f.tokens.shipperA);
  const snapshot = getIntegrationShipmentSnapshot(f.store, f.shipperA.org.id, id);
  const tracking = getIntegrationShipmentTracking(f.store, f.shipperA.org.id, id);
  assert.equal(JSON.stringify(snapshot).includes("ewayBill"), false);
  assert.equal(JSON.stringify(snapshot).includes("123456789012"), false);
  assert.equal(JSON.stringify(tracking).includes("ewayBill"), false);
});

test("only the shipper adds the truck; every carrier login is refused; any change clears the check; carriers see truck and time", async t => {
  const f = await httpFixture(t); const id = await bookedShipment(f);
  registerCustomerUser(f.store, { fullName: "Synthetic Driver", phone: "8000000013" });
  const driver = inviteCarrierDriver(f.store, f.carrierA.user.id, { orgId: f.carrierA.org.id, phone: "8000000013", role: "DRIVER", vehicleRegistrationNumber: "TEST-D", vehicleClass: "MEDIUM", vehicleCapacityKg: 1000 });
  assert.equal((await f.request(`/v1/pilot/anchor-trips/${f.trip.id}/assignment`, "POST", { vehicleId: driver.vehicle.id, driverUserId: driver.user.id }, f.tokens.carrierA)).status, 200, "a driver sees only a trip naming them");
  const driverToken = await f.login("8000000013");
  const shipperRoute = `/shipments/${id}/eway-bill/truck`, carrierRoute = `/v1/pilot/carrier/shipments/${id}/eway-bill/truck`;
  const tomorrow = Date.now() + 24 * 60 * 60 * 1000;
  assert.equal((await f.request(shipperRoute, "POST", { truckNumber: "KA01AB1234", validUntilUtcMs: tomorrow }, f.tokens.shipperA)).body.error, "eway_bill_not_entered", "no truck before a bill");
  await f.request(`/shipments/${id}/eway-bill`, "POST", goodBill, f.tokens.shipperA);
  await f.request(`/ops/eway-bills/${id}/check`, "POST", { result: "FOUND", billNumber: "123456789012" }, f.tokens.ops);
  // The carrier only reads the bill (owner decision, 18 Oct 2026): refused on both routes, the same way as any missing permission.
  for (const [route, token, who] of [[carrierRoute, f.tokens.carrierA, "carrier owner, carrier route"], [shipperRoute, f.tokens.carrierA, "carrier owner, shipper route"], [carrierRoute, driverToken, "driver"], [shipperRoute, driverToken, "driver, shipper route"], [carrierRoute, f.tokens.shipperA, "shipper on the carrier route"]] as const) {
    const refused = await f.request(route, "POST", { truckNumber: "KA01AB1234", validUntilUtcMs: tomorrow }, token);
    assert.deepEqual([refused.status, refused.body.error], [403, "forbidden"], who);
  }
  assert.equal(f.store.shipments.get(id)!.ewayBill!.truckNumber, undefined, "no refused call wrote a truck");
  assert.equal((await f.request(carrierRoute, "POST", { truckNumber: "KA01AB1234", validUntilUtcMs: tomorrow }, f.tokens.carrierB)).status, 404);
  assert.equal((await f.request(shipperRoute, "POST", { truckNumber: "KA01AB1234", validUntilUtcMs: tomorrow }, f.tokens.shipperB)).status, 404);
  const refusedTruckChanges: Array<[Record<string, unknown>, string]> = [[{ truckNumber: "X" }, "truckNumber"], [{ validUntilUtcMs: Date.now() - 1000 }, "validUntilUtcMs"], [{ validUntilUtcMs: Date.now() + 90 * 86400000 }, "validUntilUtcMs"], [{ validUntilUtcMs: "tomorrow" }, "validUntilUtcMs"]];
  for (const [change, field] of refusedTruckChanges) {
    const refused = await f.request(shipperRoute, "POST", { truckNumber: "KA01AB1234", validUntilUtcMs: tomorrow, ...change }, f.tokens.shipperA);
    assert.deepEqual([refused.status, refused.body.field], [400, field]);
  }
  const added = await f.request(shipperRoute, "POST", { truckNumber: "ka 01-ab 1234", validUntilUtcMs: tomorrow }, f.tokens.shipperA);
  assert.equal(added.status, 200); assert.equal(added.body.shipment.ewayBill.truckNumber, "KA01AB1234");
  assert.equal(added.body.shipment.ewayBill.check, undefined, "adding the truck clears ops' check");
  for (const token of [f.tokens.carrierA, driverToken]) {
    const seen = (await f.request("/v1/pilot/carrier/shipments", "GET", undefined, token)).body.shipments.find((s: { id: string }) => s.id === id).ewayBill;
    assert.deepEqual([seen.truckNumber, seen.validUntilUtcMs, seen.makerGstin, seen.truckEnteredByUserId], ["KA01AB1234", Math.round(tomorrow), undefined, undefined]);
  }
  const edited = await f.request(`/shipments/${id}/eway-bill`, "POST", { ...goodBill, invoiceNumber: "INV/2026/009" }, f.tokens.shipperA);
  assert.equal(edited.body.shipment.ewayBill.truckNumber, "KA01AB1234", "editing the same bill keeps its truck");
  const other = await f.request(`/shipments/${id}/eway-bill`, "POST", { ...goodBill, billNumber: "210987654321" }, f.tokens.shipperA);
  assert.equal(other.body.shipment.ewayBill.truckNumber, undefined, "a different bill starts with no truck");
  assert.equal((await f.request(shipperRoute, "POST", { truckNumber: "MH12XY9876", validUntilUtcMs: tomorrow }, f.tokens.shipperA)).status, 200, "the shipper adds it again for the new bill");
  const restored = loadStoreFromDisk(f.dataFilePath!);
  assert.ok([...restored.auditEvents.values()].some(e => e.action === "EWAY_BILL_TRUCK_ADDED"));
  assert.equal(JSON.stringify([...restored.auditEvents.values()]).includes("KA01AB1234"), false, "no typed text in the audit log");
});
