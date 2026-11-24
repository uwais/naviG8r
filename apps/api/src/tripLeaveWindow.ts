/**
 * A trip's leave window ends with its last leaving day, by the date in India. From the next India day the trip is
 * no longer on offer: shippers do not see it in Book a trip or route search, and booking it is refused. Nothing is
 * stored; the trip keeps its status, and a trip with bookings carries on as before.
 */
import { indiaDateString } from "./ewayBillValidation.ts";
import type { AnchorTrip } from "./types.ts";

/** A windowEnd that does not parse never ends, so a bad date cannot hide a trip. */
export function leaveWindowEnded(trip: Pick<AnchorTrip, "windowEnd">, nowUtcMs: number): boolean {
  const endUtcMs = Date.parse(trip.windowEnd);
  if (Number.isNaN(endUtcMs)) return false;
  return indiaDateString(endUtcMs) < indiaDateString(nowUtcMs);
}
