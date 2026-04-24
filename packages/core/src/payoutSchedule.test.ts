import assert from "node:assert/strict";
import test from "node:test";
import {
  addIstCalendarDaysFromUtc,
  computeFirstPayoutEligibleAtUtcMs,
  computePayoutBatchAssignment,
  nextWeeklyBatchCutoffUtcMs,
  startOfIstDayContainingUtc,
  utcMsFromIstWallParts,
} from "./payoutSchedule.ts";

test("startOfIstDayContainingUtc floors to IST midnight", () => {
  // Mar 20 2024 18:30 UTC = Mar 21 2024 00:00 IST
  const pod = Date.UTC(2024, 2, 20, 18, 30, 0, 0);
  const start = startOfIstDayContainingUtc(pod);
  assert.equal(start, utcMsFromIstWallParts(2024, 2, 21, 0, 0, 0, 0));
});

test("first payout eligible is IST midnight POD date + 7 calendar days", () => {
  const pod = Date.UTC(2024, 2, 20, 18, 30, 0, 0); // IST Mar 21
  const eligible = computeFirstPayoutEligibleAtUtcMs(pod);
  assert.equal(eligible, utcMsFromIstWallParts(2024, 2, 28, 0, 0, 0, 0));
});

test("nextWeeklyBatchCutoffUtcMs uses same-week cutoff if not passed", () => {
  // IST Wed Mar 20 2024 10:00 -> Wed 18:00 same day
  const from = utcMsFromIstWallParts(2024, 2, 20, 10, 0, 0, 0);
  const cutoff = nextWeeklyBatchCutoffUtcMs(from, { cutoffWeekday: 3, cutoffHour: 18, cutoffMinute: 0 });
  assert.equal(cutoff, utcMsFromIstWallParts(2024, 2, 20, 18, 0, 0, 0));
});

test("nextWeeklyBatchCutoffUtcMs rolls to next week if same-day cutoff passed", () => {
  const from = utcMsFromIstWallParts(2024, 2, 20, 19, 0, 0, 0); // Wed 19:00 IST
  const cutoff = nextWeeklyBatchCutoffUtcMs(from, { cutoffWeekday: 3, cutoffHour: 18, cutoffMinute: 0 });
  assert.equal(cutoff, utcMsFromIstWallParts(2024, 2, 27, 18, 0, 0, 0));
});

test("end-to-end: POD then eligibility then next Wed 18:00 batch", () => {
  // POD IST: Mar 21, 2024
  const pod = Date.UTC(2024, 2, 20, 18, 30, 0, 0);
  const a = computePayoutBatchAssignment(pod, { cutoffWeekday: 3, cutoffHour: 18, cutoffMinute: 0 });
  // Eligibility: Mar 28 00:00 IST
  assert.equal(a.firstPayoutEligibleAtUtcMs, utcMsFromIstWallParts(2024, 2, 28, 0, 0, 0, 0));
  // Next Wed after Mar 28 is Apr 3 18:00 IST
  assert.equal(a.payoutBatchCutoffUtcMs, utcMsFromIstWallParts(2024, 3, 3, 18, 0, 0, 0));
});

test("addIstCalendarDaysFromUtc handles month overflow", () => {
  const base = utcMsFromIstWallParts(2024, 0, 30, 0, 0, 0, 0); // Jan 30 IST
  const out = addIstCalendarDaysFromUtc(base, 7); // Feb 6 IST
  assert.equal(out, utcMsFromIstWallParts(2024, 1, 6, 0, 0, 0, 0));
});

