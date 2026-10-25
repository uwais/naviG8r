// An invite adds a phone to the inviter's organisation. It must not move someone off another carrier, and the
// reply carries only what the inviter typed plus the new membership, never the invitee's stored name or user id.
import test from "node:test";
import assert from "node:assert/strict";
import { httpFixture } from "../test/httpFixtures.ts";
import { inviteCarrierDriver, registerCustomerUser } from "./services.ts";

const driverInvite = { role: "DRIVER", vehicleRegistrationNumber: "TEST-INVITE", vehicleClass: "MEDIUM", vehicleCapacityKg: 1000 };

test("a carrier cannot invite the owner of another carrier, and that carrier's profile and truck stay put", async t => {
  const f = await httpFixture(t);
  const before = structuredClone(f.store.driverProfiles.get(f.carrierB.user.id));
  const out = await f.request("/v1/pilot/carrier/drivers/invite", "POST", { ...driverInvite, orgId: f.carrierA.org.id, phone: f.carrierB.user.phone }, f.tokens.carrierA);
  assert.equal(out.status, 409);
  assert.equal(out.body.detail, "This number belongs to someone at another carrier.");
  assert.deepEqual(f.store.driverProfiles.get(f.carrierB.user.id), before);
  assert.equal(f.store.memberships.has(`${f.carrierB.user.id}:${f.carrierA.org.id}`), false);
});

test("a carrier cannot invite a driver who works for another carrier", async t => {
  const f = await httpFixture(t);
  registerCustomerUser(f.store, { fullName: "Synthetic Driver Of B", phone: "8000000021" });
  const hired = inviteCarrierDriver(f.store, f.carrierB.user.id, { ...driverInvite, role: "DRIVER", vehicleClass: "MEDIUM", orgId: f.carrierB.org.id, phone: "8000000021" });
  const out = await f.request("/v1/pilot/carrier/drivers/invite", "POST", { ...driverInvite, orgId: f.carrierA.org.id, phone: "8000000021", role: "DISPATCHER" }, f.tokens.carrierA);
  assert.equal(out.status, 409);
  assert.equal(f.store.driverProfiles.get(hired.user.id)?.orgId, f.carrierB.org.id);
  assert.equal(f.store.driverProfiles.get(hired.user.id)?.primaryVehicleId, hired.vehicle.id);
});

test("the carrier invite reply does not carry the invitee's stored name or user id", async t => {
  const f = await httpFixture(t);
  const invitee = registerCustomerUser(f.store, { fullName: "Synthetic Private Name", phone: "8000000022" });
  const out = await f.request("/v1/pilot/carrier/drivers/invite", "POST", { ...driverInvite, orgId: f.carrierA.org.id, phone: "8000000022" }, f.tokens.carrierA);
  assert.equal(out.status, 201);
  assert.equal(out.body.membership.role, "DRIVER");
  assert.equal(out.body.vehicle.registrationNumber, "TEST-INVITE");
  const reply = JSON.stringify(out.body);
  assert.equal(reply.includes("Synthetic Private Name"), false);
  assert.equal(reply.includes(invitee.user.id), false);
});

test("the shipper team invite reply does not carry the invitee's stored name or user id", async t => {
  const f = await httpFixture(t);
  const invitee = registerCustomerUser(f.store, { fullName: "Synthetic Private Teammate", phone: "8000000023" });
  const out = await f.request("/v1/pilot/customer/members/invite", "POST", { orgId: f.shipperA.org.id, phone: "8000000023" }, f.tokens.shipperA);
  assert.equal(out.status, 201);
  assert.equal(out.body.membership.role, "CUSTOMER_MEMBER");
  const reply = JSON.stringify(out.body);
  assert.equal(reply.includes("Synthetic Private Teammate"), false);
  assert.equal(reply.includes(invitee.user.id), false);
});
