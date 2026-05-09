import { PrismaClient } from "@prisma/client";
import { createStore, type Store } from "./store.ts";
import type {
  AnchorTrip,
  AuthSession,
  Carrier,
  DriverProfile,
  GeoPoint,
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
      weightKg: row.weightKg,
      pickupAddress: row.pickupAddress,
      dropAddress: row.dropAddress,
      pickup: asGeo(row.pickup),
      drop: asGeo(row.drop),
      status: row.status as Shipment["status"],
      grossPaise: row.grossPaise,
      commissionPaise: row.commissionPaise,
      netToCarrierPaise: row.netToCarrierPaise,
      paymentId: row.paymentId,
      podAtUtcMs: row.podAtUtcMs != null ? Number(row.podAtUtcMs) : null,
      firstPayoutEligibleAtUtcMs: row.firstPayoutEligibleAtUtcMs != null
        ? Number(row.firstPayoutEligibleAtUtcMs)
        : null,
      payoutBatchCutoffUtcMs: row.payoutBatchCutoffUtcMs != null ? Number(row.payoutBatchCutoffUtcMs) : null,
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
    const batch: PayoutBatch = {
      id: b.id,
      cutoffUtcMs: Number(b.cutoffUtcMs),
      createdAtUtcMs: Number(b.createdAtUtcMs),
      totalNetToCarrierPaise: b.totalNetToCarrierPaise,
      lineIds,
    };
    store.payoutBatches.set(batch.id, batch);
  }

  return store;
}

export async function saveStoreToDatabase(store: Store): Promise<void> {
  await prisma.$transaction(async (tx) => {
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
          weightKg: s.weightKg,
          pickupAddress: s.pickupAddress,
          dropAddress: s.dropAddress,
          pickup: s.pickup ?? undefined,
          drop: s.drop ?? undefined,
          status: s.status,
          grossPaise: s.grossPaise,
          commissionPaise: s.commissionPaise,
          netToCarrierPaise: s.netToCarrierPaise,
          paymentId: s.paymentId,
          podAtUtcMs: s.podAtUtcMs != null ? BigInt(s.podAtUtcMs) : null,
          firstPayoutEligibleAtUtcMs: s.firstPayoutEligibleAtUtcMs != null
            ? BigInt(s.firstPayoutEligibleAtUtcMs)
            : null,
          payoutBatchCutoffUtcMs: s.payoutBatchCutoffUtcMs != null ? BigInt(s.payoutBatchCutoffUtcMs) : null,
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
        },
      });
    }
  });
}

export async function disconnectDatabase(): Promise<void> {
  await prisma.$disconnect();
}
