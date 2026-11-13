/**
 * What of a shipment's e-way bill each caller may see. The record is cut here before it leaves the server,
 * because the general serializer does not filter nested objects.
 */
import type { EwayBill } from "./types.ts";

/**
 * Shipper and ops see everything except user ids. Carrier logins (owner, dispatcher, driver alike) never get
 * the bill date, the maker's GSTIN or the invoice number. Finance and admin get nothing.
 */
export function ewayBillForRoles(bill: EwayBill | undefined, roles: readonly string[]): Record<string, unknown> | undefined {
  if (!bill) return undefined;
  const sharesAll = roles.includes("SHIPPER") || roles.includes("OPS");
  if (!sharesAll && !roles.includes("CARRIER")) return undefined;
  const check = bill.check
    ? { result: bill.check.result, ...(bill.check.problemReason ? { problemReason: bill.check.problemReason } : {}), checkedAtUtcMs: bill.check.checkedAtUtcMs }
    : undefined;
  return {
    kind: bill.kind,
    ...(bill.billNumber ? { billNumber: bill.billNumber } : {}),
    ...(bill.truckNumber ? { truckNumber: bill.truckNumber } : {}),
    ...(bill.validUntilUtcMs ? { validUntilUtcMs: bill.validUntilUtcMs } : {}),
    ...(bill.notNeededReason ? { notNeededReason: bill.notNeededReason } : {}),
    ...(bill.notNeededNote ? { notNeededNote: bill.notNeededNote } : {}),
    ...(check ? { check } : {}),
    ...(sharesAll ? {
      enteredAtUtcMs: bill.enteredAtUtcMs,
      ...(bill.billDate ? { billDate: bill.billDate } : {}),
      ...(bill.makerGstin ? { makerGstin: bill.makerGstin } : {}),
      ...(bill.invoiceNumber ? { invoiceNumber: bill.invoiceNumber } : {}),
    } : {}),
  };
}

/** ERP callers are other systems, not people the shipper chose to show a bill to. */
export function withoutEwayBill<T extends { ewayBill?: unknown }>(shipment: T): Omit<T, "ewayBill"> {
  const copy = { ...shipment };
  delete copy.ewayBill;
  return copy;
}
