import test from "node:test";
import assert from "node:assert/strict";
import { httpFixture } from "../test/httpFixtures.ts";

// A booking's addresses are stored and sent to every screen and webhook, so their length is capped.
test("a pickup or drop address over 500 characters is refused with address_too_long", async t => {
  const f = await httpFixture(t);
  const long = "Plot 12, ".repeat(56);
  assert.ok(long.length > 500);
  for (const field of ["pickupAddress", "dropAddress"]) {
    const refused = await f.book(f.tokens.shipperA, { [field]: long });
    assert.equal(refused.status, 400, field);
    assert.equal(refused.body.error, "address_too_long", field);
  }
  assert.equal(f.store.shipments.size, 0, "nothing was booked");

  const atTheLimit = await f.book(f.tokens.shipperA, { pickupAddress: "a".repeat(500) });
  assert.equal(atTheLimit.status, 201, "500 characters is allowed");
});
