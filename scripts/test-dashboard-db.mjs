// Run only against the named disposable local database; never reads an env file.
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
const url = new URL(process.env.DASHBOARD_TEST_DATABASE_URL || "");
if (
  !["localhost", "127.0.0.1"].includes(url.hostname) ||
  url.pathname !== "/navig8r_dashboard_test"
)
  throw Error("A disposable local navig8r_dashboard_test database is required");
process.env.DATABASE_URL = url.toString();
const { createStore } = await import("../apps/api/src/store.ts");
const { internalUser, asUser } = await import("../apps/api/test/fixtures.ts");
const { onboardCarrier, setInternalAccess } = await import(
  "../apps/api/src/dashboard.ts"
);
const { authorizationContext } = await import("../apps/api/src/rbac.ts");
const { loadStoreFromDatabase, saveStoreToDatabase, closeDatabase } =
  await import("../apps/api/src/persistenceDb.ts");
const store = createStore();
const ops = internalUser(store, "OPS"),
  admin = internalUser(store, "ADMIN"),
  finance = internalUser(store, "FINANCE");
const input = {
  displayName: "Synthetic persisted fleet",
  ownerUserId: finance.userId,
  requestId: "dashboard-database-test-" + randomUUID(),
};
let result;
try {
  result = asUser(store, ops.userId, () => {
    authorizationContext.getStore().reason = "PILOT_ONBOARDING";
    return onboardCarrier(store, input);
  });
  asUser(store, admin.userId, () => {
    authorizationContext.getStore().reason = "ACCESS_REVIEW";
    setInternalAccess(store, {
      userId: finance.userId,
      roles: ["ADMIN", "FINANCE"],
    });
  });
  await saveStoreToDatabase(store);
  const restored = await loadStoreFromDatabase();
  assert.equal(
    restored.organizations.get(result.org.id).kycStatus,
    "NOT_STARTED",
  );
  assert.equal(
    restored.memberships.get(`${finance.userId}:${result.org.id}`).role,
    "OWNER",
  );
  assert.deepEqual(
    restored.membershipRoles.get(`${finance.userId}:${finance.orgId}`).sort(),
    ["ADMIN", "FINANCE"],
  );
  assert.equal(
    [...restored.auditEvents.values()].filter(
      (e) => e.action === "CARRIER_ONBOARDED" && e.resourceId === result.org.id,
    ).length,
    1,
  );
  const retry = asUser(
    restored,
    ops.userId,
    () => {
      authorizationContext.getStore().reason = "PILOT_ONBOARDING";
      return onboardCarrier(restored, input);
    },
    ops.orgId,
  );
  assert.equal(retry.created, false);
  await saveStoreToDatabase(restored);
  assert.equal(
    (await loadStoreFromDatabase()).auditEvents.size,
    restored.auditEvents.size,
  );
  console.log(
    "PASS: PostgreSQL dashboard ownership, roles, KYC, audit and retry round trip",
  );
} finally {
  await closeDatabase();
}
