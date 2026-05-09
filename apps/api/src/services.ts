import { computePayoutBatchAssignment } from "../../../packages/core/src/payoutSchedule.ts";
import {
  COMMISSION_BPS,
  FREIGHT_MODEL_VERSION,
  PAYOUT_BATCH_SCHEDULE,
  PRICE_PAISE_PER_KG,
  freightMinGrossPaise,
  freightPaisePerKmForClass,
} from "./config.ts";
import type {
  AnchorTrip,
  Carrier,
  DriverProfile,
  GeoPoint,
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
import {
  captureRazorpayPayment,
  createAuthorizeOnlyOrder,
  razorpayPaymentsEnabled,
  razorpayRefundPayment,
} from "./razorpayPayments.ts";

function nowUtcMs(): number {
  return Date.now();
}

function assertGeoPoint(v: any, name: string): asserts v is GeoPoint {
  if (!v || typeof v !== "object") throw new Error(`invalid_${name}`);
  const lat = (v as any).lat;
  const lng = (v as any).lng;
  if (typeof lat !== "number" || Number.isNaN(lat) || lat < -90 || lat > 90) throw new Error(`invalid_${name}`);
  if (typeof lng !== "number" || Number.isNaN(lng) || lng < -180 || lng > 180) throw new Error(`invalid_${name}`);
}

/** Great-circle distance between two WGS84 points (km). */
export function distanceBetweenGeoPointsKm(a: GeoPoint, b: GeoPoint): number {
  const toRad = (d: number) => (d * Math.PI) / 180;
  const R = 6371;
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const sa = Math.sin(dLat / 2);
  const sb = Math.sin(dLng / 2);
  const aa = sa * sa + Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * sb * sb;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(aa)));
}

function haversineKm(a: GeoPoint, b: GeoPoint): number {
  return distanceBetweenGeoPointsKm(a, b);
}

/** Structured API error (handlers map {@link ApiError.httpStatus}, default 400). */
export class ApiError extends Error {
  readonly extra: Record<string, unknown>;
  /** HTTP status for API handlers (default 400). */
  readonly httpStatus: number;

  constructor(message: string, extra: Record<string, unknown> = {}, httpStatus = 400) {
    super(message);
    this.name = "ApiError";
    this.extra = extra;
    this.httpStatus = httpStatus;
    Object.setPrototypeOf(this, new.target.prototype);
  }
}

/** Max distance from trip origin / destination for Phase A booking (km). Env overrides for ops. */
function phaseAEndpointRadiiKm(): { maxPickupKm: number; maxDropKm: number } {
  const p = Number(process.env.PHASE_A_MAX_PICKUP_KM ?? "15");
  const d = Number(process.env.PHASE_A_MAX_DROP_KM ?? "15");
  return {
    maxPickupKm: Number.isFinite(p) && p > 0 ? p : 15,
    maxDropKm: Number.isFinite(d) && d > 0 ? d : 15,
  };
}

/** When [trip] has `origin` + `destination`, booking must supply pickup/drop geo within Phase A radii. Legacy trips without geo skip this. */
export function assertPhaseABookingEligible(params: {
  trip: AnchorTrip;
  pickup?: GeoPoint;
  drop?: GeoPoint;
  maxPickupKm?: number;
  maxDropKm?: number;
}): void {
  const { trip } = params;
  if (!trip.origin || !trip.destination) return;

  const radii = phaseAEndpointRadiiKm();
  const maxP = params.maxPickupKm ?? radii.maxPickupKm;
  const maxD = params.maxDropKm ?? radii.maxDropKm;

  if (!params.pickup || !params.drop) {
    throw new ApiError("phase_a_pickup_drop_required", {
      detail: "Anchor trip has map endpoints; include pickup and drop coordinates to book.",
    });
  }
  assertGeoPoint(params.pickup, "pickup");
  assertGeoPoint(params.drop, "drop");

  const pickupDistanceKm = haversineKm(params.pickup, trip.origin);
  const dropDistanceKm = haversineKm(params.drop, trip.destination);
  if (pickupDistanceKm > maxP || dropDistanceKm > maxD) {
    throw new ApiError("phase_a_not_eligible", {
      reason: "too_far_from_endpoints",
      pickupDistanceKm: Math.round(pickupDistanceKm * 10) / 10,
      dropDistanceKm: Math.round(dropDistanceKm * 10) / 10,
      maxPickupKm: maxP,
      maxDropKm: maxD,
    });
  }
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
/** First CUSTOMER org for this user (stable order if several). */
export function customerPrimaryOrgForUser(store: Store, userId: string): Organization | null {
  const matches: Organization[] = [];
  for (const m of store.memberships.values()) {
    if (m.userId !== userId) continue;
    const o = store.organizations.get(m.orgId);
    if (o?.kind === "CUSTOMER") matches.push(o);
  }
  if (matches.length === 0) return null;
  matches.sort((a, b) => a.id.localeCompare(b.id));
  return matches[0]!;
}

export function shipmentBelongsToCustomerOrg(shipment: Shipment, org: Organization): boolean {
  if (shipment.customerOrgId != null && shipment.customerOrgId !== "") {
    return shipment.customerOrgId === org.id;
  }
  return shipment.customerOrgName === org.displayName;
}

/** List/detail/POD visibility: org-scoped booking, or anonymous booking tied to the same phone as the logged-in user. */
export function shipmentVisibleToCustomerUser(store: Store, shipment: Shipment, userId: string): boolean {
  const user = store.users.get(userId);
  if (!user) return false;
  const org = customerPrimaryOrgForUser(store, userId);
  if (org && shipmentBelongsToCustomerOrg(shipment, org)) return true;
  if (shipment.bookedByPhone != null && shipment.bookedByPhone !== "" && shipment.bookedByPhone === user.phone) {
    return true;
  }
  return false;
}

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
  origin?: GeoPoint;
  destination?: GeoPoint;
  windowStart: string;
  windowEnd: string;
  vehicleClass: VehicleClass;
  capacityKg: number;
}): AnchorTrip {
  // `carrierId` is legacy naming; it is the Organization id for carrier-side entities.
  getOrgOrThrow(store, params.carrierId);
  if (params.capacityKg <= 0) throw new Error("invalid_capacityKg");
  if (params.origin) assertGeoPoint(params.origin, "origin");
  if (params.destination) assertGeoPoint(params.destination, "destination");
  const t: AnchorTrip = {
    id: id("trip"),
    carrierId: params.carrierId,
    originCity: params.originCity,
    destCity: params.destCity,
    origin: params.origin,
    destination: params.destination,
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
  origin?: GeoPoint;
  destination?: GeoPoint;
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
    origin: params.origin,
    destination: params.destination,
    windowStart: params.windowStart,
    windowEnd: params.windowEnd,
    vehicleClass: params.vehicleClass,
    capacityKg: params.capacityKg,
  });
}

export function customerEligibleAnchorTripsPhaseA(store: Store, params: {
  pickup: GeoPoint;
  drop: GeoPoint;
  weightKg: number;
  maxPickupDistanceKm?: number;
  maxDropDistanceKm?: number;
}): Array<{
  trip: AnchorTrip;
  eligibility: { eligible: boolean; reason: string; score: number; pickupDistanceKm: number; dropDistanceKm: number };
}> {
  assertGeoPoint(params.pickup, "pickup");
  assertGeoPoint(params.drop, "drop");
  if (params.weightKg <= 0) throw new Error("invalid_weightKg");

  const radii = phaseAEndpointRadiiKm();
  const maxPickup = params.maxPickupDistanceKm ?? radii.maxPickupKm;
  const maxDrop = params.maxDropDistanceKm ?? radii.maxDropKm;

  const out: Array<{
    trip: AnchorTrip;
    eligibility: { eligible: boolean; reason: string; score: number; pickupDistanceKm: number; dropDistanceKm: number };
  }> = [];

  for (const trip of store.anchorTrips.values()) {
    if (trip.status !== "OPEN") continue;
    const remaining = trip.capacityKg - trip.reservedKg;
    if (remaining < params.weightKg) continue;
    if (!trip.origin || !trip.destination) continue; // Phase A requires endpoints

    const pickupDistanceKm = haversineKm(params.pickup, trip.origin);
    const dropDistanceKm = haversineKm(params.drop, trip.destination);

    const eligible = pickupDistanceKm <= maxPickup && dropDistanceKm <= maxDrop;
    const score = Math.max(0, 1 - (pickupDistanceKm / maxPickup + dropDistanceKm / maxDrop) / 2);
    out.push({
      trip,
      eligibility: {
        eligible,
        reason: eligible ? "near_endpoints" : "too_far_from_endpoints",
        score,
        pickupDistanceKm: Math.round(pickupDistanceKm * 10) / 10,
        dropDistanceKm: Math.round(dropDistanceKm * 10) / 10,
      },
    });
  }

  out.sort((a, b) => b.eligibility.score - a.eligibility.score);
  return out;
}

export type FreightPricingMode = "distance_weight" | "weight_only";

export type FreightBreakdown = {
  pricingMode: FreightPricingMode;
  modelVersion: string;
  vehicleClass: VehicleClass;
  laneKm: number | null;
  shipmentKm: number | null;
  distanceKmForPrice: number | null;
  paisePerKm: number | null;
  distanceComponentPaise: number;
  weightComponentPaise: number;
};

function userHasPilotCarrierMembership(store: Store, userId: string): boolean {
  for (const m of store.memberships.values()) {
    if (m.userId !== userId) continue;
    const o = store.organizations.get(m.orgId);
    if (!o) continue;
    if (o.kind === "CARRIER_SOLO" || o.kind === "CARRIER_FLEET" || o.kind === "CARRIER_LEGACY") return true;
  }
  return false;
}

/**
 * Pure freight price: paise per km (class) + ₹5/kg when a distance basis exists
 * (`shipmentKm` preferred else `laneKm`). Without distance, falls back to weight-only.
 */
export function computeFreightGrossPaise(params: {
  weightKg: number;
  vehicleClass: VehicleClass;
  laneKm?: number | null;
  shipmentKm?: number | null;
}): { grossPaise: number; breakdown: FreightBreakdown } {
  assertVehicleClass(params.vehicleClass);
  if (params.weightKg <= 0) throw new Error("invalid_weightKg");

  const laneKm = params.laneKm != null && params.laneKm > 0 ? params.laneKm : null;
  const shipmentKm = params.shipmentKm != null && params.shipmentKm > 0 ? params.shipmentKm : null;
  const distanceKmForPrice = shipmentKm ?? laneKm;
  const paisePerKm = distanceKmForPrice != null ? freightPaisePerKmForClass(params.vehicleClass) : null;

  let distanceComponentPaise = 0;
  let weightComponentPaise = 0;
  let pricingMode: FreightPricingMode;
  let grossPaise: number;

  if (distanceKmForPrice != null && paisePerKm != null) {
    pricingMode = "distance_weight";
    distanceComponentPaise = Math.round(distanceKmForPrice * paisePerKm);
    weightComponentPaise = Math.round(params.weightKg * PRICE_PAISE_PER_KG);
    grossPaise = distanceComponentPaise + weightComponentPaise;
    const floor = freightMinGrossPaise();
    if (floor > 0 && grossPaise < floor) grossPaise = floor;
  } else {
    pricingMode = "weight_only";
    weightComponentPaise = Math.round(params.weightKg * PRICE_PAISE_PER_KG);
    grossPaise = weightComponentPaise;
  }

  return {
    grossPaise,
    breakdown: {
      pricingMode,
      modelVersion: FREIGHT_MODEL_VERSION,
      vehicleClass: params.vehicleClass,
      laneKm: laneKm != null ? Math.round(laneKm * 10) / 10 : null,
      shipmentKm: shipmentKm != null ? Math.round(shipmentKm * 10) / 10 : null,
      distanceKmForPrice: distanceKmForPrice != null ? Math.round(distanceKmForPrice * 10) / 10 : null,
      paisePerKm,
      distanceComponentPaise,
      weightComponentPaise,
    },
  };
}

export function quoteShipmentMarketplace(store: Store, params: {
  weightKg: number;
  pickup?: unknown;
  drop?: unknown;
  anchorTripId?: string;
}): { grossPaise: number; breakdown: FreightBreakdown } {
  if (params.weightKg <= 0) throw new ApiError("invalid_weightKg", {});

  let vehicleClass: VehicleClass = "MEDIUM";
  let laneKm: number | null = null;
  let shipmentKm: number | null = null;

  if (params.anchorTripId) {
    const trip = store.anchorTrips.get(params.anchorTripId);
    if (trip) {
      vehicleClass = trip.vehicleClass;
      if (trip.origin && trip.destination) {
        laneKm = haversineKm(trip.origin, trip.destination);
      }
    }
  }

  const hasP = params.pickup != null && params.pickup !== undefined;
  const hasD = params.drop != null && params.drop !== undefined;
  if (hasP !== hasD) {
    throw new ApiError("pickup_drop_both_required", {
      detail: "Send both pickup and drop objects with lat/lng, or omit both.",
    });
  }
  if (hasP && hasD) {
    assertGeoPoint(params.pickup, "pickup");
    assertGeoPoint(params.drop, "drop");
    shipmentKm = haversineKm(params.pickup as GeoPoint, params.drop as GeoPoint);
  }

  return computeFreightGrossPaise({
    weightKg: params.weightKg,
    vehicleClass,
    laneKm,
    shipmentKm,
  });
}

export function pilotRatesEstimate(store: Store, userId: string, body: {
  origin: unknown;
  destination: unknown;
  vehicleClass?: unknown;
  sampleWeightsKg?: unknown;
}): {
  laneKm: number;
  samples: Array<{ weightKg: number; grossPaise: number; breakdown: FreightBreakdown }>;
  modelVersion: string;
} {
  if (!userHasPilotCarrierMembership(store, userId)) {
    throw new ApiError(
      "pilot_carrier_required",
      { detail: "User must belong to a carrier organization." },
      403,
    );
  }
  assertGeoPoint(body.origin, "origin");
  assertGeoPoint(body.destination, "destination");
  const origin = body.origin as GeoPoint;
  const destination = body.destination as GeoPoint;

  let vc: VehicleClass = "MEDIUM";
  if (body.vehicleClass != null && body.vehicleClass !== "") {
    assertVehicleClass(body.vehicleClass);
    vc = body.vehicleClass;
  }

  let sampleWeights: number[] = [100, 250, 500];
  if (Array.isArray(body.sampleWeightsKg) && body.sampleWeightsKg.length > 0) {
    const parsed = body.sampleWeightsKg
      .map((w) => Number(w))
      .filter((n) => Number.isFinite(n) && n > 0);
    if (parsed.length > 0) {
      sampleWeights = [...new Set(parsed)].sort((a, b) => a - b).slice(0, 8);
    }
  }

  const laneKmRaw = haversineKm(origin, destination);
  const laneKmRounded = Math.round(laneKmRaw * 100) / 100;

  const samples = sampleWeights.map((weightKg) => {
    const { grossPaise, breakdown } = computeFreightGrossPaise({
      weightKg,
      vehicleClass: vc,
      laneKm: laneKmRaw,
      shipmentKm: null,
    });
    return { weightKg, grossPaise, breakdown };
  });

  return { laneKm: laneKmRounded, samples, modelVersion: FREIGHT_MODEL_VERSION };
}

/** Legacy weight-only helper; same as marketplace quote with no geography. */
export function quoteShipment(params: { weightKg: number }): { grossPaise: number } {
  const { grossPaise } = computeFreightGrossPaise({
    weightKg: params.weightKg,
    vehicleClass: "MEDIUM",
    laneKm: null,
    shipmentKm: null,
  });
  return { grossPaise };
}

export function bookShipment(store: Store, params: {
  anchorTripId: string;
  customerOrgName: string;
  /** When set (e.g. Bearer customer session), shipment is tagged for scoped listing. */
  customerOrg?: { id: string; displayName: string };
  /** Same digits as `User.phone` after OTP; links anonymous bookings to that user for GET /shipments. */
  bookedByPhoneRaw?: string;
  weightKg: number;
  pickupAddress: string;
  dropAddress: string;
  pickup?: GeoPoint;
  drop?: GeoPoint;
}): Shipment {
  const trip = store.anchorTrips.get(params.anchorTripId);
  if (!trip) throw new Error("anchor_trip_not_found");
  if (trip.status !== "OPEN") throw new Error("anchor_trip_not_open");
  if (params.weightKg <= 0) throw new Error("invalid_weightKg");
  if (trip.reservedKg + params.weightKg > trip.capacityKg) throw new Error("insufficient_capacity");

  assertPhaseABookingEligible({
    trip,
    pickup: params.pickup,
    drop: params.drop,
  });

  let laneKm: number | null = null;
  if (trip.origin && trip.destination) {
    laneKm = haversineKm(trip.origin, trip.destination);
  }
  let shipmentKm: number | null = null;
  if (params.pickup && params.drop) {
    assertGeoPoint(params.pickup, "pickup");
    assertGeoPoint(params.drop, "drop");
    shipmentKm = haversineKm(params.pickup, params.drop);
  }

  const { grossPaise } = computeFreightGrossPaise({
    weightKg: params.weightKg,
    vehicleClass: trip.vehicleClass,
    laneKm,
    shipmentKm,
  });

  // Reserve capacity immediately (instant booking).
  trip.reservedKg += params.weightKg;
  if (trip.reservedKg === trip.capacityKg) trip.status = "FULL";
  store.anchorTrips.set(trip.id, trip);

  const { commissionPaise, netToCarrierPaise } = moneySplit(grossPaise);
  const now = nowUtcMs();

  const useRzp = razorpayPaymentsEnabled();
  const payment: Payment = {
    id: id("payin"),
    shipmentId: "pending", // set after shipment id is generated
    amountPaise: grossPaise,
    status: useRzp ? "CREATED" : "CAPTURED",
    provider: useRzp ? "RAZORPAY" : "MOCK",
    providerRef: useRzp ? "" : id("mock"),
    createdAtUtcMs: now,
    updatedAtUtcMs: now,
  };

  const co = params.customerOrg;
  const customerOrgName = co != null ? co.displayName : params.customerOrgName;

  let bookedByPhone: string | undefined;
  const rawPhone = params.bookedByPhoneRaw;
  if (rawPhone != null && String(rawPhone).trim() !== "") {
    bookedByPhone = normalizeInPhone(String(rawPhone));
  }

  const s: Shipment = {
    id: id("shp"),
    anchorTripId: trip.id,
    carrierId: trip.carrierId,
    ...(co != null ? { customerOrgId: co.id } : {}),
    customerOrgName,
    ...(bookedByPhone != null ? { bookedByPhone } : {}),
    weightKg: params.weightKg,
    pickupAddress: params.pickupAddress,
    dropAddress: params.dropAddress,
    pickup: params.pickup,
    drop: params.drop,
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

/** Reverse a BOOKED shipment + free trip capacity if Razorpay order could not be created. */
export function rollbackBooking(store: Store, shipmentId: string): void {
  const s = store.shipments.get(shipmentId);
  if (!s) return;
  const trip = store.anchorTrips.get(s.anchorTripId);
  if (trip) {
    trip.reservedKg = Math.max(0, trip.reservedKg - s.weightKg);
    if (trip.status === "FULL" && trip.reservedKg < trip.capacityKg) trip.status = "OPEN";
    store.anchorTrips.set(trip.id, trip);
  }
  store.payments.delete(s.paymentId);
  store.shipments.delete(shipmentId);
}

export async function attachRazorpayOrderForShipment(store: Store, shipmentId: string): Promise<void> {
  const s = store.shipments.get(shipmentId);
  if (!s) throw new Error("shipment_not_found");
  const pay = store.payments.get(s.paymentId);
  if (!pay || pay.provider !== "RAZORPAY") throw new Error("not_razorpay_shipment");
  const { id: orderId } = await createAuthorizeOnlyOrder(pay.amountPaise, s.id);
  const t = nowUtcMs();
  store.payments.set(pay.id, {
    ...pay,
    razorpayOrderId: orderId,
    providerRef: orderId,
    updatedAtUtcMs: t,
  });
}

/** After customer authorizes, capture funds at POD time (authorize-then-capture). */
export async function ensureRazorpayCapturedBeforePod(store: Store, shipmentId: string): Promise<void> {
  const s = store.shipments.get(shipmentId);
  if (!s) throw new Error("shipment_not_found");
  const pay = store.payments.get(s.paymentId);
  if (!pay) throw new Error("payment_not_found");
  if (pay.provider !== "RAZORPAY") return;
  if (pay.status === "CAPTURED") return;
  if (pay.status !== "AUTHORIZED") {
    throw new ApiError("checkout_not_completed_for_pod", {
      detail: "Complete Razorpay checkout (authorized) before POD, or wait for webhook.",
      status: pay.status,
    });
  }
  const pid = pay.razorpayPaymentId;
  if (!pid) throw new ApiError("payment_id_missing", {});
  await captureRazorpayPayment(pid, pay.amountPaise);
  store.payments.set(pay.id, { ...pay, status: "CAPTURED", updatedAtUtcMs: nowUtcMs() });
}

export async function failCarrierAndRefund(store: Store, params: { shipmentId: string }): Promise<Shipment> {
  const s = store.shipments.get(params.shipmentId);
  if (!s) throw new Error("shipment_not_found");
  if (s.status !== "BOOKED") throw new Error("shipment_not_refundable");

  const pay = store.payments.get(s.paymentId);
  if (!pay) throw new Error("payment_not_found");

  if (pay.provider === "RAZORPAY") {
    if (pay.status === "AUTHORIZED" || pay.status === "CAPTURED") {
      if (!pay.razorpayPaymentId) {
        throw new ApiError("razorpay_payment_id_missing", { status: pay.status });
      }
      try {
        await razorpayRefundPayment(pay.razorpayPaymentId, pay.amountPaise);
      } catch (e: any) {
        throw new ApiError("razorpay_refund_failed", { detail: String(e?.message ?? e) });
      }
    } else if (pay.status !== "CREATED" && pay.status !== "FAILED") {
      throw new ApiError("payment_not_refundable", { status: pay.status });
    }
  } else if (pay.status !== "CAPTURED") {
    throw new Error("payment_not_captured");
  }

  const trip = store.anchorTrips.get(s.anchorTripId);
  if (trip) {
    trip.reservedKg = Math.max(0, trip.reservedKg - s.weightKg);
    if (trip.status === "FULL") trip.status = "OPEN";
    store.anchorTrips.set(trip.id, trip);
  }

  const now = nowUtcMs();
  store.payments.set(pay.id, { ...pay, status: "REFUNDED", updatedAtUtcMs: now });

  const updated: Shipment = {
    ...s,
    status: "FAILED_CARRIER_REFUNDED",
    updatedAtUtcMs: now,
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

