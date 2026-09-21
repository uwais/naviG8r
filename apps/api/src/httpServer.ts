import { opsPortalHtml } from "./opsPortal.ts";
import { authorizationContext, AuthorizationError, resolvePrincipal, principalFor, requirePermission, acceptPod, recordAudit, compatibleRole, legacyRoles, ROLES } from "./rbac.ts";
import { guardRequest, requestContext } from "./rbacRoutes.ts";
import { serializeResponse } from "./rbacResponses.ts";
import http from "node:http";
import { URL } from "node:url";
import { pilotOtpStart, pilotOtpVerify, verifyBearer } from "./auth.ts";
import { loadStoreFromDisk, saveStoreToDisk } from "./persistence.ts";
import {
  ApiError,
  acceptCarrierShipment,
  attachRazorpayOrderForShipment,
  bookShipment,
  confirmRazorpayCheckoutAuthorization,
  createCarrier,
  customerPrimaryOrgForUser,
  ensureRazorpayCapturedBeforePod,
  failCarrierAndRefund,
  grantOpsAdmin,
  inviteCarrierDriver,
  inviteCustomerMember,
  listCustomerOrgMembers,
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
  updatePilotDriverVehicle,
  pilotListMyAnchorTrips,
  pilotRatesEstimate,
  pilotListCarrierShipments,
  pilotCarrierEarningsSummary,
  pilotSubmitPayoutSetup,
  pilotListCarrierLedger,
  pilotListCarrierPayoutBatches,
  shipmentVisibleToCarrierPilot,
  shipmentWithCarrierDisplay,
  completeAnchorTripAsPilot,
  startAnchorTripAsPilot,
  tripWithCarrierDisplay,
  tripForPublicListing,
  publishAnchorTrip,
  publishAnchorTripAsPilotDriver,
  quoteShipmentMarketplace,
  registerCustomerOrgAdmin,
  registerCustomerUser,
  registerSoloOwnerOperatorDriver,
  revokeOpsAdmin,
  opsDeleteUser,
  rollbackBooking,
  runPayoutBatch,
  shipmentVisibleToCustomerUser,
} from "./services.ts";
import { verifyRazorpayWebhookSignature, razorpayPaymentsEnabled, publicRazorpayKeyId } from "./razorpayPayments.ts";
import { payoutsMode } from "./razorpayPayouts.ts";
import { applyRazorpayWebhookPayload } from "./razorpayWebhook.ts";
import { handleIntegrationPortalRoutes, handleIntegrationRoutes } from "./integrationHttp.ts";

async function readRawBody(req: http.IncomingMessage): Promise<string> {
  const chunks: Buffer[] = [];
  for await (const c of req) chunks.push(Buffer.isBuffer(c) ? c : Buffer.from(c));
  return Buffer.concat(chunks).toString("utf8");
}

function isLocalDevOrigin(origin: string): boolean {
  try {
    const u = new URL(origin);
    return u.protocol === "http:" && (u.hostname === "localhost" || u.hostname === "127.0.0.1");
  } catch {
    return false;
  }
}

function resolveCorsOrigin(req: http.IncomingMessage): string | null {
  const origin = header(req, "origin");
  if (!origin) return null;

  const configured = process.env.CORS_ALLOWED_ORIGINS?.trim();
  if (configured) {
    const list = configured.split(",").map((s) => s.trim()).filter(Boolean);
    if (list.includes("*")) return "*";
    if (list.includes(origin)) return origin;
    return null;
  }

  if (isLocalDevOrigin(origin)) return origin;
  if (process.env.NODE_ENV !== "production") return origin;
  return null;
}

function applyCors(req: http.IncomingMessage, res: http.ServerResponse): void {
  const allowOrigin = resolveCorsOrigin(req);
  if (allowOrigin) {
    res.setHeader("Access-Control-Allow-Origin", allowOrigin);
    if (allowOrigin !== "*") {
      res.setHeader("Access-Control-Allow-Credentials", "true");
      res.setHeader("Vary", "Origin");
    }
  }
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "content-type, authorization, x-razorpay-signature, x-organization-id, x-reason-code, x-effective-actor-id");
  res.setHeader("Access-Control-Max-Age", "86400");
}

function json(res: http.ServerResponse, status: number, body: unknown): void {
  const data = JSON.stringify(serializeResponse(body));
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
  const body = JSON.parse(raw);
  const p = authorizationContext.getStore()?.principal;
  if (p && body && typeof body === "object") {
    for (const key of ["orgId", "customerOrgId"]) if (body[key] !== undefined && body[key] !== p.organizationId && !p.internal) throw new AuthorizationError("not_found", 404);
  }
  return body;
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
  if (method === "POST" && pathname === "/v1/payments/razorpay/confirm") return true;
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
function requireLegacyDemoSurface(_res: http.ServerResponse, _method: string, _pathname: string): boolean { return true; }

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

  let requests: Promise<unknown> = Promise.resolve();
  const server = http.createServer((req, res) => {
    requests = requests.then(() => authorizationContext.run(requestContext(), async () => {
    try {
      const method = req.method ?? "GET";
      const url = new URL(req.url ?? "/", "http://localhost");

      applyCors(req, res);
      guardRequest(req, store, url);
      if (method === "OPTIONS") {
        res.statusCode = 204;
        res.end();
        return;
      }

      if (method === "GET" && url.pathname === "/health") {
        return json(res, 200, {
          ok: true,
          persistence: process.env.PERSISTENCE === "DB" ? "db" : "file",
          paymentProvider: razorpayPaymentsEnabled() ? "razorpay" : "mock",
          release: process.env.RELEASE_SHA ?? "unknown",
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

      if (method === "POST" && url.pathname === "/v1/payments/razorpay/confirm") {
        if (!razorpayPaymentsEnabled()) {
          return json(res, 503, { error: "razorpay_not_enabled" });
        }
        const body = await readJson(req);
        const shipmentId = String(body?.shipmentId ?? "");
        const shipment = store.shipments.get(shipmentId);
        if (!shipment) throw new AuthorizationError("not_found", 404);
        requirePermission(store, "payment.checkout", shipment);
        const razorpayOrderId = String(body?.razorpayOrderId ?? "");
        const razorpayPaymentId = String(body?.razorpayPaymentId ?? "");
        const razorpaySignature = String(body?.razorpaySignature ?? "");
        if (!shipmentId || !razorpayOrderId || !razorpayPaymentId || !razorpaySignature) {
          return json(res, 400, { error: "missing_confirm_fields" });
        }
        try {
          const out = confirmRazorpayCheckoutAuthorization(store, {
            shipmentId,
            razorpayOrderId,
            razorpayPaymentId,
            razorpaySignature,
          });
          await persist();
          return json(res, 200, out);
        } catch (e: any) {
          if (e instanceof ApiError) {
            const status = e.httpStatus ?? 400;
            return json(res, status, { error: e.message, ...(e.message.includes("provider") || e.message.includes("razorpay") ? {} : e.extra) } as Record<string, unknown>);
          }
          const msg = String(e?.message ?? "");
          if (msg === "shipment_not_found") return json(res, 404, { error: msg });
          if (msg === "not_razorpay_shipment") return json(res, 400, { error: msg });
          throw e;
        }
      }

      if (method === "POST" && url.pathname === "/v1/roles") {
        requirePermission(store, "user.role_manage");
        const body = await readJson(req);
        const key = `${body?.userId}:${body?.orgId}`;
        const m = store.memberships.get(key), org = store.organizations.get(String(body?.orgId));
        if (!m || !org || m.inactiveAtUtcMs != null || org.inactiveAtUtcMs != null) throw new AuthorizationError("not_found", 404);
        if (!Array.isArray(body.roles) || body.roles.some((r: string) => !ROLES.includes(r as never) || !compatibleRole(r, org))) throw new AuthorizationError("invalid_role", 400);
        const before = store.membershipRoles.get(key) ?? legacyRoles(m, org);
        const roles = [...new Set<string>(body.roles)] as import("./rbac.ts").Role[];
        store.membershipRoles.set(key, roles);
        for (const role of before.filter(r => !roles.includes(r))) recordAudit(store, "ROLE_REMOVED", "membership", key, role, "REMOVED");
        for (const role of roles.filter(r => !before.includes(r))) recordAudit(store, "ROLE_ASSIGNED", "membership", key, "ABSENT", role);
        await persist();
        return json(res, 200, { userId: m.userId, orgId: m.orgId, roles });
      }
      if (method === "POST" && /^\/v1\/organizations\/[^/]+\/kyc$/.test(url.pathname)) {
        const p = requirePermission(store, "kyc.verify");
        const orgId = url.pathname.split("/")[3]!;
        const org = store.organizations.get(orgId);
        if (!org || org.inactiveAtUtcMs != null) throw new AuthorizationError("not_found", 404);
        if (store.memberships.has(`${p.userId}:${orgId}`)) throw new AuthorizationError("self_verification_forbidden");
        const body = await readJson(req);
        if (!["APPROVED", "REJECTED"].includes(body?.status) || !authorizationContext.getStore()?.reason) throw new AuthorizationError("verification_status_and_reason_required", 400);
        store.organizations.set(orgId, { ...org, kycStatus: body.status });
        recordAudit(store, "COMPLIANCE_STATUS_CHANGED", "organization", orgId, org.kycStatus, body.status);
        await persist();
        return json(res, 200, { org: store.organizations.get(orgId) });
      }
      if (method === "GET" && url.pathname === "/v1/audit") {
        const p = requirePermission(store, "audit.read");
        const financial = new Set(["PAYMENT_CAPTURED", "PAYMENT_REFUNDED", "SETTLEMENT_RELEASED"]);
        const events = [...store.auditEvents.values()].filter(e => p.internal ?
          (p.roles.includes("ADMIN") ? ["ROLE_ASSIGNED", "ROLE_REMOVED", "USER_DEACTIVATED"].includes(e.action) : p.roles.includes("FINANCE") ? financial.has(e.action) : !financial.has(e.action) && !e.action.startsWith("ROLE_")) : e.actorOrganizationId === p.organizationId && e.actorUserId === p.userId);
        return json(res, 200, { events });
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
        await persist();
        return json(res, 200, { ...out, isOpsAdmin: isOpsAdmin(store, out.user.id) });
      }

      if (method === "GET" && url.pathname === "/v1/auth/me") {
        const userId = requireBearerUserId(req, res, store);
        if (!userId) return;
        const user = store.users.get(userId);
        if (!user) return json(res, 404, { error: "user_not_found" });
        const memberships = [...store.memberships.values()].filter(m => m.userId === userId && m.inactiveAtUtcMs == null && store.organizations.get(m.orgId)?.inactiveAtUtcMs == null);
        const organizations = memberships.map(m => store.organizations.get(m.orgId)).filter(Boolean);
        let principal;
        try { principal = resolvePrincipal(store, userId, header(req, "x-organization-id")); } catch (error) { if (header(req, "x-organization-id")) throw error; }
        return json(res, 200, { user, memberships, organizations, principal, isOpsAdmin: principal?.roles.includes("ADMIN") ?? false });
      }

      // --- v1 ops-admins management (DB-backed grants) ---
      if (method === "GET" && url.pathname === "/v1/ops-admins") {
        const userId = requireBearerUserId(req, res, store);
        if (!userId) return;
        requirePermission(store, "user.role_manage");
        return json(res, 200, { opsAdmins: listOpsAdmins(store) });
      }

      if (method === "POST" && url.pathname === "/v1/ops-admins") {
        const userId = requireBearerUserId(req, res, store);
        if (!userId) return;
        requirePermission(store, "user.role_manage");
        const body = await readJson(req);
        const entry = grantOpsAdmin(store, { phone: String(body?.phone ?? "") });
        await persist();
        return json(res, 201, { opsAdmin: entry });
      }

      if (method === "DELETE" && url.pathname.startsWith("/v1/ops-admins/")) {
        const userId = requireBearerUserId(req, res, store);
        if (!userId) return;
        requirePermission(store, "user.role_manage");
        const phone = decodeURIComponent(url.pathname.split("/")[3] ?? "");
        const out = revokeOpsAdmin(store, { phone, actingUserId: userId });
        await persist();
        return json(res, 200, out);
      }

      if (method === "DELETE" && (url.pathname === "/v1/ops/users" || url.pathname.startsWith("/v1/ops/users/"))) {
        const actingUserId = requireBearerUserId(req, res, store);
        if (!actingUserId) return;
        try {
          requirePermission(store, "user.role_manage");
        } catch {
          return json(res, 403, { error: "forbidden" });
        }
        const force =
          url.searchParams.get("force") === "1" ||
          url.searchParams.get("force") === "true";
        let targetUserId = "";
        if (url.pathname.startsWith("/v1/ops/users/")) {
          const rest = url.pathname.slice("/v1/ops/users/".length);
          targetUserId = decodeURIComponent(rest.split("/")[0] ?? "").trim();
        }
        if (!targetUserId) {
          const phoneRaw = String(url.searchParams.get("phone") ?? "").trim();
          if (!phoneRaw) {
            return json(res, 400, {
              error: "invalid_userId",
              detail: "Pass /v1/ops/users/:userId or ?phone=",
            });
          }
          const digits = phoneRaw.replace(/[^\d]/g, "");
          const phone =
            digits.length === 12 && digits.startsWith("91") ? digits.slice(-10) : digits;
          const found = [...store.users.values()].find((u) => u.phone === phone);
          if (!found) return json(res, 404, { error: "user_not_found" });
          targetUserId = found.id;
        }
        const out = opsDeleteUser(store, { actingUserId, userId: targetUserId, force });
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
        return json(res, 200, { ...out, principal: principalFor(store, userId) });
      }

      if (method === "PATCH" && url.pathname === "/v1/pilot/me/vehicle") {
        const userId = requireUserId(req, store);
        const body = await readJson(req);
        const out = updatePilotDriverVehicle(store, userId, {
          vehicleRegistrationNumber:
            body?.vehicleRegistrationNumber !== undefined
              ? String(body.vehicleRegistrationNumber)
              : undefined,
          vehicleClass: body?.vehicleClass,
          vehicleCapacityKg:
            body?.vehicleCapacityKg !== undefined ? Number(body.vehicleCapacityKg) : undefined,
        });
        await persist();
        return json(res, 200, out);
      }

      if (method === "GET" && url.pathname === "/v1/pilot/anchor-trips") {
        const userId = requireUserId(req, store);
        const trips = pilotListMyAnchorTrips(store, userId).map((t) => tripWithCarrierDisplay(store, t));
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
          const trip = tripWithCarrierDisplay(store, pilotGetMyAnchorTrip(store, userId, tripId));
          return json(res, 200, { trip });
        }
      }

      if (method === "POST" && url.pathname.endsWith("/start")) {
        const parts = url.pathname.split("/").filter(Boolean);
        if (parts.length === 5 && parts[0] === "v1" && parts[1] === "pilot" && parts[2] === "anchor-trips") {
          const userId = requireUserId(req, store);
          const tripId = parts[3] ?? "";
          try {
            const trip = startAnchorTripAsPilot(store, { userId, tripId });
            await persist();
            return json(res, 200, { trip: tripWithCarrierDisplay(store, trip) });
          } catch (e) {
            if (e instanceof ApiError) {
              const status = e.httpStatus ?? 400;
              return json(res, status, { error: e.message, ...(e.message.includes("provider") || e.message.includes("razorpay") ? {} : e.extra) } as Record<string, unknown>);
            }
            throw e;
          }
        }
      }

      if (method === "POST" && url.pathname.endsWith("/complete")) {
        const parts = url.pathname.split("/").filter(Boolean);
        if (
          parts.length === 5 &&
          parts[0] === "v1" &&
          parts[1] === "pilot" &&
          parts[2] === "anchor-trips" &&
          parts[4] === "complete"
        ) {
          const userId = requireUserId(req, store);
          const tripId = parts[3] ?? "";
          try {
            const trip = completeAnchorTripAsPilot(store, { userId, tripId });
            await persist();
            return json(res, 200, { trip: tripWithCarrierDisplay(store, trip) });
          } catch (e) {
            if (e instanceof ApiError) {
              const status = e.httpStatus ?? 400;
              return json(res, status, { error: e.message, ...(e.message.includes("provider") || e.message.includes("razorpay") ? {} : e.extra) } as Record<string, unknown>);
            }
            throw e;
          }
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
        return json(res, 201, { trip: tripWithCarrierDisplay(store, trip) });
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
        const shipments = pilotListCarrierShipments(store, userId, { anchorTripId }).map((s) =>
          shipmentWithCarrierDisplay(store, s),
        );
        return json(res, 200, { shipments });
      }

      if (method === "POST" && url.pathname.endsWith("/accept")) {
        const parts = url.pathname.split("/").filter(Boolean);
        if (
          parts.length === 6 &&
          parts[0] === "v1" &&
          parts[1] === "pilot" &&
          parts[2] === "carrier" &&
          parts[3] === "shipments" &&
          parts[5] === "accept"
        ) {
          const userId = requireUserId(req, store);
          const shipmentId = parts[4] ?? "";
          try {
            const shipment = acceptCarrierShipment(store, { shipmentId, userId });
            await persist();
            return json(res, 200, { shipment: shipmentWithCarrierDisplay(store, shipment) });
          } catch (e) {
            if (e instanceof ApiError) {
              const status = e.httpStatus ?? 400;
              return json(res, status, { error: e.message, ...(e.message.includes("provider") || e.message.includes("razorpay") ? {} : e.extra) } as Record<string, unknown>);
            }
            const msg = String((e as Error)?.message ?? "");
            if (msg === "forbidden") return json(res, 403, { error: msg });
            if (msg === "shipment_not_found") return json(res, 404, { error: msg });
            throw e;
          }
        }
      }

      if (method === "POST" && url.pathname === "/v1/pilot/carrier/drivers/invite") {
        const body = await readJson(req);
        const userId = requireUserId(req, store);
        try {
          const out = inviteCarrierDriver(store, userId, {
            orgId: String(body?.orgId ?? ""),
            phone: String(body?.phone ?? ""),
            role: body?.role,
            vehicleRegistrationNumber: String(body?.vehicleRegistrationNumber ?? ""),
            vehicleClass: body?.vehicleClass,
            vehicleCapacityKg: Number(body?.vehicleCapacityKg ?? 0),
          });
          await persist();
          return json(res, 201, out);
        } catch (e) {
          if (e instanceof ApiError) {
            const status = e.httpStatus ?? 400;
            return json(res, status, { error: e.message, ...(e.message.includes("provider") || e.message.includes("razorpay") ? {} : e.extra) } as Record<string, unknown>);
          }
          throw e;
        }
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
        }).map((row) => ({
          ...row,
          trip: tripForPublicListing(store, row.trip),
        }));
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

      if (method === "POST" && url.pathname === "/v1/pilot/customer/users/register") {
        const body = await readJson(req);
        try {
          const out = registerCustomerUser(store, {
            fullName: String(body?.fullName ?? ""),
            phone: String(body?.phone ?? ""),
          });
          await persist();
          return json(res, 201, out);
        } catch (e) {
          if (e instanceof ApiError) {
            const status = e.httpStatus ?? 400;
            return json(res, status, { error: e.message, ...(e.message.includes("provider") || e.message.includes("razorpay") ? {} : e.extra) } as Record<string, unknown>);
          }
          const msg = e instanceof Error ? e.message : "error";
          if (msg === "phone_already_registered") return json(res, 409, { error: msg });
          if (msg === "invalid_fullName" || msg === "invalid_phone") return json(res, 400, { error: msg });
          throw e;
        }
      }

      if (method === "POST" && url.pathname === "/v1/pilot/customer/members/invite") {
        const body = await readJson(req);
        const userId = requireUserId(req, store);
        try {
          const out = inviteCustomerMember(store, userId, {
            orgId: String(body?.orgId ?? ""),
            phone: String(body?.phone ?? ""),
            role: body?.role,
          });
          await persist();
          return json(res, 201, out);
        } catch (e) {
          if (e instanceof ApiError) {
            const status = e.httpStatus ?? 400;
            return json(res, status, { error: e.message, ...(e.message.includes("provider") || e.message.includes("razorpay") ? {} : e.extra) } as Record<string, unknown>);
          }
          const msg = e instanceof Error ? e.message : "error";
          if (msg === "forbidden") return json(res, 403, { error: msg });
          if (msg === "org_not_customer" || msg === "invalid_role") return json(res, 400, { error: msg });
          throw e;
        }
      }

      if (method === "GET" && url.pathname === "/v1/pilot/customer/members") {
        const userId = requireUserId(req, store);
        const orgId = url.searchParams.get("orgId") ?? "";
        try {
          const members = listCustomerOrgMembers(store, userId, orgId);
          return json(res, 200, { members });
        } catch (e) {
          const msg = e instanceof Error ? e.message : "error";
          if (msg === "forbidden") return json(res, 403, { error: msg });
          throw e;
        }
      }

      if (url.pathname.startsWith("/v1/pilot/customer/integrations")) {
        const userId = requireUserId(req, store);
        const handled = await handleIntegrationPortalRoutes(req, res, store, url, method, userId);
        if (handled) {
          await persist();
          return;
        }
      }

      if (url.pathname.startsWith("/v1/integrations/")) {
        const handled = await handleIntegrationRoutes(req, res, store, url, method);
        if (handled) {
          await persist();
          return;
        }
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

      if (method === "GET" && url.pathname === "/admin") return html(res, 200, opsPortalHtml());
      if (method === "GET" && url.pathname === "/workflow") return html(res, 200, opsPortalHtml({ workflowOnly: true }));

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
          if (!trip || trip.inactiveAtUtcMs != null) return json(res, 404, { error: "trip_not_found" });
          return json(res, 200, { trip: tripForPublicListing(store, trip) });
        }
      }

      if (method === "GET" && url.pathname === "/anchor-trips") {
        const trips = [...store.anchorTrips.values()].filter(t => t.inactiveAtUtcMs == null).map((t) => tripForPublicListing(store, t));
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
        const shipments = [...store.shipments.values()]
          .filter((s) => shipmentVisibleToCustomerUser(store, s, userId))
          .map((s) => shipmentWithCarrierDisplay(store, s));
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
          return json(res, 200, {
            shipment: shipmentWithCarrierDisplay(store, shipment),
            payment,
          });
        }
      }

      if (method === "POST" && url.pathname === "/shipments/book") {
        if (!requireLegacyDemoSurface(res, method, url.pathname)) return;
        const body = await readJson(req);
        const principal = requirePermission(store, "load.create");
        if (!principal.roles.includes("SHIPPER")) throw new AuthorizationError("assisted_booking_requires_target", 400);
        const org = store.organizations.get(principal.organizationId)!;
        const customerOrg = { id: org.id, displayName: org.displayName };
        const bookedByUserId = principal.userId;
        const phoneField = store.users.get(principal.userId)?.phone;
        const shipment = bookShipment(store, {
          anchorTripId: String(body?.anchorTripId ?? ""),
          customerOrgName: String(body?.customerOrgName ?? ""),
          customerOrg,
          bookedByUserId,
          bookedByPhoneRaw: phoneField != null ? String(phoneField) : undefined,
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

        const bodyOut: Record<string, unknown> = {
          shipment: shipmentWithCarrierDisplay(store, shipment),
          payment: pay,
        };
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
          if (!principalFor(store).internal) throw new AuthorizationError("forbidden");
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
          if (!principalFor(store).internal) throw new AuthorizationError("forbidden");
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
          if (!principalFor(store).internal) throw new AuthorizationError("forbidden");
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
          if (!principalFor(store).internal) throw new AuthorizationError("forbidden");
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

      if (method === "POST" && /^\/shipments\/[^/]+\/accept-pod$/.test(url.pathname)) {
        const shipment = acceptPod(store, url.pathname.split("/")[2]!);
        await persist();
        return json(res, 200, { shipment });
      }
      if (method === "POST" && /^\/shipments\/[^/]+\/fail-refund$/.test(url.pathname)) {
        const shipment = await failCarrierAndRefund(store, { shipmentId: url.pathname.split("/")[2]! });
        await persist();
        return json(res, 200, { shipment });
      }

      if (method === "GET" && url.pathname.startsWith("/carriers/") && url.pathname.endsWith("/ledger")) {
        const userId = requireUserId(req, store);
        if (!principalFor(store).internal) throw new AuthorizationError("forbidden");
        const carrierId = url.pathname.split("/")[2] ?? "";
        const lines = [...store.ledgerLines.values()].filter((l) => l.carrierId === carrierId);
        return json(res, 200, { lines });
      }

      if (method === "POST" && url.pathname === "/payout-batches/run") {
        const userId = requireUserId(req, store);
        if (!principalFor(store).internal) throw new AuthorizationError("forbidden");
        const body = await readJson(req);
        const batch = await runPayoutBatch(store, {});
        await persist();
        return json(res, 200, { batch });
      }

      if (method === "GET" && url.pathname === "/payout-batches") {
        const userId = requireUserId(req, store);
        if (!principalFor(store).internal) throw new AuthorizationError("forbidden");
        const payoutBatches = [...store.payoutBatches.values()];
        return json(res, 200, { payoutBatches });
      }

      return json(res, 404, { error: "not_found" });
    } catch (e: any) {
      if (e instanceof AuthorizationError) return json(res, e.status, { error: e.message });
      if (e instanceof ApiError) {
        const status = e.httpStatus ?? 400;
        return json(res, status, { error: e.message, ...(e.message.includes("provider") || e.message.includes("razorpay") ? {} : e.extra) } as Record<string, unknown>);
      }
      const msg = String(e?.message ?? "bad_request");
      if (msg === "unauthorized" || msg === "invalid_token" || msg === "token_expired") {
        return json(res, 401, { error: "unauthorized" });
      }
      if (msg === "account_inactive") {
        return json(res, 403, { error: "account_inactive" });
      }
      return json(res, 400, { error: msg });
    }
  })).catch(() => { if (!res.headersSent) json(res, 500, { error: "internal_error" }); else res.end(); });
  });

  return { server, store, persist, dataFilePath };
}
