import { computePayoutBatchAssignment } from "../../../packages/core/src/payoutSchedule.ts";
import {
  COMMISSION_BPS,
  FREIGHT_MODEL_VERSION,
  PAYOUT_BATCH_SCHEDULE,
  PRICE_PAISE_PER_KG,
  TRIP_TRACKING_STALE_MS,
  freightMinGrossPaise,
  freightPaisePerKmForClass,
} from "./config.ts";
import type {
  AnchorTrip,
  Carrier,
  DriverProfile,
  GeoPoint,
  KycStatus,
  LedgerLine,
  Membership,
  Organization,
  PayoutBatch,
  PayoutTransfer,
  Payment,
  Shipment,
  TripLiveLocation,
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
  verifyRazorpayCheckoutSignature,
} from "./razorpayPayments.ts";
import {
  createRazorpayBankFundAccount,
  createRazorpayPayout,
  payoutsMode,
  razorpayPayoutsEnabled,
} from "./razorpayPayouts.ts";

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

function assertCarrierCanInviteStaff(store: Store, userId: string, orgId: string): void {
  const m = store.memberships.get(membershipKey(userId, orgId));
  if (!m) throw new Error("membership_not_found");
  if (m.role !== "OWNER_DRIVER" && m.role !== "OWNER" && m.role !== "DISPATCHER") {
    throw new Error("forbidden");
  }
}

/** First vehicle provisioned for a carrier org (owner's solo register vehicle). */
function primaryOrgVehicle(store: Store, orgId: string): Vehicle | null {
  const vehicles = [...store.vehicles.values()].filter((v) => v.orgId === orgId);
  vehicles.sort((a, b) => a.createdAtUtcMs - b.createdAtUtcMs);
  return vehicles[0] ?? null;
}

export function carrierDisplayName(store: Store, carrierId: string): string {
  return store.organizations.get(carrierId)?.displayName ?? carrierId;
}

export function tripWithCarrierDisplay(store: Store, trip: AnchorTrip): AnchorTrip & { carrierDisplayName: string } {
  return { ...trip, carrierDisplayName: carrierDisplayName(store, trip.carrierId) };
}

export function shipmentWithCarrierDisplay(
  store: Store,
  shipment: Shipment,
): Shipment & { carrierDisplayName: string } {
  return { ...shipment, carrierDisplayName: carrierDisplayName(store, shipment.carrierId) };
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
/** All CUSTOMER orgs for this user (stable order). */
export function customerOrgsForUser(store: Store, userId: string): Organization[] {
  const matches: Organization[] = [];
  for (const m of store.memberships.values()) {
    if (m.userId !== userId) continue;
    const o = store.organizations.get(m.orgId);
    if (o?.kind === "CUSTOMER") matches.push(o);
  }
  matches.sort((a, b) => a.id.localeCompare(b.id));
  return matches;
}

/** First CUSTOMER org for this user (stable order if several). Used when booking tags a single org. */
export function customerPrimaryOrgForUser(store: Store, userId: string): Organization | null {
  const orgs = customerOrgsForUser(store, userId);
  return orgs[0] ?? null;
}

function assertCustomerCanInviteMember(store: Store, userId: string, orgId: string): void {
  const m = store.memberships.get(membershipKey(userId, orgId));
  if (!m || m.role !== "CUSTOMER_ADMIN") throw new Error("forbidden");
  const org = store.organizations.get(orgId);
  if (org?.kind !== "CUSTOMER") throw new Error("org_not_customer");
}

export function shipmentBelongsToCustomerOrg(shipment: Shipment, org: Organization): boolean {
  if (shipment.customerOrgId != null && shipment.customerOrgId !== "") {
    return shipment.customerOrgId === org.id;
  }
  return shipment.customerOrgName === org.displayName;
}

const PLATFORM_OPS_ORG_ID = "org_platform_ops";

/** Returns the singleton naviG8r Platform Ops org, creating it on first use. */
export function getOrCreatePlatformOpsOrg(store: Store): Organization {
  const existing = store.organizations.get(PLATFORM_OPS_ORG_ID);
  if (existing) return existing;
  const org: Organization = {
    id: PLATFORM_OPS_ORG_ID,
    kind: "PLATFORM",
    displayName: "naviG8r Platform Ops",
    kycStatus: "APPROVED",
    createdAtUtcMs: nowUtcMs(),
  };
  store.organizations.set(org.id, org);
  return org;
}

function envOpsAdminPhones(): string[] {
  return String(process.env.OPS_ADMIN_PHONES ?? "")
    .split(",")
    .map((s) => s.trim().replace(/[^\d]/g, ""))
    .map((d) => (d.length === 12 && d.startsWith("91") ? d.slice(-10) : d))
    .filter((d) => d.length === 10);
}

/**
 * True if this user is an authorized naviG8r operations admin.
 * Two grant paths:
 *   1. Membership row with role "OPS_ADMIN" in the platform-ops org (preferred, DB-managed).
 *   2. OPS_ADMIN_PHONES env var — bootstrap-only fallback for the first admin(s).
 *      Once a DB grant exists for that phone, the env var entry can be removed.
 */
export function isOpsAdmin(store: Store, userId: string): boolean {
  const user = store.users.get(userId);
  if (!user) return false;
  for (const m of store.memberships.values()) {
    if (m.userId === userId && (m.role === "OPS_ADMIN" || m.role === "OPS_AGENT")) return true;
  }
  if (envOpsAdminPhones().includes(user.phone)) return true;
  return false;
}

/** Ops/support agent: platform OPS_AGENT or OPS_ADMIN membership (or env bootstrap). */
export function isOpsAgent(store: Store, userId: string): boolean {
  return isOpsAdmin(store, userId);
}

export function assertOpsAgent(store: Store, userId: string): void {
  if (!isOpsAgent(store, userId)) throw new Error("forbidden");
}

export type OpsAdminEntry = {
  userId: string;
  phone: string;
  fullName: string;
  source: "DB" | "ENV";
  createdAtUtcMs: number | null;
};

export function listOpsAdmins(store: Store): OpsAdminEntry[] {
  const out: OpsAdminEntry[] = [];
  const seen = new Set<string>();
  for (const m of store.memberships.values()) {
    if (m.role !== "OPS_ADMIN" && m.role !== "OPS_AGENT") continue;
    const user = store.users.get(m.userId);
    if (!user) continue;
    seen.add(user.id);
    out.push({
      userId: user.id,
      phone: user.phone,
      fullName: user.fullName,
      source: "DB",
      createdAtUtcMs: m.createdAtUtcMs,
    });
  }
  for (const envPhone of envOpsAdminPhones()) {
    const user = [...store.users.values()].find((u) => u.phone === envPhone);
    if (!user || seen.has(user.id)) continue;
    out.push({
      userId: user.id,
      phone: user.phone,
      fullName: user.fullName,
      source: "ENV",
      createdAtUtcMs: null,
    });
  }
  return out.sort((a, b) => a.phone.localeCompare(b.phone));
}

function normalizeOpsPhone(raw: string): string {
  const digits = String(raw ?? "").replace(/[^\d]/g, "");
  if (digits.length === 12 && digits.startsWith("91")) return digits.slice(-10);
  if (digits.length === 10) return digits;
  throw new ApiError("invalid_phone", { detail: "Phone must be 10 digits (or +91-prefixed)." });
}

/**
 * Grants OPS_ADMIN to the user with the given phone. The user must already exist
 * (registered as a customer/driver/operator). Creates the platform-ops org if needed.
 */
export function grantOpsAdmin(store: Store, params: { phone: string }): OpsAdminEntry {
  const phone = normalizeOpsPhone(params.phone);
  const user = [...store.users.values()].find((u) => u.phone === phone);
  if (!user) {
    throw new ApiError("user_not_found", {
      detail: "Register this phone (customer or driver) before granting ops-admin.",
    });
  }
  const org = getOrCreatePlatformOpsOrg(store);
  const key = membershipKey(user.id, org.id);
  const existing = store.memberships.get(key);
  if (existing && (existing.role === "OPS_ADMIN" || existing.role === "OPS_AGENT")) {
    return {
      userId: user.id,
      phone: user.phone,
      fullName: user.fullName,
      source: "DB",
      createdAtUtcMs: existing.createdAtUtcMs,
    };
  }
  const m: Membership = {
    userId: user.id,
    orgId: org.id,
    role: "OPS_AGENT",
    createdAtUtcMs: nowUtcMs(),
  };
  store.memberships.set(key, m);
  return {
    userId: user.id,
    phone: user.phone,
    fullName: user.fullName,
    source: "DB",
    createdAtUtcMs: m.createdAtUtcMs,
  };
}

/**
 * Revokes OPS_ADMIN from the user with the given phone. Guards:
 *   - At least one ops admin must remain (counting both DB rows and env-var phones).
 *   - Cannot revoke yourself if you are the last DB ops admin.
 */
export function revokeOpsAdmin(
  store: Store,
  params: { phone: string; actingUserId: string },
): { revoked: boolean } {
  const phone = normalizeOpsPhone(params.phone);
  const user = [...store.users.values()].find((u) => u.phone === phone);
  if (!user) throw new ApiError("user_not_found", {});
  const org = store.organizations.get(PLATFORM_OPS_ORG_ID);
  if (!org) throw new ApiError("ops_admin_not_found", { detail: "No platform-ops org exists." });
  const key = membershipKey(user.id, org.id);
  const m = store.memberships.get(key);
  if (!m || (m.role !== "OPS_ADMIN" && m.role !== "OPS_AGENT")) {
    throw new ApiError("ops_admin_not_found", { detail: "This phone has no DB ops-admin grant." });
  }
  const remainingDb = [...store.memberships.values()].filter(
    (x) => (x.role === "OPS_ADMIN" || x.role === "OPS_AGENT") && x.userId !== user.id,
  ).length;
  const envCount = envOpsAdminPhones().length;
  if (remainingDb + envCount === 0) {
    throw new ApiError("cannot_revoke_last_ops_admin", {
      detail: "At least one ops admin must remain.",
    });
  }
  store.memberships.delete(key);
  return { revoked: true };
}

/** List/detail/POD visibility: org-scoped booking, or anonymous booking tied to the same phone as the logged-in user. */
export function shipmentVisibleToCustomerUser(store: Store, shipment: Shipment, userId: string): boolean {
  const user = store.users.get(userId);
  if (!user) return false;
  for (const org of customerOrgsForUser(store, userId)) {
    if (shipmentBelongsToCustomerOrg(shipment, org)) return true;
  }
  if (shipment.bookedByPhone != null && shipment.bookedByPhone !== "" && shipment.bookedByPhone === user.phone) {
    return true;
  }
  if (shipment.bookedByUserId != null && shipment.bookedByUserId === userId) {
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

/**
 * Team member bootstrap: user account only (no org). They sign in with OTP after an admin invites them.
 */
export function registerCustomerUser(store: Store, params: {
  fullName: string;
  phone: string;
}): { user: User } {
  if (!String(params.fullName ?? "").trim()) throw new Error("invalid_fullName");

  const phone = normalizeInPhone(params.phone);
  const dup = [...store.users.values()].find((u) => u.phone === phone);
  if (dup) throw new Error("phone_already_registered");

  const now = nowUtcMs();
  const user: User = { id: id("usr"), phone, fullName: String(params.fullName).trim(), createdAtUtcMs: now };
  store.users.set(user.id, user);
  return { user };
}

/**
 * Customer org admin invites an existing user (by phone) to the org as CUSTOMER_MEMBER or CUSTOMER_ADMIN.
 * Invitee must register first via POST /v1/pilot/customer/users/register (or business register).
 */
export function inviteCustomerMember(
  store: Store,
  actingUserId: string,
  params: {
    orgId: string;
    phone: string;
    role?: "CUSTOMER_MEMBER" | "CUSTOMER_ADMIN";
  },
): { user: User; membership: Membership; org: Organization } {
  assertCustomerCanInviteMember(store, actingUserId, params.orgId);
  const org = getOrgOrThrow(store, params.orgId);
  if (org.kind !== "CUSTOMER") throw new Error("org_not_customer");

  const phone = normalizeInPhone(params.phone);
  const user = [...store.users.values()].find((u) => u.phone === phone);
  if (!user) {
    throw new ApiError("user_not_found", {
      detail: "Teammate must register their phone first, then you can invite them to your org.",
    });
  }

  const existing = store.memberships.get(membershipKey(user.id, params.orgId));
  if (existing) {
    throw new ApiError("membership_already_exists", { role: existing.role });
  }

  const role = params.role ?? "CUSTOMER_MEMBER";
  if (role !== "CUSTOMER_MEMBER" && role !== "CUSTOMER_ADMIN") throw new Error("invalid_role");

  const now = nowUtcMs();
  const membership: Membership = {
    userId: user.id,
    orgId: params.orgId,
    role,
    createdAtUtcMs: now,
  };
  store.memberships.set(membershipKey(user.id, params.orgId), membership);
  return { user, membership, org };
}

export function listCustomerOrgMembers(
  store: Store,
  actingUserId: string,
  orgId: string,
): Array<{ user: User; membership: Membership }> {
  assertCustomerCanInviteMember(store, actingUserId, orgId);
  const rows: Array<{ user: User; membership: Membership }> = [];
  for (const m of store.memberships.values()) {
    if (m.orgId !== orgId) continue;
    const user = store.users.get(m.userId);
    if (user) rows.push({ user, membership: m });
  }
  rows.sort((a, b) => a.user.fullName.localeCompare(b.user.fullName));
  return rows;
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

export function pilotCarrierOrgIds(store: Store, userId: string): string[] {
  const me = pilotMe(store, userId);
  return me.organizations
    .filter((o) => o.kind === "CARRIER_SOLO" || o.kind === "CARRIER_FLEET" || o.kind === "CARRIER_LEGACY")
    .map((o) => o.id);
}

/** Driver can act on shipments for orgs they belong to as carrier staff. */
export function shipmentVisibleToCarrierPilot(store: Store, shipment: Shipment, userId: string): boolean {
  const ids = new Set(pilotCarrierOrgIds(store, userId));
  return ids.has(shipment.carrierId);
}

export function pilotListCarrierShipments(
  store: Store,
  userId: string,
  params?: { anchorTripId?: string },
): Shipment[] {
  const ids = new Set(pilotCarrierOrgIds(store, userId));
  let list = [...store.shipments.values()].filter((s) => ids.has(s.carrierId));
  const tripId = params?.anchorTripId?.trim();
  if (tripId) list = list.filter((s) => s.anchorTripId === tripId);
  list.sort((a, b) => b.createdAtUtcMs - a.createdAtUtcMs);
  return list;
}

export function pilotCarrierEarningsSummary(store: Store, userId: string, carrierOrgId: string): {
  carrierOrgId: string;
  kycStatus: KycStatus;
  pendingAccruedPaise: number;
  paidPaise: number;
  bookedCount: number;
  deliveredCount: number;
} {
  assertPilotDriverCanManageOrg(store, userId, carrierOrgId);
  const org = getOrgOrThrow(store, carrierOrgId);
  const shipments = [...store.shipments.values()].filter((s) => s.carrierId === carrierOrgId);
  const lines = [...store.ledgerLines.values()].filter((l) => l.carrierId === carrierOrgId);
  const pendingAccruedPaise = lines.filter((l) => l.status === "ACCRUED").reduce((sum, l) => sum + l.netToCarrierPaise, 0);
  const paidPaise = lines.filter((l) => l.status === "PAID").reduce((sum, l) => sum + l.netToCarrierPaise, 0);
  return {
    carrierOrgId,
    kycStatus: org.kycStatus,
    pendingAccruedPaise,
    paidPaise,
    bookedCount: shipments.filter(
      (s) => s.status === "PENDING_CARRIER_ACCEPT" || s.status === "BOOKED" || s.status === "PENDING_RELEASE",
    ).length,
    deliveredCount: shipments.filter((s) => s.status === "DELIVERED").length,
  };
}

export async function pilotSubmitPayoutSetup(
  store: Store,
  userId: string,
  params: { orgId: string; accountHolderName: string; ifsc: string; accountNumber?: string },
): Promise<{ org: Organization; message: string }> {
  assertPilotDriverCanManageOrg(store, userId, params.orgId);
  const org = getOrgOrThrow(store, params.orgId);
  const accountHolderName = String(params.accountHolderName ?? "").trim();
  const ifsc = String(params.ifsc ?? "").trim();
  const accountNumber = String(params.accountNumber ?? "").trim();
  if (!accountHolderName || !ifsc) {
    throw new ApiError("invalid_payout_profile", { detail: "accountHolderName and ifsc are required." });
  }

  // With real payouts enabled, provision a RazorpayX contact + fund account so this
  // carrier can actually receive transfers. Requires a bank account number.
  if (razorpayPayoutsEnabled()) {
    if (!accountNumber) {
      throw new ApiError("invalid_payout_profile", {
        detail: "accountNumber is required to register a bank account for real payouts.",
      });
    }
    try {
      const { contactId, fundAccountId } = await createRazorpayBankFundAccount({
        name: accountHolderName,
        ifsc,
        accountNumber,
        referenceId: org.id,
      });
      const updated: Organization = {
        ...org,
        kycStatus: "APPROVED",
        payoutContactId: contactId,
        payoutFundAccountId: fundAccountId,
      };
      store.organizations.set(org.id, updated);
      return {
        org: updated,
        message:
          "Bank account registered for payouts. Transfers run after POD, cooling-off, and batch settlement — not at signup.",
      };
    } catch (err) {
      throw new ApiError("payout_setup_provider_error", {
        detail: err instanceof Error ? err.message : String(err),
      });
    }
  }

  const updated: Organization = { ...org, kycStatus: "SUBMITTED" };
  store.organizations.set(org.id, updated);
  return {
    org: updated,
    message:
      "Payout details received for verification. Transfers run after POD, cooling-off, and batch settlement — not at signup.",
  };
}

export function pilotListCarrierLedger(store: Store, userId: string, carrierOrgId: string): LedgerLine[] {
  assertPilotDriverCanManageOrg(store, userId, carrierOrgId);
  const lines = [...store.ledgerLines.values()].filter((l) => l.carrierId === carrierOrgId);
  lines.sort((a, b) => b.createdAtUtcMs - a.createdAtUtcMs);
  return lines;
}

export function pilotListCarrierPayoutBatches(store: Store, userId: string, carrierOrgId: string): PayoutBatch[] {
  assertPilotDriverCanManageOrg(store, userId, carrierOrgId);
  const lineIds = new Set(
    [...store.ledgerLines.values()].filter((l) => l.carrierId === carrierOrgId).map((l) => l.id),
  );
  const batches = [...store.payoutBatches.values()].filter((b) => b.lineIds.some((id) => lineIds.has(id)));
  batches.sort((a, b) => b.createdAtUtcMs - a.createdAtUtcMs);
  return batches;
}

export function pilotGetMyAnchorTrip(store: Store, userId: string, tripId: string): AnchorTrip {
  const trips = pilotListMyAnchorTrips(store, userId);
  const t = trips.find((x) => x.id === tripId);
  if (!t) throw new Error("anchor_trip_not_found");
  return t;
}

export function isTripLocationLive(
  loc: TripLiveLocation | undefined,
  nowUtcMs: number,
  staleMs: number = TRIP_TRACKING_STALE_MS,
): boolean {
  if (!loc) return false;
  return nowUtcMs - loc.recordedAtUtcMs <= staleMs;
}

/** Driver pings GPS while on an active trip; stored on the anchor trip for customer tracking. */
export function reportAnchorTripLocation(
  store: Store,
  userId: string,
  tripId: string,
  params: {
    lat: number;
    lng: number;
    recordedAtUtcMs?: number;
    accuracyM?: number;
    speedMps?: number;
    headingDeg?: number;
  },
): AnchorTrip {
  const trip = pilotGetMyAnchorTrip(store, userId, tripId);
  if (trip.status !== "IN_PROGRESS") {
    throw new ApiError("trip_not_started", {
      detail: "Mark the load as started before sending live location.",
      status: trip.status,
    });
  }
  const point: GeoPoint = { lat: params.lat, lng: params.lng };
  assertGeoPoint(point, "location");
  const recordedAtUtcMs = params.recordedAtUtcMs ?? nowUtcMs();
  const lastLiveLocation: TripLiveLocation = {
    lat: params.lat,
    lng: params.lng,
    recordedAtUtcMs,
    ...(params.accuracyM != null && !Number.isNaN(params.accuracyM) ? { accuracyM: params.accuracyM } : {}),
    ...(params.speedMps != null && !Number.isNaN(params.speedMps) ? { speedMps: params.speedMps } : {}),
    ...(params.headingDeg != null && !Number.isNaN(params.headingDeg) ? { headingDeg: params.headingDeg } : {}),
  };
  const updated: AnchorTrip = { ...trip, lastLiveLocation };
  store.anchorTrips.set(trip.id, updated);
  return updated;
}

export function getShipmentTripTracking(
  store: Store,
  userId: string,
  shipmentId: string,
  params?: { nowUtcMs?: number },
): {
  shipment: Shipment;
  trip: AnchorTrip;
  liveLocation: TripLiveLocation | null;
  isLive: boolean;
  staleAfterUtcMs: number;
} {
  const shipment = store.shipments.get(shipmentId);
  if (!shipment) throw new Error("shipment_not_found");
  const visible =
    shipmentVisibleToCustomerUser(store, shipment, userId) ||
    isOpsAdmin(store, userId) ||
    isOpsAgent(store, userId);
  if (!visible) {
    try {
      pilotGetMyAnchorTrip(store, userId, shipment.anchorTripId);
    } catch {
      throw new Error("shipment_not_found");
    }
  }
  const trip = store.anchorTrips.get(shipment.anchorTripId);
  if (!trip) throw new Error("anchor_trip_not_found");
  const now = params?.nowUtcMs ?? nowUtcMs();
  const loc = trip.lastLiveLocation ?? null;
  const fresh = isTripLocationLive(loc ?? undefined, now);
  const tripStarted = trip.status === "IN_PROGRESS";
  const isLive = fresh && shipment.status === "BOOKED" && tripStarted;
  return {
    shipment: shipmentWithCarrierDisplay(store, shipment),
    trip: tripWithCarrierDisplay(store, trip),
    liveLocation: loc,
    isLive,
    staleAfterUtcMs: TRIP_TRACKING_STALE_MS,
  };
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
  /** Authenticated booker (OTP session); scopes GET /shipments even without CUSTOMER org. */
  bookedByUserId?: string;
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
    ...(params.bookedByUserId != null ? { bookedByUserId: params.bookedByUserId } : {}),
    weightKg: params.weightKg,
    pickupAddress: params.pickupAddress,
    dropAddress: params.dropAddress,
    pickup: params.pickup,
    drop: params.drop,
    status: "PENDING_CARRIER_ACCEPT",
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

function finalizeDeliveredShipment(
  store: Store,
  s: Shipment,
  podAtUtcMs: number,
): { shipment: Shipment; ledgerLine: LedgerLine } {
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

/** Driver confirms delivery; payment capture and ledger wait for ops release. */
export function submitDriverPod(
  store: Store,
  params: { shipmentId: string; userId: string; notes?: string },
): Shipment {
  const s = store.shipments.get(params.shipmentId);
  if (!s) throw new Error("shipment_not_found");
  if (!shipmentVisibleToCarrierPilot(store, s, params.userId)) {
    throw new Error("forbidden");
  }
  if (s.status !== "BOOKED") {
    throw new ApiError("shipment_not_deliverable", { status: s.status });
  }
  const pay = store.payments.get(s.paymentId);
  if (!pay) throw new Error("payment_not_found");
  const payOk =
    pay.status === "AUTHORIZED" || (pay.provider === "MOCK" && pay.status === "CAPTURED");
  if (!payOk) {
    throw new ApiError("checkout_not_completed_for_pod", {
      detail: "Customer must complete payment authorization before driver POD.",
      status: pay.status,
    });
  }

  const podAtUtcMs = nowUtcMs();
  const updated: Shipment = {
    ...s,
    status: "PENDING_RELEASE",
    podAtUtcMs,
    podSubmittedByUserId: params.userId,
    ...(params.notes != null && String(params.notes).trim() !== ""
      ? { podNotes: String(params.notes).trim() }
      : {}),
    updatedAtUtcMs: podAtUtcMs,
  };
  store.shipments.set(updated.id, updated);
  return updated;
}

function paymentAuthorizedForCarrierAccept(pay: Payment): boolean {
  return pay.status === "AUTHORIZED" || (pay.provider === "MOCK" && pay.status === "CAPTURED");
}

/** Carrier accepts a customer booking (PENDING_CARRIER_ACCEPT → BOOKED). */
export function acceptCarrierShipment(
  store: Store,
  params: { shipmentId: string; userId: string },
): Shipment {
  const s = store.shipments.get(params.shipmentId);
  if (!s) throw new Error("shipment_not_found");
  if (!shipmentVisibleToCarrierPilot(store, s, params.userId)) {
    throw new Error("forbidden");
  }
  if (s.status !== "PENDING_CARRIER_ACCEPT") {
    throw new ApiError("shipment_not_acceptable", { status: s.status });
  }
  const pay = store.payments.get(s.paymentId);
  if (!pay) throw new Error("payment_not_found");
  if (!paymentAuthorizedForCarrierAccept(pay)) {
    throw new ApiError("checkout_not_completed_for_accept", {
      detail: "Customer must complete payment authorization before carrier can accept.",
      status: pay.status,
    });
  }
  const now = nowUtcMs();
  const updated: Shipment = {
    ...s,
    status: "BOOKED",
    acceptedAtUtcMs: now,
    acceptedByUserId: params.userId,
    updatedAtUtcMs: now,
  };
  store.shipments.set(updated.id, updated);
  return updated;
}

/** Carrier/driver explicitly starts a load (anchor trip → IN_PROGRESS). */
export function startAnchorTripAsPilot(
  store: Store,
  params: { userId: string; tripId: string },
): AnchorTrip {
  const trip = pilotGetMyAnchorTrip(store, params.userId, params.tripId);
  if (trip.status === "IN_PROGRESS") return trip;
  if (trip.status !== "OPEN" && trip.status !== "FULL") {
    throw new ApiError("trip_not_startable", { status: trip.status });
  }
  const hasAccepted = [...store.shipments.values()].some(
    (s) => s.anchorTripId === trip.id && s.status === "BOOKED",
  );
  if (!hasAccepted) {
    throw new ApiError("no_accepted_shipments", {
      detail: "Accept at least one customer booking before starting the trip.",
    });
  }
  const now = nowUtcMs();
  const updated: AnchorTrip = {
    ...trip,
    status: "IN_PROGRESS",
    startedAtUtcMs: now,
    startedByUserId: params.userId,
  };
  store.anchorTrips.set(updated.id, updated);
  return updated;
}

/**
 * Fleet: link an existing user (by phone) to a carrier org as DRIVER or DISPATCHER.
 * The invitee must already be registered; owner/dispatcher calls this.
 */
export function inviteCarrierDriver(
  store: Store,
  actingUserId: string,
  params: {
    orgId: string;
    phone: string;
    role?: "DRIVER" | "DISPATCHER";
    /** Required for DRIVER; ignored for DISPATCHER (uses org's primary vehicle). */
    vehicleRegistrationNumber?: string;
    vehicleClass?: VehicleClass;
    vehicleCapacityKg?: number;
  },
): { user: User; membership: Membership; vehicle: Vehicle; driverProfile: DriverProfile } {
  assertCarrierCanInviteStaff(store, actingUserId, params.orgId);
  const org = getOrgOrThrow(store, params.orgId);
  if (org.kind !== "CARRIER_SOLO" && org.kind !== "CARRIER_FLEET" && org.kind !== "CARRIER_LEGACY") {
    throw new Error("org_not_carrier");
  }
  const phone = normalizeInPhone(params.phone);
  const user = [...store.users.values()].find((u) => u.phone === phone);
  if (!user) {
    throw new ApiError("user_not_found", {
      detail: "Driver must register (OTP) before they can be invited to your carrier org.",
    });
  }
  const existing = store.memberships.get(membershipKey(user.id, params.orgId));
  if (existing) {
    throw new ApiError("membership_already_exists", { role: existing.role });
  }
  const role = params.role ?? "DRIVER";
  if (role !== "DRIVER" && role !== "DISPATCHER") throw new Error("invalid_role");

  const now = nowUtcMs();
  const membership: Membership = {
    userId: user.id,
    orgId: params.orgId,
    role,
    createdAtUtcMs: now,
  };

  let vehicle: Vehicle;
  if (role === "DISPATCHER") {
    const orgVehicle = primaryOrgVehicle(store, params.orgId);
    if (!orgVehicle) {
      throw new ApiError("org_has_no_vehicle", {
        detail: "Carrier org has no vehicle on file; register the owner vehicle first.",
      });
    }
    vehicle = orgVehicle;
  } else {
    assertVehicleClass(params.vehicleClass);
    if ((params.vehicleCapacityKg ?? 0) <= 0) throw new Error("invalid_vehicleCapacityKg");
    if (!String(params.vehicleRegistrationNumber ?? "").trim()) {
      throw new Error("invalid_vehicleRegistrationNumber");
    }
    vehicle = {
      id: id("veh"),
      orgId: params.orgId,
      registrationNumber: String(params.vehicleRegistrationNumber).trim(),
      vehicleClass: params.vehicleClass!,
      capacityKg: params.vehicleCapacityKg!,
      createdAtUtcMs: now,
    };
    store.vehicles.set(vehicle.id, vehicle);
  }

  const driverProfile: DriverProfile = {
    userId: user.id,
    orgId: params.orgId,
    primaryVehicleId: vehicle.id,
    createdAtUtcMs: now,
  };

  if (org.kind === "CARRIER_SOLO") {
    store.organizations.set(params.orgId, { ...org, kind: "CARRIER_FLEET" });
  }

  store.memberships.set(membershipKey(user.id, params.orgId), membership);
  store.driverProfiles.set(user.id, driverProfile);

  return { user, membership, vehicle, driverProfile };
}

/** Ops releases payment after driver POD; captures Razorpay then marks DELIVERED. */
export async function releasePaymentAndDeliver(
  store: Store,
  params: { shipmentId: string; podAtUtcMs?: number },
): Promise<{ shipment: Shipment; ledgerLine: LedgerLine }> {
  const s = store.shipments.get(params.shipmentId);
  if (!s) throw new Error("shipment_not_found");
  if (s.status !== "PENDING_RELEASE") {
    throw new ApiError("shipment_not_pending_release", { status: s.status });
  }
  await ensureRazorpayCapturedBeforePod(store, params.shipmentId);
  const pay = store.payments.get(s.paymentId);
  if (!pay) throw new Error("payment_not_found");
  if (pay.provider !== "MOCK" && pay.status !== "CAPTURED") {
    throw new Error("payment_not_captured");
  }
  const podAtUtcMs = params.podAtUtcMs ?? s.podAtUtcMs ?? nowUtcMs();
  return finalizeDeliveredShipment(store, s, podAtUtcMs);
}

export function opsListPendingRelease(store: Store): Shipment[] {
  return [...store.shipments.values()]
    .filter((s) => s.status === "PENDING_RELEASE")
    .sort((a, b) => (b.podAtUtcMs ?? 0) - (a.podAtUtcMs ?? 0));
}

export function opsListRecentlyDelivered(store: Store, limit = 20): Shipment[] {
  return [...store.shipments.values()]
    .filter((s) => s.status === "DELIVERED")
    .sort((a, b) => (b.podAtUtcMs ?? 0) - (a.podAtUtcMs ?? 0))
    .slice(0, limit);
}

export function opsShipmentDetail(store: Store, shipmentId: string): {
  shipment: Shipment;
  payment: Payment | null;
  carrierOrgName: string;
  podSubmittedBy: User | null;
} {
  const shipment = store.shipments.get(shipmentId);
  if (!shipment) throw new Error("shipment_not_found");
  const payment = store.payments.get(shipment.paymentId) ?? null;
  const org = store.organizations.get(shipment.carrierId);
  const carrierOrgName = org?.displayName ?? shipment.carrierId;
  const podSubmittedBy =
    shipment.podSubmittedByUserId != null
      ? store.users.get(shipment.podSubmittedByUserId) ?? null
      : null;
  return { shipment, payment, carrierOrgName, podSubmittedBy };
}

/** Legacy/admin instant POD: BOOKED + payment already captured (or MOCK). */
export function markPodDelivered(store: Store, params: {
  shipmentId: string;
  podAtUtcMs?: number;
}): { shipment: Shipment; ledgerLine: LedgerLine } {
  const s = store.shipments.get(params.shipmentId);
  if (!s) throw new Error("shipment_not_found");
  if (s.status !== "BOOKED" && s.status !== "PENDING_RELEASE") {
    throw new Error("shipment_not_deliverable");
  }
  if (s.status === "PENDING_RELEASE") {
    throw new ApiError("use_ops_release", {
      detail: "Shipment awaits ops payment release. POST /ops/shipments/:id/release",
    });
  }
  const pay = store.payments.get(s.paymentId);
  if (!pay || pay.status !== "CAPTURED") throw new Error("payment_not_captured");

  const podAtUtcMs = params.podAtUtcMs ?? nowUtcMs();
  return finalizeDeliveredShipment(store, s, podAtUtcMs);
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

/** Client callback after Razorpay Standard Checkout success (webhook may lag or be unset in pilot). */
export function confirmRazorpayCheckoutAuthorization(
  store: Store,
  params: {
    shipmentId: string;
    razorpayOrderId: string;
    razorpayPaymentId: string;
    razorpaySignature: string;
  },
): { payment: Payment } {
  const s = store.shipments.get(params.shipmentId);
  if (!s) throw new Error("shipment_not_found");
  const pay = store.payments.get(s.paymentId);
  if (!pay || pay.provider !== "RAZORPAY") throw new Error("not_razorpay_shipment");
  if (!pay.razorpayOrderId || pay.razorpayOrderId !== params.razorpayOrderId) {
    throw new ApiError("razorpay_order_mismatch", { expected: pay.razorpayOrderId ?? null });
  }
  if (!verifyRazorpayCheckoutSignature(
    params.razorpayOrderId,
    params.razorpayPaymentId,
    params.razorpaySignature,
  )) {
    throw new ApiError("invalid_razorpay_signature", {});
  }
  if (pay.status === "AUTHORIZED" || pay.status === "CAPTURED") {
    return { payment: pay };
  }
  if (pay.status !== "CREATED") {
    throw new ApiError("payment_not_confirmable", { status: pay.status });
  }
  const now = nowUtcMs();
  const updated: Payment = {
    ...pay,
    status: "AUTHORIZED",
    razorpayPaymentId: params.razorpayPaymentId,
    updatedAtUtcMs: now,
  };
  store.payments.set(pay.id, updated);
  return { payment: updated };
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
  if (s.status !== "BOOKED" && s.status !== "PENDING_CARRIER_ACCEPT") {
    throw new Error("shipment_not_refundable");
  }

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

/**
 * Run the next due payout batch.
 *
 * Behaviour is gated by PAYOUTS_MODE:
 *   - BOOKKEEPING (default): ledger lines are marked PAID; no money moves (MVP bookkeeping).
 *   - RAZORPAYX: a real RazorpayX payout is created per carrier (test keys in dev).
 *     Carriers missing a fund account are skipped (lines stay ACCRUED to retry next run);
 *     transfers that error are marked FAILED and their lines stay ACCRUED.
 */
export async function runPayoutBatch(store: Store, params: { nowUtcMs?: number }): Promise<PayoutBatch> {
  const now = params.nowUtcMs ?? Date.now();
  const provider = payoutsMode();
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
      provider,
      transfers: [],
    };
    store.payoutBatches.set(empty.id, empty);
    return empty;
  }

  // Group by cutoff timestamp; for MVP we run one cutoff at a time: the earliest due.
  const earliestCutoff = Math.min(...eligibleLines.map((l) => l.payoutBatchCutoffUtcMs));
  const linesForBatch = eligibleLines.filter((l) => l.payoutBatchCutoffUtcMs === earliestCutoff);

  const batchId = id("pay");

  // One transfer per carrier (money goes to different carriers separately).
  const linesByCarrier = new Map<string, LedgerLine[]>();
  for (const l of linesForBatch) {
    const arr = linesByCarrier.get(l.carrierId) ?? [];
    arr.push(l);
    linesByCarrier.set(l.carrierId, arr);
  }

  const transfers: PayoutTransfer[] = [];
  const settledLineIds: string[] = [];

  for (const [carrierId, lines] of linesByCarrier) {
    const netToCarrierPaise = lines.reduce((sum, l) => sum + l.netToCarrierPaise, 0);
    const lineIds = lines.map((l) => l.id);

    if (provider === "BOOKKEEPING") {
      for (const l of lines) store.ledgerLines.set(l.id, { ...l, status: "PAID", paidAtUtcMs: now });
      settledLineIds.push(...lineIds);
      transfers.push({ carrierId, netToCarrierPaise, lineIds, status: "BOOKKEEPING_PAID" });
      continue;
    }

    // RAZORPAYX mode: needs a fund account on the carrier org.
    const org = store.organizations.get(carrierId);
    const fundAccountId = org?.payoutFundAccountId;
    if (!fundAccountId) {
      transfers.push({ carrierId, netToCarrierPaise, lineIds, status: "SKIPPED_NO_FUND_ACCOUNT" });
      continue; // leave lines ACCRUED so they retry once payout setup completes
    }
    try {
      const result = await createRazorpayPayout({
        amountPaise: netToCarrierPaise,
        fundAccountId,
        referenceId: `${batchId}_${carrierId}`,
        narration: "naviG8r payout",
      });
      const settledStatuses = new Set(["processed", "completed"]);
      const failedStatuses = new Set(["rejected", "cancelled", "reversed"]);
      let transferStatus: PayoutTransfer["status"] = "PROCESSING";
      if (settledStatuses.has(result.status)) transferStatus = "PAID";
      else if (failedStatuses.has(result.status)) transferStatus = "FAILED";

      if (transferStatus === "FAILED") {
        transfers.push({
          carrierId,
          netToCarrierPaise,
          lineIds,
          status: "FAILED",
          providerPayoutId: result.id,
          error: `payout_status_${result.status}`,
        });
        continue; // lines stay ACCRUED to retry
      }
      // PROCESSING or PAID: mark lines PAID (queued/processing payouts are in-flight, not reversible here).
      for (const l of lines) store.ledgerLines.set(l.id, { ...l, status: "PAID", paidAtUtcMs: now });
      settledLineIds.push(...lineIds);
      transfers.push({
        carrierId,
        netToCarrierPaise,
        lineIds,
        status: transferStatus,
        providerPayoutId: result.id,
      });
    } catch (err) {
      transfers.push({
        carrierId,
        netToCarrierPaise,
        lineIds,
        status: "FAILED",
        error: err instanceof Error ? err.message : String(err),
      });
      // lines stay ACCRUED to retry on the next run
    }
  }

  const batch: PayoutBatch = {
    id: batchId,
    cutoffUtcMs: earliestCutoff,
    createdAtUtcMs: now,
    totalNetToCarrierPaise: transfers
      .filter((t) => t.status === "BOOKKEEPING_PAID" || t.status === "PAID" || t.status === "PROCESSING")
      .reduce((sum, t) => sum + t.netToCarrierPaise, 0),
    lineIds: settledLineIds,
    provider,
    transfers,
  };

  store.payoutBatches.set(batch.id, batch);
  return batch;
}

