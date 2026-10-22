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

// Review, 21 Oct 2026: the app's box counts characters as a person sees them (Flutter's
// characters.length), so a Devanagari address the box takes must not be refused for its UTF-16 length.
test("the cap counts characters as the app's address box does, so a Devanagari address it takes is booked", async t => {
  const f = await httpFixture(t);
  const seen = (text: string) => [...new Intl.Segmenter("en", { granularity: "grapheme" }).segment(text)].length;
  const fits = "किला गली ".repeat(80);
  assert.equal(seen(fits), 480, "each letter and its vowel sign are one character");
  assert.ok(fits.length > 500, "but more than 500 UTF-16 units");
  const booked = await f.book(f.tokens.shipperA, { pickupAddress: fits });
  assert.equal(booked.status, 201, "480 characters is under the limit");

  const over = "किला गली ".repeat(90);
  assert.equal(seen(over), 540);
  const refused = await f.book(f.tokens.shipperA, { dropAddress: over });
  assert.equal(refused.body.error, "address_too_long");

  const markHeavy = "a" + "\u0301".repeat(4000);
  assert.equal(seen(markHeavy), 1);
  const heavy = await f.book(f.tokens.shipperA, { pickupAddress: markHeavy });
  assert.equal(heavy.body.error, "address_too_long", "one character with 4,000 marks is still too long to store");
});
