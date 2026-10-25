import test from "node:test";
import assert from "node:assert/strict";
import { httpFixture } from "../test/httpFixtures.ts";
import { registerCustomerUser } from "./services.ts";

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

test("a shipper invite reply leaves out the invitee's name, phone and user id", async t => {
  const f = await httpFixture(t);
  const invitee = registerCustomerUser(f.store, { fullName: "Synthetic Invitee Buyer", phone: "8000000014" });
  const invited = await f.request("/v1/pilot/customer/members/invite", "POST", { orgId: f.shipperA.org.id, phone: "8000000014" }, f.tokens.shipperA);
  assert.equal(invited.status, 201);
  assert.equal(invited.body.membership.role, "CUSTOMER_MEMBER");
  const reply = JSON.stringify(invited.body);
  for (const known of [invitee.user.fullName, invitee.user.phone, invitee.user.id]) assert.equal(reply.includes(known), false, `reply holds ${known}`);
});
