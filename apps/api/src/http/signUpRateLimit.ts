import { FixedWindowRateLimiter } from "./rateLimit.ts";

/**
 * Sign-up needs no account and answers whether a number already has one, so each IP and each phone get
 * a few tries: the same limits as sign-in code requests, 30 per IP in 10 minutes and 5 per phone in an hour.
 * Pass a null IP when the caller's address cannot be trusted; only the phone is counted then.
 */
export function createSignUpRateLimit() {
  // One limiter per window, so trimming the IP counts never resets a phone's count, or the reverse.
  const perIp = new FixedWindowRateLimiter(10_000);
  const perPhone = new FixedWindowRateLimiter(10_000);
  return (clientIp: string | null, phone: string, now = Date.now()): { allowed: boolean; retryAfterSeconds: number } => {
    if (clientIp !== null) {
      const ipLimit = perIp.consume(clientIp, 30, 600_000, now);
      if (!ipLimit.allowed) return ipLimit;
    }
    return perPhone.consume(phone.replace(/\D/g, "").slice(-10), 5, 3_600_000, now);
  };
}
