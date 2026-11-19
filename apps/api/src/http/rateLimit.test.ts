import assert from "node:assert/strict";
import test from "node:test";
import { FixedWindowRateLimiter } from "./rateLimit.ts";

test("a limiter with a key cap drops the oldest window first", () => {
  const limiter = new FixedWindowRateLimiter(2);
  assert.equal(limiter.consume("first", 1, 60_000, 1_000).allowed, true);
  assert.equal(limiter.consume("first", 1, 60_000, 1_001).allowed, false);
  assert.equal(limiter.consume("second", 1, 60_000, 1_002).allowed, true);
  assert.equal(limiter.consume("third", 1, 60_000, 1_003).allowed, true);
  // "first" was the oldest window, so the third key pushed it out.
  assert.equal(limiter.consume("first", 1, 60_000, 1_004).allowed, true);
  assert.equal(limiter.consume("third", 1, 60_000, 1_005).allowed, false);
});

test("a limiter without a key cap keeps every window", () => {
  const limiter = new FixedWindowRateLimiter();
  assert.equal(limiter.consume("first", 1, 60_000, 1_000).allowed, true);
  for (let index = 0; index < 100; index++) limiter.consume(`other-${index}`, 1, 60_000, 1_001);
  assert.equal(limiter.consume("first", 1, 60_000, 1_002).allowed, false);
});
