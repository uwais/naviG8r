import crypto from "node:crypto";

/** Customer payments via Razorpay (test keys in dev). Authorize-only orders → capture at POD (see services). */

export function razorpayPaymentsEnabled(): boolean {
  return process.env.PAYMENT_PROVIDER === "RAZORPAY";
}

export function publicRazorpayKeyId(): string | undefined {
  const id = process.env.RAZORPAY_KEY_ID;
  return id && id.trim().length > 0 ? id.trim() : undefined;
}

// Lazy-loaded so Node tests boot without `npm install` under apps/api.

type Razor = InstanceType<Awaited<typeof import("razorpay")>["default"]>;
let cachedRzp: Razor | null = null;

async function getRzp(): Promise<Razor> {
  if (cachedRzp) return cachedRzp;
  let Razorpay: (typeof import("razorpay"))["default"];
  try {
    ({ default: Razorpay } = await import("razorpay"));
  } catch {
    throw new Error(
      "razorpay_dependency_missing_run_npm_install_in_apps_api_then_prisma_generate_if_using_db_mode",
    );
  }
  const key_id = process.env.RAZORPAY_KEY_ID?.trim();
  const key_secret = process.env.RAZORPAY_KEY_SECRET?.trim();
  if (!key_id || !key_secret) {
    throw new Error("missing_razorpay_credentials");
  }
  cachedRzp = new Razorpay({ key_id, key_secret });
  return cachedRzp;
}

export async function createAuthorizeOnlyOrder(amountPaise: number, receiptShipmentId: string): Promise<{ id: string }> {
  const rzp = await getRzp();
  const receiptBase = receiptShipmentId.replace(/[^\w\-]/g, "").slice(0, 36);
  const receipt = receiptBase.length >= 6 ? receiptBase : receiptShipmentId.slice(0, 36).replace(/[^\w\-]/g, "x");

  const order = await rzp.orders.create({
    amount: amountPaise,
    currency: "INR",
    receipt,
    payment_capture: false,
  });
  const oid = typeof order?.id === "string" ? order.id : "";
  if (!oid) throw new Error("razorpay_order_missing_id");
  return { id: oid };
}

/** True when Razorpay rejects capture because the payment is already captured. */
export function isRazorpayAlreadyCapturedError(err: unknown): boolean {
  const msg = String((err as Error)?.message ?? err ?? "").toLowerCase();
  return (
    msg.includes("already been captured") ||
    msg.includes("already_captured") ||
    msg.includes("payment_already_captured") ||
    (msg.includes("captured") && msg.includes("already"))
  );
}

/** True when Razorpay rejects refund because the payment is already fully refunded. */
export function isRazorpayAlreadyRefundedError(err: unknown): boolean {
  const msg = String((err as Error)?.message ?? err ?? "").toLowerCase();
  return (
    msg.includes("already refunded") ||
    msg.includes("already_refunded") ||
    msg.includes("payment_already_refunded") ||
    (msg.includes("refund") && msg.includes("fully"))
  );
}

export async function captureRazorpayPayment(paymentId: string, amountPaise: number): Promise<void> {
  const rzp = await getRzp();
  try {
    await rzp.payments.capture(paymentId, amountPaise, "INR");
  } catch (e) {
    // Idempotent retry after gateway success + local crash/persist loss.
    if (!isRazorpayAlreadyCapturedError(e)) throw e;
  }
}

export async function razorpayRefundPayment(paymentId: string, amountPaise?: number): Promise<void> {
  const rzp = await getRzp();
  try {
    if (amountPaise != null) {
      await rzp.payments.refund(paymentId, { amount: amountPaise });
    } else {
      await rzp.payments.refund(paymentId);
    }
  } catch (e) {
    if (!isRazorpayAlreadyRefundedError(e)) throw e;
  }
}

export function verifyRazorpayWebhookSignature(payload: string, signatureHeader: string | undefined, secret: string): boolean {
  if (!signatureHeader || !payload || !secret) return false;
  const expected = crypto.createHmac("sha256", secret).update(payload).digest("hex");
  return timingSafeHexEqual(signatureHeader, expected);
}

/** Standard Checkout success callback: HMAC-SHA256 of `order_id|payment_id`. */
export function verifyRazorpayCheckoutSignature(
  orderId: string,
  paymentId: string,
  signature: string,
): boolean {
  const secret = process.env.RAZORPAY_KEY_SECRET?.trim();
  if (!secret || !orderId || !paymentId || !signature) return false;
  const expected = crypto.createHmac("sha256", secret).update(`${orderId}|${paymentId}`).digest("hex");
  return timingSafeHexEqual(signature, expected);
}

function timingSafeHexEqual(a: string, b: string): boolean {
  try {
    const ba = Buffer.from(a);
    const bb = Buffer.from(b);
    return ba.length === bb.length && crypto.timingSafeEqual(ba, bb);
  } catch {
    return false;
  }
}
