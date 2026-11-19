type Bucket = { startedAtUtcMs: number; count: number };

/** Small single-process fixed-window limiter for routes on the single-writer API. */
export class FixedWindowRateLimiter {
  private readonly buckets = new Map<string, Bucket>();

  /** With a cap, a new key past it drops the key whose window started first. */
  readonly maxKeys: number;

  constructor(maxKeys = Number.POSITIVE_INFINITY) {
    this.maxKeys = maxKeys;
  }

  consume(key: string, limit: number, windowMs: number, now = Date.now()): { allowed: boolean; retryAfterSeconds: number } {
    let bucket = this.buckets.get(key);
    if (!bucket || now - bucket.startedAtUtcMs >= windowMs || now < bucket.startedAtUtcMs) {
      bucket = { startedAtUtcMs: now, count: 0 };
      this.buckets.delete(key);
      this.buckets.set(key, bucket);
      while (this.buckets.size > this.maxKeys) this.buckets.delete(this.buckets.keys().next().value!);
    }
    if (bucket.count >= limit) {
      return {
        allowed: false,
        retryAfterSeconds: Math.max(1, Math.ceil((bucket.startedAtUtcMs + windowMs - now) / 1000)),
      };
    }
    bucket.count += 1;
    if (this.buckets.size > 50_000) {
      const oldestAllowed = now - windowMs * 2;
      for (const [entryKey, value] of this.buckets) {
        if (value.startedAtUtcMs < oldestAllowed) this.buckets.delete(entryKey);
      }
    }
    return { allowed: true, retryAfterSeconds: 0 };
  }
}
