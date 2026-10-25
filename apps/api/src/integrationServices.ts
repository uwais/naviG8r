import { AuthorizationError, principalFor, recordAudit, requirePermission } from "./rbac.ts";
import { withoutEwayBill } from "./ewayBillVisibility.ts";
import { withoutPodPhotos } from "./podPhotos.ts";
import { withoutTripAssignment } from "./tripAssignmentRules.ts";
import { withoutCarrierTransporterId } from "./carrierTransporterId.ts";
import { isActiveEntity } from "./softDelete.ts";
import crypto from "node:crypto";
import {
  bookShipment,
  customerEligibleAnchorTripsPhaseA,
  shipmentWithCarrierDisplay,
  tripWithCarrierDisplay,
  attachRazorpayOrderForShipment,
  isOpsAdmin,
  isOpsAgent,
} from "./services.ts";
import type {
  GeoPoint,
  IntegrationApiKey,
  IntegrationApiScope,
  IntegrationConnection,
  IntegrationEvent,
  IntegrationPaymentPolicy,
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
  if (!org || !isActiveEntity(org) || org.kind !== "CUSTOMER") throw new Error("integration_org_invalid");
}

export function assertCustomerOrgAdmin(store: Store, orgId: string, userId: string): void {
  assertCustomerOrg(store, orgId);
  requirePermission(store, "integration.manage", { orgId }, userId);
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

const PAYMENT_POLICIES: readonly IntegrationPaymentPolicy[] = ["portal_checkout", "erp_preauthorized"];

export function updateIntegrationConnection(
  store: Store,
  orgId: string,
  params: {
    webhookUrl?: string;
    paymentPolicy?: IntegrationConnection["paymentPolicy"];
    displayName?: string;
    regenerateWebhookSecret?: boolean;
    /** Who asks; only NaviG8r platform OPS or ADMIN may change paymentPolicy. */
    changedByUserId?: string;
  },
): IntegrationConnection {
  const conn = getOrCreateIntegrationConnection(store, orgId);
  if (params.paymentPolicy != null) {
    if (!PAYMENT_POLICIES.includes(params.paymentPolicy)) throw new Error("invalid_payment_policy");
    const staff = params.changedByUserId != null && (isOpsAgent(store, params.changedByUserId) || isOpsAdmin(store, params.changedByUserId));
    if (params.paymentPolicy !== conn.paymentPolicy && !staff) throw new Error("forbidden");
  }
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

/** POST /v1/ops/organizations/:orgId/erp-payment-policy: platform OPS or ADMIN set it, with an audit row per change. */
export function setErpPaymentPolicyAsStaff(store: Store, orgId: string, paymentPolicy: unknown): IntegrationConnection {
  const userId = principalFor(store).userId;
  if (!isOpsAgent(store, userId) && !isOpsAdmin(store, userId)) throw new AuthorizationError("forbidden");
  const org = store.organizations.get(orgId);
  if (!org || !isActiveEntity(org) || org.kind !== "CUSTOMER") throw new AuthorizationError("not_found", 404);
  if (!PAYMENT_POLICIES.includes(paymentPolicy as IntegrationPaymentPolicy)) throw new Error("invalid_payment_policy");
  const previous = getOrCreateIntegrationConnection(store, orgId).paymentPolicy;
  const conn = updateIntegrationConnection(store, orgId, { paymentPolicy: paymentPolicy as IntegrationPaymentPolicy, changedByUserId: userId });
  if (conn.paymentPolicy !== previous) recordAudit(store, "ERP_PAYMENT_POLICY_CHANGED", "organization", orgId, previous, conn.paymentPolicy);
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

/** This and the lookup by idempotency key skip a booking the unpaid expiry closed, so a retry books again. */
function findShipmentByExternalLoadId(store: Store, orgId: string, externalLoadId: string): Shipment | null {
  const ext = externalLoadId.trim();
  if (!ext) return null;
  return (
    [...store.shipments.values()].find(
      (s) => s.customerOrgId === orgId && s.externalLoadId === ext && s.expiredUnpaidAtUtcMs == null,
    ) ?? null
  );
}

function findShipmentByIdempotencyKey(store: Store, orgId: string, idempotencyKey: string): Shipment | null {
  const rec = store.integrationIdempotency.get(idempotencyStoreKey(orgId, idempotencyKey));
  if (!rec) return null;
  const shipment = store.shipments.get(rec.shipmentId);
  return shipment && shipment.expiredUnpaidAtUtcMs == null ? shipment : null;
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
  // A booking closed when its trip left unpaid keeps its CREATED payment, and takes no checkout.
  const checkoutRequired =
    connection.paymentPolicy === "portal_checkout" &&
    shipment.status === "PENDING_CARRIER_ACCEPT" &&
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

/** A shipper's ERP never gets the carrier's amount, NaviG8r's cut or when the carrier is paid (owner hard rule, 21 Oct 2026). */
function withoutCarrierPay<T extends Shipment>(shipment: T): Omit<T, "netToCarrierPaise" | "commissionPaise" | "firstPayoutEligibleAtUtcMs" | "payoutBatchCutoffUtcMs"> {
  const { netToCarrierPaise: _net, commissionPaise: _commission, firstPayoutEligibleAtUtcMs: _eligible, payoutBatchCutoffUtcMs: _cutoff, ...rest } = shipment;
  return rest;
}

/**
 * A carrier's cancel request, its note above all, is between the carrier and NaviG8r; an ERP caller reads the status only.
 * The truck's position goes out only as the tracking route's liveLocation, and the driver's user ids not at all.
 */
function tripForErp<T extends { cancelRequest?: unknown; lastLiveLocation?: unknown; startedByUserId?: string; completedByUserId?: string }>(trip: T) {
  const { cancelRequest: _request, lastLiveLocation: _location, startedByUserId: _startedBy, completedByUserId: _completedBy, ...rest } = withoutTripAssignment(trip);
  return rest;
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
  // The same rule as the app: a shipper sees the truck only while its own goods are on it.
  const shipperMaySeeTruck = shipment.status === "BOOKED" && trip.status === "IN_PROGRESS";
  const isLive = fresh && shipperMaySeeTruck;
  return {
    shipment: withoutPodPhotos(withoutCarrierPay(withoutCarrierTransporterId(withoutTripAssignment(withoutEwayBill(shipmentWithCarrierDisplay(store, shipment)))))),
    trip: tripForErp(tripWithCarrierDisplay(store, trip)),
    liveLocation: shipperMaySeeTruck ? loc : null,
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
    shipment: withoutPodPhotos(withoutCarrierPay(withoutCarrierTransporterId(withoutTripAssignment(withoutEwayBill(enriched))))),
    payment,
    trip: trip ? tripForErp(trip) : null,
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
