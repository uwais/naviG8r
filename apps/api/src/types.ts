export type VehicleClass = "SMALL" | "MEDIUM" | "LARGE";

export type OrgKind = "CARRIER_SOLO" | "CARRIER_FLEET" | "CUSTOMER" | "CARRIER_LEGACY";

export type KycStatus = "NOT_STARTED" | "SUBMITTED" | "APPROVED" | "REJECTED";

export type MembershipRole = "OWNER_DRIVER" | "OWNER" | "DISPATCHER" | "DRIVER" | "CUSTOMER_ADMIN";

export type AnchorTripStatus = "OPEN" | "FULL" | "COMPLETED";

export type ShipmentStatus =
  | "BOOKED"
  | "DELIVERED"
  | "FAILED_CARRIER_REFUNDED";

export type LedgerLineStatus = "ACCRUED" | "PAID";

export type PaymentStatus = "CAPTURED" | "REFUNDED";

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

export type AnchorTrip = {
  id: string;
  carrierId: string;
  originCity: string;
  destCity: string;
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
  customerOrgName: string;
  weightKg: number;
  pickupAddress: string;
  dropAddress: string;
  status: ShipmentStatus;
  // Money in paise
  grossPaise: number;
  commissionPaise: number;
  netToCarrierPaise: number;
  paymentId: string;
  podAtUtcMs: number | null;
  firstPayoutEligibleAtUtcMs: number | null;
  payoutBatchCutoffUtcMs: number | null;
  createdAtUtcMs: number;
  updatedAtUtcMs: number;
};

export type Payment = {
  id: string;
  shipmentId: string;
  amountPaise: number;
  status: PaymentStatus;
  provider: "MOCK";
  providerRef: string;
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

