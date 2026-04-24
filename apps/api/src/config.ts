import type { WeeklyBatchSchedule } from "../../../packages/core/src/payoutSchedule.ts";

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

