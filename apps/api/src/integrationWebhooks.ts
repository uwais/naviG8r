import type {
  IntegrationEvent,
  IntegrationEventType,
  IntegrationWebhookDelivery,
  Shipment,
} from "./types.ts";
import type { Store } from "./store.ts";
import { signWebhookPayload } from "./integrationAuth.ts";

const EVENT_VERSION = "2026-06-01";
const WEBHOOK_RETRY_MS = [60_000, 5 * 60_000, 30 * 60_000, 2 * 60 * 60_000, 24 * 60 * 60_000];
const MAX_WEBHOOK_ATTEMPTS = 10;
const LOCATION_EVENT_THROTTLE_MS = 5 * 60_000;

function nowUtcMs(): number {
  return Date.now();
}

function id(prefix: string): string {
  return `${prefix}_${Math.random().toString(16).slice(2)}_${Date.now().toString(16)}`;
}

function carrierDisplayName(store: Store, carrierId: string): string {
  const org = store.organizations.get(carrierId);
  if (org) return org.displayName;
  const legacy = store.carriers.get(carrierId);
  return legacy?.name ?? carrierId;
}

function userDisplayName(store: Store, userId: string | undefined): string | null {
  if (!userId) return null;
  return store.users.get(userId)?.fullName ?? null;
}

/** Best-effort vehicle reg for ERP writeback: driver's primary vehicle, else first on carrier org. */
function carrierVehicleRegistration(
  store: Store,
  carrierOrgId: string,
  driverUserId: string | undefined,
): string | null {
  if (driverUserId) {
    const profile = store.driverProfiles.get(driverUserId);
    if (profile?.primaryVehicleId) {
      const v = store.vehicles.get(profile.primaryVehicleId);
      if (v?.registrationNumber) return v.registrationNumber;
    }
  }
  for (const v of store.vehicles.values()) {
    if (v.orgId === carrierOrgId && v.registrationNumber.trim()) {
      return v.registrationNumber;
    }
  }
  return null;
}

function carrierOpsSnapshot(
  store: Store,
  shipment: Shipment,
  trip: { startedByUserId?: string; startedAtUtcMs?: number } | undefined,
): Record<string, unknown> {
  const driverUserId = trip?.startedByUserId ?? shipment.acceptedByUserId;
  return {
    name: carrierDisplayName(store, shipment.carrierId),
    vehicleNumber: carrierVehicleRegistration(store, shipment.carrierId, driverUserId),
    driverName: userDisplayName(store, driverUserId),
  };
}

export function customerWebBaseUrl(): string {
  return (process.env.CUSTOMER_WEB_BASE_URL ?? "https://navig8r-customer-web.onrender.com").replace(/\/$/, "");
}

export function shipmentTrackingUrl(shipmentId: string): string {
  return `${customerWebBaseUrl()}/#/customer/shipments/${shipmentId}`;
}

function trackingSnapshot(store: Store, shipment: Shipment): Record<string, unknown> {
  const trip = store.anchorTrips.get(shipment.anchorTripId);
  const payment = store.payments.get(shipment.paymentId);
  const staleMs = 15 * 60 * 1000;
  const loc = trip?.lastLiveLocation;
  const fresh = loc != null && nowUtcMs() - loc.recordedAtUtcMs <= staleMs;
  const isLive = fresh && shipment.status === "BOOKED" && trip?.status === "IN_PROGRESS";
  return {
    url: shipmentTrackingUrl(shipment.id),
    isLive,
    lastLocation: loc ?? null,
    staleAfterUtcMs: staleMs,
    paymentStatus: payment?.status ?? null,
  };
}

function nextShipmentSequence(store: Store, shipment: Shipment): number {
  const seq = (shipment.integrationSequence ?? 0) + 1;
  shipment.integrationSequence = seq;
  shipment.updatedAtUtcMs = nowUtcMs();
  store.shipments.set(shipment.id, shipment);
  return seq;
}

export function buildIntegrationEventPayload(
  store: Store,
  params: {
    eventType: IntegrationEventType;
    shipment: Shipment;
    sequence: number;
  },
): Record<string, unknown> {
  const shipment = params.shipment;
  const trip = store.anchorTrips.get(shipment.anchorTripId);
  const payment = store.payments.get(shipment.paymentId);

  return {
    eventVersion: EVENT_VERSION,
    eventType: params.eventType,
    sequence: params.sequence,
    orgId: shipment.customerOrgId ?? null,
    externalLoadId: shipment.externalLoadId ?? null,
    occurredAtUtcMs: nowUtcMs(),
    shipment: {
      id: shipment.id,
      status: shipment.status,
      weightKg: shipment.weightKg,
      pickupAddress: shipment.pickupAddress,
      dropAddress: shipment.dropAddress,
      grossPaise: shipment.grossPaise,
      carrierId: shipment.carrierId,
      carrierDisplayName: carrierDisplayName(store, shipment.carrierId),
      externalLoadId: shipment.externalLoadId ?? null,
      metadata: shipment.metadata ?? {},
    },
    trip: trip
      ? {
          id: trip.id,
          status: trip.status,
          originCity: trip.originCity,
          destCity: trip.destCity,
          startedAtUtcMs: trip.startedAtUtcMs ?? null,
          completedAtUtcMs: trip.completedAtUtcMs ?? null,
        }
      : null,
    carrier: carrierOpsSnapshot(store, shipment, trip ?? undefined),
    tracking: trackingSnapshot(store, shipment),
    pod: {
      podAtUtcMs: shipment.podAtUtcMs,
      notes: shipment.podNotes ?? null,
    },
    payment: payment
      ? {
          status: payment.status,
          amountPaise: payment.amountPaise,
          provider: payment.provider,
        }
      : null,
    metadata: shipment.metadata ?? {},
  };
}

function queueWebhookDelivery(store: Store, event: IntegrationEvent, connectionId: string): void {
  const conn = store.integrationConnections.get(connectionId);
  if (!conn || conn.status !== "ACTIVE" || !conn.webhookUrl?.trim()) return;

  const payloadJson = JSON.stringify({
    eventId: event.id,
    ...event.payload,
  });
  const now = nowUtcMs();
  const delivery: IntegrationWebhookDelivery = {
    id: id("whd"),
    eventId: event.id,
    orgId: event.orgId,
    connectionId: conn.id,
    webhookUrl: conn.webhookUrl.trim(),
    payloadJson,
    status: "PENDING",
    attempts: 0,
    nextRetryAtUtcMs: now,
    lastHttpStatus: null,
    lastError: null,
    deliveredAtUtcMs: null,
    createdAtUtcMs: now,
    updatedAtUtcMs: now,
  };
  store.integrationWebhookDeliveries.set(delivery.id, delivery);
}

export function emitIntegrationEvent(
  store: Store,
  params: {
    eventType: IntegrationEventType;
    shipmentId: string;
    skipLocationThrottle?: boolean;
  },
): IntegrationEvent | null {
  const shipment = store.shipments.get(params.shipmentId);
  if (!shipment?.customerOrgId) return null;

  if (params.eventType === "load.location_updated" && !params.skipLocationThrottle) {
    const last = [...store.integrationEvents.values()]
      .filter((e) => e.shipmentId === shipment.id && e.eventType === "load.location_updated")
      .sort((a, b) => b.occurredAtUtcMs - a.occurredAtUtcMs)[0];
    if (last && nowUtcMs() - last.occurredAtUtcMs < LOCATION_EVENT_THROTTLE_MS) return null;
  }

  const sequence = nextShipmentSequence(store, shipment);
  const payload = buildIntegrationEventPayload(store, {
    eventType: params.eventType,
    shipment,
    sequence,
  });

  const now = nowUtcMs();
  const event: IntegrationEvent = {
    id: id("evt"),
    orgId: shipment.customerOrgId,
    shipmentId: shipment.id,
    externalLoadId: shipment.externalLoadId,
    eventType: params.eventType,
    sequence,
    payload,
    occurredAtUtcMs: now,
    createdAtUtcMs: now,
  };
  store.integrationEvents.set(event.id, event);

  if (shipment.integrationConnectionId) {
    queueWebhookDelivery(store, event, shipment.integrationConnectionId);
  } else {
    for (const conn of store.integrationConnections.values()) {
      if (conn.orgId === shipment.customerOrgId && conn.status === "ACTIVE") {
        queueWebhookDelivery(store, event, conn.id);
        break;
      }
    }
  }

  return event;
}

export async function deliverIntegrationWebhook(
  delivery: IntegrationWebhookDelivery,
  webhookSecret: string | undefined,
): Promise<{ ok: boolean; httpStatus: number; error?: string }> {
  const headers: Record<string, string> = {
    "content-type": "application/json",
    "user-agent": "NaviG8r-Integration/1.0",
  };
  if (webhookSecret) {
    headers["x-navig8r-signature"] = signWebhookPayload(webhookSecret, delivery.payloadJson);
  }

  try {
    const res = await fetch(delivery.webhookUrl, {
      method: "POST",
      headers,
      body: delivery.payloadJson,
      signal: AbortSignal.timeout(30_000),
    });
    if (res.ok) {
      return { ok: true, httpStatus: res.status };
    }
    const text = await res.text().catch(() => "");
    return { ok: false, httpStatus: res.status, error: text.slice(0, 500) || res.statusText };
  } catch (e: any) {
    return { ok: false, httpStatus: 0, error: String(e?.message ?? e) };
  }
}

export async function processPendingWebhookDeliveries(store: Store): Promise<number> {
  const now = nowUtcMs();
  let processed = 0;

  for (const d of store.integrationWebhookDeliveries.values()) {
    if (d.status !== "PENDING") continue;
    if (d.nextRetryAtUtcMs > now) continue;

    const conn = store.integrationConnections.get(d.connectionId);
    const result = await deliverIntegrationWebhook(d, conn?.webhookSecret);
    processed += 1;

    d.attempts += 1;
    d.updatedAtUtcMs = now;
    d.lastHttpStatus = result.httpStatus;

    if (result.ok) {
      d.status = "DELIVERED";
      d.deliveredAtUtcMs = now;
      d.lastError = null;
    } else {
      d.lastError = result.error ?? "delivery_failed";
      if (d.attempts >= MAX_WEBHOOK_ATTEMPTS) {
        d.status = "DEAD";
      } else {
        const backoff = WEBHOOK_RETRY_MS[Math.min(d.attempts - 1, WEBHOOK_RETRY_MS.length - 1)]!;
        d.nextRetryAtUtcMs = now + backoff;
      }
    }
    store.integrationWebhookDeliveries.set(d.id, d);
  }

  return processed;
}

export function retryWebhookDelivery(store: Store, deliveryId: string): IntegrationWebhookDelivery {
  const d = store.integrationWebhookDeliveries.get(deliveryId);
  if (!d) throw new Error("webhook_delivery_not_found");
  d.status = "PENDING";
  d.nextRetryAtUtcMs = nowUtcMs();
  d.updatedAtUtcMs = nowUtcMs();
  store.integrationWebhookDeliveries.set(d.id, d);
  return d;
}
