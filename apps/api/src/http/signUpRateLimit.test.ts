import assert from "node:assert/strict";
import test from "node:test";
import { FixedWindowRateLimiter } from "./rateLimit.ts";
import { createSignUpRateLimit } from "./signUpRateLimit.ts";

test("a capped limiter drops its oldest window first", () => {
  const limiter = new FixedWindowRateLimiter(2);
  limiter.consume("first", 1, 60_000, 0);
  limiter.consume("second", 1, 60_000, 1);
  limiter.consume("third", 1, 60_000, 2);
  assert.equal(limiter.consume("second", 1, 60_000, 3).allowed, false);
  assert.equal(limiter.consume("first", 1, 60_000, 4).allowed, true);
});

test("a sign-up refused for its IP does not use one of the phone's tries", () => {
  const signUpLimit = createSignUpRateLimit();
  for (let attempt = 0; attempt < 30; attempt++) {
    assert.equal(signUpLimit("192.0.2.1", String(9100000000 + attempt), 0).allowed, true);
  }
  for (let attempt = 0; attempt < 5; attempt++) {
    const refused = signUpLimit("192.0.2.1", "9100000500", 0);
    assert.equal(refused.allowed, false);
    assert.equal(refused.retryAfterSeconds, 600);
  }
  assert.equal(signUpLimit("192.0.2.2", "9100000500", 0).allowed, true);
});

test("without an IP, only the phone is counted", () => {
  const signUpLimit = createSignUpRateLimit();
  for (let attempt = 0; attempt < 5; attempt++) assert.equal(signUpLimit(null, "+91 91000 00600", 0).allowed, true);
  const refused = signUpLimit(null, "9100000600", 0);
  assert.equal(refused.allowed, false);
  assert.equal(refused.retryAfterSeconds, 3600);
  assert.equal(signUpLimit(null, "9100000601", 0).allowed, true);
});

test("many new IPs do not reset a phone's count", () => {
  const signUpLimit = createSignUpRateLimit();
  for (let attempt = 0; attempt < 5; attempt++) signUpLimit("192.0.2.1", "9100000700", 0);
  for (let address = 0; address < 10_001; address++) signUpLimit(`10.0.${address >> 8}.${address & 255}`, "9100000701", 1);
  assert.equal(signUpLimit("192.0.2.2", "9100000700", 2).allowed, false);
});
