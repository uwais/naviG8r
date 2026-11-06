// An invite adds a phone to the inviter's organisation. It must not move someone off another carrier, and the
// reply carries only what the inviter typed plus the new membership, never the invitee's stored name or user id.
import test from "node:test";
import assert from "node:assert/strict";
import { httpFixture } from "../test/httpFixtures.ts";
import { inviteCarrierDriver, registerCustomerUser } from "./services.ts";

const driverInvite = { role: "DRIVER", vehicleRegistrationNumber: "KA02XY9999", vehicleClass: "MEDIUM", vehicleCapacityKg: 1000 };

test("a carrier cannot invite someone at another carrier, and that person's profile and truck stay as they were", async t => {
  const f = await httpFixture(t);
  const profileBefore = f.store.driverProfiles.get(f.carrierB.user.id);
  const vehiclesBefore = f.store.vehicles.size;
  const invited = await f.request("/v1/pilot/carrier/drivers/invite", "POST", { ...driverInvite, orgId: f.carrierA.org.id, phone: f.carrierB.user.phone }, f.tokens.carrierA);
  assert.equal(invited.status, 409);
  assert.equal(invited.body.error, "member_of_another_carrier");
  assert.equal(invited.body.detail, "This number belongs to someone at another carrier and cannot be added yet.");
  assert.deepEqual(f.store.driverProfiles.get(f.carrierB.user.id), profileBefore);
  assert.equal(f.store.vehicles.size, vehiclesBefore, "no truck was added");
  assert.equal(f.store.memberships.has(`${f.carrierB.user.id}:${f.carrierA.org.id}`), false, "no membership in the inviting carrier");
});

test("a carrier cannot invite the owner of another carrier, and that carrier's profile and truck stay put", async t => {
  const f = await httpFixture(t);
  const before = structuredClone(f.store.driverProfiles.get(f.carrierB.user.id));
  const out = await f.request("/v1/pilot/carrier/drivers/invite", "POST", { ...driverInvite, orgId: f.carrierA.org.id, phone: f.carrierB.user.phone }, f.tokens.carrierA);
  assert.equal(out.status, 409);
  assert.equal(out.body.detail, "This number belongs to someone at another carrier and cannot be added yet.");
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

test("a carrier invite reply leaves out the invitee's name, phone and user id", async t => {
  const f = await httpFixture(t);
  const invitee = registerCustomerUser(f.store, { fullName: "Synthetic Invitee Driver", phone: "8000000013" });
  const invited = await f.request("/v1/pilot/carrier/drivers/invite", "POST", { ...driverInvite, orgId: f.carrierA.org.id, phone: "8000000013" }, f.tokens.carrierA);
  assert.equal(invited.status, 201);
  assert.equal(invited.body.membership.role, "DRIVER");
  assert.equal(invited.body.vehicle.registrationNumber, "KA02XY9999");
  const reply = JSON.stringify(invited.body);
  for (const known of [invitee.user.fullName, invitee.user.phone, invitee.user.id]) assert.equal(reply.includes(known), false, `reply holds ${known}`);
});

test("the carrier invite reply does not carry the invitee's stored name or user id", async t => {
  const f = await httpFixture(t);
  const invitee = registerCustomerUser(f.store, { fullName: "Synthetic Private Name", phone: "8000000022" });
  const out = await f.request("/v1/pilot/carrier/drivers/invite", "POST", { ...driverInvite, orgId: f.carrierA.org.id, phone: "8000000022" }, f.tokens.carrierA);
  assert.equal(out.status, 201);
  assert.equal(out.body.membership.role, "DRIVER");
  assert.equal(out.body.vehicle.registrationNumber, driverInvite.vehicleRegistrationNumber);
  const reply = JSON.stringify(out.body);
  assert.equal(reply.includes("Synthetic Private Name"), false);
  assert.equal(reply.includes(invitee.user.id), false);
});

test("a shipper invite reply leaves out the invitee's name, phone and user id", async t => {
  const f = await httpFixture(t);
  const invitee = registerCustomerUser(f.store, { fullName: "Synthetic Invitee Buyer", phone: "8000000014" });
  const invited = await f.request("/v1/pilot/customer/members/invite", "POST", { orgId: f.shipperA.org.id, phone: "8000000014" }, f.tokens.shipperA);
  assert.equal(invited.status, 201);
  assert.equal(invited.body.membership.role, "CUSTOMER_MEMBER");
  const reply = JSON.stringify(invited.body);
  for (const known of [invitee.user.fullName, invitee.user.phone, invitee.user.id]) assert.equal(reply.includes(known), false, `reply holds ${known}`);
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
