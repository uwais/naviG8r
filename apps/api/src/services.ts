import { computePayoutBatchAssignment } from "../../../packages/core/src/payoutSchedule.ts";
import { COMMISSION_BPS, PAYOUT_BATCH_SCHEDULE, PRICE_PAISE_PER_KG } from "./config.ts";
import type {
  AnchorTrip,
  Carrier,
  DriverProfile,
  LedgerLine,
  Membership,
  Organization,
  PayoutBatch,
  Payment,
  Shipment,
  User,
  Vehicle,
  VehicleClass,
} from "./types.ts";
import type { Store } from "./store.ts";

function nowUtcMs(): number {
  return Date.now();
}

function id(prefix: string): string {
  return `${prefix}_${Math.random().toString(16).slice(2)}_${Date.now().toString(16)}`;
}

function moneySplit(grossPaise: number): { commissionPaise: number; netToCarrierPaise: number } {
  const commissionPaise = Math.floor((grossPaise * COMMISSION_BPS) / 10_000);
  return { commissionPaise, netToCarrierPaise: grossPaise - commissionPaise };
}

function membershipKey(userId: string, orgId: string): string {
  return `${userId}:${orgId}`;
}

function normalizeInPhone(phone: string): string {
  const p = String(phone ?? "").trim();
  if (!p) throw new Error("invalid_phone");
  // MVP pilot: accept 10-digit Indian mobile numbers, optional +91 prefix.
  const digits = p.replace(/[^\d]/g, "");
  if (digits.length === 12 && digits.startsWith("91")) return digits.slice(-10);
  if (digits.length === 10) return digits;
  throw new Error("invalid_phone");
}

function assertVehicleClass(v: any): asserts v is VehicleClass {
  if (v !== "SMALL" && v !== "MEDIUM" && v !== "LARGE") throw new Error("invalid_vehicleClass");
}

function getOrgOrThrow(store: Store, orgId: string): Organization {
  const org = store.organizations.get(orgId);
  if (!org) throw new Error("org_not_found");
  return org;
}

function assertPilotDriverCanManageOrg(store: Store, userId: string, orgId: string): void {
  const m = store.memberships.get(membershipKey(userId, orgId));
  if (!m) throw new Error("membership_not_found");
  if (m.role !== "OWNER_DRIVER" && m.role !== "OWNER" && m.role !== "DISPATCHER" && m.role !== "DRIVER") {
    throw new Error("forbidden");
  }
}

export function createCarrier(store: Store, name: string): Carrier {
  const c: Carrier = { id: id("car"), name, createdAtUtcMs: nowUtcMs() };
  store.carriers.set(c.id, c);
  // Keep org model in sync for older demo flows.
  store.organizations.set(c.id, {
    id: c.id,
    kind: "CARRIER_LEGACY",
    displayName: c.name,
    kycStatus: "NOT_STARTED",
    createdAtUtcMs: c.createdAtUtcMs,
  });
  return c;
}

/**
 * Pilot onboarding for solo owner-operators represented as a carrier org-of-one.
 * Intended to be called from the Driver app.
 */
export function registerSoloOwnerOperatorDriver(store: Store, params: {
  fullName: string;
  phone: string;
  orgDisplayName: string;
  vehicleRegistrationNumber: string;
  vehicleClass: VehicleClass;
  vehicleCapacityKg: number;
}): { user: User; org: Organization; membership: Membership; vehicle: Vehicle; driverProfile: DriverProfile } {
  if (!String(params.fullName ?? "").trim()) throw new Error("invalid_fullName");
  if (!String(params.orgDisplayName ?? "").trim()) throw new Error("invalid_orgDisplayName");
  if (!String(params.vehicleRegistrationNumber ?? "").trim()) throw new Error("invalid_vehicleRegistrationNumber");
  assertVehicleClass(params.vehicleClass);
  if (params.vehicleCapacityKg <= 0) throw new Error("invalid_vehicleCapacityKg");

  const phone = normalizeInPhone(params.phone);
  const dup = [...store.users.values()].find((u) => u.phone === phone);
  if (dup) throw new Error("phone_already_registered");

  const now = nowUtcMs();
  const user: User = { id: id("usr"), phone, fullName: String(params.fullName).trim(), createdAtUtcMs: now };
  const org: Organization = {
    id: id("org"),
    kind: "CARRIER_SOLO",
    displayName: String(params.orgDisplayName).trim(),
    kycStatus: "NOT_STARTED",
    createdAtUtcMs: now,
  };
  const membership: Membership = {
    userId: user.id,
    orgId: org.id,
    role: "OWNER_DRIVER",
    createdAtUtcMs: now,
  };
  const vehicle: Vehicle = {
    id: id("veh"),
    orgId: org.id,
    registrationNumber: String(params.vehicleRegistrationNumber).trim(),
    vehicleClass: params.vehicleClass,
    capacityKg: params.vehicleCapacityKg,
    createdAtUtcMs: now,
  };
  const driverProfile: DriverProfile = {
    userId: user.id,
    orgId: org.id,
    primaryVehicleId: vehicle.id,
    createdAtUtcMs: now,
  };

  store.users.set(user.id, user);
  store.organizations.set(org.id, org);
  store.memberships.set(membershipKey(user.id, org.id), membership);
  store.vehicles.set(vehicle.id, vehicle);
  store.driverProfiles.set(user.id, driverProfile);

  return { user, org, membership, vehicle, driverProfile };
}

/**
 * Minimal customer org bootstrap for pilot bookings (Factories/SMBs).
 * Not used by the Driver app, but defines the API resource shape early.
 */
export function registerCustomerOrgAdmin(store: Store, params: {
  fullName: string;
  phone: string;
  orgDisplayName: string;
}): { user: User; org: Organization; membership: Membership } {
  if (!String(params.fullName ?? "").trim()) throw new Error("invalid_fullName");
  if (!String(params.orgDisplayName ?? "").trim()) throw new Error("invalid_orgDisplayName");

  const phone = normalizeInPhone(params.phone);
  const dup = [...store.users.values()].find((u) => u.phone === phone);
  if (dup) throw new Error("phone_already_registered");

  const now = nowUtcMs();
  const user: User = { id: id("usr"), phone, fullName: String(params.fullName).trim(), createdAtUtcMs: now };
  const org: Organization = {
    id: id("org"),
    kind: "CUSTOMER",
    displayName: String(params.orgDisplayName).trim(),
    kycStatus: "NOT_STARTED",
    createdAtUtcMs: now,
  };
  const membership: Membership = {
    userId: user.id,
    orgId: org.id,
    role: "CUSTOMER_ADMIN",
    createdAtUtcMs: now,
  };

  store.users.set(user.id, user);
  store.organizations.set(org.id, org);
  store.memberships.set(membershipKey(user.id, org.id), membership);

  return { user, org, membership };
}

export function pilotLoginDriverByPhone(store: Store, phone: string): { user: User; org: Organization; membership: Membership; vehicle: Vehicle; driverProfile: DriverProfile } {
  const p = normalizeInPhone(phone);
  const user = [...store.users.values()].find((u) => u.phone === p);
  if (!user) throw new Error("user_not_found");

  const memberships = [...store.memberships.values()].filter((m) => m.userId === user.id);
  if (memberships.length !== 1) throw new Error("ambiguous_membership");

  const membership = memberships[0]!;
  const org = getOrgOrThrow(store, membership.orgId);
  const driverProfile = store.driverProfiles.get(user.id);
  if (!driverProfile) throw new Error("driver_profile_missing");
  const vehicle = store.vehicles.get(driverProfile.primaryVehicleId);
  if (!vehicle) throw new Error("vehicle_missing");

  return { user, org, membership, vehicle, driverProfile };
}

export function pilotMe(store: Store, userId: string): {
  user: User;
  memberships: Membership[];
  organizations: Organization[];
  vehicles: Vehicle[];
  driverProfile: DriverProfile | null;
} {
  const user = store.users.get(userId);
  if (!user) throw new Error("user_not_found");
  const memberships = [...store.memberships.values()].filter((m) => m.userId === user.id);
  const orgs = memberships.map((m) => getOrgOrThrow(store, m.orgId));
  const vehicles = [...store.vehicles.values()].filter((v) => orgs.some((o) => o.id === v.orgId));
  const driverProfile = store.driverProfiles.get(user.id) ?? null;
  return { user, memberships, organizations: orgs, vehicles, driverProfile };
}

/**
 * Anchor trips published under any carrier org the user belongs to (pilot driver context).
 */
export function pilotListMyAnchorTrips(store: Store, userId: string): AnchorTrip[] {
  const me = pilotMe(store, userId);
  const carrierOrgIds = new Set(
    me.organizations
      .filter((o) => o.kind === "CARRIER_SOLO" || o.kind === "CARRIER_FLEET" || o.kind === "CARRIER_LEGACY")
      .map((o) => o.id),
  );
  const trips = [...store.anchorTrips.values()].filter((t) => carrierOrgIds.has(t.carrierId));
  trips.sort((a, b) => b.createdAtUtcMs - a.createdAtUtcMs);
  return trips;
}

export function pilotGetMyAnchorTrip(store: Store, userId: string, tripId: string): AnchorTrip {
  const trips = pilotListMyAnchorTrips(store, userId);
  const t = trips.find((x) => x.id === tripId);
  if (!t) throw new Error("anchor_trip_not_found");
  return t;
}

export function publishAnchorTrip(store: Store, params: {
  carrierId: string;
  originCity: string;
  destCity: string;
  windowStart: string;
  windowEnd: string;
  vehicleClass: VehicleClass;
  capacityKg: number;
}): AnchorTrip {
  // `carrierId` is legacy naming; it is the Organization id for carrier-side entities.
  getOrgOrThrow(store, params.carrierId);
  if (params.capacityKg <= 0) throw new Error("invalid_capacityKg");
  const t: AnchorTrip = {
    id: id("trip"),
    carrierId: params.carrierId,
    originCity: params.originCity,
    destCity: params.destCity,
    windowStart: params.windowStart,
    windowEnd: params.windowEnd,
    vehicleClass: params.vehicleClass,
    capacityKg: params.capacityKg,
    reservedKg: 0,
    status: "OPEN",
    createdAtUtcMs: nowUtcMs(),
  };
  store.anchorTrips.set(t.id, t);
  return t;
}

export function publishAnchorTripAsPilotDriver(store: Store, params: {
  userId: string;
  orgId: string;
  originCity: string;
  destCity: string;
  windowStart: string;
  windowEnd: string;
  vehicleClass: VehicleClass;
  capacityKg: number;
}): AnchorTrip {
  assertPilotDriverCanManageOrg(store, params.userId, params.orgId);
  const org = getOrgOrThrow(store, params.orgId);
  if (org.kind !== "CARRIER_SOLO" && org.kind !== "CARRIER_FLEET" && org.kind !== "CARRIER_LEGACY") {
    throw new Error("org_not_carrier");
  }
  return publishAnchorTrip(store, {
    carrierId: params.orgId,
    originCity: params.originCity,
    destCity: params.destCity,
    windowStart: params.windowStart,
    windowEnd: params.windowEnd,
    vehicleClass: params.vehicleClass,
    capacityKg: params.capacityKg,
  });
}

export function quoteShipment(params: { weightKg: number }): { grossPaise: number } {
  if (params.weightKg <= 0) throw new Error("invalid_weightKg");
  return { grossPaise: Math.round(params.weightKg * PRICE_PAISE_PER_KG) };
}

export function bookShipment(store: Store, params: {
  anchorTripId: string;
  customerOrgName: string;
  weightKg: number;
  pickupAddress: string;
  dropAddress: string;
}): Shipment {
  const trip = store.anchorTrips.get(params.anchorTripId);
  if (!trip) throw new Error("anchor_trip_not_found");
  if (trip.status !== "OPEN") throw new Error("anchor_trip_not_open");
  if (params.weightKg <= 0) throw new Error("invalid_weightKg");
  if (trip.reservedKg + params.weightKg > trip.capacityKg) throw new Error("insufficient_capacity");

  // Reserve capacity immediately (instant booking).
  trip.reservedKg += params.weightKg;
  if (trip.reservedKg === trip.capacityKg) trip.status = "FULL";
  store.anchorTrips.set(trip.id, trip);

  const { grossPaise } = quoteShipment({ weightKg: params.weightKg });
  const { commissionPaise, netToCarrierPaise } = moneySplit(grossPaise);
  const now = nowUtcMs();

  // MVP payment: captured at booking (mock provider).
  const payment: Payment = {
    id: id("payin"),
    shipmentId: "pending", // set after shipment id is generated
    amountPaise: grossPaise,
    status: "CAPTURED",
    provider: "MOCK",
    providerRef: id("mock"),
    createdAtUtcMs: now,
    updatedAtUtcMs: now,
  };

  const s: Shipment = {
    id: id("shp"),
    anchorTripId: trip.id,
    carrierId: trip.carrierId,
    customerOrgName: params.customerOrgName,
    weightKg: params.weightKg,
    pickupAddress: params.pickupAddress,
    dropAddress: params.dropAddress,
    status: "BOOKED",
    grossPaise,
    commissionPaise,
    netToCarrierPaise,
    paymentId: payment.id,
    podAtUtcMs: null,
    firstPayoutEligibleAtUtcMs: null,
    payoutBatchCutoffUtcMs: null,
    createdAtUtcMs: now,
    updatedAtUtcMs: now,
  };
  payment.shipmentId = s.id;
  store.payments.set(payment.id, payment);
  store.shipments.set(s.id, s);
  return s;
}

export function markPodDelivered(store: Store, params: {
  shipmentId: string;
  podAtUtcMs?: number;
}): { shipment: Shipment; ledgerLine: LedgerLine } {
  const s = store.shipments.get(params.shipmentId);
  if (!s) throw new Error("shipment_not_found");
  if (s.status !== "BOOKED") throw new Error("shipment_not_deliverable");
  const pay = store.payments.get(s.paymentId);
  if (!pay || pay.status !== "CAPTURED") throw new Error("payment_not_captured");

  const podAtUtcMs = params.podAtUtcMs ?? nowUtcMs();
  const assignment = computePayoutBatchAssignment(podAtUtcMs, PAYOUT_BATCH_SCHEDULE);
  const now = nowUtcMs();

  const updated: Shipment = {
    ...s,
    status: "DELIVERED",
    podAtUtcMs,
    firstPayoutEligibleAtUtcMs: assignment.firstPayoutEligibleAtUtcMs,
    payoutBatchCutoffUtcMs: assignment.payoutBatchCutoffUtcMs,
    updatedAtUtcMs: now,
  };
  store.shipments.set(updated.id, updated);

  const line: LedgerLine = {
    id: id("led"),
    shipmentId: updated.id,
    carrierId: updated.carrierId,
    grossPaise: updated.grossPaise,
    commissionPaise: updated.commissionPaise,
    netToCarrierPaise: updated.netToCarrierPaise,
    podAtUtcMs,
    firstPayoutEligibleAtUtcMs: assignment.firstPayoutEligibleAtUtcMs,
    payoutBatchCutoffUtcMs: assignment.payoutBatchCutoffUtcMs,
    status: "ACCRUED",
    createdAtUtcMs: now,
    paidAtUtcMs: null,
  };
  store.ledgerLines.set(line.id, line);

  return { shipment: updated, ledgerLine: line };
}

export function failCarrierAndRefund(store: Store, params: { shipmentId: string }): Shipment {
  const s = store.shipments.get(params.shipmentId);
  if (!s) throw new Error("shipment_not_found");
  if (s.status !== "BOOKED") throw new Error("shipment_not_refundable");

  const pay = store.payments.get(s.paymentId);
  if (!pay || pay.status !== "CAPTURED") throw new Error("payment_not_captured");

  const trip = store.anchorTrips.get(s.anchorTripId);
  if (trip) {
    trip.reservedKg = Math.max(0, trip.reservedKg - s.weightKg);
    if (trip.status === "FULL") trip.status = "OPEN";
    store.anchorTrips.set(trip.id, trip);
  }

  store.payments.set(pay.id, { ...pay, status: "REFUNDED", updatedAtUtcMs: nowUtcMs() });

  const updated: Shipment = {
    ...s,
    status: "FAILED_CARRIER_REFUNDED",
    updatedAtUtcMs: nowUtcMs(),
  };
  store.shipments.set(updated.id, updated);
  return updated;
}

export function runPayoutBatch(store: Store, params: { nowUtcMs?: number }): PayoutBatch {
  const now = params.nowUtcMs ?? Date.now();
  const eligibleLines = [...store.ledgerLines.values()].filter(
    (l) => l.status === "ACCRUED" && l.payoutBatchCutoffUtcMs <= now
  );
  if (eligibleLines.length === 0) {
    // Still create an empty batch for determinism in MVP.
    const empty: PayoutBatch = {
      id: id("pay"),
      cutoffUtcMs: now,
      createdAtUtcMs: now,
      totalNetToCarrierPaise: 0,
      lineIds: [],
    };
    store.payoutBatches.set(empty.id, empty);
    return empty;
  }

  // Group by cutoff timestamp; for MVP we run one cutoff at a time: the earliest due.
  const earliestCutoff = Math.min(...eligibleLines.map((l) => l.payoutBatchCutoffUtcMs));
  const linesForBatch = eligibleLines.filter((l) => l.payoutBatchCutoffUtcMs === earliestCutoff);

  const batch: PayoutBatch = {
    id: id("pay"),
    cutoffUtcMs: earliestCutoff,
    createdAtUtcMs: now,
    totalNetToCarrierPaise: linesForBatch.reduce((sum, l) => sum + l.netToCarrierPaise, 0),
    lineIds: linesForBatch.map((l) => l.id),
  };

  for (const l of linesForBatch) {
    store.ledgerLines.set(l.id, { ...l, status: "PAID", paidAtUtcMs: now });
  }
  store.payoutBatches.set(batch.id, batch);
  return batch;
}

