/**
 * Format checks for the bank details a carrier gives us for payouts.
 *
 * This catches typos. It does NOT verify that the account exists or belongs to
 * the person claiming it - that needs a penny-drop against a bank, which is a
 * paid external call and a separate decision. Anything here passing means only
 * "this is shaped like a real account", never "this account is real".
 *
 * The limits come from RazorpayX, because RazorpayX is what rejects these
 * downstream: a local rule stricter than the real consumer locks out valid
 * carriers, and one looser than it just moves the failure to payout day, which
 * is the worst moment to discover a typo. Sources are named per rule below.
 */

/** Result of a check. Deliberately not an exception: validation should not know about HTTP. */
export type BankDetailsCheck =
  | { ok: true; value: { accountHolderName: string; ifsc: string; accountNumber: string } }
  | { ok: false; field: "accountHolderName" | "ifsc" | "accountNumber"; detail: string };

/**
 * RBI format: 11 characters, first four alphabetic for the bank, fifth always
 * zero and reserved, last six the branch - "usually numeric, but can be
 * alphabetic" (en.wikipedia.org/wiki/Indian_Financial_System_Code).
 */
const IFSC_PATTERN = /^[A-Z]{4}0[A-Z0-9]{6}$/;

/**
 * RazorpayX: 5 to 35 characters, a-z A-Z 0-9. Letters are allowed on purpose -
 * several Indian banks issue alphanumeric account numbers, so a digits-only
 * rule would refuse real accounts.
 */
const ACCOUNT_NUMBER_PATTERN = /^[A-Za-z0-9]{5,35}$/;

/**
 * Letters, digits, space and ' - _ / ( ) , . &
 *
 * The ampersand is here because "Kumar & Sons Transport" and "M/s Sharma & Co."
 * are ordinary Indian carrier names, and the first version of this file rejected
 * both. That is the failure this module's header warns about, committed in the
 * module itself.
 *
 * Capped at 50, not RazorpayX's documented 120, because razorpayPayouts.ts:107
 * and :118 both truncate with slice(0, 50) before sending. Validating to 120
 * would accept a name, silently cut it, and send the provider something the
 * carrier never typed.
 */
const ACCOUNT_HOLDER_NAME_PATTERN = /^[A-Za-z0-9 '\-_/(),.&]{3,50}$/;

/** A name made only of punctuation is not a name: "..." passed the pattern above. */
const CONTAINS_A_LETTER = /[A-Za-z]/;

/** Non-ASCII is rejected before upper-casing, because some characters expand when
 * upper-cased and would produce a valid-looking IFSC the carrier never typed. */
const ASCII_ONLY = /^[\x00-\x7F]*$/;

/**
 * Checks the three fields and returns them normalised: IFSC upper-cased, the
 * rest trimmed. Callers should store what comes back rather than what went in,
 * so a lower-case IFSC does not reach the payout provider.
 *
 * `accountNumber` is optional because it is only required once real payouts are
 * switched on; pass an empty string when it is not being collected and it is
 * skipped rather than rejected.
 */
export function validatePayoutBankDetails(input: {
  accountHolderName?: string;
  ifsc?: string;
  accountNumber?: string;
}): BankDetailsCheck {
  const accountHolderName = String(input.accountHolderName ?? "").trim();
  const ifscRaw = String(input.ifsc ?? "").trim();
  const ifsc = ASCII_ONLY.test(ifscRaw) ? ifscRaw.toUpperCase() : ifscRaw;
  const accountNumber = String(input.accountNumber ?? "").trim();

  if (!accountHolderName) {
    return { ok: false, field: "accountHolderName", detail: "Account holder name is required." };
  }
  if (!ACCOUNT_HOLDER_NAME_PATTERN.test(accountHolderName)) {
    return {
      ok: false,
      field: "accountHolderName",
      detail:
        "Account holder name must be 3 to 50 characters and use only letters, numbers, spaces and ' - _ / ( ) , . &",
    };
  }
  if (!CONTAINS_A_LETTER.test(accountHolderName)) {
    return { ok: false, field: "accountHolderName", detail: "Account holder name must contain a letter." };
  }

  if (!ifsc) {
    return { ok: false, field: "ifsc", detail: "IFSC is required." };
  }
  if (!IFSC_PATTERN.test(ifsc)) {
    return {
      ok: false,
      field: "ifsc",
      detail:
        "IFSC must be 11 characters: four letters for the bank, then 0, then six letters or digits for the branch. Example: HDFC0000123.",
    };
  }

  // Empty means not being collected yet, which is allowed. A value that is
  // present but malformed is not.
  if (accountNumber && !ACCOUNT_NUMBER_PATTERN.test(accountNumber)) {
    return {
      ok: false,
      field: "accountNumber",
      detail: "Account number must be 5 to 35 letters or digits, with no spaces or punctuation.",
    };
  }

  return { ok: true, value: { accountHolderName, ifsc, accountNumber } };
}
