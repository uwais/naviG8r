// Owner decision, 21 Oct 2026: quotes, rate estimates and booking are for companies NaviG8r has approved, plus NaviG8r ops.
import test from "node:test";
import assert from "node:assert/strict";
import { httpFixture } from "../test/httpFixtures.ts";

const quoteBody = { weightKg: 10, pickup: { lat: 12.97, lng: 77.59 }, drop: { lat: 13.08, lng: 80.27 } };
const estimateBody = { origin: { lat: 12.97, lng: 77.59 }, destination: { lat: 13.08, lng: 80.27 }, vehicleClass: "MEDIUM" };

/** The HTTP fixture approves every company; this puts one back to waiting for NaviG8r. */
function notYetApproved(f: Awaited<ReturnType<typeof httpFixture>>, orgId: string) {
  f.store.organizations.set(orgId, { ...f.store.organizations.get(orgId)!, kycStatus: "NOT_STARTED" });
}

test("ops can approve a shipper company with the same review route it uses for carriers", async t => {
  const f = await httpFixture(t);
  const orgId = f.shipperA.org.id;
  notYetApproved(f, orgId);
  const reviewed = await f.request(`/v1/organizations/${orgId}/kyc`, "POST", { status: "APPROVED" }, f.tokens.ops, { "x-reason-code": "DOCUMENTS_REVIEWED" });
  assert.equal(reviewed.status, 200);
  assert.equal(reviewed.body.org.kycStatus, "APPROVED");
  assert.equal(reviewed.body.org.kind, "CUSTOMER");
});

test("a shipper gets a quote only after NaviG8r approves its company", async t => {
  const f = await httpFixture(t);
  notYetApproved(f, f.shipperA.org.id);
  const refused = await f.request("/shipments/quote", "POST", quoteBody, f.tokens.shipperA);
  assert.equal(refused.status, 403);
  assert.equal(refused.body.error, "company_not_approved");
  assert.equal(refused.body.quote, undefined);

  await f.request(`/v1/organizations/${f.shipperA.org.id}/kyc`, "POST", { status: "APPROVED" }, f.tokens.ops, { "x-reason-code": "DOCUMENTS_REVIEWED" });
  const quoted = await f.request("/shipments/quote", "POST", quoteBody, f.tokens.shipperA);
  assert.equal(quoted.status, 200);
  assert.equal(typeof quoted.body.quote.grossPaise, "number");
});

test("a shipper books only after NaviG8r approves its company", async t => {
  const f = await httpFixture(t);
  for (const status of ["NOT_STARTED", "SUBMITTED", "REJECTED"] as const) {
    f.store.organizations.set(f.shipperA.org.id, { ...f.store.organizations.get(f.shipperA.org.id)!, kycStatus: status });
    const refused = await f.book();
    assert.equal(refused.status, 403, status);
    assert.equal(refused.body.error, "company_not_approved", status);
    assert.equal(refused.body.shipment, undefined, status);
  }
  assert.equal(f.store.shipments.size, 0, "no refused booking leaves a shipment behind");

  await f.request(`/v1/organizations/${f.shipperA.org.id}/kyc`, "POST", { status: "APPROVED" }, f.tokens.ops, { "x-reason-code": "DOCUMENTS_REVIEWED" });
  const booked = await f.book();
  assert.equal(booked.status, 201);
  assert.equal(booked.body.shipment.customerOrgId, f.shipperA.org.id);
});

test("ops gets a quote without a company approval of its own", async t => {
  const f = await httpFixture(t);
  const quoted = await f.request("/shipments/quote", "POST", quoteBody, f.tokens.ops);
  assert.equal(quoted.status, 200);
});

test("a carrier gets a rate estimate only while NaviG8r has its company approved", async t => {
  const f = await httpFixture(t);
  assert.equal((await f.request("/v1/pilot/rates/estimate", "POST", estimateBody, f.tokens.carrierA)).status, 200, "approved in the fixture");
  for (const status of ["NOT_STARTED", "SUBMITTED", "REJECTED"] as const) {
    f.store.organizations.set(f.carrierA.org.id, { ...f.store.organizations.get(f.carrierA.org.id)!, kycStatus: status });
    const refused = await f.request("/v1/pilot/rates/estimate", "POST", estimateBody, f.tokens.carrierA);
    assert.equal(refused.status, 403, status);
    assert.equal(refused.body.error, "company_not_approved", status);
    assert.equal(refused.body.samples, undefined, status);
  }
});

test("each login gets at most 30 quotes and 120 rate estimates an hour", async t => {
  const f = await httpFixture(t);
  for (const [path, body, token, other, perHour] of [
    ["/shipments/quote", quoteBody, f.tokens.shipperA, f.tokens.shipperB, 30],
    ["/v1/pilot/rates/estimate", estimateBody, f.tokens.carrierA, f.tokens.carrierB, 120],
  ] as const) {
    for (let call = 1; call <= perHour; call += 1) assert.equal((await f.request(path, "POST", body, token)).status, 200, `${path} call ${call}`);
    const limited = await f.request(path, "POST", body, token);
    assert.equal(limited.status, 429, path);
    assert.equal(limited.body.error, "rate_limited", path);
    assert.equal((await f.request(path, "POST", body, other)).status, 200, `${path}: another login keeps its own count`);
  }
});

test("a shipper company waiting for approval is in the ops approval list until ops approves it", async t => {
  const f = await httpFixture(t);
  const waiting = async () => (await f.request("/ops/compliance/pending", "GET", undefined, f.tokens.ops)).body.organizations.map((o: { id: string }) => o.id);
  notYetApproved(f, f.shipperA.org.id);
  assert.deepEqual(await waiting(), [f.shipperA.org.id]);
  await f.request(`/v1/organizations/${f.shipperA.org.id}/kyc`, "POST", { status: "APPROVED" }, f.tokens.ops, { "x-reason-code": "DOCUMENTS_REVIEWED" });
  assert.deepEqual(await waiting(), []);
});

test("ops books for a shipper company only once NaviG8r has approved that company", async t => {
  const f = await httpFixture(t);
  const bookFor = () => f.request("/shipments/book", "POST", { anchorTripId: f.trip.id, customerOrgId: f.shipperA.org.id, weightKg: 10, pickupAddress: "Synthetic A", dropAddress: "Synthetic B" }, f.tokens.ops, { "x-reason-code": "CUSTOMER_REQUEST", "x-effective-actor-id": f.shipperA.user.id });
  notYetApproved(f, f.shipperA.org.id);
  const refused = await bookFor();
  assert.equal(refused.status, 403);
  assert.equal(refused.body.error, "company_not_approved");
  assert.equal(f.store.shipments.size, 0, "no refused booking leaves a shipment behind");

  await f.request(`/v1/organizations/${f.shipperA.org.id}/kyc`, "POST", { status: "APPROVED" }, f.tokens.ops, { "x-reason-code": "DOCUMENTS_REVIEWED" });
  const booked = await bookFor();
  assert.equal(booked.status, 201);
  assert.equal(booked.body.shipment.customerOrgId, f.shipperA.org.id);
});
