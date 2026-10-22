// Disposable local RBAC demo. Never loads .env, existing stores, or a database.
import { randomBytes } from "node:crypto";
import { existsSync, mkdtempSync, readFileSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { extname, join, resolve, sep } from "node:path";

// Anyone can sign in here with the code shown on screen, so it must never sit next to real money or a real database.
// Razorpay test keys move no money (owner, 21 Oct 2026), so they are the one payment setting it takes.
const razorpayKeyId = process.env.RAZORPAY_KEY_ID?.trim() ?? "";
const razorpayKeySecret = process.env.RAZORPAY_KEY_SECRET?.trim() ?? "";
const unsafeReason = ["production", "beta"].includes(process.env.NODE_ENV) ? `NODE_ENV is ${process.env.NODE_ENV}`
  : razorpayKeySecret && !razorpayKeyId.startsWith("rzp_test_")
    ? "RAZORPAY_KEY_SECRET is set but RAZORPAY_KEY_ID is not a test key (rzp_test_...); live Razorpay keys are refused"
  : process.env.DATABASE_URL ? "DATABASE_URL is set"
  : null;
if (unsafeReason) {
  console.error(`Refusing to start the practice server: ${unsafeReason}. It runs only with fake accounts, and mock payments or Razorpay test payments.`);
  process.exit(1);
}
const razorpayTestPayments = Boolean(razorpayKeyId && razorpayKeySecret);

// Serving the web build, or listening beyond this machine, means anyone with the link can reach it.
const hosted = Boolean(process.env.RBAC_MANUAL_WEB_DIR)
  || !["127.0.0.1", "localhost", "::1"].includes(process.env.RBAC_MANUAL_HOST ?? "127.0.0.1");
const directory = mkdtempSync(join(tmpdir(), "navig8r-rbac-manual-"));
Object.assign(process.env, {
  NODE_ENV: "test",
  PERSISTENCE: "FILE",
  DATA_FILE: join(directory, "synthetic-store.json"),
  // The fixed secret is in the public repository, so a hosted server with it would accept anyone's forged sign-in.
  AUTH_SECRET: hosted ? randomBytes(32).toString("hex") : "synthetic-local-rbac-demo-not-for-deployment",
  OUTBOUND_WEBHOOKS_OFF: hosted ? "1" : "0",
  OTP_DEBUG: "1",
  // RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET and RAZORPAY_WEBHOOK_SECRET stay in the environment as they came.
  PAYMENT_PROVIDER: razorpayTestPayments ? "RAZORPAY" : "MOCK",
  PAYOUTS_MODE: "BOOKKEEPING",
  ALLOW_X_USER_ID: "0",
  ENABLE_LEGACY_DEMO_SURFACE: "0",
});

const { createStore } = await import("../apps/api/src/store.ts");
const { saveStoreToDisk, loadStoreFromDisk } = await import("../apps/api/src/persistence.ts");
const { migrateAuthorization, resolvePrincipal } = await import("../apps/api/src/rbac.ts");
const { createApp } = await import("../apps/api/src/httpServer.ts");
const { SEEDED_TRUCK_VALID_UNTIL_UTC_MS } = await import("../apps/api/src/ewayDemoPortal.ts");
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
  ["user-all", "8000000011", "platform", "ADMIN"],
  ["user-admin-finance", "8000000012", "platform", "ADMIN"],
  ["user-driver-b", "8000000013", "carrier-a", "DRIVER"],
];
for (const [userId, phone, orgId, role] of accounts) {
  store.users.set(userId, { id: userId, phone, fullName: `Synthetic ${userId}`, createdAtUtcMs: now });
  store.memberships.set(`${userId}:${orgId}`, { userId, orgId, role, createdAtUtcMs: now });
}
// The owner's driver list on a trip shows these names, so carrier A's people who can drive get real ones.
store.users.get("user-carrier-a").fullName = "Synthetic Owner A";
store.users.get("user-driver").fullName = "Synthetic Driver A";
store.users.get("user-driver-b").fullName = "Synthetic Driver B";

// Each carrier A driver has a truck. The first truck is the one already on the seeded bill, so the two match until
// the owner changes the trip's truck; then the bill and the trip differ and both cards say so.
for (const [vehicleId, registrationNumber, userId] of [
  ["vehicle-carrier-a-1", "KA01AB1234", "user-driver"],
  ["vehicle-carrier-a-2", "KA02XY9999", "user-driver-b"],
]) {
  store.vehicles.set(vehicleId, { id: vehicleId, orgId: "carrier-a", registrationNumber, vehicleClass: "MEDIUM", capacityKg: 1000, createdAtUtcMs: now });
  store.driverProfiles.set(userId, { userId, orgId: "carrier-a", primaryVehicleId: vehicleId, createdAtUtcMs: now });
}
store.memberships.set("user-dual:platform", {
  userId: "user-dual", orgId: "platform", role: "FINANCE", createdAtUtcMs: now,
});

// Each shipment gets its own route and weight so the list rows can be told apart.
const seededShipments = [
  ["load-a-hold", "shipper-a", "carrier-a", "PENDING_RELEASE", now - 3600000, 120, "Peenya, Bengaluru", "Ambattur, Chennai", "trip-carrier-a"],
  ["load-a-expired", "shipper-a", "carrier-a", "PENDING_RELEASE", now - 49 * 3600000, 45, "Whitefield, Bengaluru", "Hosur", "trip-carrier-a"],
  ["load-a-booked", "shipper-a", "carrier-a", "BOOKED", null, 250, "Bommasandra, Bengaluru", "Guindy, Chennai", "trip-carrier-a"],
  ["load-a-with-bill", "shipper-a", "carrier-a", "BOOKED", null, 80, "Yeshwanthpur, Bengaluru", "Mysuru", "trip-carrier-a"],
  ["load-a-with-truck", "shipper-a", "carrier-a", "BOOKED", null, 400, "Electronic City, Bengaluru", "Coimbatore", "trip-carrier-a"],
  ["load-a2-booked", "shipper-a", "carrier-a", "BOOKED", null, 150, "Hoskote, Bengaluru", "Kolar", "trip-carrier-a-2"],
  ["load-b-pending", "shipper-b", "carrier-b", "PENDING_CARRIER_ACCEPT", null, 10, "Hebbal, Bengaluru", "Tumakuru", "trip-carrier-b"],
];

// Only the Hoskote to Kolar trip has real towns, so only it gets town pins; the Book screen's 15 km rule needs them.
const townPinsByTripId = {
  "trip-carrier-a-2": { origin: { lat: 13.0707, lng: 77.7982 }, destination: { lat: 13.1362, lng: 78.1292 } },
};
// Each trip's reserved weight is the weight of the shipments seeded on it, so its remaining capacity adds up.
// Carrier A's two trips each name a driver, so each driver login sees only its own trip.
for (const [id, carrierId, originCity, destCity, assignedVehicleId, assignedDriverUserId] of [
  ["trip-carrier-a", "carrier-a", "Synthetic Origin", "Synthetic Destination", "vehicle-carrier-a-1", "user-driver"],
  ["trip-carrier-a-2", "carrier-a", "Hoskote", "Kolar", "vehicle-carrier-a-2", "user-driver-b"],
  ["trip-carrier-b", "carrier-b", "Synthetic Origin", "Synthetic Destination", null, null],
]) {
  const reservedKg = seededShipments.filter(shipment => shipment[8] === id).reduce((sum, shipment) => sum + shipment[5], 0);
  store.anchorTrips.set(id, {
    id, carrierId, originCity, destCity,
    windowStart: new Date(now).toISOString(), windowEnd: new Date(now + 86400000).toISOString(),
    vehicleClass: "MEDIUM", capacityKg: 1000, reservedKg,
    status: "OPEN", createdAtUtcMs: now,
    ...(assignedVehicleId ? { assignedVehicleId, assignedDriverUserId } : {}),
    ...townPinsByTripId[id],
  });
}

for (const [id, customerOrgId, carrierId, status, podAtUtcMs, weightKg, pickupAddress, dropAddress, anchorTripId] of seededShipments) {
  const paymentId = `payment-${id}`;
  store.shipments.set(id, {
    id, anchorTripId, customerOrgId, carrierId,
    customerOrgName: store.organizations.get(customerOrgId).displayName,
    status, weightKg, pickupAddress, dropAddress,
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
// One booked shipment already has a bill typed in and not yet checked, so ops has something to check at first sign-in.
// The practice portal (apps/api/src/ewayDemoPortalStore.ts) holds this same bill so ops' look-up finds it; change both together.
store.shipments.get("load-a-with-bill").ewayBill = {
  kind: "BILL", billNumber: "123456789012", billDate: "2026-10-01", makerGstin: "29ABCDE1234F1Z5",
  invoiceNumber: "SYN/2026/001", enteredAtUtcMs: now, enteredByUserId: "user-shipper-a",
};
// A second bill whose shipper has already added the truck, so every row state shows at first sign-in.
// The portal holds it too, with the same truck. The valid-until is imported from the portal, so the two match
// when this script starts the server; a server started separately after --seed-only computes its own.
store.shipments.get("load-a-with-truck").ewayBill = {
  kind: "BILL", billNumber: "234567890123", billDate: "2026-10-02", makerGstin: "29ABCDE1234F1Z5",
  invoiceNumber: "SYN/2026/002", enteredAtUtcMs: now, enteredByUserId: "user-shipper-a",
  truckNumber: "KA01AB1234", validUntilUtcMs: SEEDED_TRUCK_VALID_UNTIL_UTC_MS, truckEnteredByUserId: "user-shipper-a",
};
migrateAuthorization(store);
store.membershipRoles.set("user-all:platform", ["ADMIN", "OPS", "FINANCE"]);
store.membershipRoles.set("user-admin-finance:platform", ["ADMIN", "FINANCE"]);
saveStoreToDisk(process.env.DATA_FILE, store);
const restored = loadStoreFromDisk(process.env.DATA_FILE);
for (const [userId, , orgId] of accounts) resolvePrincipal(restored, userId, orgId);
console.table(accounts.map(([userId, phone, orgId, role]) => ({ phone, userId, orgId, role })));
console.log("OTP_DEBUG=1 returns each generated six-digit code from otp/start. Dual user also has FINANCE in platform.");
console.log(`Synthetic data: ${process.env.DATA_FILE}`);
console.log(razorpayTestPayments
  ? "Payments: Razorpay test mode. No money moves."
  : "Payments: mock. No payment provider is called.");

if (!process.argv.includes("--seed-only")) {
  const app = await createApp();
  // Deliberately no background payout or outbound webhook workers.
  app.server.on("error", error => { console.error(error.message); process.exitCode = 1; });
  if (process.env.RBAC_MANUAL_WEB_DIR) serveWebApp(app.server, process.env.RBAC_MANUAL_WEB_DIR, process.env.MAPS_API_KEY?.trim() ?? "");
  const port = Number(process.env.RBAC_MANUAL_PORT ?? 3139);
  const host = process.env.RBAC_MANUAL_HOST ?? "127.0.0.1";
  app.server.listen(port, host, () => {
    console.log(`Open http://${host}:${app.server.address().port}/ops — Ctrl+C stops this local demo.`);
  });
  // In the container node is PID 1, which has no default signal handling, so without this Render's stop is ignored.
  for (const signal of ["SIGTERM", "SIGINT"]) process.once(signal, () => app.server.close(() => process.exit(0)));
}

// The hosted demo serves the built web app and the API from one origin. The app calls the API under /api, as it
// does behind the customer-web proxy, so that prefix is stripped; every other path that is not a built file is the API's.
function serveWebApp(server, webDirectory, mapsApiKey) {
  if (mapsApiKey && !/^[A-Za-z0-9_-]+$/.test(mapsApiKey)) {
    throw new Error("MAPS_API_KEY has characters a Google key never has; refusing to write it into the page.");
  }
  const root = resolve(webDirectory);
  const builtIndex = readFileSync(join(root, "index.html"), "utf8");
  // Same result as scripts/inject-maps-api-key.sh: the key in the Maps script, or no Maps script at all.
  const indexHtml = mapsApiKey
    ? builtIndex.replaceAll("__MAPS_API_KEY__", mapsApiKey)
    : builtIndex.replace(/<!-- BEGIN MAPS_API_SCRIPT -->[\s\S]*?<!-- END MAPS_API_SCRIPT -->\n?/, "");
  const runtimeConfig = `window.__NAVI8R_CONFIG__ = { MAPS_API_KEY: ${JSON.stringify(mapsApiKey)} };\n`;
  const contentTypes = {
    ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".json": "application/json", ".wasm": "application/wasm",
    ".css": "text/css", ".png": "image/png", ".ico": "image/x-icon", ".svg": "image/svg+xml", ".ttf": "font/ttf", ".otf": "font/otf",
  };
  // The public demo must not be framed by another site, where taps could be steered onto its buttons.
  const send = (res, contentType, body) => {
    res.writeHead(200, {
      "content-type": contentType, "cache-control": "no-cache", "x-content-type-options": "nosniff",
      "x-frame-options": "DENY", "content-security-policy": "frame-ancestors 'none'",
    });
    res.end(body);
  };
  const [handleApiRequest] = server.listeners("request");
  server.removeAllListeners("request");
  server.on("request", (req, res) => {
    const requestUrl = req.url ?? "/";
    if (/^\/api(?=\/|\?|$)/.test(requestUrl)) {
      req.url = requestUrl.replace(/^\/api\/?/, "/");
      return handleApiRequest(req, res);
    }
    if (req.method === "GET" || req.method === "HEAD") {
      let pathname = null;
      try { pathname = decodeURIComponent(new URL(requestUrl, "http://localhost").pathname); } catch { pathname = null; }
      if (pathname === "/" || pathname === "/index.html") return send(res, contentTypes[".html"], indexHtml);
      if (pathname === "/runtime-config.js") return send(res, contentTypes[".js"], runtimeConfig);
      const file = pathname === null ? null : resolve(root, `.${pathname}`);
      if (file?.startsWith(root + sep) && existsSync(file) && statSync(file).isFile()) {
        return send(res, contentTypes[extname(file)] ?? "application/octet-stream", readFileSync(file));
      }
    }
    handleApiRequest(req, res);
  });
}
