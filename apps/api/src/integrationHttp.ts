import type http from "node:http";
import type { Store } from "./store.ts";
import {
  assertIntegrationScope,
  resolveIntegrationAuth,
} from "./integrationAuth.ts";
import {
  assertCustomerOrgAdmin,
  createIntegrationApiKey,
  createIntegrationLoad,
  getIntegrationShipmentSnapshot,
  getIntegrationShipmentTracking,
  listIntegrationEvents,
  listIntegrationLoads,
  listWebhookDeliveries,
  retryWebhookDelivery,
  testIntegrationWebhook,
  updateIntegrationConnection,
  integrationPortalSummary,
  revokeIntegrationApiKey,
} from "./integrationServices.ts";
import { publicRazorpayKeyId } from "./razorpayPayments.ts";

function json(res: http.ServerResponse, status: number, body: unknown): void {
  const data = JSON.stringify(body);
  res.statusCode = status;
  res.setHeader("content-type", "application/json; charset=utf-8");
  res.setHeader("content-length", Buffer.byteLength(data));
  res.end(data);
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

function integrationErrorStatus(msg: string): number {
  if (msg === "integration_unauthorized") return 401;
  if (msg === "integration_forbidden" || msg === "integration_connection_inactive" || msg === "integration_org_invalid") {
    return 403;
  }
  if (msg === "shipment_not_found" || msg === "webhook_delivery_not_found" || msg === "integration_key_not_found") {
    return 404;
  }
  if (msg === "no_eligible_lane") return 422;
  return 400;
}

async function readJson(req: http.IncomingMessage): Promise<any> {
  const chunks: Buffer[] = [];
  for await (const c of req) chunks.push(Buffer.isBuffer(c) ? c : Buffer.from(c));
  if (chunks.length === 0) return null;
  return JSON.parse(Buffer.concat(chunks).toString("utf8"));
}

export async function handleIntegrationRoutes(
  req: http.IncomingMessage,
  res: http.ServerResponse,
  store: Store,
  url: URL,
  method: string,
): Promise<boolean> {
  if (!url.pathname.startsWith("/v1/integrations/")) return false;

  try {
    const ctx = resolveIntegrationAuth(store, {
      bearerToken: bearerToken(req),
      apiKey: header(req, "x-api-key"),
      apiSecret: header(req, "x-api-secret"),
    });

    if (method === "POST" && url.pathname === "/v1/integrations/loads") {
      assertIntegrationScope(ctx, "loads:write");
      const body = await readJson(req);
      const idempotencyKey = header(req, "idempotency-key") ?? body?.idempotencyKey;
      const out = await createIntegrationLoad(store, ctx, {
        externalLoadId: String(body?.externalLoadId ?? ""),
        weightKg: Number(body?.weightKg ?? 0),
        pickupAddress: String(body?.pickupAddress ?? ""),
        dropAddress: String(body?.dropAddress ?? ""),
        pickup: body?.pickup,
        drop: body?.drop,
        lanePreference: body?.lanePreference === "explicit" ? "explicit" : "auto_match",
        anchorTripId: body?.anchorTripId?.toString(),
        metadata: body?.metadata,
        idempotencyKey: idempotencyKey ?? undefined,
      });
      const payload: Record<string, unknown> = {
        ...out.response,
        created: out.created,
      };
      const keyId = publicRazorpayKeyId();
      if (keyId && out.response.checkoutRequired) payload.razorpayKeyId = keyId;
      json(res, out.created ? 201 : 200, payload);
      return true;
    }

    if (method === "GET" && url.pathname === "/v1/integrations/loads") {
      assertIntegrationScope(ctx, "loads:read");
      const externalLoadId = url.searchParams.get("externalLoadId") ?? undefined;
      const updatedSinceRaw = url.searchParams.get("updatedSince");
      const updatedSince = updatedSinceRaw != null ? Number(updatedSinceRaw) : undefined;
      const loads = listIntegrationLoads(store, ctx.orgId, {
        externalLoadId,
        updatedSince: Number.isFinite(updatedSince) ? updatedSince : undefined,
        limit: Number(url.searchParams.get("limit") ?? 50),
      });
      json(res, 200, {
        loads: loads.map((s) => getIntegrationShipmentSnapshot(store, ctx.orgId, s.id)),
      });
      return true;
    }

    const shipmentMatch = /^\/v1\/integrations\/shipments\/([^/]+)$/.exec(url.pathname);
    if (method === "GET" && shipmentMatch) {
      assertIntegrationScope(ctx, "loads:read");
      const snap = getIntegrationShipmentSnapshot(store, ctx.orgId, shipmentMatch[1]!);
      json(res, 200, snap);
      return true;
    }

    const trackingMatch = /^\/v1\/integrations\/shipments\/([^/]+)\/tracking$/.exec(url.pathname);
    if (method === "GET" && trackingMatch) {
      assertIntegrationScope(ctx, "loads:read");
      const shipmentId = trackingMatch[1]!;
      const shipment = store.shipments.get(shipmentId);
      if (!shipment || shipment.customerOrgId !== ctx.orgId) {
        json(res, 404, { error: "shipment_not_found" });
        return true;
      }
      const snap = getIntegrationShipmentTracking(store, ctx.orgId, shipmentId);
      json(res, 200, snap);
      return true;
    }

    if (method === "GET" && url.pathname === "/v1/integrations/events") {
      assertIntegrationScope(ctx, "loads:read");
      const events = listIntegrationEvents(store, ctx.orgId, {
        sinceEventId: url.searchParams.get("sinceEventId") ?? undefined,
        shipmentId: url.searchParams.get("shipmentId") ?? undefined,
        limit: Number(url.searchParams.get("limit") ?? 100),
      });
      json(res, 200, { events });
      return true;
    }

    json(res, 404, { error: "not_found" });
    return true;
  } catch (e: any) {
    const msg = String(e?.message ?? "bad_request");
    json(res, integrationErrorStatus(msg), { error: msg });
    return true;
  }
}

export async function handleIntegrationPortalRoutes(
  req: http.IncomingMessage,
  res: http.ServerResponse,
  store: Store,
  url: URL,
  method: string,
  userId: string,
): Promise<boolean> {
  const base = "/v1/pilot/customer/integrations";
  if (!url.pathname.startsWith(base)) return false;

  try {
    const orgId = url.searchParams.get("orgId") ?? "";
    const org = store.organizations.get(orgId);
    if (!org || org.kind !== "CUSTOMER") {
      json(res, 400, { error: "invalid_org" });
      return true;
    }

    try {
      assertCustomerOrgAdmin(store, orgId, userId);
    } catch (e: any) {
      if (String(e?.message) === "forbidden") {
        json(res, 403, { error: "forbidden" });
        return true;
      }
      throw e;
    }

    if (method === "GET" && url.pathname === base) {
      const summary = integrationPortalSummary(store, orgId, userId);
      json(res, 200, summary);
      return true;
    }

    if (method === "POST" && url.pathname === `${base}/keys`) {
      const body = await readJson(req);
      const { key, token, connection } = createIntegrationApiKey(store, orgId, body?.scopes);
      json(res, 201, {
        key: { id: key.id, keyId: key.keyId, scopes: key.scopes, createdAtUtcMs: key.createdAtUtcMs },
        token,
        connectionId: connection.id,
      });
      return true;
    }

    if (method === "POST" && url.pathname === `${base}/keys/revoke`) {
      const body = await readJson(req);
      revokeIntegrationApiKey(store, orgId, String(body?.keyId ?? ""));
      json(res, 200, { ok: true });
      return true;
    }

    if (method === "PATCH" && url.pathname === `${base}/connection`) {
      const body = await readJson(req);
      const conn = updateIntegrationConnection(store, orgId, {
        webhookUrl: body?.webhookUrl,
        paymentPolicy: body?.paymentPolicy,
        displayName: body?.displayName,
        regenerateWebhookSecret: Boolean(body?.regenerateWebhookSecret),
      });
      json(res, 200, {
        connection: {
          id: conn.id,
          displayName: conn.displayName,
          webhookUrl: conn.webhookUrl ?? "",
          paymentPolicy: conn.paymentPolicy,
          webhookSecret: conn.webhookSecret,
        },
      });
      return true;
    }

    if (method === "POST" && url.pathname === `${base}/webhooks/test`) {
      const result = await testIntegrationWebhook(store, orgId);
      json(res, result.ok ? 200 : 502, result);
      return true;
    }

    if (method === "GET" && url.pathname === `${base}/deliveries`) {
      const deliveries = listWebhookDeliveries(store, orgId, {
        limit: Number(url.searchParams.get("limit") ?? 50),
      });
      json(res, 200, { deliveries });
      return true;
    }

    const retryMatch = new RegExp(`^${base}/deliveries/([^/]+)/retry$`).exec(url.pathname);
    if (method === "POST" && retryMatch) {
      const d = retryWebhookDelivery(store, retryMatch[1]!);
      if (d.orgId !== orgId) {
        json(res, 404, { error: "webhook_delivery_not_found" });
        return true;
      }
      json(res, 200, { delivery: d });
      return true;
    }

    json(res, 404, { error: "not_found" });
    return true;
  } catch (e: any) {
    const msg = String(e?.message ?? "bad_request");
    if (msg === "forbidden") {
      json(res, 403, { error: msg });
      return true;
    }
    json(res, 400, { error: msg });
    return true;
  }
}
