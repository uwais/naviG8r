import test from "node:test";
import assert from "node:assert/strict";
import { httpFixture } from "../test/httpFixtures.ts";

test("a shipper's or carrier's own audit rows ignore the effective actor and reason headers", async t => {
  const f = await httpFixture(t);
  const madeUp = { "x-effective-actor-id": f.shipperB.user.id, "x-reason-code": "CUSTOMER_REQUEST" };
  const booking = { anchorTripId: f.trip.id, customerOrgName: "ignored", weightKg: 10, pickupAddress: "Synthetic A", dropAddress: "Synthetic B" };
  const booked = await f.request("/shipments/book", "POST", booking, f.tokens.shipperA, madeUp);
  assert.equal(booked.status, 201);
  const shipmentId = booked.body.shipment.id as string;
  assert.equal((await f.request(`/v1/pilot/carrier/shipments/${shipmentId}/accept`, "POST", {}, f.tokens.carrierA, madeUp)).status, 200);
  const rows = [...f.store.auditEvents.values()].filter(e => e.resourceId === shipmentId);
  assert.ok(rows.length > 0, "the booking wrote audit rows");
  for (const row of rows) {
    assert.equal(row.effectiveActorId, undefined, row.action);
    assert.equal(row.reasonCode, undefined, row.action);
    assert.equal(row.source, "USER", row.action);
  }
});

test("an ops-assisted booking still records who it was for and why", async t => {
  const f = await httpFixture(t);
  const booking = { anchorTripId: f.trip.id, customerOrgId: f.shipperA.org.id, weightKg: 10, pickupAddress: "A", dropAddress: "B" };
  const booked = await f.request("/shipments/book", "POST", booking, f.tokens.ops, { "x-reason-code": "CUSTOMER_REQUEST", "x-effective-actor-id": f.shipperA.user.id });
  assert.equal(booked.status, 201);
  const rows = [...f.store.auditEvents.values()].filter(e => e.resourceId === booked.body.shipment.id);
  assert.ok(rows.some(e => e.source === "OPS_ASSISTED" && e.effectiveActorId === f.shipperA.user.id && e.reasonCode === "CUSTOMER_REQUEST"));
});

test("an admin who is not ops keeps the reason but cannot say whom they acted for", async t => {
  const f = await httpFixture(t);
  const before = new Set(f.store.auditEvents.keys());
  const granted = await f.request("/v1/ops/dashboard-access", "POST", { userId: f.finance.user.id, roles: ["ADMIN", "FINANCE"] }, f.tokens.admin,
    { "x-reason-code": "ACCESS_REVIEW", "x-effective-actor-id": f.shipperA.user.id });
  assert.equal(granted.status, 200);
  const rows = [...f.store.auditEvents.entries()].filter(([id]) => !before.has(id)).map(([, e]) => e);
  assert.ok(rows.length > 0, "the grant wrote audit rows");
  for (const row of rows) {
    assert.equal(row.reasonCode, "ACCESS_REVIEW", row.action);
    assert.equal(row.effectiveActorId, undefined, row.action);
  }
});
