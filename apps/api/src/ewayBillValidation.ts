/**
 * Format checks for the e-way bill details a shipper types in from the government portal.
 *
 * This catches typos. It does NOT show that the bill exists, is current, or belongs to this
 * shipment: only a person looking it up on the portal can do that, and naviG8r ops does it by
 * hand. A pass here means "shaped like a bill", never "this bill is real".
 *
 * Deliberately lenient where the shape is not confirmed: the invoice number is any short printable
 * text, because refusing a real invoice number is worse than accepting an odd one that ops then
 * fails to find on the portal.
 */
import type { EwayBillNotNeededReason } from "./types.ts";

export type EwayBillDetailsCheck =
  | { ok: true; value: { billNumber: string; billDate: string; makerGstin: string; invoiceNumber: string } }
  | { ok: false; field: "billNumber" | "billDate" | "makerGstin" | "invoiceNumber"; detail: string };

export type EwayBillStatementCheck =
  | { ok: true; value: { reason: EwayBillNotNeededReason; note?: string } }
  | { ok: false; field: "reason" | "note"; detail: string };

/** A bill number is 12 digits (CBIC e-way bill FAQ, read 3 Oct 2026). People paste it as "1234 5678 9012". */
const BILL_NUMBER_PATTERN = /^[0-9]{12}$/;
/** Two-digit state code, ten-character PAN, entity number, the letter Z, a check character. Shape only; the check character is not computed. */
const GSTIN_PATTERN = /^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$/;
const DATE_PATTERN = /^([0-9]{4})-([0-9]{2})-([0-9]{2})$/;
const PRINTABLE_ASCII = /^[\x20-\x7E]+$/;
const NOT_NEEDED_REASONS: readonly string[] = ["BELOW_THRESHOLD", "GOODS_EXEMPT", "OTHER"];

const INDIA_OFFSET_MS = 5.5 * 60 * 60 * 1000;

/** Today's date in India as YYYY-MM-DD. */
export function indiaDateString(nowUtcMs: number): string {
  return new Date(nowUtcMs + INDIA_OFFSET_MS).toISOString().slice(0, 10);
}

function isRealCalendarDate(text: string): boolean {
  const match = DATE_PATTERN.exec(text);
  if (!match) return false;
  const [year, month, day] = [Number(match[1]), Number(match[2]), Number(match[3])];
  const date = new Date(Date.UTC(year, month - 1, day));
  return date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day;
}

export function checkEwayBillDetails(input: Record<string, unknown>, nowUtcMs: number): EwayBillDetailsCheck {
  const billNumber = String(input.billNumber ?? "").replace(/[\s-]/g, "");
  if (!BILL_NUMBER_PATTERN.test(billNumber)) {
    return { ok: false, field: "billNumber", detail: "The e-way bill number is 12 digits." };
  }
  const billDate = String(input.billDate ?? "").trim();
  if (!isRealCalendarDate(billDate)) {
    return { ok: false, field: "billDate", detail: "Choose the date shown on the e-way bill." };
  }
  if (billDate > indiaDateString(nowUtcMs)) {
    return { ok: false, field: "billDate", detail: "The bill date cannot be in the future." };
  }
  const makerGstin = String(input.makerGstin ?? "").replace(/\s/g, "").toUpperCase();
  if (!GSTIN_PATTERN.test(makerGstin)) {
    return { ok: false, field: "makerGstin", detail: "The GSTIN is 15 letters and digits, for example 29ABCDE1234F1Z5." };
  }
  const invoiceNumber = String(input.invoiceNumber ?? "").trim();
  if (invoiceNumber.length < 1 || invoiceNumber.length > 32 || !PRINTABLE_ASCII.test(invoiceNumber)) {
    return { ok: false, field: "invoiceNumber", detail: "Type the invoice number, up to 32 characters." };
  }
  return { ok: true, value: { billNumber, billDate, makerGstin, invoiceNumber } };
}

export function checkEwayBillStatement(input: Record<string, unknown>): EwayBillStatementCheck {
  const reason = String(input.reason ?? "");
  if (!NOT_NEEDED_REASONS.includes(reason)) {
    return { ok: false, field: "reason", detail: "Choose why no e-way bill is needed." };
  }
  if (reason !== "OTHER") return { ok: true, value: { reason: reason as EwayBillNotNeededReason } };
  const note = String(input.note ?? "").trim();
  if (note.length < 3 || note.length > 140) {
    return { ok: false, field: "note", detail: "Write the reason in 3 to 140 characters." };
  }
  return { ok: true, value: { reason: "OTHER", note } };
}
