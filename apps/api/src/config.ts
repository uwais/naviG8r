import type { WeeklyBatchSchedule } from "../../../packages/core/src/payoutSchedule.ts";
import type { VehicleClass } from "./types.ts";

export const PAYOUT_BATCH_SCHEDULE: WeeklyBatchSchedule = {
  cutoffWeekday: 3, // Wednesday
  cutoffHour: 18,
  cutoffMinute: 0,
};

export const COMMISSION_BPS = 1000; // 10%

/**
 * MVP quote: ₹5/kg (in paise).
 * Replace with lane-based rate cards + detour rules later.
 */
export const PRICE_PAISE_PER_KG = 500;

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

