/**
 * Reads a shipper's "Post a load" form into the fields of a posted load, refusing anything outside the rules agreed on
 * 4 Nov 2026: earliest pickup from today to 7 days ahead, a window of at most 3 days, a note of at most 300 characters.
 * Each refusal is a plain error code, as the route form's are.
 */
import { MAX_WEIGHT_KG } from "../../config.ts";
import {
  MAX_DAYS_TO_EARLIEST_PICKUP,
  MAX_NOTE_LENGTH,
  MAX_PICKUP_WINDOW_DAYS,
  daysBetween,
  indiaToday,
  type PostedLoad,
  type PostedLoadPackages,
  type PostedLoadPlace,
} from "./postedLoad.ts";

const MAX_CITY_LENGTH = 80;
const MAX_PACKAGE_COUNT = 10_000;
// Generous: a 40-foot container is about 1,200 cm or 480 inches long, and about 68 cubic metres.
const MAX_PACKAGE_SIDE = 10_000;
const MAX_TOTAL_VOLUME = 100_000;
// Line breaks and tabs are allowed in the note; other control characters are not.
const CONTROL_CHARACTERS = /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/;

function place(raw: any, name: "from" | "to"): PostedLoadPlace {
  const city = typeof raw?.city === "string" ? raw.city.trim() : "";
  const { lat, lng } = raw ?? {};
  const pointOk = typeof lat === "number" && Number.isFinite(lat) && lat >= -90 && lat <= 90
    && typeof lng === "number" && Number.isFinite(lng) && lng >= -180 && lng <= 180;
  if (!city || city.length > MAX_CITY_LENGTH || /[\u0000-\u001f\u007f]/.test(city) || !pointOk) throw new Error(`invalid_${name}`);
  return { city, lat, lng };
}

const positiveUpTo = (value: unknown, max: number): value is number =>
  typeof value === "number" && Number.isFinite(value) && value > 0 && value <= max;

function packages(raw: any): PostedLoadPackages {
  if (raw?.kind === "SIZES") {
    const { count, length, width, height, unit } = raw;
    const sidesOk = [length, width, height].every((side) => positiveUpTo(side, MAX_PACKAGE_SIDE));
    if (Number.isInteger(count) && count >= 1 && count <= MAX_PACKAGE_COUNT && sidesOk && (unit === "INCHES" || unit === "CENTIMETRES")) {
      return { kind: "SIZES", count, length, width, height, unit };
    }
  }
  if (raw?.kind === "TOTAL_VOLUME") {
    const { volume, unit } = raw;
    if (positiveUpTo(volume, MAX_TOTAL_VOLUME) && (unit === "CUBIC_FEET" || unit === "CUBIC_METRES")) return { kind: "TOTAL_VOLUME", volume, unit };
  }
  throw new Error("invalid_packages");
}

/** A real calendar day written YYYY-MM-DD (2026-02-30 is refused). */
function calendarDay(raw: unknown, name: string): string {
  if (typeof raw !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(raw)) throw new Error(`invalid_${name}`);
  const parsed = new Date(`${raw}T00:00:00Z`);
  if (Number.isNaN(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== raw) throw new Error(`invalid_${name}`);
  return raw;
}

function note(raw: unknown): string | undefined {
  if (raw == null) return undefined;
  if (typeof raw !== "string" || CONTROL_CHARACTERS.test(raw)) throw new Error("invalid_note");
  const trimmed = raw.trim();
  if ([...trimmed].length > MAX_NOTE_LENGTH) throw new Error("note_too_long");
  return trimmed || undefined;
}

export type PostedLoadFields = Pick<PostedLoad, "from" | "to" | "weightKg" | "packages" | "earliestPickupDate" | "latestPickupDate" | "note">;

export function readPostedLoadInput(body: any, nowUtcMs: number): PostedLoadFields {
  const from = place(body?.from, "from");
  const to = place(body?.to, "to");
  const weightKg = body?.weightKg;
  if (!positiveUpTo(weightKg, MAX_WEIGHT_KG)) throw new Error("invalid_weightKg");
  const earliestPickupDate = calendarDay(body?.earliestPickupDate, "earliestPickupDate");
  const latestPickupDate = calendarDay(body?.latestPickupDate, "latestPickupDate");
  const today = indiaToday(nowUtcMs);
  if (earliestPickupDate < today) throw new Error("earliest_pickup_in_the_past");
  if (daysBetween(today, earliestPickupDate) > MAX_DAYS_TO_EARLIEST_PICKUP) throw new Error("earliest_pickup_too_far_ahead");
  if (latestPickupDate < earliestPickupDate) throw new Error("latest_pickup_before_earliest");
  if (daysBetween(earliestPickupDate, latestPickupDate) > MAX_PICKUP_WINDOW_DAYS) throw new Error("pickup_window_too_long");
  const shipperNote = note(body?.note);
  return { from, to, weightKg, packages: packages(body?.packages), earliestPickupDate, latestPickupDate, ...(shipperNote ? { note: shipperNote } : {}) };
}
