import type { WeeklyBatchSchedule } from "../../../packages/core/src/payoutSchedule.ts";
import type { VehicleClass } from "./types.ts";

export const PAYOUT_BATCH_SCHEDULE: WeeklyBatchSchedule = {
  cutoffWeekday: 3, // Wednesday
  cutoffHour: 18,
  cutoffMinute: 0,
};

export const COMMISSION_BPS = 1000; // 10%

/** Driver location older than this is not shown as "live" to customers. */
export const TRIP_TRACKING_STALE_MS = 15 * 60 * 1000;

/**
 * MVP quote: ₹5/kg (in paise).
 * Replace with lane-based rate cards + detour rules later.
 */
export const PRICE_PAISE_PER_KG = 500;

/** The most a booking may weigh, or a trip or truck carry, in kilograms. */
export const MAX_WEIGHT_KG = 100_000;

/** How long after booking the shipper is told to pay, or the booking closes and stops holding room on its trip. */
export const UNPAID_BOOKING_EXPIRY_MS = 30 * 60 * 1000;

/** The booking closes only this long after UNPAID_BOOKING_EXPIRY_MS, so a payment finished just in time still lands. */
export const UNPAID_BOOKING_GRACE_MS = 10 * 60 * 1000;

/** What the shipper is told when an unpaid booking closes. */
export const BOOKING_EXPIRED_SENTENCE = `This booking expired because it was not paid within ${UNPAID_BOOKING_EXPIRY_MS / 60_000} minutes.`;

/** Said after it when the shipper may have paid: Razorpay releases a hold it never captured, and the bank adds its own days. */
export const BOOKING_EXPIRED_MONEY_SENTENCE = "If your bank shows a payment, it comes back within 3 days of when you paid. Your bank may take 5-7 more working days.";

/** Bump when distance/weight formula or defaults change (returned on quote/estimate). */
export const FREIGHT_MODEL_VERSION = "freight-v1";

const DEFAULT_FREIGHT_PAISE_PER_KM: Record<VehicleClass, number> = {
  SMALL: 1500,
  MEDIUM: 2000,
  LARGE: 2500,
};

/** Paise per km for `vehicleClass`; override with `FREIGHT_PAISE_PER_KM_SMALL` etc. */
export function freightPaisePerKmForClass(vc: VehicleClass): number {
  const envKey = `FREIGHT_PAISE_PER_KM_${vc}`;
  const raw = process.env[envKey];
  const n = raw != null ? Number(raw) : NaN;
  if (Number.isFinite(n) && n >= 0) return n;
  return DEFAULT_FREIGHT_PAISE_PER_KM[vc];
}

/** Minimum gross charge in paise when distance is in the price (0 = no floor). */
export function freightMinGrossPaise(): number {
  const n = Number(process.env.FREIGHT_MIN_GROSS_PAISE ?? "0");
  return Number.isFinite(n) && n > 0 ? Math.floor(n) : 0;
}

