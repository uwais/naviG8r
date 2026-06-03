export type VehicleClass = "SMALL" | "MEDIUM" | "LARGE";

export type OrgKind = "CARRIER_SOLO" | "CARRIER_FLEET" | "CUSTOMER" | "CARRIER_LEGACY" | "PLATFORM";

export type KycStatus = "NOT_STARTED" | "SUBMITTED" | "APPROVED" | "REJECTED";

export type MembershipRole =
  | "OWNER_DRIVER"
  | "OWNER"
  | "DISPATCHER"
  | "DRIVER"
  | "CUSTOMER_ADMIN"
  | "OPS_ADMIN"
  | "OPS_AGENT";

export type AnchorTripStatus = "OPEN" | "FULL" | "COMPLETED";

export type ShipmentStatus =
  | "BOOKED"
  | "PENDING_RELEASE"
  | "DELIVERED"
  | "FAILED_CARRIER_REFUNDED";

export type LedgerLineStatus = "ACCRUED" | "PAID";

export type PaymentStatus = "CREATED" | "AUTHORIZED" | "CAPTURED" | "FAILED" | "REFUNDED";

/**
 * @deprecated Legacy demo entity. Prefer {@link Organization}.
 * Kept for backwards compatibility with older store.json files and /carriers routes.
 */
export type Carrier = {
  id: string;
  name: string;
  createdAtUtcMs: number;
};

export type Organization = {
  id: string;
  kind: OrgKind;
  displayName: string;
  kycStatus: KycStatus;
  createdAtUtcMs: number;
};

export type User = {
  id: string;
  phone: string;
  fullName: string;
  createdAtUtcMs: number;
};

export type Membership = {
  userId: string;
  orgId: string;
  role: MembershipRole;
  createdAtUtcMs: number;
};

export type Vehicle = {
  id: string;
  orgId: string;
  registrationNumber: string;
  vehicleClass: VehicleClass;
  capacityKg: number;
  createdAtUtcMs: number;
};

export type DriverProfile = {
  userId: string;
  orgId: string;
  primaryVehicleId: string;
  createdAtUtcMs: number;
};

export type OtpChallengeStatus = "PENDING" | "CONSUMED" | "EXPIRED";

/**
 * Pilot OTP challenge (mock SMS). Replace with real SMS + rate limits in production.
 */
export type OtpChallenge = {
  id: string;
  phone: string;
  code: string;
  status: OtpChallengeStatus;
  expiresAtUtcMs: number;
  createdAtUtcMs: number;
};

export type AuthSession = {
  id: string;
  userId: string;
  createdAtUtcMs: number;
  expiresAtUtcMs: number;
  revokedAtUtcMs: number | null;
};

export type GeoPoint = {
  lat: number;
  lng: number;
  placeId?: string;
  label?: string;
};

export type AnchorTrip = {
  id: string;
  carrierId: string;
  originCity: string;
  destCity: string;
  /** Optional location-based origin. */
  origin?: GeoPoint;
  /** Optional location-based destination. */
  destination?: GeoPoint;
  /** ISO 8601. */
  windowStart: string;
  /** ISO 8601. */
  windowEnd: string;
  vehicleClass: VehicleClass;
  capacityKg: number;
  reservedKg: number;
  status: AnchorTripStatus;
  createdAtUtcMs: number;
};

export type Shipment = {
  id: string;
  anchorTripId: string;
  carrierId: string;
  /** Set when booked with a logged-in customer; used to scope GET /shipments. */
  customerOrgId?: string;
  customerOrgName: string;
  /** Normalized India mobile; optional on anonymous book so the same user can list via OTP + phone match. */
  bookedByPhone?: string;
  weightKg: number;
  pickupAddress: string;
  dropAddress: string;
  /** Optional location-based pickup. */
  pickup?: GeoPoint;
  /** Optional location-based drop. */
  drop?: GeoPoint;
  status: ShipmentStatus;
  // Money in paise
  grossPaise: number;
  commissionPaise: number;
  netToCarrierPaise: number;
  paymentId: string;
  podAtUtcMs: number | null;
  /** User who submitted driver POD (ops release follows). */
  podSubmittedByUserId?: string;
  podNotes?: string;
  firstPayoutEligibleAtUtcMs: number | null;
  payoutBatchCutoffUtcMs: number | null;
  createdAtUtcMs: number;
  updatedAtUtcMs: number;
};

export type PaymentProviderId = "MOCK" | "RAZORPAY";

export type Payment = {
  id: string;
  shipmentId: string;
  amountPaise: number;
  status: PaymentStatus;
  provider: PaymentProviderId;
  /** MOCK ref, Razorpay order id once created, or payment id alias for debugging */
  providerRef: string;
  /** Set after Razorpay order create (manual authorize/capture flow). */
  razorpayOrderId?: string;
  /** Set after payment authorized (checkout success / webhook). */
  razorpayPaymentId?: string;
  createdAtUtcMs: number;
  updatedAtUtcMs: number;
};

export type LedgerLine = {
  id: string;
  shipmentId: string;
  carrierId: string;
  grossPaise: number;
  commissionPaise: number;
  netToCarrierPaise: number;
  podAtUtcMs: number;
  firstPayoutEligibleAtUtcMs: number;
  payoutBatchCutoffUtcMs: number;
  status: LedgerLineStatus;
  createdAtUtcMs: number;
  paidAtUtcMs: number | null;
};

export type PayoutBatch = {
  id: string;
  cutoffUtcMs: number;
  createdAtUtcMs: number;
  totalNetToCarrierPaise: number;
  lineIds: string[];
};

