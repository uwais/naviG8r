// The reason code and the represented member are staff-only headers. A shipper or carrier who sends them must not
// get them written into the audit trail; ops acting for a member still records both.
import test from "node:test";
import assert from "node:assert/strict";
import type http from "node:http";
import { httpFixture } from "../test/httpFixtures.ts";
import { authorizationContext } from "./rbac.ts";
import { guardRequest, requestContext } from "./rbacRoutes.ts";

const staffHeaders = (memberUserId: string) => ({ "x-reason-code": "CUSTOMER_REQUEST", "x-effective-actor-id": memberUserId });

test("audit rows ignore reason and represented-member headers sent by a carrier or a shipper", async t => {
  const f = await httpFixture(t);
  const id = (await f.book()).body.shipment.id;
  assert.equal((await f.request(`/v1/pilot/carrier/shipments/${id}/accept`, "POST", {}, f.tokens.carrierA)).status, 200);
  assert.equal((await f.request(`/shipments/${id}/driver-pod`, "POST", {}, f.tokens.carrierA, staffHeaders(f.ops.user.id))).status, 200);
  assert.equal((await f.request(`/shipments/${id}/accept-pod`, "POST", {}, f.tokens.shipperA, staffHeaders(f.ops.user.id))).status, 200);
  for (const action of ["POD_UPLOADED", "POD_ACCEPTED"]) {
    const row = [...f.store.auditEvents.values()].find(e => e.action === action && e.resourceId === id);
    assert.ok(row, action);
    assert.equal(row.reasonCode, undefined, action);
    assert.equal(row.effectiveActorId, undefined, action);
    assert.equal(row.source, "USER", action);
  }
});

test("ops acting for a carrier member still records the reason and the represented member", async t => {
  const f = await httpFixture(t);
  const id = (await f.book()).body.shipment.id;
  assert.equal((await f.request(`/v1/pilot/carrier/shipments/${id}/accept`, "POST", {}, f.tokens.carrierA)).status, 200);
  assert.equal((await f.request(`/shipments/${id}/driver-pod`, "POST", {}, f.tokens.ops, staffHeaders(f.carrierA.user.id))).status, 200);
  const row = [...f.store.auditEvents.values()].find(e => e.action === "POD_UPLOADED" && e.resourceId === id);
  assert.ok(row);
  assert.equal(row.reasonCode, "CUSTOMER_REQUEST");
  assert.equal(row.effectiveActorId, f.carrierA.user.id);
  assert.equal(row.source, "OPS_ASSISTED");
});

test("only ops can name a represented member; an admin who is not ops sending the header records none", async t => {
  const f = await httpFixture(t);
  const representedMemberFor = (token: string) => {
    const req = { method: "GET", headers: { authorization: `Bearer ${token}`, ...staffHeaders(f.carrierA.user.id) } } as unknown as http.IncomingMessage;
    return authorizationContext.run(requestContext(), () => {
      guardRequest(req, f.store, new URL("http://test/v1/orgs"));
      return authorizationContext.getStore()!.effectiveActorId;
    });
  };
  assert.equal(representedMemberFor(f.tokens.admin), undefined);
});
