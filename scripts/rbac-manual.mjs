// Disposable local RBAC demo. Never loads .env, existing stores, or a database.
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const directory = mkdtempSync(join(tmpdir(), "navig8r-rbac-manual-"));
Object.assign(process.env, {
  NODE_ENV: "test",
  PERSISTENCE: "FILE",
  DATA_FILE: join(directory, "synthetic-store.json"),
  AUTH_SECRET: "synthetic-local-rbac-demo-not-for-deployment",
  OTP_DEBUG: "1",
  OTP_FIXED_CODE: "123456",
  PAYMENT_PROVIDER: "MOCK",
  PAYOUTS_MODE: "BOOKKEEPING",
  ALLOW_X_USER_ID: "0",
  ENABLE_LEGACY_DEMO_SURFACE: "0",
});

const { createStore } = await import("../apps/api/src/store.ts");
const { saveStoreToDisk, loadStoreFromDisk } = await import("../apps/api/src/persistence.ts");
const { migrateAuthorization, resolvePrincipal } = await import("../apps/api/src/rbac.ts");
const { createApp } = await import("../apps/api/src/httpServer.ts");
const store = createStore();
const now = Date.now();

for (const [id, kind, displayName, kycStatus] of [
  ["shipper-a", "CUSTOMER", "Synthetic Shipper A", "NOT_STARTED"],
  ["shipper-b", "CUSTOMER", "Synthetic Shipper B", "NOT_STARTED"],
  ["carrier-a", "CARRIER_FLEET", "Synthetic Carrier A", "APPROVED"],
  ["carrier-b", "CARRIER_FLEET", "Synthetic Carrier B", "SUBMITTED"],
  ["platform", "PLATFORM", "Synthetic NaviG8r Internal", "APPROVED"],
]) store.organizations.set(id, { id, kind, displayName, kycStatus, createdAtUtcMs: now });

const accounts = [
  ["user-shipper-a", "8000000001", "shipper-a", "CUSTOMER_ADMIN"],
  ["user-shipper-b", "8000000002", "shipper-b", "CUSTOMER_ADMIN"],
  ["user-carrier-a", "8000000003", "carrier-a", "OWNER"],
  ["user-carrier-b", "8000000004", "carrier-b", "OWNER"],
  ["user-ops", "8000000005", "platform", "OPS"],
  ["user-finance", "8000000006", "platform", "FINANCE"],
  ["user-admin", "8000000007", "platform", "ADMIN"],
  ["user-dual", "8000000008", "shipper-a", "CUSTOMER_MEMBER"],
  ["user-driver", "8000000009", "carrier-a", "DRIVER"],
  ["user-member", "8000000010", "shipper-a", "CUSTOMER_MEMBER"],
];
for (const [userId, phone, orgId, role] of accounts) {
  store.users.set(userId, { id: userId, phone, fullName: `Synthetic ${userId}`, createdAtUtcMs: now });
  store.memberships.set(`${userId}:${orgId}`, { userId, orgId, role, createdAtUtcMs: now });
}
store.memberships.set("user-dual:platform", {
  userId: "user-dual", orgId: "platform", role: "FINANCE", createdAtUtcMs: now,
});

for (const carrierId of ["carrier-a", "carrier-b"]) {
  const id = `trip-${carrierId}`;
  store.anchorTrips.set(id, {
    id, carrierId, originCity: "Synthetic Origin", destCity: "Synthetic Destination",
    windowStart: new Date(now).toISOString(), windowEnd: new Date(now + 86400000).toISOString(),
    vehicleClass: "MEDIUM", capacityKg: 1000, reservedKg: carrierId === "carrier-a" ? 30 : 10,
    status: "OPEN", createdAtUtcMs: now,
  });
}

for (const [id, customerOrgId, carrierId, status, podAtUtcMs] of [
  ["load-a-hold", "shipper-a", "carrier-a", "PENDING_RELEASE", now - 3600000],
  ["load-a-expired", "shipper-a", "carrier-a", "PENDING_RELEASE", now - 49 * 3600000],
  ["load-a-booked", "shipper-a", "carrier-a", "BOOKED", null],
  ["load-b-pending", "shipper-b", "carrier-b", "PENDING_CARRIER_ACCEPT", null],
]) {
  const paymentId = `payment-${id}`;
  store.shipments.set(id, {
    id, anchorTripId: `trip-${carrierId}`, customerOrgId, carrierId,
    customerOrgName: store.organizations.get(customerOrgId).displayName,
    status, weightKg: 10, pickupAddress: "Synthetic pickup", dropAddress: "Synthetic drop",
    grossPaise: 5000, commissionPaise: 500, netToCarrierPaise: 4500, paymentId,
    podAtUtcMs, firstPayoutEligibleAtUtcMs: null, payoutBatchCutoffUtcMs: null,
    createdAtUtcMs: now - 50 * 3600000, updatedAtUtcMs: now,
  });
  store.payments.set(paymentId, {
    id: paymentId, shipmentId: id, amountPaise: 5000, status: "CAPTURED",
    provider: "MOCK", providerRef: "synthetic-no-payment-provider",
    createdAtUtcMs: now, updatedAtUtcMs: now,
  });
}
migrateAuthorization(store);
saveStoreToDisk(process.env.DATA_FILE, store);
const restored = loadStoreFromDisk(process.env.DATA_FILE);
for (const [userId, , orgId] of accounts) resolvePrincipal(restored, userId, orgId);
console.table(accounts.map(([userId, phone, orgId, role]) => ({ phone, userId, orgId, role })));
console.log("All test accounts use OTP 123456. Dual user also has FINANCE in platform.");
console.log(`Synthetic data: ${process.env.DATA_FILE}`);

if (!process.argv.includes("--seed-only")) {
  const app = await createApp();
  // Deliberately no background payout or outbound webhook workers.
  app.server.on("error", error => { console.error(error.message); process.exitCode = 1; });
  const port = Number(process.env.RBAC_MANUAL_PORT ?? 3139);
  app.server.listen(port, "127.0.0.1", () => {
    console.log(`Open http://127.0.0.1:${port}/ops — Ctrl+C stops this local demo.`);
  });
}
