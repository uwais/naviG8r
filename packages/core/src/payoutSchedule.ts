/**
 * Payout rule (MVP):
 * Carrier net (X − C) is included in the next weekly batch cutoff that is
 * >= (POD IST calendar date + 7 calendar days) at 00:00 IST.
 *
 * Notes:
 * - IST is UTC+05:30 with no DST, so we can safely compute using a fixed offset.
 * - We store all instants as UTC milliseconds since epoch.
 */

export const PAYOUT_HOLD_CALENDAR_DAYS = 7;

/** IST offset always (India has no DST). */
export const IST_OFFSET_MS = (5 * 60 + 30) * 60 * 1000;

/** 0 = Sunday … 6 = Saturday (JS getDay convention). */
export type JsWeekday = 0 | 1 | 2 | 3 | 4 | 5 | 6;

export type WeeklyBatchSchedule = {
  cutoffWeekday: JsWeekday; // in IST
  cutoffHour: number; // 0-23 (IST)
  cutoffMinute: number; // 0-59 (IST)
};

export type PayoutBatchAssignment = {
  podAtUtcMs: number;
  firstPayoutEligibleAtUtcMs: number;
  payoutBatchCutoffUtcMs: number;
};

function assertWeekday(w: number): asserts w is JsWeekday {
  if (w < 0 || w > 6 || !Number.isInteger(w)) throw new Error(`Invalid weekday ${w}`);
}

/**
 * Get IST wall-clock date parts for a UTC instant by shifting then reading as UTC.
 */
export function istWallClockFromUtc(utcMs: number): {
  year: number;
  monthIndex: number;
  day: number;
  jsWeekday: JsWeekday;
} {
  const shifted = utcMs + IST_OFFSET_MS;
  const d = new Date(shifted);
  const dow = d.getUTCDay();
  assertWeekday(dow);
  return {
    year: d.getUTCFullYear(),
    monthIndex: d.getUTCMonth(),
    day: d.getUTCDate(),
    jsWeekday: dow,
  };
}

/**
 * Convert an IST wall-clock datetime to UTC milliseconds.
 *
 * `year/monthIndex/day/hour/minute/...` are interpreted *as if* they are IST,
 * then shifted back by IST offset to yield the underlying UTC instant.
 */
export function utcMsFromIstWallParts(
  year: number,
  monthIndex: number,
  day: number,
  hour: number,
  minute: number,
  second: number,
  ms: number
): number {
  return Date.UTC(year, monthIndex, day, hour, minute, second, ms) - IST_OFFSET_MS;
}

/**
 * Start of IST day (IST midnight) containing the provided UTC instant.
 */
export function startOfIstDayContainingUtc(utcMs: number): number {
  const { year, monthIndex, day } = istWallClockFromUtc(utcMs);
  return utcMsFromIstWallParts(year, monthIndex, day, 0, 0, 0, 0);
}

/**
 * Add N IST calendar days to the IST date of `utcMs` and return that day's IST midnight (as UTC ms).
 *
 * Implementation detail: we compute using a noon anchor to avoid edge cases when month rolls.
 */
export function addIstCalendarDaysFromUtc(utcMs: number, days: number): number {
  const { year, monthIndex, day } = istWallClockFromUtc(utcMs);
  const noonIstAsUtc = utcMsFromIstWallParts(year, monthIndex, day, 12, 0, 0, 0);
  const shiftedNoon = noonIstAsUtc + days * 86_400_000;
  const { year: y2, monthIndex: m2, day: d2 } = istWallClockFromUtc(shiftedNoon);
  return utcMsFromIstWallParts(y2, m2, d2, 0, 0, 0, 0);
}

/**
 * First moment a POD'd shipment can be included in payout (UTC ms):
 * IST midnight on (POD IST date + 7 calendar days).
 */
export function computeFirstPayoutEligibleAtUtcMs(podAtUtcMs: number): number {
  const podIstMidnightAsUtc = startOfIstDayContainingUtc(podAtUtcMs);
  return addIstCalendarDaysFromUtc(podIstMidnightAsUtc, PAYOUT_HOLD_CALENDAR_DAYS);
}

/**
 * Next weekly batch cutoff instant (UTC ms) whose IST weekday+time is >= `fromUtcMs`.
 */
export function nextWeeklyBatchCutoffUtcMs(
  fromUtcMs: number,
  schedule: WeeklyBatchSchedule
): number {
  assertWeekday(schedule.cutoffWeekday);
  const { cutoffHour: hour, cutoffMinute: minute } = schedule;
  if (
    hour < 0 ||
    hour > 23 ||
    minute < 0 ||
    minute > 59 ||
    !Number.isInteger(hour) ||
    !Number.isInteger(minute)
  ) {
    throw new Error(`Invalid cutoff time hour=${hour} minute=${minute}`);
  }

  const fromIst = istWallClockFromUtc(fromUtcMs);
  const targetDow = schedule.cutoffWeekday;
  const daysUntil = (targetDow - fromIst.jsWeekday + 7) % 7;

  // Candidate cutoff on the same IST date as fromUtcMs.
  let candidate = utcMsFromIstWallParts(fromIst.year, fromIst.monthIndex, fromIst.day, hour, minute, 0, 0);

  if (daysUntil > 0) {
    candidate = utcMsFromIstWallParts(
      fromIst.year,
      fromIst.monthIndex,
      fromIst.day + daysUntil,
      hour,
      minute,
      0,
      0
    );
  } else if (candidate < fromUtcMs) {
    candidate = utcMsFromIstWallParts(
      fromIst.year,
      fromIst.monthIndex,
      fromIst.day + 7,
      hour,
      minute,
      0,
      0
    );
  }

  if (candidate < fromUtcMs) throw new Error("Failed to compute next batch cutoff");
  return candidate;
}

export function computePayoutBatchAssignment(
  podAtUtcMs: number,
  weeklyBatch: WeeklyBatchSchedule
): PayoutBatchAssignment {
  const firstPayoutEligibleAtUtcMs = computeFirstPayoutEligibleAtUtcMs(podAtUtcMs);
  const payoutBatchCutoffUtcMs = nextWeeklyBatchCutoffUtcMs(firstPayoutEligibleAtUtcMs, weeklyBatch);
  return { podAtUtcMs, firstPayoutEligibleAtUtcMs, payoutBatchCutoffUtcMs };
}

