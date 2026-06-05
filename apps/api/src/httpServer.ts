import http from "node:http";
import { URL } from "node:url";
import { pilotOtpStart, pilotOtpVerify, verifyBearer } from "./auth.ts";
import { loadStoreFromDisk, saveStoreToDisk } from "./persistence.ts";
import {
  ApiError,
  attachRazorpayOrderForShipment,
  bookShipment,
  createCarrier,
  customerPrimaryOrgForUser,
  ensureRazorpayCapturedBeforePod,
  failCarrierAndRefund,
  grantOpsAdmin,
  isOpsAdmin,
  listOpsAdmins,
  markPodDelivered,
  opsListPendingRelease,
  opsListRecentlyDelivered,
  opsShipmentDetail,
  releasePaymentAndDeliver,
  submitDriverPod,
  assertOpsAgent,
  customerEligibleAnchorTripsPhaseA,
  pilotLoginDriverByPhone,
  pilotGetMyAnchorTrip,
  reportAnchorTripLocation,
  getShipmentTripTracking,
  pilotMe,
  pilotListMyAnchorTrips,
  pilotRatesEstimate,
  pilotListCarrierShipments,
  pilotCarrierEarningsSummary,
  pilotSubmitPayoutSetup,
  pilotListCarrierLedger,
  pilotListCarrierPayoutBatches,
  shipmentVisibleToCarrierPilot,
  publishAnchorTrip,
  publishAnchorTripAsPilotDriver,
  quoteShipmentMarketplace,
  registerCustomerOrgAdmin,
  registerSoloOwnerOperatorDriver,
  revokeOpsAdmin,
  rollbackBooking,
  runPayoutBatch,
  shipmentVisibleToCustomerUser,
} from "./services.ts";
import { verifyRazorpayWebhookSignature, razorpayPaymentsEnabled, publicRazorpayKeyId } from "./razorpayPayments.ts";
import { payoutsMode } from "./razorpayPayouts.ts";
import { applyRazorpayWebhookPayload } from "./razorpayWebhook.ts";

async function readRawBody(req: http.IncomingMessage): Promise<string> {
  const chunks: Buffer[] = [];
  for await (const c of req) chunks.push(Buffer.isBuffer(c) ? c : Buffer.from(c));
  return Buffer.concat(chunks).toString("utf8");
}

function json(res: http.ServerResponse, status: number, body: unknown): void {
  const data = JSON.stringify(body);
  res.statusCode = status;
  res.setHeader("content-type", "application/json; charset=utf-8");
  res.setHeader("content-length", Buffer.byteLength(data));
  res.end(data);
}

function html(res: http.ServerResponse, status: number, body: string): void {
  res.statusCode = status;
  res.setHeader("content-type", "text/html; charset=utf-8");
  res.end(body);
}

function opsPortalHtml(): string {
  return `<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>naviG8r Ops</title>
    <style>
      body { font-family: ui-sans-serif, system-ui, sans-serif; margin: 16px; max-width: 960px; }
      .card { border: 1px solid #e5e5e5; border-radius: 10px; padding: 12px; margin-bottom: 12px; }
      table { width: 100%; border-collapse: collapse; font-size: 13px; }
      th, td { border-bottom: 1px solid #eee; padding: 8px; text-align: left; vertical-align: top; }
      button { padding: 6px 12px; cursor: pointer; }
      input { width: 100%; padding: 8px; margin: 6px 0; box-sizing: border-box; }
      .muted { color: #666; font-size: 12px; }
      .warn { background: #fff1f0; border: 1px solid #ffa39e; padding: 10px; border-radius: 8px; margin-bottom: 12px; }
    </style>
  </head>
  <body>
    <div id="loginGate">
      <div class="card">
        <h1>naviG8r Ops</h1>
        <p class="muted">Sign in with an ops-agent phone (OTP).</p>
        <div id="otpStep1">
          <input id="loginPhone" placeholder="10-digit phone" />
          <button onclick="startOtp()">Send OTP</button>
        </div>
        <div id="otpStep2" style="display:none;">
          <input id="loginCode" placeholder="6-digit code" maxlength="6" />
          <button onclick="verifyOtp()">Verify</button>
        </div>
        <div id="loginError" style="color:#c00;display:none;"></div>
      </div>
    </div>
    <div id="opsContent" style="display:none;">
      <h1>Payment release</h1>
      <p class="muted">Logged in as <span id="sessionPhone"></span> · <button onclick="logout()">Logout</button></p>
      <div id="nonOpsWarn" class="warn" style="display:none;">Not an ops agent — cannot release payments.</div>
      <h2>Pending release</h2>
      <div id="pendingTable" class="muted">Loading…</div>
      <h2>Recently delivered</h2>
      <div id="deliveredTable" class="muted">Loading…</div>
    </div>
    <script>
      const LS_TOKEN = "n8r_ops_token";
      const LS_PHONE = "n8r_ops_phone";
      let _challengeId = null;
      function authHeaders() {
        const h = { "content-type": "application/json" };
        const t = localStorage.getItem(LS_TOKEN);
        if (t) h["authorization"] = "Bearer " + t;
        return h;
      }
      function showErr(msg) {
        const el = document.getElementById("loginError");
        el.textContent = msg || "";
        el.style.display = msg ? "block" : "none";
      }
      async function startOtp() {
        showErr("");
        const phone = document.getElementById("loginPhone").value.trim();
        const res = await fetch("/v1/auth/otp/start", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ phone }) });
        const out = await res.json();
        if (!res.ok) return showErr(out.error || "Failed");
        _challengeId = out.challengeId;
        document.getElementById("otpStep1").style.display = "none";
        document.getElementById("otpStep2").style.display = "block";
        if (out.debugCode) document.getElementById("loginCode").value = out.debugCode;
      }
      async function verifyOtp() {
        showErr("");
        const phone = document.getElementById("loginPhone").value.trim();
        const code = document.getElementById("loginCode").value.trim();
        const res = await fetch("/v1/auth/otp/verify", { method: "POST", headers: { "content-type": "application/json" },
          body: JSON.stringify({ phone, challengeId: _challengeId, code }) });
        const out = await res.json();
        if (!res.ok) return showErr(out.error || "Failed");
        localStorage.setItem(LS_TOKEN, out.accessToken);
        localStorage.setItem(LS_PHONE, phone);
        enterOps();
      }
      function logout() {
        localStorage.removeItem(LS_TOKEN);
        localStorage.removeItem(LS_PHONE);
        location.reload();
      }
      async function enterOps() {
        document.getElementById("loginGate").style.display = "none";
        document.getElementById("opsContent").style.display = "block";
        document.getElementById("sessionPhone").textContent = localStorage.getItem(LS_PHONE) || "";
        const me = await fetch("/v1/auth/me", { headers: authHeaders() });
        const meOut = await me.json();
        const isOps = meOut.isOpsAdmin === true;
        document.getElementById("nonOpsWarn").style.display = isOps ? "none" : "block";
        if (!isOps) return;
        loadPending();
        loadDelivered();
      }
      function fmtInr(paise) { return "₹" + (paise / 100).toFixed(2); }
      function fmtTime(ms) { if (!ms) return "—"; return new Date(ms).toLocaleString(); }
      async function loadPending() {
        const el = document.getElementById("pendingTable");
        const res = await fetch("/ops/shipments/pending-release", { headers: authHeaders() });
        const out = await res.json();
        if (!res.ok) { el.textContent = "Error: " + (out.error || res.status); return; }
        const rows = out.shipments || [];
        if (!rows.length) { el.innerHTML = "<em>None</em>"; return; }
        el.innerHTML = "<table><thead><tr><th>Shipment</th><th>Customer</th><th>Carrier</th><th>Gross</th><th>POD at</th><th></th></tr></thead><tbody>" +
          rows.map(function(s) {
            return "<tr><td><code>" + s.id + "</code></td><td>" + (s.customerOrgName||"") + "</td><td>" + (s.carrierId||"") +
              "</td><td>" + fmtInr(s.grossPaise) + "</td><td>" + fmtTime(s.podAtUtcMs) +
              "</td><td><button onclick=\\"release('" + s.id + "')\\">Release payment</button></td></tr>";
          }).join("") + "</tbody></table>";
      }
      async function loadDelivered() {
        const el = document.getElementById("deliveredTable");
        const res = await fetch("/ops/shipments/delivered", { headers: authHeaders() });
        if (!res.ok) { el.textContent = "Error loading delivered"; return; }
        const out = await res.json();
        const rows = out.shipments || [];
        if (!rows.length) { el.innerHTML = "<em>None recent</em>"; return; }
        el.innerHTML = "<table><thead><tr><th>Shipment</th><th>Customer</th><th>Delivered</th></tr></thead><tbody>" +
          rows.map(function(s) {
            return "<tr><td><code>" + s.id + "</code></td><td>" + (s.customerOrgName||"") + "</td><td>" + fmtTime(s.podAtUtcMs) + "</td></tr>";
          }).join("") + "</tbody></table>";
      }
      async function release(id) {
        if (!confirm("Capture payment and mark " + id + " delivered?")) return;
        const res = await fetch("/ops/shipments/" + id + "/release", { method: "POST", headers: authHeaders(), body: "{}" });
        const out = await res.json();
        alert(JSON.stringify(out, null, 2));
        loadPending();
        loadDelivered();
      }
      if (localStorage.getItem(LS_TOKEN)) enterOps();
    </script>
  </body>
</html>`;
}

async function readJson(req: http.IncomingMessage): Promise<any> {
  const chunks: Buffer[] = [];
  for await (const c of req) chunks.push(Buffer.isBuffer(c) ? c : Buffer.from(c));
  if (chunks.length === 0) return null;
  const raw = Buffer.concat(chunks).toString("utf8");
  return JSON.parse(raw);
}

function header(req: http.IncomingMessage, name: string): string | null {
  const v = req.headers[name.toLowerCase()];
  if (Array.isArray(v)) return v[0] ?? null;
  return v ?? null;
}

function bearerToken(req: http.IncomingMessage): string | null {
  const h = header(req, "authorization");
  if (!h) return null;
  const m = /^Bearer\s+(.+)$/i.exec(h.trim());
  return m?.[1] ?? null;
}

function requireUserId(req: http.IncomingMessage, store: ReturnType<typeof loadStoreFromDisk>): string {
  const allowHeader = process.env.ALLOW_X_USER_ID === "1";
  if (allowHeader) {
    const hdr = String(header(req, "x-user-id") ?? "");
    if (hdr) return hdr;
  }
  const { userId } = verifyBearer(store, bearerToken(req));
  return userId;
}

/**
 * Public marketplace JSON (customer pilot + book flow). Not treated as legacy demo;
 * stays available when NODE_ENV=production unless you remove these routes intentionally.
 */
function publicMarketplaceRouteAllowed(method: string, pathname: string): boolean {
  if (method === "GET" && pathname === "/anchor-trips") return true;
  const segs = pathname.split("/").filter(Boolean);
  if (method === "GET" && segs.length === 2 && segs[0] === "anchor-trips") return true;
  if (method === "POST" && pathname === "/shipments/quote") return true;
  if (method === "POST" && pathname === "/shipments/book") return true;
  if (method === "POST" && pathname === "/v1/payments/razorpay/webhook") return true;
  if (method === "GET" && pathname === "/shipments") return true;
  if (method === "GET" && segs.length === 2 && segs[0] === "shipments") return true;
  if (method === "GET" && segs.length === 3 && segs[0] === "shipments" && segs[2] === "tracking") return true;
  if (method === "POST" && segs.length === 3 && segs[0] === "shipments" && segs[2] === "pod") return true;
  if (method === "POST" && segs.length === 3 && segs[0] === "shipments" && segs[2] === "fail-refund") return true;
  return false;
}

/**
 * Locks down unauthenticated demo/admin surfaces in production (user dumps, HTML console,
 * legacy carrier CRUD, legacy trip publish, ledger/payout toys). Set ENABLE_LEGACY_DEMO_SURFACE=1 to re-enable.
 */
function requireLegacyDemoSurface(res: http.ServerResponse, method: string, pathname: string): boolean {
  if (publicMarketplaceRouteAllowed(method, pathname)) return true;
  const enabled = process.env.NODE_ENV !== "production" || process.env.ENABLE_LEGACY_DEMO_SURFACE === "1";
  if (enabled) return true;
  json(res, 403, { error: "legacy_demo_surface_disabled" });
  return false;
}

/** Any valid Bearer user (OTP session); listing uses org + optional bookedByPhone match. */
function requireBearerUserId(
  req: http.IncomingMessage,
  res: http.ServerResponse,
  store: ReturnType<typeof loadStoreFromDisk>,
): string | null {
  try {
    return verifyBearer(store, bearerToken(req)).userId;
  } catch {
    json(res, 401, { error: "unauthorized" });
    return null;
  }
}

export async function createApp(): Promise<{
  server: http.Server;
  store: ReturnType<typeof loadStoreFromDisk>;
  persist: () => Promise<void>;
  dataFilePath: string | null;
}> {
  const dataFilePath = process.env.PERSISTENCE === "DB" ? null : (process.env.DATA_FILE ?? "./data/store.json");

  let store: ReturnType<typeof loadStoreFromDisk>;
  let persist: () => Promise<void>;

  if (process.env.PERSISTENCE === "DB") {
    if (!process.env.DATABASE_URL?.trim()) {
      throw new Error("PERSISTENCE=DB requires DATABASE_URL");
    }
    const db = await import("./persistenceDb.ts");
    store = await db.loadStoreFromDatabase();
    persist = async () => {
      await db.saveStoreToDatabase(store);
    };
  } else {
    store = loadStoreFromDisk(dataFilePath!);
    persist = async () => {
      saveStoreToDisk(dataFilePath!, store);
    };
  }

  const server = http.createServer(async (req, res) => {
    try {
      const method = req.method ?? "GET";
      const url = new URL(req.url ?? "/", "http://localhost");

      if (method === "GET" && url.pathname === "/health") {
        return json(res, 200, {
          ok: true,
          persistence: process.env.PERSISTENCE === "DB" ? "db" : "file",
          paymentProvider: razorpayPaymentsEnabled() ? "razorpay" : "mock",
        });
      }

      if (method === "POST" && url.pathname === "/v1/payments/razorpay/webhook") {
        const secret = process.env.RAZORPAY_WEBHOOK_SECRET?.trim();
        if (!secret) {
          return json(res, 503, { error: "webhook_secret_not_configured" });
        }
        const raw = await readRawBody(req);
        const sig = header(req, "x-razorpay-signature");
        if (!verifyRazorpayWebhookSignature(raw, sig ?? undefined, secret)) {
          return json(res, 401, { error: "invalid_webhook_signature" });
        }
        let parsed: Record<string, unknown>;
        try {
          parsed = JSON.parse(raw) as Record<string, unknown>;
        } catch {
          return json(res, 400, { error: "invalid_json" });
        }
        applyRazorpayWebhookPayload(store, parsed);
        await persist();
        return json(res, 200, { ok: true });
      }

      // --- v1 auth (pilot OTP + bearer token) ---
      if (method === "POST" && url.pathname === "/v1/auth/otp/start") {
        const body = await readJson(req);
        const out = pilotOtpStart(store, { phone: String(body?.phone ?? "") });
        await persist();
        return json(res, 200, out);
      }

      if (method === "POST" && url.pathname === "/v1/auth/otp/verify") {
        const body = await readJson(req);
        const out = pilotOtpVerify(store, {
          phone: String(body?.phone ?? ""),
          challengeId: String(body?.challengeId ?? ""),
          code: String(body?.code ?? ""),
        });
        // Auto-promote env-var ops admins to a DB membership on first login,
        // so OPS_ADMIN_PHONES can be removed once each admin has logged in once.
        if (isOpsAdmin(store, out.user.id)) {
          try { grantOpsAdmin(store, { phone: out.user.phone }); } catch {}
        }
        await persist();
        return json(res, 200, { ...out, isOpsAdmin: isOpsAdmin(store, out.user.id) });
      }

      if (method === "GET" && url.pathname === "/v1/auth/me") {
        const userId = requireBearerUserId(req, res, store);
        if (!userId) return;
        const user = store.users.get(userId);
        if (!user) return json(res, 404, { error: "user_not_found" });
        return json(res, 200, { user, isOpsAdmin: isOpsAdmin(store, userId) });
      }

      // --- v1 ops-admins management (DB-backed grants) ---
      if (method === "GET" && url.pathname === "/v1/ops-admins") {
        const userId = requireBearerUserId(req, res, store);
        if (!userId) return;
        if (!isOpsAdmin(store, userId)) return json(res, 403, { error: "forbidden" });
        return json(res, 200, { opsAdmins: listOpsAdmins(store) });
      }

      if (method === "POST" && url.pathname === "/v1/ops-admins") {
        const userId = requireBearerUserId(req, res, store);
        if (!userId) return;
        if (!isOpsAdmin(store, userId)) return json(res, 403, { error: "forbidden" });
        const body = await readJson(req);
        const entry = grantOpsAdmin(store, { phone: String(body?.phone ?? "") });
        await persist();
        return json(res, 201, { opsAdmin: entry });
      }

      if (method === "DELETE" && url.pathname.startsWith("/v1/ops-admins/")) {
        const userId = requireBearerUserId(req, res, store);
        if (!userId) return;
        if (!isOpsAdmin(store, userId)) return json(res, 403, { error: "forbidden" });
        const phone = decodeURIComponent(url.pathname.split("/")[3] ?? "");
        const out = revokeOpsAdmin(store, { phone, actingUserId: userId });
        await persist();
        return json(res, 200, out);
      }

      // --- v1 pilot API resources (Flutter Driver app first) ---
      if (method === "POST" && url.pathname === "/v1/pilot/driver/register") {
        const body = await readJson(req);
        const out = registerSoloOwnerOperatorDriver(store, {
          fullName: String(body?.fullName ?? ""),
          phone: String(body?.phone ?? ""),
          orgDisplayName: String(body?.orgDisplayName ?? ""),
          vehicleRegistrationNumber: String(body?.vehicleRegistrationNumber ?? ""),
          vehicleClass: body?.vehicleClass,
          vehicleCapacityKg: Number(body?.vehicleCapacityKg ?? 0),
        });
        await persist();
        return json(res, 201, out);
      }

      if (method === "POST" && url.pathname === "/v1/pilot/driver/login") {
        if (!requireLegacyDemoSurface(res, method, url.pathname)) return;
        const body = await readJson(req);
        const out = pilotLoginDriverByPhone(store, String(body?.phone ?? ""));
        return json(res, 200, out);
      }

      if (method === "GET" && url.pathname === "/v1/pilot/me") {
        const userId = requireUserId(req, store);
        const out = pilotMe(store, userId);
        return json(res, 200, out);
      }

      if (method === "GET" && url.pathname === "/v1/pilot/anchor-trips") {
        const userId = requireUserId(req, store);
        const trips = pilotListMyAnchorTrips(store, userId);
        return json(res, 200, { trips });
      }

      if (method === "POST" && url.pathname.endsWith("/location")) {
        const parts = url.pathname.split("/").filter(Boolean);
        if (parts.length === 5 && parts[0] === "v1" && parts[1] === "pilot" && parts[2] === "anchor-trips") {
          const userId = requireUserId(req, store);
          const tripId = parts[3] ?? "";
          const body = await readJson(req);
          const trip = reportAnchorTripLocation(store, userId, tripId, {
            lat: Number(body?.lat),
            lng: Number(body?.lng),
            recordedAtUtcMs: body?.recordedAtUtcMs != null ? Number(body.recordedAtUtcMs) : undefined,
            accuracyM: body?.accuracyM != null ? Number(body.accuracyM) : undefined,
            speedMps: body?.speedMps != null ? Number(body.speedMps) : undefined,
            headingDeg: body?.headingDeg != null ? Number(body.headingDeg) : undefined,
          });
          await persist();
          return json(res, 200, { trip });
        }
      }

      if (method === "GET" && url.pathname.startsWith("/v1/pilot/anchor-trips/")) {
        const parts = url.pathname.split("/").filter(Boolean);
        if (parts.length === 4 && parts[0] === "v1" && parts[1] === "pilot" && parts[2] === "anchor-trips") {
          const userId = requireUserId(req, store);
          const tripId = parts[3] ?? "";
          const trip = pilotGetMyAnchorTrip(store, userId, tripId);
          return json(res, 200, { trip });
        }
      }

      if (method === "POST" && url.pathname === "/v1/pilot/anchor-trips") {
        const body = await readJson(req);
        const userId = requireUserId(req, store);
        const trip = publishAnchorTripAsPilotDriver(store, {
          userId,
          orgId: String(body?.orgId ?? ""),
          originCity: String(body?.originCity ?? ""),
          destCity: String(body?.destCity ?? ""),
          origin: body?.origin,
          destination: body?.destination,
          windowStart: String(body?.windowStart ?? ""),
          windowEnd: String(body?.windowEnd ?? ""),
          vehicleClass: body?.vehicleClass,
          capacityKg: Number(body?.capacityKg ?? 0),
        });
        await persist();
        return json(res, 201, { trip });
      }

      if (method === "POST" && url.pathname === "/v1/pilot/rates/estimate") {
        const body = await readJson(req);
        const userId = requireUserId(req, store);
        const out = pilotRatesEstimate(store, userId, {
          origin: body?.origin,
          destination: body?.destination,
          vehicleClass: body?.vehicleClass,
          sampleWeightsKg: body?.sampleWeightsKg,
        });
        return json(res, 200, out);
      }

      if (method === "GET" && url.pathname === "/v1/pilot/carrier/shipments") {
        const userId = requireUserId(req, store);
        const anchorTripId = url.searchParams.get("anchorTripId") ?? undefined;
        const shipments = pilotListCarrierShipments(store, userId, { anchorTripId });
        return json(res, 200, { shipments });
      }

      if (method === "GET" && url.pathname === "/v1/pilot/carrier/earnings") {
        const userId = requireUserId(req, store);
        const orgId = url.searchParams.get("orgId") ?? "";
        const summary = pilotCarrierEarningsSummary(store, userId, orgId);
        return json(res, 200, { summary });
      }

      if (method === "POST" && url.pathname === "/v1/pilot/carrier/payout-setup") {
        const body = await readJson(req);
        const userId = requireUserId(req, store);
        const out = await pilotSubmitPayoutSetup(store, userId, {
          orgId: String(body?.orgId ?? ""),
          accountHolderName: String(body?.accountHolderName ?? ""),
          ifsc: String(body?.ifsc ?? ""),
          accountNumber: body?.accountNumber != null ? String(body.accountNumber) : undefined,
        });
        await persist();
        return json(res, 200, out);
      }

      if (method === "GET" && url.pathname === "/v1/pilot/carrier/ledger") {
        const userId = requireUserId(req, store);
        const orgId = url.searchParams.get("orgId") ?? "";
        const lines = pilotListCarrierLedger(store, userId, orgId);
        return json(res, 200, { lines });
      }

      if (method === "GET" && url.pathname === "/v1/pilot/carrier/payout-batches") {
        const userId = requireUserId(req, store);
        const orgId = url.searchParams.get("orgId") ?? "";
        const payoutBatches = pilotListCarrierPayoutBatches(store, userId, orgId);
        return json(res, 200, { payoutBatches });
      }

      if (method === "GET" && url.pathname === "/v1/customer/eligible-anchor-trips") {
        const pickupLat = Number(url.searchParams.get("pickupLat"));
        const pickupLng = Number(url.searchParams.get("pickupLng"));
        const dropLat = Number(url.searchParams.get("dropLat"));
        const dropLng = Number(url.searchParams.get("dropLng"));
        const weightKg = Number(url.searchParams.get("weightKg"));
        const trips = customerEligibleAnchorTripsPhaseA(store, {
          pickup: { lat: pickupLat, lng: pickupLng },
          drop: { lat: dropLat, lng: dropLng },
          weightKg,
        });
        return json(res, 200, { trips });
      }

      if (method === "POST" && url.pathname === "/v1/pilot/customer/register") {
        const body = await readJson(req);
        const out = registerCustomerOrgAdmin(store, {
          fullName: String(body?.fullName ?? ""),
          phone: String(body?.phone ?? ""),
          orgDisplayName: String(body?.orgDisplayName ?? ""),
        });
        await persist();
        return json(res, 201, out);
      }

      if (method === "GET" && url.pathname === "/v1/orgs") {
        if (!requireLegacyDemoSurface(res, method, url.pathname)) return;
        const orgs = [...store.organizations.values()];
        return json(res, 200, { orgs });
      }

      if (method === "GET" && url.pathname === "/v1/users") {
        if (!requireLegacyDemoSurface(res, method, url.pathname)) return;
        const users = [...store.users.values()];
        return json(res, 200, { users });
      }

      if (method === "GET" && url.pathname === "/admin") {
        if (!requireLegacyDemoSurface(res, method, url.pathname)) return;
        const carriers = [...store.carriers.values()];
        const orgs = [...store.organizations.values()];
        const users = [...store.users.values()];
        const memberships = [...store.memberships.values()];
        const vehicles = [...store.vehicles.values()];
        const driverProfiles = [...store.driverProfiles.values()];
        const trips = [...store.anchorTrips.values()];
        const shipments = [...store.shipments.values()];
        const ledgerLines = [...store.ledgerLines.values()];
        const payoutBatches = [...store.payoutBatches.values()];

        const esc = (s: any) =>
          String(s)
            .replaceAll("&", "&amp;")
            .replaceAll("<", "&lt;")
            .replaceAll(">", "&gt;")
            .replaceAll("\"", "&quot;");

        const persistenceBacking =
          dataFilePath != null ? dataFilePath : "Postgres (Prisma, PERSISTENCE=DB)";

        return html(
          res,
          200,
          `<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Logistics MVP Admin</title>
    <style>
      body { font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Arial; margin: 16px; }
      code, pre { background: #f6f6f6; padding: 2px 6px; border-radius: 6px; }
      pre { padding: 12px; overflow: auto; }
      .row { display: flex; gap: 16px; flex-wrap: wrap; }
      .card { border: 1px solid #e5e5e5; border-radius: 10px; padding: 12px; min-width: 320px; }
      h2 { margin: 0 0 8px; font-size: 16px; }
      h3 { margin: 12px 0 8px; font-size: 14px; }
      input { width: 100%; padding: 8px; margin: 6px 0; box-sizing: border-box; }
      button { padding: 8px 12px; cursor: pointer; }
      table { width: 100%; border-collapse: collapse; }
      th, td { border-bottom: 1px solid #eee; padding: 6px; text-align: left; font-size: 12px; vertical-align: top; }
      .muted { color: #666; font-size: 12px; }
      #loginGate { max-width: 380px; margin: 60px auto; }
      #loginGate .card { background: #fafafa; }
      #loginGate h2 { font-size: 18px; }
      #loginError { color: #c00; font-size: 13px; margin-top: 6px; display: none; }
      .topbar { display: flex; align-items: center; justify-content: space-between; margin-bottom: 4px; }
      .topbar .session-info { font-size: 13px; color: #555; }
      .topbar button { background: none; border: 1px solid #ccc; border-radius: 6px; font-size: 13px; padding: 4px 10px; }
      .role-badge { display: inline-block; font-size: 11px; padding: 2px 8px; border-radius: 10px; margin-left: 6px; font-weight: 600; }
      .role-ops { background: #e6f7ff; color: #0050b3; border: 1px solid #91d5ff; }
      .role-customer { background: #f6f6f6; color: #555; border: 1px solid #ddd; }
      .warning-banner { background: #fff1f0; border: 1px solid #ffa39e; color: #a8071a; padding: 10px 14px; border-radius: 8px; margin-bottom: 12px; font-size: 13px; }
    </style>
  </head>
  <body>
    <!-- Login gate — shown when no session stored -->
    <div id="loginGate" style="display:none;">
      <div class="card">
        <h2>Admin Login</h2>
        <div id="otpStep1">
          <input id="loginPhone" placeholder="Phone number (10 digits)" autocomplete="tel" />
          <button onclick="startOtp()">Send OTP</button>
        </div>
        <div id="otpStep2" style="display:none;">
          <p class="muted">OTP sent. Enter the 6-digit code:</p>
          <input id="loginCode" placeholder="6-digit code" maxlength="6" autocomplete="one-time-code" />
          <button onclick="verifyOtp()">Verify</button>
          <button onclick="resetLogin()" style="background:none;border:none;color:#666;font-size:12px;margin-top:4px;">Back</button>
        </div>
        <div id="loginError"></div>
      </div>
    </div>

    <!-- Main admin content — shown after login -->
    <div id="adminContent" style="display:none;">
    <div class="topbar">
      <div>
        <h1 style="margin:0;">Logistics MVP Admin</h1>
        <p class="muted" style="margin:2px 0 0;">Backed by <code>${esc(persistenceBacking)}</code></p>
      </div>
      <div style="text-align:right;">
        <span class="session-info" id="sessionInfo"></span>
        <span id="roleBadge"></span><br/>
        <button onclick="logout()">Logout</button>
      </div>
    </div>
    <div id="nonOpsWarning" class="warning-banner" style="display:none;">
      You're logged in but you're not an <strong>Ops Admin</strong>.
      You can only act on shipments you booked. To get operator access,
      ask an existing ops admin to grant you the role, or have your phone added
      to <code>OPS_ADMIN_PHONES</code> (bootstrap-only) on the server.
    </div>

    <div id="opsAdminsCard" class="card" style="margin-bottom:12px;display:none;">
      <h2>Ops Admins <span class="muted">(DB-backed — survives env-var removal)</span></h2>
      <div id="opsAdminsList" class="muted" style="margin-bottom:10px;">Loading…</div>
      <div style="display:flex;gap:8px;align-items:center;">
        <input id="grantPhone" placeholder="10-digit phone to grant" style="flex:1;margin:0;" />
        <button onclick="grantOps()">Grant Ops Admin</button>
      </div>
      <p class="muted" style="margin:6px 0 0;">User must already be registered (customer or driver) before granting.</p>
    </div>

    <div class="row">
      <div class="card">
        <h2>Create carrier</h2>
        <form method="post" action="/carriers" onsubmit="return submitJson(event)">
          <input name="name" placeholder="Carrier name" required />
          <button type="submit">Create</button>
        </form>
      </div>

      <div class="card">
        <h2>Publish anchor trip</h2>
        <form method="post" action="/anchor-trips" onsubmit="return submitJson(event)">
          <input name="carrierId" placeholder="carrierId" required />
          <input name="originCity" placeholder="originCity" required />
          <input name="destCity" placeholder="destCity" required />
          <input name="windowStart" placeholder="windowStart (ISO, +05:30)" required />
          <input name="windowEnd" placeholder="windowEnd (ISO, +05:30)" required />
          <input name="vehicleClass" placeholder="vehicleClass (SMALL|MEDIUM|LARGE)" required />
          <input name="capacityKg" placeholder="capacityKg" required />
          <button type="submit">Publish</button>
        </form>
      </div>

      <div class="card">
        <h2>Book shipment</h2>
        <form method="post" action="/shipments/book" onsubmit="return submitJson(event)">
          <input name="anchorTripId" placeholder="anchorTripId" required />
          <input name="customerOrgName" placeholder="customerOrgName" required />
          <input name="weightKg" placeholder="weightKg" required />
          <input name="pickupAddress" placeholder="pickupAddress" required />
          <input name="dropAddress" placeholder="dropAddress" required />
          <button type="submit">Book</button>
        </form>
      </div>

      <div class="card">
        <h2>Mark POD</h2>
        <form method="post" action="/shipments/__SHIPMENT__/pod" onsubmit="return submitPod(event)">
          <input name="shipmentId" placeholder="shipmentId" required />
          <button type="submit">Mark delivered</button>
        </form>
      </div>

      <div class="card">
        <h2>Fail + refund</h2>
        <form method="post" action="/shipments/__SHIPMENT__/fail-refund" onsubmit="return submitFailRefund(event)">
          <input name="shipmentId" placeholder="shipmentId" required />
          <button type="submit">Fail + refund</button>
        </form>
      </div>

      <div class="card">
        <h2>Run payout batch</h2>
        <p class="muted" style="margin:2px 0 8px;">
          Mode: <code>${esc(payoutsMode())}</code>
          ${
            payoutsMode() === "RAZORPAYX"
              ? "&mdash; real RazorpayX transfers per carrier (test keys)."
              : "&mdash; bookkeeping only (marks ledger PAID, no money moves). Set <code>PAYOUTS_MODE=RAZORPAYX</code> to enable transfers."
          }
          <br/>Requires an Ops Admin/Agent login.
        </p>
        <form method="post" action="/payout-batches/run" onsubmit="return submitJson(event)">
          <input name="nowUtcMs" placeholder="nowUtcMs (optional)" />
          <button type="submit">Run</button>
        </form>
      </div>
    </div>

    <h3>Carriers (${carriers.length})</h3>
    <pre>${esc(JSON.stringify(carriers, null, 2))}</pre>

    <h3>Organizations (${orgs.length})</h3>
    <pre>${esc(JSON.stringify(orgs, null, 2))}</pre>

    <h3>Users (${users.length})</h3>
    <pre>${esc(JSON.stringify(users, null, 2))}</pre>

    <h3>Memberships (${memberships.length})</h3>
    <pre>${esc(JSON.stringify(memberships, null, 2))}</pre>

    <h3>Vehicles (${vehicles.length})</h3>
    <pre>${esc(JSON.stringify(vehicles, null, 2))}</pre>

    <h3>Driver profiles (${driverProfiles.length})</h3>
    <pre>${esc(JSON.stringify(driverProfiles, null, 2))}</pre>

    <h3>Anchor trips (${trips.length})</h3>
    <pre>${esc(JSON.stringify(trips, null, 2))}</pre>

    <h3>Shipments (${shipments.length})</h3>
    <pre>${esc(JSON.stringify(shipments, null, 2))}</pre>

    <h3>Ledger lines (${ledgerLines.length})</h3>
    <pre>${esc(JSON.stringify(ledgerLines, null, 2))}</pre>

    <h3>Payout batches (${payoutBatches.length})</h3>
    <pre>${esc(JSON.stringify(payoutBatches, null, 2))}</pre>

    </div><!-- end adminContent -->

    <script>
      const LS_TOKEN = "n8r_admin_token";
      const LS_PHONE = "n8r_admin_phone";
      const LS_OPS = "n8r_admin_isops";
      let _challengeId = null;

      function showError(msg) {
        const el = document.getElementById("loginError");
        el.textContent = msg;
        el.style.display = msg ? "block" : "none";
      }

      async function startOtp() {
        showError("");
        const phone = document.getElementById("loginPhone").value.trim();
        if (!phone) return showError("Enter a phone number.");
        try {
          const res = await fetch("/v1/auth/otp/start", {
            method: "POST",
            headers: { "content-type": "application/json" },
            body: JSON.stringify({ phone })
          });
          const out = await res.json();
          if (!res.ok) return showError(out.error || "Failed to send OTP.");
          _challengeId = out.challengeId;
          document.getElementById("otpStep1").style.display = "none";
          document.getElementById("otpStep2").style.display = "block";
          if (out.debugCode) {
            document.getElementById("loginCode").value = out.debugCode;
          }
        } catch (e) { showError("Network error."); }
      }

      async function verifyOtp() {
        showError("");
        const phone = document.getElementById("loginPhone").value.trim();
        const code = document.getElementById("loginCode").value.trim();
        if (!code) return showError("Enter the OTP code.");
        try {
          const res = await fetch("/v1/auth/otp/verify", {
            method: "POST",
            headers: { "content-type": "application/json" },
            body: JSON.stringify({ phone, challengeId: _challengeId, code })
          });
          const out = await res.json();
          if (!res.ok) return showError(out.error || "Verification failed.");
          localStorage.setItem(LS_TOKEN, out.accessToken);
          localStorage.setItem(LS_PHONE, phone);
          localStorage.setItem(LS_OPS, out.isOpsAdmin ? "1" : "0");
          enterAdmin();
        } catch (e) { showError("Network error."); }
      }

      function resetLogin() {
        _challengeId = null;
        document.getElementById("loginCode").value = "";
        document.getElementById("otpStep1").style.display = "block";
        document.getElementById("otpStep2").style.display = "none";
        showError("");
      }

      function logout() {
        localStorage.removeItem(LS_TOKEN);
        localStorage.removeItem(LS_PHONE);
        localStorage.removeItem(LS_OPS);
        document.getElementById("adminContent").style.display = "none";
        document.getElementById("loginGate").style.display = "block";
        resetLogin();
      }

      async function refreshOpsAdminStatus() {
        try {
          const res = await fetch("/v1/auth/me", { headers: authHeaders() });
          if (!res.ok) return;
          const out = await res.json();
          localStorage.setItem(LS_OPS, out.isOpsAdmin ? "1" : "0");
          renderRoleBadge();
        } catch (e) {}
      }

      function renderRoleBadge() {
        const isOps = localStorage.getItem(LS_OPS) === "1";
        const badge = document.getElementById("roleBadge");
        const warn = document.getElementById("nonOpsWarning");
        const opsCard = document.getElementById("opsAdminsCard");
        if (isOps) {
          badge.innerHTML = '<span class="role-badge role-ops">Ops Admin</span>';
          warn.style.display = "none";
          opsCard.style.display = "block";
          loadOpsAdmins();
        } else {
          badge.innerHTML = '<span class="role-badge role-customer">Customer</span>';
          warn.style.display = "block";
          opsCard.style.display = "none";
        }
      }

      async function loadOpsAdmins() {
        const listEl = document.getElementById("opsAdminsList");
        try {
          const res = await fetch("/v1/ops-admins", { headers: authHeaders() });
          if (!res.ok) { listEl.textContent = "Failed to load ops admins."; return; }
          const out = await res.json();
          const items = out.opsAdmins || [];
          if (items.length === 0) { listEl.innerHTML = '<em>None</em>'; return; }
          listEl.innerHTML = items.map(function(a) {
            const tag = a.source === "DB"
              ? '<span class="role-badge role-ops">DB</span>'
              : '<span class="role-badge role-customer">env</span>';
            const revoke = a.source === "DB"
              ? '<button onclick="revokeOps(\\''+a.phone+'\\')" style="font-size:11px;padding:2px 8px;">Revoke</button>'
              : '';
            return '<div style="display:flex;justify-content:space-between;align-items:center;padding:4px 0;border-bottom:1px solid #f0f0f0;">' +
              '<span><code>'+a.phone+'</code> &mdash; '+ (a.fullName || '(no name)') +' '+tag+'</span>' + revoke + '</div>';
          }).join("");
        } catch (e) { listEl.textContent = "Network error loading ops admins."; }
      }

      async function grantOps() {
        const phone = document.getElementById("grantPhone").value.trim();
        if (!phone) { alert("Enter a phone."); return; }
        const res = await fetch("/v1/ops-admins", {
          method: "POST",
          headers: authHeaders(),
          body: JSON.stringify({ phone })
        });
        const out = await res.json().catch(() => ({}));
        if (!res.ok) { alert("Grant failed: " + (out.error || res.status) + (out.detail ? " — " + out.detail : "")); return; }
        document.getElementById("grantPhone").value = "";
        loadOpsAdmins();
      }

      async function revokeOps(phone) {
        if (!confirm("Revoke ops-admin from " + phone + "?")) return;
        const res = await fetch("/v1/ops-admins/" + encodeURIComponent(phone), {
          method: "DELETE",
          headers: authHeaders()
        });
        const out = await res.json().catch(() => ({}));
        if (!res.ok) { alert("Revoke failed: " + (out.error || res.status) + (out.detail ? " — " + out.detail : "")); return; }
        loadOpsAdmins();
      }

      function enterAdmin() {
        document.getElementById("loginGate").style.display = "none";
        document.getElementById("adminContent").style.display = "block";
        const phone = localStorage.getItem(LS_PHONE) || "";
        document.getElementById("sessionInfo").textContent = phone ? "Logged in as " + phone : "";
        renderRoleBadge();
        refreshOpsAdminStatus();
      }

      function authHeaders() {
        const h = { "content-type": "application/json" };
        const tok = localStorage.getItem(LS_TOKEN);
        if (tok) h["authorization"] = "Bearer " + tok;
        return h;
      }

      async function submitJson(e) {
        e.preventDefault();
        const form = e.target;
        const data = Object.fromEntries(new FormData(form).entries());
        for (const k of ["capacityKg","weightKg","nowUtcMs"]) if (data[k] !== undefined && data[k] !== "") data[k] = Number(data[k]);
        const res = await fetch(form.action, {
          method: "POST",
          headers: authHeaders(),
          body: JSON.stringify(data)
        });
        const out = await res.json().catch(() => ({}));
        alert(JSON.stringify(out, null, 2));
        location.reload();
        return false;
      }

      async function submitPod(e) {
        e.preventDefault();
        const form = e.target;
        const data = Object.fromEntries(new FormData(form).entries());
        const shipmentId = data.shipmentId;
        const res = await fetch("/shipments/" + shipmentId + "/pod", { method: "POST", headers: authHeaders(), body: "{}" });
        const out = await res.json().catch(() => ({}));
        alert(JSON.stringify(out, null, 2));
        location.reload();
        return false;
      }

      async function submitFailRefund(e) {
        e.preventDefault();
        const form = e.target;
        const data = Object.fromEntries(new FormData(form).entries());
        const shipmentId = data.shipmentId;
        const res = await fetch("/shipments/" + shipmentId + "/fail-refund", { method: "POST", headers: authHeaders(), body: "{}" });
        const out = await res.json().catch(() => ({}));
        alert(JSON.stringify(out, null, 2));
        location.reload();
        return false;
      }

      // On page load: check for stored session
      if (localStorage.getItem(LS_TOKEN)) {
        enterAdmin();
      } else {
        document.getElementById("loginGate").style.display = "block";
      }
    </script>
  </body>
</html>`
        );
      }

      if (method === "POST" && url.pathname === "/carriers") {
        if (!requireLegacyDemoSurface(res, method, url.pathname)) return;
        const body = await readJson(req);
        const carrier = createCarrier(store, String(body?.name ?? ""));
        await persist();
        return json(res, 201, { carrier });
      }

      if (method === "GET" && url.pathname === "/carriers") {
        if (!requireLegacyDemoSurface(res, method, url.pathname)) return;
        const carriers = [...store.carriers.values()];
        return json(res, 200, { carriers });
      }

      if (method === "POST" && url.pathname === "/anchor-trips") {
        if (!requireLegacyDemoSurface(res, method, url.pathname)) return;
        const body = await readJson(req);
        const trip = publishAnchorTrip(store, {
          carrierId: String(body?.carrierId ?? ""),
          originCity: String(body?.originCity ?? ""),
          destCity: String(body?.destCity ?? ""),
          windowStart: String(body?.windowStart ?? ""),
          windowEnd: String(body?.windowEnd ?? ""),
          vehicleClass: body?.vehicleClass,
          capacityKg: Number(body?.capacityKg ?? 0),
        });
        await persist();
        return json(res, 201, { trip });
      }

      if (method === "GET" && url.pathname.startsWith("/anchor-trips/")) {
        const tripId = url.pathname.slice("/anchor-trips/".length).split("/")[0] ?? "";
        if (tripId.length > 0) {
          const trip = store.anchorTrips.get(tripId);
          if (!trip) return json(res, 404, { error: "trip_not_found" });
          return json(res, 200, { trip });
        }
      }

      if (method === "GET" && url.pathname === "/anchor-trips") {
        const trips = [...store.anchorTrips.values()];
        return json(res, 200, { trips });
      }

      if (method === "POST" && url.pathname === "/shipments/quote") {
        if (!requireLegacyDemoSurface(res, method, url.pathname)) return;
        const body = await readJson(req);
        const anchorRaw = body?.anchorTripId;
        const anchorTripId =
          anchorRaw != null && String(anchorRaw).trim() !== "" ? String(anchorRaw).trim() : undefined;
        const quote = quoteShipmentMarketplace(store, {
          weightKg: Number(body?.weightKg ?? 0),
          pickup: body?.pickup,
          drop: body?.drop,
          anchorTripId,
        });
        return json(res, 200, { quote });
      }

      if (method === "GET" && url.pathname === "/shipments") {
        if (!requireLegacyDemoSurface(res, method, url.pathname)) return;
        const userId = requireBearerUserId(req, res, store);
        if (!userId) return;
        const shipments = [...store.shipments.values()].filter((s) => shipmentVisibleToCustomerUser(store, s, userId));
        return json(res, 200, { shipments });
      }

      if (method === "GET" && url.pathname.startsWith("/shipments/")) {
        const segs = url.pathname.split("/").filter(Boolean);
        if (segs.length === 3 && segs[0] === "shipments" && segs[2] === "tracking") {
          if (!requireLegacyDemoSurface(res, method, url.pathname)) return;
          const userId = requireBearerUserId(req, res, store);
          if (!userId) return;
          const shipmentId = segs[1] ?? "";
          try {
            const out = getShipmentTripTracking(store, userId, shipmentId);
            return json(res, 200, out);
          } catch (e: any) {
            const msg = String(e?.message ?? "");
            if (msg === "shipment_not_found" || msg === "anchor_trip_not_found") {
              return json(res, 404, { error: msg });
            }
            throw e;
          }
        }
        if (segs.length === 2 && segs[0] === "shipments") {
          if (!requireLegacyDemoSurface(res, method, url.pathname)) return;
          const userId = requireBearerUserId(req, res, store);
          if (!userId) return;
          const shipmentId = segs[1] ?? "";
          const shipment = store.shipments.get(shipmentId);
          if (!shipment || !shipmentVisibleToCustomerUser(store, shipment, userId)) {
            return json(res, 404, { error: "shipment_not_found" });
          }
          const payment = store.payments.get(shipment.paymentId) ?? null;
          return json(res, 200, { shipment, payment });
        }
      }

      if (method === "POST" && url.pathname === "/shipments/book") {
        if (!requireLegacyDemoSurface(res, method, url.pathname)) return;
        const body = await readJson(req);
        let customerOrg: { id: string; displayName: string } | undefined;
        try {
          const { userId } = verifyBearer(store, bearerToken(req));
          const org = customerPrimaryOrgForUser(store, userId);
          if (org) customerOrg = { id: org.id, displayName: org.displayName };
        } catch {
          /* anonymous booking: no customerOrgId on shipment */
        }
        const phoneField = body?.customerPhone ?? body?.bookedByPhone;
        const shipment = bookShipment(store, {
          anchorTripId: String(body?.anchorTripId ?? ""),
          customerOrgName: String(body?.customerOrgName ?? ""),
          customerOrg,
          bookedByPhoneRaw:
            phoneField != null && String(phoneField).trim() !== "" ? String(phoneField) : undefined,
          weightKg: Number(body?.weightKg ?? 0),
          pickupAddress: String(body?.pickupAddress ?? ""),
          dropAddress: String(body?.dropAddress ?? ""),
          pickup: body?.pickup,
          drop: body?.drop,
        });

        try {
          if (razorpayPaymentsEnabled()) {
            await attachRazorpayOrderForShipment(store, shipment.id);
          }
        } catch (e) {
          rollbackBooking(store, shipment.id);
          throw e;
        }

        await persist();

        const pay = store.payments.get(shipment.paymentId) ?? null;
        const rzpKey = publicRazorpayKeyId();

        const bodyOut: Record<string, unknown> = { shipment, payment: pay };
        if (razorpayPaymentsEnabled() && rzpKey) bodyOut["razorpayKeyId"] = rzpKey;
        return json(res, 201, bodyOut);
      }

      if (method === "POST" && url.pathname.startsWith("/shipments/") && url.pathname.endsWith("/driver-pod")) {
        const userId = requireUserId(req, store);
        const shipmentId = url.pathname.split("/")[2] ?? "";
        const body = await readJson(req);
        try {
          const shipment = submitDriverPod(store, {
            shipmentId,
            userId,
            notes: body?.notes != null ? String(body.notes) : undefined,
          });
          await persist();
          return json(res, 200, { shipment });
        } catch (e) {
          if (e instanceof ApiError) throw e;
          const msg = String((e as Error)?.message ?? "");
          if (msg === "forbidden") return json(res, 403, { error: "forbidden" });
          throw e;
        }
      }

      if (method === "GET" && url.pathname === "/ops/shipments/pending-release") {
        const userId = requireBearerUserId(req, res, store);
        if (!userId) return;
        try {
          assertOpsAgent(store, userId);
        } catch {
          return json(res, 403, { error: "forbidden" });
        }
        const shipments = opsListPendingRelease(store);
        return json(res, 200, { shipments });
      }

      if (method === "GET" && url.pathname === "/ops/shipments/delivered") {
        const userId = requireBearerUserId(req, res, store);
        if (!userId) return;
        try {
          assertOpsAgent(store, userId);
        } catch {
          return json(res, 403, { error: "forbidden" });
        }
        const shipments = opsListRecentlyDelivered(store);
        return json(res, 200, { shipments });
      }

      if (method === "GET" && url.pathname.startsWith("/ops/shipments/") && url.pathname.split("/").length === 4) {
        const userId = requireBearerUserId(req, res, store);
        if (!userId) return;
        try {
          assertOpsAgent(store, userId);
        } catch {
          return json(res, 403, { error: "forbidden" });
        }
        const shipmentId = url.pathname.split("/")[3] ?? "";
        const out = opsShipmentDetail(store, shipmentId);
        return json(res, 200, out);
      }

      if (method === "POST" && url.pathname.startsWith("/ops/shipments/") && url.pathname.endsWith("/release")) {
        const userId = requireBearerUserId(req, res, store);
        if (!userId) return;
        try {
          assertOpsAgent(store, userId);
        } catch {
          return json(res, 403, { error: "forbidden" });
        }
        const parts = url.pathname.split("/");
        const shipmentId = parts[3] ?? "";
        const body = await readJson(req);
        const out = await releasePaymentAndDeliver(store, {
          shipmentId,
          podAtUtcMs: body?.podAtUtcMs,
        });
        await persist();
        return json(res, 200, out);
      }

      if (method === "GET" && url.pathname === "/ops") {
        return html(res, 200, opsPortalHtml());
      }

      if (method === "POST" && url.pathname.startsWith("/shipments/") && url.pathname.endsWith("/pod")) {
        if (!requireLegacyDemoSurface(res, method, url.pathname)) return;
        const shipmentId = url.pathname.split("/")[2] ?? "";
        const demoSurface = process.env.ENABLE_LEGACY_DEMO_SURFACE === "1";
        const hasBearerToken = !!bearerToken(req);
        if (hasBearerToken) {
          const userId = requireBearerUserId(req, res, store);
          if (!userId) return;
          const shipment = store.shipments.get(shipmentId);
          if (!shipment) return json(res, 404, { error: "shipment_not_found" });
          const opsAdmin = isOpsAdmin(store, userId);
          const visible =
            opsAdmin ||
            shipmentVisibleToCustomerUser(store, shipment, userId) ||
            shipmentVisibleToCarrierPilot(store, shipment, userId);
          if (!visible) {
            return json(res, 404, { error: "shipment_not_found" });
          }
        } else if (!demoSurface) {
          return json(res, 401, { error: "unauthorized" });
        } else {
          if (!store.shipments.get(shipmentId)) {
            return json(res, 404, { error: "shipment_not_found" });
          }
        }
        const body = await readJson(req);
        await ensureRazorpayCapturedBeforePod(store, shipmentId);
        const out = markPodDelivered(store, { shipmentId, podAtUtcMs: body?.podAtUtcMs });
        await persist();
        return json(res, 200, out);
      }

      if (method === "POST" && url.pathname.startsWith("/shipments/") && url.pathname.endsWith("/fail-refund")) {
        if (!requireLegacyDemoSurface(res, method, url.pathname)) return;
        const shipmentId = url.pathname.split("/")[2] ?? "";
        const demoSurface = process.env.ENABLE_LEGACY_DEMO_SURFACE === "1";
        const hasBearerToken = !!bearerToken(req);
        if (hasBearerToken) {
          const userId = requireBearerUserId(req, res, store);
          if (!userId) return;
          const shipmentPre = store.shipments.get(shipmentId);
          if (!shipmentPre) return json(res, 404, { error: "shipment_not_found" });
          const opsAdmin = isOpsAdmin(store, userId);
          if (!opsAdmin && !shipmentVisibleToCustomerUser(store, shipmentPre, userId)) {
            return json(res, 404, { error: "shipment_not_found" });
          }
        } else if (!demoSurface) {
          return json(res, 401, { error: "unauthorized" });
        } else {
          if (!store.shipments.get(shipmentId)) {
            return json(res, 404, { error: "shipment_not_found" });
          }
        }
        const shipment = await failCarrierAndRefund(store, { shipmentId });
        await persist();
        return json(res, 200, { shipment });
      }

      if (method === "GET" && url.pathname.startsWith("/carriers/") && url.pathname.endsWith("/ledger")) {
        const userId = requireUserId(req, store);
        assertOpsAgent(store, userId);
        const carrierId = url.pathname.split("/")[2] ?? "";
        const lines = [...store.ledgerLines.values()].filter((l) => l.carrierId === carrierId);
        return json(res, 200, { lines });
      }

      if (method === "POST" && url.pathname === "/payout-batches/run") {
        const userId = requireUserId(req, store);
        assertOpsAgent(store, userId);
        const body = await readJson(req);
        const batch = await runPayoutBatch(store, { nowUtcMs: body?.nowUtcMs });
        await persist();
        return json(res, 200, { batch });
      }

      if (method === "GET" && url.pathname === "/payout-batches") {
        const userId = requireUserId(req, store);
        assertOpsAgent(store, userId);
        const payoutBatches = [...store.payoutBatches.values()];
        return json(res, 200, { payoutBatches });
      }

      return json(res, 404, { error: "not_found" });
    } catch (e: any) {
      if (e instanceof ApiError) {
        const status = e.httpStatus ?? 400;
        return json(res, status, { error: e.message, ...e.extra } as Record<string, unknown>);
      }
      const msg = String(e?.message ?? "bad_request");
      if (msg === "unauthorized" || msg === "invalid_token" || msg === "token_expired") {
        return json(res, 401, { error: "unauthorized" });
      }
      return json(res, 400, { error: msg });
    }
  });

  return { server, store, persist, dataFilePath };
}

