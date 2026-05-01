import http from "node:http";
import { URL } from "node:url";
import { pilotOtpStart, pilotOtpVerify, verifyBearer } from "./auth.ts";
import { loadStoreFromDisk, saveStoreToDisk } from "./persistence.ts";
import {
  bookShipment,
  createCarrier,
  failCarrierAndRefund,
  markPodDelivered,
  pilotLoginDriverByPhone,
  pilotGetMyAnchorTrip,
  pilotMe,
  pilotListMyAnchorTrips,
  publishAnchorTrip,
  publishAnchorTripAsPilotDriver,
  quoteShipment,
  registerCustomerOrgAdmin,
  registerSoloOwnerOperatorDriver,
  runPayoutBatch,
} from "./services.ts";

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

export function createApp() {
  const dataFilePath = process.env.DATA_FILE ?? "./data/store.json";
  const store = loadStoreFromDisk(dataFilePath);

  const persist = () => saveStoreToDisk(dataFilePath, store);

  const server = http.createServer(async (req, res) => {
    try {
      const method = req.method ?? "GET";
      const url = new URL(req.url ?? "/", "http://localhost");

      if (method === "GET" && url.pathname === "/health") {
        return json(res, 200, { ok: true });
      }

      // --- v1 auth (pilot OTP + bearer token) ---
      if (method === "POST" && url.pathname === "/v1/auth/otp/start") {
        const body = await readJson(req);
        const out = pilotOtpStart(store, { phone: String(body?.phone ?? "") });
        persist();
        return json(res, 200, out);
      }

      if (method === "POST" && url.pathname === "/v1/auth/otp/verify") {
        const body = await readJson(req);
        const out = pilotOtpVerify(store, {
          phone: String(body?.phone ?? ""),
          challengeId: String(body?.challengeId ?? ""),
          code: String(body?.code ?? ""),
        });
        persist();
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
        persist();
        return json(res, 201, out);
      }

      if (method === "POST" && url.pathname === "/v1/pilot/driver/login") {
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

      if (method === "GET" && url.pathname.startsWith("/v1/pilot/anchor-trips/")) {
        const userId = requireUserId(req, store);
        const tripId = url.pathname.split("/").at(-1) ?? "";
        const trip = pilotGetMyAnchorTrip(store, userId, String(tripId));
        return json(res, 200, { trip });
      }

      if (method === "POST" && url.pathname === "/v1/pilot/anchor-trips") {
        const body = await readJson(req);
        const userId = requireUserId(req, store);
        const trip = publishAnchorTripAsPilotDriver(store, {
          userId,
          orgId: String(body?.orgId ?? ""),
          originCity: String(body?.originCity ?? ""),
          destCity: String(body?.destCity ?? ""),
          windowStart: String(body?.windowStart ?? ""),
          windowEnd: String(body?.windowEnd ?? ""),
          vehicleClass: body?.vehicleClass,
          capacityKg: Number(body?.capacityKg ?? 0),
        });
        persist();
        return json(res, 201, { trip });
      }

      if (method === "POST" && url.pathname === "/v1/pilot/customer/register") {
        const body = await readJson(req);
        const out = registerCustomerOrgAdmin(store, {
          fullName: String(body?.fullName ?? ""),
          phone: String(body?.phone ?? ""),
          orgDisplayName: String(body?.orgDisplayName ?? ""),
        });
        persist();
        return json(res, 201, out);
      }

      if (method === "GET" && url.pathname === "/v1/orgs") {
        requireUserId(req, store);
        const orgs = [...store.organizations.values()];
        return json(res, 200, { orgs });
      }

      if (method === "GET" && url.pathname === "/v1/users") {
        requireUserId(req, store);
        const users = [...store.users.values()];
        return json(res, 200, { users });
      }

      if (method === "GET" && url.pathname === "/admin") {
        requireUserId(req, store);
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
      input { width: 100%; padding: 8px; margin: 6px 0; }
      button { padding: 8px 12px; }
      table { width: 100%; border-collapse: collapse; }
      th, td { border-bottom: 1px solid #eee; padding: 6px; text-align: left; font-size: 12px; vertical-align: top; }
      .muted { color: #666; font-size: 12px; }
    </style>
  </head>
  <body>
    <h1>Logistics MVP Admin</h1>
    <p class="muted">Backed by <code>${esc(dataFilePath)}</code></p>

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

    <script>
      async function submitJson(e) {
        e.preventDefault();
        const form = e.target;
        const data = Object.fromEntries(new FormData(form).entries());
        // Numeric coercion for common fields.
        for (const k of ["capacityKg","weightKg","nowUtcMs"]) if (data[k] !== undefined && data[k] !== "") data[k] = Number(data[k]);
        const res = await fetch(form.action, {
          method: "POST",
          headers: { "content-type": "application/json" },
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
        const res = await fetch("/shipments/" + shipmentId + "/pod", { method: "POST", headers: { "content-type": "application/json" }, body: "{}" });
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
        const res = await fetch("/shipments/" + shipmentId + "/fail-refund", { method: "POST", headers: { "content-type": "application/json" }, body: "{}" });
        const out = await res.json().catch(() => ({}));
        alert(JSON.stringify(out, null, 2));
        location.reload();
        return false;
      }
    </script>
  </body>
</html>`
        );
      }

      if (method === "POST" && url.pathname === "/carriers") {
        const body = await readJson(req);
        const carrier = createCarrier(store, String(body?.name ?? ""));
        persist();
        return json(res, 201, { carrier });
      }

      if (method === "GET" && url.pathname === "/carriers") {
        const carriers = [...store.carriers.values()];
        return json(res, 200, { carriers });
      }

      if (method === "POST" && url.pathname === "/anchor-trips") {
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
        persist();
        return json(res, 201, { trip });
      }

      if (method === "GET" && url.pathname === "/anchor-trips") {
        const trips = [...store.anchorTrips.values()];
        return json(res, 200, { trips });
      }

      if (method === "POST" && url.pathname === "/shipments/quote") {
        const body = await readJson(req);
        const quote = quoteShipment({ weightKg: Number(body?.weightKg ?? 0) });
        return json(res, 200, { quote });
      }

      if (method === "GET" && url.pathname === "/shipments") {
        requireUserId(req, store);
        const shipments = [...store.shipments.values()];
        return json(res, 200, { shipments });
      }

      if (method === "GET" && url.pathname.startsWith("/shipments/") && url.pathname.split("/").length === 3) {
        requireUserId(req, store);
        const shipmentId = url.pathname.split("/")[2] ?? "";
        const shipment = store.shipments.get(shipmentId);
        if (!shipment) return json(res, 404, { error: "shipment_not_found" });
        const payment = store.payments.get(shipment.paymentId) ?? null;
        return json(res, 200, { shipment, payment });
      }

      if (method === "POST" && url.pathname === "/shipments/book") {
        const body = await readJson(req);
        const shipment = bookShipment(store, {
          anchorTripId: String(body?.anchorTripId ?? ""),
          customerOrgName: String(body?.customerOrgName ?? ""),
          weightKg: Number(body?.weightKg ?? 0),
          pickupAddress: String(body?.pickupAddress ?? ""),
          dropAddress: String(body?.dropAddress ?? ""),
        });
        persist();
        return json(res, 201, { shipment });
      }

      if (method === "POST" && url.pathname.startsWith("/shipments/") && url.pathname.endsWith("/pod")) {
        requireUserId(req, store);
        const shipmentId = url.pathname.split("/")[2] ?? "";
        const body = await readJson(req);
        const out = markPodDelivered(store, { shipmentId, podAtUtcMs: body?.podAtUtcMs });
        persist();
        return json(res, 200, out);
      }

      if (method === "POST" && url.pathname.startsWith("/shipments/") && url.pathname.endsWith("/fail-refund")) {
        requireUserId(req, store);
        const shipmentId = url.pathname.split("/")[2] ?? "";
        const shipment = failCarrierAndRefund(store, { shipmentId });
        persist();
        return json(res, 200, { shipment });
      }

      if (method === "GET" && url.pathname.startsWith("/carriers/") && url.pathname.endsWith("/ledger")) {
        requireUserId(req, store);
        const carrierId = url.pathname.split("/")[2] ?? "";
        const lines = [...store.ledgerLines.values()].filter((l) => l.carrierId === carrierId);
        return json(res, 200, { lines });
      }

      if (method === "POST" && url.pathname === "/payout-batches/run") {
        requireUserId(req, store);
        const body = await readJson(req);
        const batch = runPayoutBatch(store, { nowUtcMs: body?.nowUtcMs });
        persist();
        return json(res, 200, { batch });
      }

      if (method === "GET" && url.pathname === "/payout-batches") {
        requireUserId(req, store);
        const payoutBatches = [...store.payoutBatches.values()];
        return json(res, 200, { payoutBatches });
      }

      return json(res, 404, { error: "not_found" });
    } catch (e: any) {
      return json(res, 400, { error: e?.message ?? "bad_request" });
    }
  });

  return { server, store, persist, dataFilePath };
}

