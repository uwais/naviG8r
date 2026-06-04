/**
 * Carrier payouts (RazorpayX) — gated behind PAYOUTS_MODE.
 *
 * PAYOUTS_MODE:
 *   - "BOOKKEEPING" (default): no money movement; ledger lines are just marked PAID.
 *   - "RAZORPAYX": real RazorpayX payouts via the Payouts REST API (test keys in dev).
 *
 * RazorpayX uses the same key_id/key_secret as customer payments (test mode),
 * plus a source account number (RAZORPAYX_ACCOUNT_NUMBER, the virtual account
 * shown in the RazorpayX dashboard). Carriers must have a fund account id stored
 * on their org (created during payout setup) to receive a transfer.
 */

export type PayoutsMode = "BOOKKEEPING" | "RAZORPAYX";

export function payoutsMode(): PayoutsMode {
  return process.env.PAYOUTS_MODE === "RAZORPAYX" ? "RAZORPAYX" : "BOOKKEEPING";
}

export function razorpayPayoutsEnabled(): boolean {
  return payoutsMode() === "RAZORPAYX";
}

function payoutMode(): string {
  // IMPS | NEFT | RTGS | UPI — IMPS is a safe default for test payouts.
  const m = process.env.RAZORPAYX_PAYOUT_MODE?.trim().toUpperCase();
  return m && m.length > 0 ? m : "IMPS";
}

function basicAuthHeader(): string {
  const key_id = process.env.RAZORPAY_KEY_ID?.trim();
  const key_secret = process.env.RAZORPAY_KEY_SECRET?.trim();
  if (!key_id || !key_secret) throw new Error("missing_razorpay_credentials");
  return "Basic " + Buffer.from(`${key_id}:${key_secret}`).toString("base64");
}

async function razorpayxFetch(path: string, body: unknown): Promise<any> {
  const res = await fetch(`https://api.razorpay.com/v1${path}`, {
    method: "POST",
    headers: {
      authorization: basicAuthHeader(),
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  let parsed: any = {};
  try {
    parsed = text ? JSON.parse(text) : {};
  } catch {
    parsed = { raw: text };
  }
  if (!res.ok) {
    const detail = parsed?.error?.description ?? parsed?.error ?? text ?? `http_${res.status}`;
    throw new Error(`razorpayx_error_${res.status}: ${typeof detail === "string" ? detail : JSON.stringify(detail)}`);
  }
  return parsed;
}

export type RazorpayPayoutResult = {
  id: string;
  status: string;
};

/**
 * Create a single RazorpayX payout to a carrier's fund account.
 * `referenceId` must be unique per payout (we use the batch+carrier key) for idempotency.
 */
export async function createRazorpayPayout(params: {
  amountPaise: number;
  fundAccountId: string;
  referenceId: string;
  narration?: string;
}): Promise<RazorpayPayoutResult> {
  const accountNumber = process.env.RAZORPAYX_ACCOUNT_NUMBER?.trim();
  if (!accountNumber) throw new Error("missing_RAZORPAYX_ACCOUNT_NUMBER");
  if (!params.fundAccountId) throw new Error("missing_fund_account_id");

  const out = await razorpayxFetch("/payouts", {
    account_number: accountNumber,
    fund_account_id: params.fundAccountId,
    amount: params.amountPaise,
    currency: "INR",
    mode: payoutMode(),
    purpose: "payout",
    queue_if_low_balance: true,
    reference_id: params.referenceId.slice(0, 40),
    narration: (params.narration ?? "naviG8r carrier payout").slice(0, 30),
  });
  const id = typeof out?.id === "string" ? out.id : "";
  const status = typeof out?.status === "string" ? out.status : "unknown";
  if (!id) throw new Error("razorpayx_payout_missing_id");
  return { id, status };
}

/**
 * Create a RazorpayX contact + bank fund account for a carrier (payout setup).
 * Returns ids to store on the org so future payouts can target this carrier.
 */
export async function createRazorpayBankFundAccount(params: {
  name: string;
  ifsc: string;
  accountNumber: string;
  referenceId?: string;
}): Promise<{ contactId: string; fundAccountId: string }> {
  const contact = await razorpayxFetch("/contacts", {
    name: params.name.slice(0, 50),
    type: "vendor",
    reference_id: (params.referenceId ?? params.name).slice(0, 40),
  });
  const contactId = typeof contact?.id === "string" ? contact.id : "";
  if (!contactId) throw new Error("razorpayx_contact_missing_id");

  const fa = await razorpayxFetch("/fund_accounts", {
    contact_id: contactId,
    account_type: "bank_account",
    bank_account: {
      name: params.name.slice(0, 50),
      ifsc: params.ifsc.trim().toUpperCase(),
      account_number: params.accountNumber.trim(),
    },
  });
  const fundAccountId = typeof fa?.id === "string" ? fa.id : "";
  if (!fundAccountId) throw new Error("razorpayx_fund_account_missing_id");
  return { contactId, fundAccountId };
}
