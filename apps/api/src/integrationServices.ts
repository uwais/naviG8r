import crypto from "node:crypto";
import {
  bookShipment,
  customerEligibleAnchorTripsPhaseA,
  shipmentWithCarrierDisplay,
  tripWithCarrierDisplay,
  attachRazorpayOrderForShipment,
} from "./services.ts";
import type {
  GeoPoint,
  IntegrationApiKey,
  IntegrationApiScope,
  IntegrationConnection,
  IntegrationEvent,
  IntegrationWebhookDelivery,
  Shipment,
} from "./types.ts";
import type { Store } from "./store.ts";
import type { IntegrationAuthContext } from "./integrationAuth.ts";
import {
  generateApiKeyMaterial,
  hashIntegrationSecret,
} from "./integrationAuth.ts";
import {
  buildIntegrationEventPayload,
  customerWebBaseUrl,
  deliverIntegrationWebhook,
  emitIntegrationEvent,
  retryWebhookDelivery,
  shipmentTrackingUrl,
} from "./integrationWebhooks.ts";
import { razorpayPaymentsEnabled } from "./razorpayPayments.ts";

function nowUtcMs(): number {
  return Date.now();
}

function id(prefix: string): string {
  return `${prefix}_${Math.random().toString(16).slice(2)}_${Date.now().toString(16)}`;
}

function idempotencyStoreKey(orgId: string, key: string): string {
  return `${orgId}:${key}`;
}

export function assertCustomerOrg(store: Store, orgId: string): void {
  const org = store.organizations.get(orgId);
  if (!org || org.kind !== "CUSTOMER") throw new Error("integration_org_invalid");
}

export function assertCustomerOrgAdmin(store: Store, orgId: string, userId: string): void {
  assertCustomerOrg(store, orgId);
  const m = store.memberships.get(`${userId}:${orgId}`);
  if (!m || m.role !== "CUSTOMER_ADMIN") throw new Error("forbidden");
}

export function getOrCreateIntegrationConnection(
  store: Store,
  orgId: string,
  params?: { displayName?: string; externalSource?: string },
): IntegrationConnection {
  assertCustomerOrg(store, orgId);
  const existing = [...store.integrationConnections.values()].find(
    (c) => c.orgId === orgId && c.status === "ACTIVE",
  );
  if (existing) return existing;

  const now = nowUtcMs();
  const conn: IntegrationConnection = {
    id: id("intconn"),
    orgId,
    displayName: params?.displayName ?? "ERP integration",
    status: "ACTIVE",
    paymentPolicy: "portal_checkout",
    externalSource: params?.externalSource ?? "generic",
    webhookSecret: crypto.randomBytes(24).toString("hex"),
    createdAtUtcMs: now,
    updatedAtUtcMs: now,
  };
  store.integrationConnections.set(conn.id, conn);
  return conn;
}

export function updateIntegrationConnection(
  store: Store,
  orgId: string,
  params: {
    webhookUrl?: string;
    paymentPolicy?: IntegrationConnection["paymentPolicy"];
    displayName?: string;
    regenerateWebhookSecret?: boolean;
  },
): IntegrationConnection {
  const conn = getOrCreateIntegrationConnection(store, orgId);
  const now = nowUtcMs();
  if (params.webhookUrl != null) {
    const url = params.webhookUrl.trim();
    if (url && process.env.NODE_ENV === "production" && !url.startsWith("https://")) {
      throw new Error("webhook_url_must_be_https");
    }
    conn.webhookUrl = url || undefined;
  }
  if (params.paymentPolicy != null) conn.paymentPolicy = params.paymentPolicy;
  if (params.displayName != null) conn.displayName = params.displayName.trim() || conn.displayName;
  if (params.regenerateWebhookSecret) conn.webhookSecret = crypto.randomBytes(24).toString("hex");
  conn.updatedAtUtcMs = now;
  store.integrationConnections.set(conn.id, conn);
  return conn;
}

export function createIntegrationApiKey(
  store: Store,
  orgId: string,
  scopes: IntegrationApiScope[] = ["loads:read", "loads:write"],
): { key: IntegrationApiKey; token: string; connection: IntegrationConnection } {
  const conn = getOrCreateIntegrationConnection(store, orgId);
  const { keyId, secret, token } = generateApiKeyMaterial();
  const now = nowUtcMs();
  const key: IntegrationApiKey = {
    id: id("intkey"),
    keyId,
    secretHash: hashIntegrationSecret(secret),
    orgId,
    connectionId: conn.id,
    scopes,
    status: "ACTIVE",
    expiresAtUtcMs: null,
    lastUsedAtUtcMs: null,
    createdAtUtcMs: now,
  };
  store.integrationApiKeys.set(key.id, key);
  return { key, token, connection: conn };
}

export function revokeIntegrationApiKey(store: Store, orgId: string, keyRecordId: string): void {
  const key = store.integrationApiKeys.get(keyRecordId);
  if (!key || key.orgId !== orgId) throw new Error("integration_key_not_found");
  key.status = "REVOKED";
  store.integrationApiKeys.set(key.id, key);
}

export function listIntegrationApiKeys(store: Store, orgId: string): IntegrationApiKey[] {
  return [...store.integrationApiKeys.values()].filter((k) => k.orgId === orgId && k.status === "ACTIVE");
}

function findShipmentByExternalLoadId(store: Store, orgId: string, externalLoadId: string): Shipment | null {
  const ext = externalLoadId.trim();
  if (!ext) return null;
  return (
    [...store.shipments.values()].find(
      (s) => s.customerOrgId === orgId && s.externalLoadId === ext,
    ) ?? null
  );
}

function findShipmentByIdempotencyKey(store: Store, orgId: string, idempotencyKey: string): Shipment | null {
  const rec = store.integrationIdempotency.get(idempotencyStoreKey(orgId, idempotencyKey));
  if (!rec) return null;
  return store.shipments.get(rec.shipmentId) ?? null;
}

function recordIdempotency(store: Store, orgId: string, idempotencyKey: string, shipmentId: string): void {
  store.integrationIdempotency.set(idempotencyStoreKey(orgId, idempotencyKey), {
    key: idempotencyStoreKey(orgId, idempotencyKey),
    orgId,
    shipmentId,
    createdAtUtcMs: nowUtcMs(),
  });
}

function applyErpPreauthorizedPayment(store: Store, shipment: Shipment): void {
  const pay = store.payments.get(shipment.paymentId);
  if (!pay) return;
  if (razorpayPaymentsEnabled()) {
    pay.status = "AUTHORIZED";
    pay.updatedAtUtcMs = nowUtcMs();
  } else {
    pay.status = "CAPTURED";
    pay.updatedAtUtcMs = nowUtcMs();
  }
  store.payments.set(pay.id, pay);
}

export function integrationLoadResponse(store: Store, shipment: Shipment, connection: IntegrationConnection) {
  const enriched = shipmentWithCarrierDisplay(store, shipment);
  const payment = store.payments.get(shipment.paymentId);
  const checkoutRequired =
    connection.paymentPolicy === "portal_checkout" &&
    payment?.status === "CREATED" &&
    razorpayPaymentsEnabled();

  return {
    shipmentId: shipment.id,
    externalLoadId: shipment.externalLoadId ?? null,
    status: shipment.status,
    carrierDisplayName: (enriched as Shipment & { carrierDisplayName?: string }).carrierDisplayName ?? null,
    grossPaise: shipment.grossPaise,
    trackingUrl: shipmentTrackingUrl(shipment.id),
    checkoutRequired,
    payment: payment
      ? {
          status: payment.status,
          amountPaise: payment.amountPaise,
          razorpayOrderId: payment.razorpayOrderId ?? null,
        }
      : null,
    metadata: shipment.metadata ?? {},
  };
}

export async function createIntegrationLoad(
  store: Store,
  ctx: IntegrationAuthContext,
  params: {
    externalLoadId: string;
    weightKg: number;
    pickupAddress: string;
    dropAddress: string;
    pickup: GeoPoint;
    drop: GeoPoint;
    lanePreference?: "auto_match" | "explicit";
    anchorTripId?: string;
    metadata?: Record<string, string>;
    idempotencyKey?: string;
  },
): Promise<{ shipment: Shipment; response: ReturnType<typeof integrationLoadResponse>; created: boolean }> {
  const org = store.organizations.get(ctx.orgId)!;
  const conn = store.integrationConnections.get(ctx.connectionId)!;

  const externalLoadId = params.externalLoadId.trim();
  if (!externalLoadId) throw new Error("external_load_id_required");

  if (params.idempotencyKey?.trim()) {
    const existing = findShipmentByIdempotencyKey(store, ctx.orgId, params.idempotencyKey.trim());
    if (existing) {
      return { shipment: existing, response: integrationLoadResponse(store, existing, conn), created: false };
    }
  }

  const dup = findShipmentByExternalLoadId(store, ctx.orgId, externalLoadId);
  if (dup) {
    return { shipment: dup, response: integrationLoadResponse(store, dup, conn), created: false };
  }

  let anchorTripId = params.anchorTripId?.trim();
  if (params.lanePreference !== "explicit" || !anchorTripId) {
    const ranked = customerEligibleAnchorTripsPhaseA(store, {
      pickup: params.pickup,
      drop: params.drop,
      weightKg: params.weightKg,
    });
    const eligible = ranked.filter((r) => r.eligibility.eligible);
    if (!eligible.length) {
      throw new Error("no_eligible_lane");
    }
    anchorTripId = eligible[0]!.trip.id;
  }

  const shipment = bookShipment(store, {
    anchorTripId: anchorTripId!,
    customerOrgName: org.displayName,
    customerOrg: { id: org.id, displayName: org.displayName },
    weightKg: params.weightKg,
    pickupAddress: params.pickupAddress,
    dropAddress: params.dropAddress,
    pickup: params.pickup,
    drop: params.drop,
    externalLoadId,
    externalSource: conn.externalSource,
    integrationConnectionId: conn.id,
    metadata: params.metadata,
  });

  if (conn.paymentPolicy === "portal_checkout" && razorpayPaymentsEnabled()) {
    await attachRazorpayOrderForShipment(store, shipment.id);
  }

  if (conn.paymentPolicy === "erp_preauthorized") {
    applyErpPreauthorizedPayment(store, shipment);
    emitIntegrationEvent(store, { eventType: "load.payment_authorized", shipmentId: shipment.id });
  }

  if (params.idempotencyKey?.trim()) {
    recordIdempotency(store, ctx.orgId, params.idempotencyKey.trim(), shipment.id);
  }

  return {
    shipment,
    response: integrationLoadResponse(store, shipment, conn),
    created: true,
  };
}

export function listIntegrationLoads(
  store: Store,
  orgId: string,
  params: { externalLoadId?: string; updatedSince?: number; limit?: number },
): Shipment[] {
  let rows = [...store.shipments.values()].filter((s) => s.customerOrgId === orgId);
  if (params.externalLoadId?.trim()) {
    rows = rows.filter((s) => s.externalLoadId === params.externalLoadId!.trim());
  }
  if (params.updatedSince != null) {
    rows = rows.filter((s) => s.updatedAtUtcMs >= params.updatedSince!);
  }
  rows.sort((a, b) => b.updatedAtUtcMs - a.updatedAtUtcMs);
  const limit = Math.min(params.limit ?? 50, 200);
  return rows.slice(0, limit);
}

export function getIntegrationShipmentTracking(store: Store, orgId: string, shipmentId: string) {
  const shipment = store.shipments.get(shipmentId);
  if (!shipment || shipment.customerOrgId !== orgId) throw new Error("shipment_not_found");
  const trip = store.anchorTrips.get(shipment.anchorTripId);
  if (!trip) throw new Error("anchor_trip_not_found");
  const now = nowUtcMs();
  const loc = trip.lastLiveLocation ?? null;
  const staleMs = 15 * 60 * 1000;
  const fresh = loc != null && now - loc.recordedAtUtcMs <= staleMs;
  const isLive = fresh && shipment.status === "BOOKED" && trip.status === "IN_PROGRESS";
  return {
    shipment: shipmentWithCarrierDisplay(store, shipment),
    trip: tripWithCarrierDisplay(store, trip),
    liveLocation: loc,
    isLive,
    staleAfterUtcMs: staleMs,
    trackingUrl: shipmentTrackingUrl(shipmentId),
  };
}

export function getIntegrationShipmentSnapshot(store: Store, orgId: string, shipmentId: string) {
  const shipment = store.shipments.get(shipmentId);
  if (!shipment || shipment.customerOrgId !== orgId) throw new Error("shipment_not_found");
  const conn =
    (shipment.integrationConnectionId
      ? store.integrationConnections.get(shipment.integrationConnectionId)
      : null) ?? getOrCreateIntegrationConnection(store, orgId);
  const enriched = shipmentWithCarrierDisplay(store, shipment);
  const payment = store.payments.get(shipment.paymentId);
  const trip = store.anchorTrips.get(shipment.anchorTripId);
  return {
    ...integrationLoadResponse(store, shipment, conn),
    shipment: enriched,
    payment,
    trip: trip ?? null,
  };
}

export function listIntegrationEvents(
  store: Store,
  orgId: string,
  params: { sinceEventId?: string; shipmentId?: string; limit?: number },
): IntegrationEvent[] {
  let events = [...store.integrationEvents.values()].filter((e) => e.orgId === orgId);
  if (params.shipmentId) events = events.filter((e) => e.shipmentId === params.shipmentId);
  events.sort((a, b) => a.createdAtUtcMs - b.createdAtUtcMs);
  if (params.sinceEventId) {
    const idx = events.findIndex((e) => e.id === params.sinceEventId);
    events = idx >= 0 ? events.slice(idx + 1) : events;
  }
  const limit = Math.min(params.limit ?? 100, 500);
  return events.slice(-limit);
}

export function listWebhookDeliveries(
  store: Store,
  orgId: string,
  params: { limit?: number },
): IntegrationWebhookDelivery[] {
  const rows = [...store.integrationWebhookDeliveries.values()]
    .filter((d) => d.orgId === orgId)
    .sort((a, b) => b.createdAtUtcMs - a.createdAtUtcMs);
  return rows.slice(0, Math.min(params.limit ?? 50, 200));
}

export async function testIntegrationWebhook(store: Store, orgId: string): Promise<{ ok: boolean; httpStatus: number }> {
  const conn = getOrCreateIntegrationConnection(store, orgId);
  if (!conn.webhookUrl?.trim()) throw new Error("webhook_url_not_configured");

  const payloadJson = JSON.stringify({
    eventId: "evt_test_ping",
    eventVersion: "2026-06-01",
    eventType: "integration.test",
    orgId,
    message: "NaviG8r webhook test ping",
    occurredAtUtcMs: nowUtcMs(),
  });

  const delivery: IntegrationWebhookDelivery = {
    id: id("whd_test"),
    eventId: "evt_test_ping",
    orgId,
    connectionId: conn.id,
    webhookUrl: conn.webhookUrl.trim(),
    payloadJson,
    status: "PENDING",
    attempts: 0,
    nextRetryAtUtcMs: nowUtcMs(),
    lastHttpStatus: null,
    lastError: null,
    deliveredAtUtcMs: null,
    createdAtUtcMs: nowUtcMs(),
    updatedAtUtcMs: nowUtcMs(),
  };

  const result = await deliverIntegrationWebhook(delivery, conn.webhookSecret);
  return { ok: result.ok, httpStatus: result.httpStatus };
}

export function integrationPortalSummary(store: Store, orgId: string, userId: string) {
  assertCustomerOrgAdmin(store, orgId, userId);
  const conn = getOrCreateIntegrationConnection(store, orgId);
  const keys = listIntegrationApiKeys(store, orgId).map((k) => ({
    id: k.id,
    keyId: k.keyId,
    scopes: k.scopes,
    lastUsedAtUtcMs: k.lastUsedAtUtcMs,
    createdAtUtcMs: k.createdAtUtcMs,
  }));
  const recentDeliveries = listWebhookDeliveries(store, orgId, { limit: 10 });
  return {
    connection: {
      id: conn.id,
      displayName: conn.displayName,
      webhookUrl: conn.webhookUrl ?? "",
      paymentPolicy: conn.paymentPolicy,
      externalSource: conn.externalSource,
      hasWebhookSecret: Boolean(conn.webhookSecret),
    },
    apiKeys: keys,
    recentDeliveries,
    docsUrl: `${customerWebBaseUrl()}/#/customer/integrations`,
  };
}

export { retryWebhookDelivery, buildIntegrationEventPayload };
