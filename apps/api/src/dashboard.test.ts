import test from "node:test";
import assert from "node:assert/strict";
import { httpFixture } from "../test/httpFixtures.ts";
import { loadStoreFromDisk } from "./persistence.ts";
import { asUser } from "../test/fixtures.ts";
import { dashboardList, onboardCarrier } from "./dashboard.ts";
import { bookShipment } from "./services.ts";

test("V1 and V2 shells coexist without embedded records", async (t) => {
  const f = await httpFixture(t);
  for (const path of [
    "/admin",
    "/ops",
    "/admin/v1",
    "/ops/v1",
    "/admin/v2",
    "/ops/v2",
    "/workflow",
  ]) {
    const response = await fetch(f.base + path),
      html = await response.text();
    assert.equal(response.status, 200);
    assert.ok(!html.includes(f.carrierA.org.id));
    const heading = path.startsWith("/ops")
      ? "Operations workspace"
      : path === "/workflow"
        ? "NaviG8r shipments"
        : "Full dashboard";
    assert.ok(html.includes(`<h1>${heading}</h1>`), path);
    if (!path.endsWith("v1") && path !== "/workflow") {
      const target = path.startsWith("/ops") ? "/ops/v1" : "/admin/v1";
      assert.ok(
        html.includes(`href="${target}">Open full dashboard (V1)`),
        path,
      );
    }
  }
  assert.equal(
    await (await fetch(f.base + "/admin")).text(),
    await (await fetch(f.base + "/admin/v2")).text(),
  );
  assert.equal(
    await (await fetch(f.base + "/ops")).text(),
    await (await fetch(f.base + "/ops/v2")).text(),
  );
});

test("dashboard directories enforce internal roles, pagination, field allowlists and inactive filtering", async (t) => {
  const f = await httpFixture(t),
    path = "/v1/ops/dashboard/";
  for (const role of ["shipperA", "carrierA"] as const)
    for (const section of [
      "carriers",
      "users",
      "vehicles",
      "shipments",
      "ledger",
    ])
      assert.equal(
        (await f.request(path + section, "GET", undefined, f.tokens[role]))
          .status,
        403,
      );
  assert.equal((await f.request(path + "carriers")).status, 401);
  assert.equal(
    (await f.request(path + "users", "GET", undefined, f.tokens.ops)).status,
    403,
  );
  assert.equal(
    (await f.request(path + "vehicles", "GET", undefined, f.tokens.finance))
      .status,
    403,
  );
  assert.equal(
    (await f.request(path + "ledger", "GET", undefined, f.tokens.admin)).status,
    403,
  );
  f.store.organizations.get(f.carrierA.org.id)!.payoutFundAccountId =
    "synthetic-private-value";
  const carriers = await f.request(
    path + "carriers?limit=1",
    "GET",
    undefined,
    f.tokens.ops,
  );
  assert.equal(carriers.body.items.length, 1);
  assert.equal(carriers.body.total, 2);
  assert.ok(!JSON.stringify(carriers.body).includes("synthetic-private-value"));
  assert.equal(
    (
      await f.request(
        path + "carriers?limit=1000",
        "GET",
        undefined,
        f.tokens.ops,
      )
    ).status,
    400,
  );
  assert.equal(
    (
      await f.request(
        path + "carriers?inactive=true",
        "GET",
        undefined,
        f.tokens.ops,
      )
    ).status,
    403,
  );
  f.store.organizations.get(f.carrierB.org.id)!.inactiveAtUtcMs = Date.now();
  assert.equal(
    (await f.request(path + "carriers", "GET", undefined, f.tokens.ops)).body
      .total,
    1,
  );
  assert.equal(
    (
      await f.request(
        path + "carriers?inactive=true",
        "GET",
        undefined,
        f.tokens.admin,
      )
    ).body.total,
    2,
  );
  assert.throws(
    () =>
      asUser(f.store, f.carrierA.user.id, () =>
        dashboardList(f.store, "carriers", new URLSearchParams()),
      ),
    /forbidden/,
  );
});

test("carrier onboarding is Ops-only, retry-safe, unapproved and persists ownership and audit", async (t) => {
  const f = await httpFixture(t),
    path = "/v1/ops/carrier-organizations",
    body = {
      displayName: "New synthetic fleet",
      ownerUserId: f.shipperA.user.id,
      requestId: "synthetic-request-0001",
    },
    headers = { "x-reason-code": "PILOT_ONBOARDING" };
  assert.equal(
    (await f.request(path, "POST", body, f.tokens.admin, headers)).status,
    403,
  );
  assert.equal((await f.request(path, "POST", body, f.tokens.ops)).status, 400);
  assert.equal(
    (
      await f.request(
        path,
        "POST",
        { ...body, ownerUserId: "missing" },
        f.tokens.ops,
        headers,
      )
    ).status,
    404,
  );
  const created = await f.request(path, "POST", body, f.tokens.ops, headers);
  assert.equal(created.status, 201);
  assert.equal(created.body.org.kycStatus, "NOT_STARTED");
  assert.equal(
    (await f.request(path, "POST", body, f.tokens.ops, headers)).status,
    200,
  );
  assert.equal(
    (
      await f.request(
        path,
        "POST",
        { ...body, displayName: "Changed" },
        f.tokens.ops,
        headers,
      )
    ).status,
    409,
  );
  const restored = loadStoreFromDisk(f.dataFilePath!),
    key = `${f.shipperA.user.id}:${created.body.org.id}`;
  assert.equal(restored.memberships.get(key)?.role, "OWNER");
  assert.deepEqual(restored.membershipRoles.get(key), ["CARRIER"]);
  assert.equal(
    [...restored.auditEvents.values()].filter(
      (e) => e.action === "CARRIER_ONBOARDED",
    ).length,
    1,
  );
  assert.throws(
    () => asUser(f.store, f.admin.user.id, () => onboardCarrier(f.store, body)),
    /forbidden/,
  );
});

test("Ops booking validates represented membership in handler and service and preserves customer ownership", async (t) => {
  const f = await httpFixture(t),
    body = { customerOrgId: f.shipperA.org.id },
    headers = {
      "x-reason-code": "CUSTOMER_REQUEST",
      "x-effective-actor-id": f.shipperA.user.id,
    };
  assert.equal((await f.book(f.tokens.ops, body)).status, 400);
  const booking = {
    anchorTripId: f.trip.id,
    customerOrgId: f.shipperA.org.id,
    weightKg: 10,
    pickupAddress: "A",
    dropAddress: "B",
  };
  assert.equal(
    (
      await f.request("/shipments/book", "POST", booking, f.tokens.ops, {
        ...headers,
        "x-effective-actor-id": f.shipperB.user.id,
      })
    ).status,
    400,
  );
  const result = await f.request(
    "/shipments/book",
    "POST",
    booking,
    f.tokens.ops,
    headers,
  );
  assert.equal(result.status, 201);
  assert.equal(
    f.store.shipments.get(result.body.shipment.id)?.bookedByUserId,
    f.shipperA.user.id,
  );
  assert.equal(
    (
      await f.request(
        "/shipments/" + result.body.shipment.id,
        "GET",
        undefined,
        f.tokens.shipperA,
      )
    ).status,
    200,
  );
  assert.equal(
    (
      await f.request(
        "/shipments/" + result.body.shipment.id,
        "GET",
        undefined,
        f.tokens.shipperB,
      )
    ).status,
    404,
  );
  const audit = [...f.store.auditEvents.values()].find(
    (e) => e.action === "SHIPMENT_BOOKED",
  )!;
  assert.equal(audit.actorUserId, f.ops.user.id);
  assert.equal(audit.effectiveActorId, f.shipperA.user.id);
  assert.throws(
    () =>
      asUser(f.store, f.ops.user.id, () =>
        bookShipment(f.store, {
          ...booking,
          customerOrg: f.shipperA.org,
          customerOrgName: "A",
          bookedByUserId: f.shipperA.user.id,
        }),
      ),
    /assistance_attribution_required/,
  );
});

test("canonical admin grants survive restart and cannot remove the last administrator", async (t) => {
  const f = await httpFixture(t),
    path = "/v1/ops/dashboard-access",
    headers = { "x-reason-code": "ACCESS_REVIEW" };
  assert.equal(
    (
      await f.request(
        path,
        "POST",
        { userId: f.admin.user.id, roles: [] },
        f.tokens.admin,
        headers,
      )
    ).status,
    409,
  );
  assert.equal(
    (
      await f.request(
        "/v1/roles",
        "POST",
        { userId: f.admin.user.id, orgId: f.admin.orgId, roles: [] },
        f.tokens.admin,
      )
    ).status,
    409,
  );
  assert.equal(
    (
      await f.request(
        path,
        "POST",
        { userId: f.finance.user.id, roles: ["ADMIN", "FINANCE"] },
        f.tokens.ops,
        headers,
      )
    ).status,
    403,
  );
  assert.equal(
    (
      await f.request(
        path,
        "POST",
        { userId: f.finance.user.id, roles: ["ADMIN", "FINANCE"] },
        f.tokens.admin,
        headers,
      )
    ).status,
    200,
  );
  const restored = loadStoreFromDisk(f.dataFilePath!);
  assert.deepEqual(
    restored.membershipRoles.get(`${f.finance.user.id}:${f.finance.orgId}`),
    ["ADMIN", "FINANCE"],
  );
  assert.equal(
    (
      await f.request(
        path,
        "POST",
        { userId: f.admin.user.id, roles: [] },
        f.tokens.admin,
        headers,
      )
    ).status,
    200,
  );
  assert.equal(
    (
      await f.request(
        "/v1/ops/dashboard/users",
        "GET",
        undefined,
        f.tokens.admin,
      )
    ).status,
    403,
  );
});

test("combined roles see the union of authorized audit categories only in their selected membership", async (t) => {
  const f = await httpFixture(t);
  f.store.membershipRoles.set(`${f.admin.user.id}:${f.admin.orgId}`, [
    "ADMIN",
    "FINANCE",
  ]);
  for (const action of [
    "ROLE_ASSIGNED",
    "PAYMENT_CAPTURED",
    "COMPLIANCE_STATUS_CHANGED",
  ])
    f.store.auditEvents.set(action, {
      id: action,
      actorUserId: f.ops.user.id,
      actorOrganizationId: f.ops.orgId,
      action,
      resourceType: "synthetic",
      resourceId: "synthetic",
      timestamp: 1,
      requestId: "synthetic-test",
      source: "USER",
    });
  const events = (
    await f.request("/v1/audit", "GET", undefined, f.tokens.admin)
  ).body.events;
  assert.deepEqual(events.map((e: { action: string }) => e.action).sort(), [
    "PAYMENT_CAPTURED",
    "ROLE_ASSIGNED",
  ]);
});
