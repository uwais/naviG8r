import { registerCompliantCarrier } from "../test/fixtures.ts";
import assert from "node:assert/strict";
import test from "node:test";
import { ApiError, pilotSubmitPayoutSetup } from "./services.ts";
import { createStore } from "./store.ts";

// This file runs in its own test process, so real-payout mode here does not leak
// into the bookkeeping expectations in other test files.
process.env.PAYOUTS_MODE = "RAZORPAYX";
process.env.RAZORPAY_KEY_ID = "rzp_test_dummy";
process.env.RAZORPAY_KEY_SECRET = "dummy_secret";
process.env.RAZORPAYX_ACCOUNT_NUMBER = "2323230000000000";

function fakeRazorpayx(t: { after: (fn: () => void) => void }) {
  const original = globalThis.fetch;
  globalThis.fetch = (async (input: unknown) => {
    const id = String(input).endsWith("/contacts") ? "cont_test" : "fa_test";
    return new Response(JSON.stringify({ id }), { status: 200, headers: { "content-type": "application/json" } });
  }) as typeof fetch;
  t.after(() => {
    globalThis.fetch = original;
  });
}

function carrierOwner() {
  const store = createStore();
  const onboard = registerCompliantCarrier(store, {
    fullName: "Ravi Kumar",
    phone: "9876500021",
    orgDisplayName: "Ravi Transport",
    vehicleRegistrationNumber: "HR26AB1111",
    vehicleClass: "MEDIUM",
    vehicleCapacityKg: 5000,
  });
  return { store, onboard };
}

test("real payouts: saving bank details registers the account and promises no check", async (t) => {
  fakeRazorpayx(t);
  const { store, onboard } = carrierOwner();

  const setup = await pilotSubmitPayoutSetup(store, onboard.user.id, {
    orgId: onboard.org.id,
    accountHolderName: "Ravi Kumar",
    ifsc: "HDFC0001234",
    accountNumber: "1234567890",
  });

  assert.equal(setup.message, "Bank account added.");
  assert.equal(setup.org.payoutFundAccountId, "fa_test");
});

test("real payouts: a blank account number is refused in plain words", async () => {
  const { store, onboard } = carrierOwner();

  await assert.rejects(
    () =>
      pilotSubmitPayoutSetup(store, onboard.user.id, {
        orgId: onboard.org.id,
        accountHolderName: "Ravi Kumar",
        ifsc: "HDFC0001234",
      }),
    (err: unknown) =>
      err instanceof ApiError &&
      err.message === "invalid_payout_profile" &&
      err.extra.detail === "Bank account number is required.",
  );
});
