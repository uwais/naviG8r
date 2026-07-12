import { PrismaClient } from "@prisma/client";
import { createStore, type Store } from "./store.ts";
import type {
  AnchorTrip,
  TripLiveLocation,
  AuthSession,
  Carrier,
  DriverProfile,
  GeoPoint,
  IntegrationApiKey,
  IntegrationConnection,
  IntegrationEvent,
  IntegrationIdempotencyRecord,
  IntegrationWebhookDelivery,
  LedgerLine,
  Membership,
  Organization,
  OtpChallenge,
  Payment,
  PayoutBatch,
  Shipment,
  User,
  Vehicle,
} from "./types.ts";

const prisma = new PrismaClient();

function membershipKey(userId: string, orgId: string): string {
  return `${userId}:${orgId}`;
}

function asGeo(v: unknown): GeoPoint | undefined {
  if (!v || typeof v !== "object") return undefined;
  const o = v as Record<string, unknown>;
  const lat = o.lat;
  const lng = o.lng;
  if (typeof lat !== "number" || typeof lng !== "number") return undefined;
  const out: GeoPoint = { lat, lng };
  if (typeof o.placeId === "string") out.placeId = o.placeId;
  if (typeof o.label === "string") out.label = o.label;
  return out;
}

function asTripLiveLocation(v: unknown): TripLiveLocation | undefined {
  if (!v || typeof v !== "object") return undefined;
  const o = v as Record<string, unknown>;
  const lat = o.lat;
  const lng = o.lng;
  const recordedAtUtcMs = o.recordedAtUtcMs;
  if (typeof lat !== "number" || typeof lng !== "number" || typeof recordedAtUtcMs !== "number") return undefined;
  const out: TripLiveLocation = { lat, lng, recordedAtUtcMs };
  if (typeof o.accuracyM === "number") out.accuracyM = o.accuracyM;
  if (typeof o.speedMps === "number") out.speedMps = o.speedMps;
  if (typeof o.headingDeg === "number") out.headingDeg = o.headingDeg;
  return out;
}

export async function loadStoreFromDatabase(): Promise<Store> {
  const store = createStore();

  const [
    carriers,
    organizations,
    users,
    memberships,
    vehicles,
    driverProfiles,
    otpChallenges,
    authSessions,
    anchorTrips,
    shipments,
    payments,
    ledgerLines,
    payoutBatches,
    integrationConnections,
    integrationApiKeys,
    integrationIdempotency,
    integrationEvents,
    integrationWebhookDeliveries,
  ] = await Promise.all([
    prisma.carrier.findMany(),
    prisma.organization.findMany(),
    prisma.userRow.findMany(),
    prisma.membership.findMany(),
    prisma.vehicle.findMany(),
    prisma.driverProfileRow.findMany(),
    prisma.otpChallengeRow.findMany(),
    prisma.authSessionRow.findMany(),
    prisma.anchorTripRow.findMany(),
    prisma.shipmentRow.findMany(),
    prisma.paymentRow.findMany(),
    prisma.ledgerLineRow.findMany(),
    prisma.payoutBatchRow.findMany(),
    prisma.integrationConnectionRow.findMany(),
    prisma.integrationApiKeyRow.findMany(),
    prisma.integrationIdempotencyRow.findMany(),
    prisma.integrationEventRow.findMany(),
    prisma.integrationWebhookDeliveryRow.findMany(),
  ]);

  for (const c of carriers) {
    const row: Carrier = {
      id: c.id,
      name: c.name,
      createdAtUtcMs: Number(c.createdAtUtcMs),
    };
    store.carriers.set(row.id, row);
  }

  for (const o of organizations) {
    const org: Organization = {
      id: o.id,
      kind: o.kind as Organization["kind"],
      displayName: o.displayName,
      kycStatus: o.kycStatus as Organization["kycStatus"],
      createdAtUtcMs: Number(o.createdAtUtcMs),
      payoutContactId: o.payoutContactId ?? undefined,
      payoutFundAccountId: o.payoutFundAccountId ?? undefined,
    };
    store.organizations.set(org.id, org);
  }

  for (const u of users) {
    const user: User = {
      id: u.id,
      phone: u.phone,
      fullName: u.fullName,
      createdAtUtcMs: Number(u.createdAtUtcMs),
    };
    store.users.set(user.id, user);
  }

  for (const m of memberships) {
    const mem: Membership = {
      userId: m.userId,
      orgId: m.orgId,
      role: m.role as Membership["role"],
      createdAtUtcMs: Number(m.createdAtUtcMs),
    };
    store.memberships.set(membershipKey(mem.userId, mem.orgId), mem);
  }

  for (const v of vehicles) {
    const veh: Vehicle = {
      id: v.id,
      orgId: v.orgId,
      registrationNumber: v.registrationNumber,
      vehicleClass: v.vehicleClass as Vehicle["vehicleClass"],
      capacityKg: v.capacityKg,
      createdAtUtcMs: Number(v.createdAtUtcMs),
    };
    store.vehicles.set(veh.id, veh);
  }

  for (const d of driverProfiles) {
    const dp: DriverProfile = {
      userId: d.userId,
      orgId: d.orgId,
      primaryVehicleId: d.primaryVehicleId,
      createdAtUtcMs: Number(d.createdAtUtcMs),
    };
    store.driverProfiles.set(dp.userId, dp);
  }

  for (const o of otpChallenges) {
    const ch: OtpChallenge = {
      id: o.id,
      phone: o.phone,
      code: o.code,
      status: o.status as OtpChallenge["status"],
      expiresAtUtcMs: Number(o.expiresAtUtcMs),
      createdAtUtcMs: Number(o.createdAtUtcMs),
    };
    store.otpChallenges.set(ch.id, ch);
  }

  for (const s of authSessions) {
    const sess: AuthSession = {
      id: s.id,
      userId: s.userId,
      createdAtUtcMs: Number(s.createdAtUtcMs),
      expiresAtUtcMs: Number(s.expiresAtUtcMs),
      revokedAtUtcMs: s.revokedAtUtcMs != null ? Number(s.revokedAtUtcMs) : null,
    };
    store.authSessions.set(sess.id, sess);
  }

  for (const t of anchorTrips) {
    const trip: AnchorTrip = {
      id: t.id,
      carrierId: t.carrierId,
      originCity: t.originCity,
      destCity: t.destCity,
      origin: asGeo(t.origin),
      destination: asGeo(t.destination),
      windowStart: t.windowStart,
      windowEnd: t.windowEnd,
      vehicleClass: t.vehicleClass as AnchorTrip["vehicleClass"],
      capacityKg: t.capacityKg,
      reservedKg: t.reservedKg,
      status: t.status as AnchorTrip["status"],
      createdAtUtcMs: Number(t.createdAtUtcMs),
      startedAtUtcMs: t.startedAtUtcMs != null ? Number(t.startedAtUtcMs) : undefined,
      startedByUserId: t.startedByUserId ?? undefined,
      completedAtUtcMs: t.completedAtUtcMs != null ? Number(t.completedAtUtcMs) : undefined,
      completedByUserId: t.completedByUserId ?? undefined,
      lastLiveLocation: asTripLiveLocation((t as { lastLiveLocation?: unknown }).lastLiveLocation),
    };
    store.anchorTrips.set(trip.id, trip);
  }

  for (const p of payments) {
    const pay: Payment = {
      id: p.id,
      shipmentId: p.shipmentId,
      amountPaise: p.amountPaise,
      status: p.status as Payment["status"],
      provider: p.provider as Payment["provider"],
      providerRef: p.providerRef,
      ...(p.razorpayOrderId != null ? { razorpayOrderId: p.razorpayOrderId } : {}),
      ...(p.razorpayPaymentId != null ? { razorpayPaymentId: p.razorpayPaymentId } : {}),
      createdAtUtcMs: Number(p.createdAtUtcMs),
      updatedAtUtcMs: Number(p.updatedAtUtcMs),
    };
    store.payments.set(pay.id, pay);
  }

  for (const row of shipments) {
    const s: Shipment = {
      id: row.id,
      anchorTripId: row.anchorTripId,
      carrierId: row.carrierId,
      ...(row.customerOrgId != null ? { customerOrgId: row.customerOrgId } : {}),
      customerOrgName: row.customerOrgName,
      ...(row.bookedByPhone != null ? { bookedByPhone: row.bookedByPhone } : {}),
      ...(row.bookedByUserId != null ? { bookedByUserId: row.bookedByUserId } : {}),
      weightKg: row.weightKg,
      pickupAddress: row.pickupAddress,
      dropAddress: row.dropAddress,
      pickup: asGeo(row.pickup),
      drop: asGeo(row.drop),
      status: row.status as Shipment["status"],
      acceptedAtUtcMs: row.acceptedAtUtcMs != null ? Number(row.acceptedAtUtcMs) : undefined,
      acceptedByUserId: row.acceptedByUserId ?? undefined,
      grossPaise: row.grossPaise,
      commissionPaise: row.commissionPaise,
      netToCarrierPaise: row.netToCarrierPaise,
      paymentId: row.paymentId,
      podAtUtcMs: row.podAtUtcMs != null ? Number(row.podAtUtcMs) : null,
      ...(row.podSubmittedByUserId != null ? { podSubmittedByUserId: row.podSubmittedByUserId } : {}),
      ...(row.podNotes != null ? { podNotes: row.podNotes } : {}),
      firstPayoutEligibleAtUtcMs: row.firstPayoutEligibleAtUtcMs != null
        ? Number(row.firstPayoutEligibleAtUtcMs)
        : null,
      payoutBatchCutoffUtcMs: row.payoutBatchCutoffUtcMs != null ? Number(row.payoutBatchCutoffUtcMs) : null,
      ...(row.externalLoadId != null ? { externalLoadId: row.externalLoadId } : {}),
      ...(row.externalSource != null ? { externalSource: row.externalSource } : {}),
      ...(row.integrationConnectionId != null ? { integrationConnectionId: row.integrationConnectionId } : {}),
      ...(row.metadata != null ? { metadata: row.metadata as Record<string, string> } : {}),
      integrationSequence: row.integrationSequence ?? undefined,
      createdAtUtcMs: Number(row.createdAtUtcMs),
      updatedAtUtcMs: Number(row.updatedAtUtcMs),
    };
    store.shipments.set(s.id, s);
  }

  for (const l of ledgerLines) {
    const line: LedgerLine = {
      id: l.id,
      shipmentId: l.shipmentId,
      carrierId: l.carrierId,
      grossPaise: l.grossPaise,
      commissionPaise: l.commissionPaise,
      netToCarrierPaise: l.netToCarrierPaise,
      podAtUtcMs: Number(l.podAtUtcMs),
      firstPayoutEligibleAtUtcMs: Number(l.firstPayoutEligibleAtUtcMs),
      payoutBatchCutoffUtcMs: Number(l.payoutBatchCutoffUtcMs),
      status: l.status as LedgerLine["status"],
      createdAtUtcMs: Number(l.createdAtUtcMs),
      paidAtUtcMs: l.paidAtUtcMs != null ? Number(l.paidAtUtcMs) : null,
    };
    store.ledgerLines.set(line.id, line);
  }

  for (const b of payoutBatches) {
    const raw = b.lineIds;
    const lineIds = Array.isArray(raw) ? raw.filter((x): x is string => typeof x === "string") : [];
    const transfersRaw = (b as { transfers?: unknown }).transfers;
    const transfers = Array.isArray(transfersRaw) ? (transfersRaw as PayoutBatch["transfers"]) : [];
    const batch: PayoutBatch = {
      id: b.id,
      cutoffUtcMs: Number(b.cutoffUtcMs),
      createdAtUtcMs: Number(b.createdAtUtcMs),
      totalNetToCarrierPaise: b.totalNetToCarrierPaise,
      lineIds,
      provider: (b as { provider?: string }).provider === "RAZORPAYX" ? "RAZORPAYX" : "BOOKKEEPING",
      transfers,
    };
    store.payoutBatches.set(batch.id, batch);
  }

  for (const c of integrationConnections) {
    const conn: IntegrationConnection = {
      id: c.id,
      orgId: c.orgId,
      displayName: c.displayName,
      status: c.status as IntegrationConnection["status"],
      ...(c.webhookUrl != null ? { webhookUrl: c.webhookUrl } : {}),
      ...(c.webhookSecret != null ? { webhookSecret: c.webhookSecret } : {}),
      paymentPolicy: c.paymentPolicy as IntegrationConnection["paymentPolicy"],
      externalSource: c.externalSource,
      createdAtUtcMs: Number(c.createdAtUtcMs),
      updatedAtUtcMs: Number(c.updatedAtUtcMs),
    };
    store.integrationConnections.set(conn.id, conn);
  }

  for (const k of integrationApiKeys) {
    const scopes = Array.isArray(k.scopes)
      ? k.scopes.filter((scope): scope is IntegrationApiKey["scopes"][number] =>
          scope === "loads:read" || scope === "loads:write" || scope === "webhooks:manage")
      : [];
    const key: IntegrationApiKey = {
      id: k.id,
      keyId: k.keyId,
      secretHash: k.secretHash,
      orgId: k.orgId,
      connectionId: k.connectionId,
      scopes,
      status: k.status as IntegrationApiKey["status"],
      expiresAtUtcMs: k.expiresAtUtcMs != null ? Number(k.expiresAtUtcMs) : null,
      lastUsedAtUtcMs: k.lastUsedAtUtcMs != null ? Number(k.lastUsedAtUtcMs) : null,
      createdAtUtcMs: Number(k.createdAtUtcMs),
    };
    store.integrationApiKeys.set(key.id, key);
  }

  for (const r of integrationIdempotency) {
    const rec: IntegrationIdempotencyRecord = {
      key: r.key,
      orgId: r.orgId,
      shipmentId: r.shipmentId,
      createdAtUtcMs: Number(r.createdAtUtcMs),
    };
    store.integrationIdempotency.set(rec.key, rec);
  }

  for (const e of integrationEvents) {
    const event: IntegrationEvent = {
      id: e.id,
      orgId: e.orgId,
      shipmentId: e.shipmentId,
      ...(e.externalLoadId != null ? { externalLoadId: e.externalLoadId } : {}),
      eventType: e.eventType as IntegrationEvent["eventType"],
      sequence: e.sequence,
      payload: e.payload as Record<string, unknown>,
      occurredAtUtcMs: Number(e.occurredAtUtcMs),
      createdAtUtcMs: Number(e.createdAtUtcMs),
    };
    store.integrationEvents.set(event.id, event);
  }

  for (const d of integrationWebhookDeliveries) {
    const delivery: IntegrationWebhookDelivery = {
      id: d.id,
      eventId: d.eventId,
      orgId: d.orgId,
      connectionId: d.connectionId,
      webhookUrl: d.webhookUrl,
      payloadJson: d.payloadJson,
      status: d.status as IntegrationWebhookDelivery["status"],
      attempts: d.attempts,
      nextRetryAtUtcMs: Number(d.nextRetryAtUtcMs),
      lastHttpStatus: d.lastHttpStatus,
      lastError: d.lastError,
      deliveredAtUtcMs: d.deliveredAtUtcMs != null ? Number(d.deliveredAtUtcMs) : null,
      createdAtUtcMs: Number(d.createdAtUtcMs),
      updatedAtUtcMs: Number(d.updatedAtUtcMs),
    };
    store.integrationWebhookDeliveries.set(delivery.id, delivery);
  }

  return store;
}

export async function saveStoreToDatabase(store: Store): Promise<void> {
  await prisma.$transaction(async (tx) => {
    await tx.integrationWebhookDeliveryRow.deleteMany();
    await tx.integrationEventRow.deleteMany();
    await tx.integrationIdempotencyRow.deleteMany();
    await tx.integrationApiKeyRow.deleteMany();
    await tx.integrationConnectionRow.deleteMany();
    await tx.ledgerLineRow.deleteMany();
    await tx.payoutBatchRow.deleteMany();
    await tx.shipmentRow.deleteMany();
    await tx.paymentRow.deleteMany();
    await tx.anchorTripRow.deleteMany();
    await tx.driverProfileRow.deleteMany();
    await tx.vehicle.deleteMany();
    await tx.membership.deleteMany();
    await tx.authSessionRow.deleteMany();
    await tx.otpChallengeRow.deleteMany();
    await tx.userRow.deleteMany();
    await tx.carrier.deleteMany();
    await tx.organization.deleteMany();

    for (const c of store.carriers.values()) {
      await tx.carrier.create({
        data: {
          id: c.id,
          name: c.name,
          createdAtUtcMs: BigInt(c.createdAtUtcMs),
        },
      });
    }
    for (const o of store.organizations.values()) {
      await tx.organization.create({
        data: {
          id: o.id,
          kind: o.kind,
          displayName: o.displayName,
          kycStatus: o.kycStatus,
          createdAtUtcMs: BigInt(o.createdAtUtcMs),
          payoutContactId: o.payoutContactId ?? null,
          payoutFundAccountId: o.payoutFundAccountId ?? null,
        },
      });
    }
    for (const u of store.users.values()) {
      await tx.userRow.create({
        data: {
          id: u.id,
          phone: u.phone,
          fullName: u.fullName,
          createdAtUtcMs: BigInt(u.createdAtUtcMs),
        },
      });
    }
    for (const m of store.memberships.values()) {
      await tx.membership.create({
        data: {
          userId: m.userId,
          orgId: m.orgId,
          role: m.role,
          createdAtUtcMs: BigInt(m.createdAtUtcMs),
        },
      });
    }
    for (const v of store.vehicles.values()) {
      await tx.vehicle.create({
        data: {
          id: v.id,
          orgId: v.orgId,
          registrationNumber: v.registrationNumber,
          vehicleClass: v.vehicleClass,
          capacityKg: v.capacityKg,
          createdAtUtcMs: BigInt(v.createdAtUtcMs),
        },
      });
    }
    for (const d of store.driverProfiles.values()) {
      await tx.driverProfileRow.create({
        data: {
          userId: d.userId,
          orgId: d.orgId,
          primaryVehicleId: d.primaryVehicleId,
          createdAtUtcMs: BigInt(d.createdAtUtcMs),
        },
      });
    }
    for (const o of store.otpChallenges.values()) {
      await tx.otpChallengeRow.create({
        data: {
          id: o.id,
          phone: o.phone,
          code: o.code,
          status: o.status,
          expiresAtUtcMs: BigInt(o.expiresAtUtcMs),
          createdAtUtcMs: BigInt(o.createdAtUtcMs),
        },
      });
    }
    for (const s of store.authSessions.values()) {
      await tx.authSessionRow.create({
        data: {
          id: s.id,
          userId: s.userId,
          createdAtUtcMs: BigInt(s.createdAtUtcMs),
          expiresAtUtcMs: BigInt(s.expiresAtUtcMs),
          revokedAtUtcMs: s.revokedAtUtcMs != null ? BigInt(s.revokedAtUtcMs) : null,
        },
      });
    }
    for (const t of store.anchorTrips.values()) {
      await tx.anchorTripRow.create({
        data: {
          id: t.id,
          carrierId: t.carrierId,
          originCity: t.originCity,
          destCity: t.destCity,
          origin: t.origin ?? undefined,
          destination: t.destination ?? undefined,
          windowStart: t.windowStart,
          windowEnd: t.windowEnd,
          vehicleClass: t.vehicleClass,
          capacityKg: t.capacityKg,
          reservedKg: t.reservedKg,
          status: t.status,
          createdAtUtcMs: BigInt(t.createdAtUtcMs),
          startedAtUtcMs: t.startedAtUtcMs != null ? BigInt(t.startedAtUtcMs) : null,
          startedByUserId: t.startedByUserId ?? null,
          completedAtUtcMs: t.completedAtUtcMs != null ? BigInt(t.completedAtUtcMs) : null,
          completedByUserId: t.completedByUserId ?? null,
          lastLiveLocation: t.lastLiveLocation ?? undefined,
        },
      });
    }
    for (const p of store.payments.values()) {
      await tx.paymentRow.create({
        data: {
          id: p.id,
          shipmentId: p.shipmentId,
          amountPaise: p.amountPaise,
          status: p.status,
          provider: p.provider,
          providerRef: p.providerRef || p.razorpayOrderId || "",
          razorpayOrderId: p.razorpayOrderId ?? null,
          razorpayPaymentId: p.razorpayPaymentId ?? null,
          createdAtUtcMs: BigInt(p.createdAtUtcMs),
          updatedAtUtcMs: BigInt(p.updatedAtUtcMs),
        },
      });
    }
    for (const s of store.shipments.values()) {
      await tx.shipmentRow.create({
        data: {
          id: s.id,
          anchorTripId: s.anchorTripId,
          carrierId: s.carrierId,
          customerOrgId: s.customerOrgId ?? null,
          customerOrgName: s.customerOrgName,
          bookedByPhone: s.bookedByPhone ?? null,
          bookedByUserId: s.bookedByUserId ?? null,
          weightKg: s.weightKg,
          pickupAddress: s.pickupAddress,
          dropAddress: s.dropAddress,
          pickup: s.pickup ?? undefined,
          drop: s.drop ?? undefined,
          status: s.status,
          acceptedAtUtcMs: s.acceptedAtUtcMs != null ? BigInt(s.acceptedAtUtcMs) : null,
          acceptedByUserId: s.acceptedByUserId ?? null,
          grossPaise: s.grossPaise,
          commissionPaise: s.commissionPaise,
          netToCarrierPaise: s.netToCarrierPaise,
          paymentId: s.paymentId,
          podAtUtcMs: s.podAtUtcMs != null ? BigInt(s.podAtUtcMs) : null,
          podSubmittedByUserId: s.podSubmittedByUserId ?? null,
          podNotes: s.podNotes ?? null,
          firstPayoutEligibleAtUtcMs: s.firstPayoutEligibleAtUtcMs != null
            ? BigInt(s.firstPayoutEligibleAtUtcMs)
            : null,
          payoutBatchCutoffUtcMs: s.payoutBatchCutoffUtcMs != null ? BigInt(s.payoutBatchCutoffUtcMs) : null,
          externalLoadId: s.externalLoadId ?? null,
          externalSource: s.externalSource ?? null,
          integrationConnectionId: s.integrationConnectionId ?? null,
          metadata: s.metadata ?? undefined,
          integrationSequence: s.integrationSequence ?? null,
          createdAtUtcMs: BigInt(s.createdAtUtcMs),
          updatedAtUtcMs: BigInt(s.updatedAtUtcMs),
        },
      });
    }
    for (const l of store.ledgerLines.values()) {
      await tx.ledgerLineRow.create({
        data: {
          id: l.id,
          shipmentId: l.shipmentId,
          carrierId: l.carrierId,
          grossPaise: l.grossPaise,
          commissionPaise: l.commissionPaise,
          netToCarrierPaise: l.netToCarrierPaise,
          podAtUtcMs: BigInt(l.podAtUtcMs),
          firstPayoutEligibleAtUtcMs: BigInt(l.firstPayoutEligibleAtUtcMs),
          payoutBatchCutoffUtcMs: BigInt(l.payoutBatchCutoffUtcMs),
          status: l.status,
          createdAtUtcMs: BigInt(l.createdAtUtcMs),
          paidAtUtcMs: l.paidAtUtcMs != null ? BigInt(l.paidAtUtcMs) : null,
        },
      });
    }
    for (const b of store.payoutBatches.values()) {
      await tx.payoutBatchRow.create({
        data: {
          id: b.id,
          cutoffUtcMs: BigInt(b.cutoffUtcMs),
          createdAtUtcMs: BigInt(b.createdAtUtcMs),
          totalNetToCarrierPaise: b.totalNetToCarrierPaise,
          lineIds: b.lineIds,
          provider: b.provider,
          transfers: b.transfers as unknown as object[],
        },
      });
    }
    for (const c of store.integrationConnections.values()) {
      await tx.integrationConnectionRow.create({
        data: {
          id: c.id,
          orgId: c.orgId,
          displayName: c.displayName,
          status: c.status,
          webhookUrl: c.webhookUrl ?? null,
          webhookSecret: c.webhookSecret ?? null,
          paymentPolicy: c.paymentPolicy,
          externalSource: c.externalSource,
          createdAtUtcMs: BigInt(c.createdAtUtcMs),
          updatedAtUtcMs: BigInt(c.updatedAtUtcMs),
        },
      });
    }
    for (const k of store.integrationApiKeys.values()) {
      await tx.integrationApiKeyRow.create({
        data: {
          id: k.id,
          keyId: k.keyId,
          secretHash: k.secretHash,
          orgId: k.orgId,
          connectionId: k.connectionId,
          scopes: k.scopes,
          status: k.status,
          expiresAtUtcMs: k.expiresAtUtcMs != null ? BigInt(k.expiresAtUtcMs) : null,
          lastUsedAtUtcMs: k.lastUsedAtUtcMs != null ? BigInt(k.lastUsedAtUtcMs) : null,
          createdAtUtcMs: BigInt(k.createdAtUtcMs),
        },
      });
    }
    for (const r of store.integrationIdempotency.values()) {
      await tx.integrationIdempotencyRow.create({
        data: {
          key: r.key,
          orgId: r.orgId,
          shipmentId: r.shipmentId,
          createdAtUtcMs: BigInt(r.createdAtUtcMs),
        },
      });
    }
    for (const e of store.integrationEvents.values()) {
      await tx.integrationEventRow.create({
        data: {
          id: e.id,
          orgId: e.orgId,
          shipmentId: e.shipmentId,
          externalLoadId: e.externalLoadId ?? null,
          eventType: e.eventType,
          sequence: e.sequence,
          payload: e.payload,
          occurredAtUtcMs: BigInt(e.occurredAtUtcMs),
          createdAtUtcMs: BigInt(e.createdAtUtcMs),
        },
      });
    }
    for (const d of store.integrationWebhookDeliveries.values()) {
      await tx.integrationWebhookDeliveryRow.create({
        data: {
          id: d.id,
          eventId: d.eventId,
          orgId: d.orgId,
          connectionId: d.connectionId,
          webhookUrl: d.webhookUrl,
          payloadJson: d.payloadJson,
          status: d.status,
          attempts: d.attempts,
          nextRetryAtUtcMs: BigInt(d.nextRetryAtUtcMs),
          lastHttpStatus: d.lastHttpStatus,
          lastError: d.lastError,
          deliveredAtUtcMs: d.deliveredAtUtcMs != null ? BigInt(d.deliveredAtUtcMs) : null,
          createdAtUtcMs: BigInt(d.createdAtUtcMs),
          updatedAtUtcMs: BigInt(d.updatedAtUtcMs),
        },
      });
    }
  });
}

export async function disconnectDatabase(): Promise<void> {
  await prisma.$disconnect();
}
