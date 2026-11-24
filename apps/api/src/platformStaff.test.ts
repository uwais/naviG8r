// Admins add NaviG8r staff from the staff pages. Only someone who may manage roles can list or change staff, a
// shipper or carrier number is never turned into staff, and the last admin always stays.
import test from "node:test";
import assert from "node:assert/strict";
import { httpFixture } from "../test/httpFixtures.ts";
import { FakePage, inlineScript } from "../test/fakePage.ts";
import { registerCustomerUser } from "./services.ts";

const reason = { "x-reason-code": "NEW_STAFF" };
const usStaff = { fullName: "Synthetic US Staff", phone: "2025550143", countryCode: "+1", roles: ["OPS"] };

test("only someone who may manage roles can list, add or change staff", async t => {
  const f = await httpFixture(t);
  for (const who of ["ops", "finance", "shipperA", "carrierA"] as const) {
    const token = f.tokens[who];
    assert.equal((await f.request("/v1/ops/staff", "GET", undefined, token)).status, 403, who);
    assert.equal((await f.request("/v1/ops/staff", "POST", usStaff, token, reason)).status, 403, who);
    assert.equal((await f.request(`/v1/ops/staff/${f.ops.user.id}`, "PUT", { roles: ["FINANCE"] }, token, reason)).status, 403, who);
  }
  assert.equal(registeredWith(f, usStaff.phone), undefined, "no account was made");
  assert.deepEqual(f.store.membershipRoles.get(`${f.ops.user.id}:${f.ops.orgId}`), ["OPS"]);
  const listed = await f.request("/v1/ops/staff", "GET", undefined, f.tokens.admin);
  assert.equal(listed.status, 200);
  assert.deepEqual(listed.body.staff.map((s: { fullName: string }) => s.fullName).sort(), ["Synthetic ADMIN", "Synthetic FINANCE", "Synthetic OPS"]);
});

test("an admin adds a new person with a US number, who can then sign in as staff", async t => {
  const f = await httpFixture(t);
  const out = await f.request("/v1/ops/staff", "POST", usStaff, f.tokens.admin, reason);
  assert.equal(out.status, 201);
  assert.deepEqual(Object.keys(out.body.staffMember).sort(), ["countryCode", "fullName", "phoneLastFour", "roles", "userId"]);
  assert.deepEqual(out.body.staffMember.roles, ["OPS"]);
  assert.equal(out.body.staffMember.phoneLastFour, "0143");
  assert.equal(JSON.stringify(out.body).includes(usStaff.phone), false, "the reply never carries the whole number");

  const user = registeredWith(f, usStaff.phone)!;
  assert.equal(user.countryCode, "+1");
  assert.equal(user.fullName, "Synthetic US Staff");
  const memberships = [...f.store.memberships.values()].filter(m => m.userId === user.id);
  assert.deepEqual(memberships.map(m => m.orgId), [f.admin.orgId], "staff only: no shipper or carrier company");

  const audits = [...f.store.auditEvents.values()].filter(e => e.actorUserId === f.admin.user.id);
  assert.deepEqual(audits.map(e => [e.action, e.newState, e.reasonCode]), [["STAFF_USER_CREATED", "CREATED", "NEW_STAFF"], ["ROLE_ASSIGNED", "OPS", "NEW_STAFF"]]);

  const start = await f.request("/v1/auth/otp/start", "POST", { phone: usStaff.phone, countryCode: "+1" });
  const verified = await f.request("/v1/auth/otp/verify", "POST", { phone: usStaff.phone, countryCode: "+1", challengeId: start.body.challengeId, code: start.body.debugCode });
  assert.equal(verified.status, 200);
  const me = await f.request("/v1/auth/me", "GET", undefined, verified.body.accessToken);
  assert.deepEqual(me.body.principal.roles, ["OPS"]);
  assert.equal(me.body.principal.internal, true);
});

test("adding staff needs a reason code, a country and at least one staff role, and a refusal leaves no account", async t => {
  const f = await httpFixture(t);
  assert.equal((await f.request("/v1/ops/staff", "POST", usStaff, f.tokens.admin)).body.error, "reason_required");
  assert.equal((await f.request("/v1/ops/staff", "POST", { ...usStaff, countryCode: undefined }, f.tokens.admin, reason)).body.error, "invalid_country_code");
  assert.equal((await f.request("/v1/ops/staff", "POST", { ...usStaff, roles: [] }, f.tokens.admin, reason)).body.error, "invalid_role");
  assert.equal((await f.request("/v1/ops/staff", "POST", { ...usStaff, roles: ["SHIPPER"] }, f.tokens.admin, reason)).body.error, "invalid_role");
  assert.equal(registeredWith(f, usStaff.phone), undefined);
});

test("someone who already has an account is added only when the typed name matches the name on it", async t => {
  const f = await httpFixture(t);
  const { user } = registerCustomerUser(f.store, { fullName: "Synthetic Existing Person", phone: "8000000031" });
  const mismatch = await f.request("/v1/ops/staff", "POST", { fullName: "Typed Name", phone: "8000000031", countryCode: "+91", roles: ["FINANCE"] }, f.tokens.admin, reason);
  assert.equal(mismatch.status, 409);
  assert.equal(mismatch.body.error, "staff_name_mismatch");
  assert.equal(JSON.stringify(mismatch.body).includes("Synthetic Existing Person"), false, "the stored name is never revealed");
  assert.equal(f.store.memberships.has(`${user.id}:${f.admin.orgId}`), false);

  const added = await f.request("/v1/ops/staff", "POST", { fullName: "  synthetic  existing PERSON ", phone: "8000000031", countryCode: "+91", roles: ["FINANCE"] }, f.tokens.admin, reason);
  assert.equal(added.status, 201);
  assert.equal(added.body.staffMember.userId, user.id);
  assert.equal(f.store.users.get(user.id)!.fullName, "Synthetic Existing Person");
  assert.deepEqual(f.store.membershipRoles.get(`${user.id}:${f.admin.orgId}`), ["FINANCE"]);
  const audits = [...f.store.auditEvents.values()].filter(e => e.resourceId === `${user.id}:${f.admin.orgId}`);
  assert.deepEqual(audits.map(e => [e.action, e.newState, e.actorUserId]), [["ROLE_ASSIGNED", "FINANCE", f.admin.user.id]]);
});

test("adding someone who is already staff is refused and leaves their roles as they were", async t => {
  const f = await httpFixture(t);
  const out = await f.request("/v1/ops/staff", "POST", { fullName: f.finance.user.fullName, phone: f.finance.user.phone, countryCode: "+91", roles: ["OPS"] }, f.tokens.admin, reason);
  assert.equal(out.status, 409);
  assert.equal(out.body.error, "already_staff");
  assert.deepEqual(f.store.membershipRoles.get(`${f.finance.user.id}:${f.finance.orgId}`), ["FINANCE"]);
});

test("Admin is never given when adding; it is given from the list to someone already staff", async t => {
  const f = await httpFixture(t);
  const refused = await f.request("/v1/ops/staff", "POST", { ...usStaff, roles: ["OPS", "ADMIN"] }, f.tokens.admin, reason);
  assert.equal(refused.status, 400);
  assert.equal(refused.body.error, "admin_needs_existing_staff");
  assert.equal(registeredWith(f, usStaff.phone), undefined, "no account was made");

  const added = (await f.request("/v1/ops/staff", "POST", usStaff, f.tokens.admin, reason)).body.staffMember;
  const promoted = await f.request(`/v1/ops/staff/${added.userId}`, "PUT", { roles: ["OPS", "ADMIN"] }, f.tokens.admin, reason);
  assert.equal(promoted.status, 200);
  assert.deepEqual(promoted.body.staffMember.roles, ["OPS", "ADMIN"]);
});

test("a shipper's or carrier's number cannot be made staff", async t => {
  const f = await httpFixture(t);
  for (const customer of [f.shipperA, f.carrierA]) {
    const out = await f.request("/v1/ops/staff", "POST", { fullName: "x", phone: customer.user.phone, countryCode: "+91", roles: ["OPS"] }, f.tokens.admin, reason);
    assert.equal(out.status, 409);
    assert.equal(out.body.error, "staff_number_has_customer_account");
    assert.equal(f.store.memberships.has(`${customer.user.id}:${f.admin.orgId}`), false);
  }
});

test("the last admin cannot be removed; once there is another admin, removal works and is audited", async t => {
  const f = await httpFixture(t);
  const last = await f.request(`/v1/ops/staff/${f.admin.user.id}`, "PUT", { roles: [] }, f.tokens.admin, reason);
  assert.equal(last.status, 409);
  assert.equal(last.body.error, "cannot_revoke_last_admin");
  assert.equal((await f.request(`/v1/ops/staff/${f.admin.user.id}`, "PUT", { roles: ["OPS"] }, f.tokens.admin, reason)).status, 409);

  const second = (await f.request("/v1/ops/staff", "POST", usStaff, f.tokens.admin, reason)).body.staffMember;
  assert.equal((await f.request(`/v1/ops/staff/${second.userId}`, "PUT", { roles: ["ADMIN"] }, f.tokens.admin, reason)).status, 200);
  const removed = await f.request(`/v1/ops/staff/${f.admin.user.id}`, "PUT", { roles: [] }, f.tokens.admin, reason);
  assert.equal(removed.status, 200);
  assert.deepEqual(removed.body.staffMember.roles, []);
  const removal = [...f.store.auditEvents.values()].find(e => e.action === "ROLE_REMOVED" && e.resourceId === `${f.admin.user.id}:${f.admin.orgId}`);
  assert.deepEqual([removal?.previousState, removal?.actorUserId, removal?.reasonCode], ["ADMIN", f.admin.user.id, "NEW_STAFF"]);
  assert.equal((await f.request("/v1/ops/staff", "GET", undefined, f.tokens.admin)).status, 403, "the removed admin can no longer list staff");
  assert.equal((await f.request(`/v1/ops/staff/${second.userId}`, "PUT", { roles: [] }, f.tokens.admin, reason)).status, 403);
});

test("changing someone who is not staff is refused", async t => {
  const f = await httpFixture(t);
  const out = await f.request(`/v1/ops/staff/${f.shipperA.user.id}`, "PUT", { roles: ["OPS"] }, f.tokens.admin, reason);
  assert.equal(out.status, 404);
  assert.equal(f.store.memberships.has(`${f.shipperA.user.id}:${f.admin.orgId}`), false);
});

test("one admin session gets at most 30 staff changes in ten minutes", async t => {
  const f = await httpFixture(t);
  for (let i = 0; i < 30; i++) {
    assert.equal((await f.request(`/v1/ops/staff/${f.ops.user.id}`, "PUT", { roles: ["OPS"] }, f.tokens.admin, reason)).status, 200);
  }
  const limited = await f.request("/v1/ops/staff", "POST", usStaff, f.tokens.admin, reason);
  assert.equal(limited.status, 429);
  assert.equal(limited.body.error, "staff_write_rate_limited");
  assert.equal(registeredWith(f, usStaff.phone), undefined);
});

test("/admin shows the staff section to an admin, who adds someone from it; other staff never see it", async t => {
  const f = await httpFixture(t);
  const opsPage = await openAs(f, f.tokens.ops, "/admin");
  assert.equal(opsPage.byId("staffManagement").hidden, true);
  assert.equal(opsPage.requests.some(r => r.path === "/v1/ops/staff"), false, "the page does not even ask for the list");

  const page = await openAs(f, f.tokens.admin, "/admin");
  assert.equal(page.byId("staffManagement").hidden, false);
  assert.ok(page.byId("staffList").textContent.includes("Synthetic OPS"));
  page.byId("staffReason").value = "NEW_STAFF";
  page.byId("staffName").value = usStaff.fullName;
  page.byId("staffCountry").value = "+1";
  page.byId("staffPhone").value = "(202) 555-0143";
  page.byId("staffNewFINANCE").checked = true;
  await page.click(page.byId("addStaff"));
  assert.equal(page.byId("error").textContent, "");
  assert.equal(page.byId("staffNotice").textContent, "Synthetic US Staff is now staff. They can sign in on this page with their phone.");
  assert.ok(page.byId("staffList").textContent.includes("+1 number ending 0143 · Finance"));
  assert.equal(registeredWith(f, usStaff.phone)?.countryCode, "+1");

  await page.click(page.byId("addStaff"));
  assert.equal(page.byId("error").textContent, "Choose at least one role.");
});

test("the staff section is not on the shipment workspace page, and stays hidden in the admin page's markup", async t => {
  const f = await httpFixture(t);
  const workflow = await (await fetch(f.base + "/workflow")).text();
  assert.equal(workflow.includes('id="staffManagement"') || workflow.includes("/v1/ops/staff"), false);
  for (const path of ["/admin", "/admin/v2", "/ops", "/ops/v2"]) {
    const markup = await (await fetch(f.base + path)).text();
    assert.ok(markup.includes('<section id="staffManagement" hidden>'), path);
    assert.equal(markup.includes('id="staffNewADMIN"'), false, `${path}: Admin is given from the list, not the add form`);
  }
});

function registeredWith(f: Awaited<ReturnType<typeof httpFixture>>, phone: string) {
  return [...f.store.users.values()].find(u => u.phone === phone);
}

async function openAs(f: Awaited<ReturnType<typeof httpFixture>>, token: string, path: string) {
  const page = new FakePage(f.base);
  page.session.set("navig8r_access", token);
  page.run(inlineScript(await (await fetch(f.base + path)).text()));
  await page.settle();
  return page;
}
