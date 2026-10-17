/**
 * Format check for a carrier's transporter ID: the 15 characters an e-way bill names its transporter by, the
 * carrier's GSTIN or, for a transporter with no GST registration, the TRANSIN the e-way bill portal gives it (CBIC
 * e-way bill FAQ, 2019). Shape only: a pass does not show that the ID exists or is this carrier's.
 */

/** Result of a check. Not an exception, so services.ts can call it without this file knowing about HTTP. */
export type TransporterIdCheck =
  | { ok: true; value: string | undefined }
  | { ok: false; field: "transporterId"; detail: string };

/** Two digits, then 13 letters or digits. Checked before upper-casing, so no letter can turn into two. */
const TRANSPORTER_ID_PATTERN = /^[0-9]{2}[A-Za-z0-9]{13}$/;

/**
 * Null, or nothing but spaces, means no transporter ID: none given at sign-up, or the owner cleared it. Anything
 * else must be a string of the right shape once its spaces are removed; it comes back upper-cased.
 */
export function checkTransporterId(raw: unknown): TransporterIdCheck {
  if (raw === null) return { ok: true, value: undefined };
  const typed = typeof raw === "string" ? raw.replace(/\s/g, "") : undefined;
  if (typed === "") return { ok: true, value: undefined };
  if (typed === undefined || !TRANSPORTER_ID_PATTERN.test(typed)) {
    return { ok: false, field: "transporterId", detail: "A transporter ID is 15 letters and digits, starting with two digits: your GSTIN, or the TRANSIN from the e-way bill portal. Leave it empty if you do not have one." };
  }
  return { ok: true, value: typed.toUpperCase() };
}
