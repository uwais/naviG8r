import { registerCompliantCarrier, runTestPayoutBatch } from "../test/fixtures.ts";
import assert from "node:assert/strict";
import test from "node:test";
import { createStore } from "./store.ts";
import type { Store } from "./store.ts";
import { pilotListCarrierPayoutBatches } from "./services.ts";
import type { LedgerLine, Organization } from "./types.ts";

// This file runs in its own test process, so setting RAZORPAYX env here does not
// leak into the default (bookkeeping) expectations in other test files.
process.env.PAYOUTS_MODE = "RAZORPAYX";
process.env.RAZORPAY_KEY_ID = "rzp_test_dummy";
process.env.RAZORPAY_KEY_SECRET = "dummy_secret";
process.env.RAZORPAYX_ACCOUNT_NUMBER = "2323230000000000";

const CUTOFF = 1_700_000_000_000;

function addOrg(store: Store, id: string, fundAccountId?: string): Organization {
  const org: Organization = {
    id,
    kind: "CARRIER_FLEET",
    displayName: id,
    kycStatus: fundAccountId ? "APPROVED" : "SUBMITTED",
    createdAtUtcMs: CUTOFF,
    payoutFundAccountId: fundAccountId,
  };
  store.organizations.set(org.id, org);
  return org;
}

function addLine(store: Store, lineId: string, carrierId: string, netPaise: number, cutoff = CUTOFF): LedgerLine {
  const line: LedgerLine = {
    id: lineId,
    shipmentId: `shp_${lineId}`,
    carrierId,
    grossPaise: netPaise + 1000,
    commissionPaise: 1000,
    netToCarrierPaise: netPaise,
    podAtUtcMs: CUTOFF - 1000,
    firstPayoutEligibleAtUtcMs: CUTOFF - 1000,
    payoutBatchCutoffUtcMs: cutoff,
    status: "ACCRUED",
    createdAtUtcMs: CUTOFF - 1000,
    paidAtUtcMs: null,
  };
  store.shipments.set(line.shipmentId, {
    id: line.shipmentId, anchorTripId: "test-trip", carrierId, customerOrgName: "Synthetic", customerOrgId: "test-shipper", weightKg: 1, pickupAddress: "A", dropAddress: "B", status: "DELIVERED", grossPaise: line.grossPaise, commissionPaise: line.commissionPaise, netToCarrierPaise: netPaise, paymentId: "test-payment", podAtUtcMs: CUTOFF - 49 * 3600000, firstPayoutEligibleAtUtcMs: line.firstPayoutEligibleAtUtcMs, payoutBatchCutoffUtcMs: cutoff, createdAtUtcMs: 1, updatedAtUtcMs: 1,
  });
  store.ledgerLines.set(line.id, line);
  return line;
}

type FetchCall = { url: string; body: any; headers: Record<string, string> };

function mockFetch(handler: (url: string, body: any) => { status: number; json: any }) {
  const calls: FetchCall[] = [];
  const original = globalThis.fetch;
  globalThis.fetch = (async (input: any, init?: any) => {
    const url = String(input);
    const body = init?.body ? JSON.parse(init.body) : {};
    calls.push({ url, body, headers: init?.headers ?? {} });
    const { status, json } = handler(url, body);
    return new Response(JSON.stringify(json), {
      status,
      headers: { "content-type": "application/json" },
    });
  }) as typeof fetch;
  return { calls, restore: () => { globalThis.fetch = original; } };
}

test("RAZORPAYX: one payout per carrier; carrier without fund account is skipped", async (t) => {
  const store = createStore();
  addOrg(store, "org_a", "fa_aaa"); // has fund account
  addOrg(store, "org_b"); // no fund account
  addLine(store, "ll_a1", "org_a", 50000);
  addLine(store, "ll_b1", "org_b", 70000);

  const { calls, restore } = mockFetch((url) => {
    if (url.endsWith("/payouts")) {
      return { status: 200, json: { id: "pout_123", status: "processed" } };
    }
    return { status: 200, json: {} };
  });
  t.after(restore);

  const batch = await runTestPayoutBatch(store, { nowUtcMs: CUTOFF });

  // Exactly one real payout call (org_a only); org_b skipped before any call.
  assert.equal(calls.length, 1);
  assert.equal(calls[0]!.body.fund_account_id, "fa_aaa");
  assert.equal(calls[0]!.body.amount, 50000);
  assert.equal(calls[0]!.body.account_number, "2323230000000000");

  assert.equal(batch.provider, "RAZORPAYX");
  const byCarrier = new Map(batch.transfers.map((tr) => [tr.carrierId, tr]));

  const a = byCarrier.get("org_a")!;
  assert.equal(a.status, "PAID");
  assert.equal(a.providerPayoutId, "pout_123");
  assert.equal(store.ledgerLines.get("ll_a1")!.status, "PAID");

  const b = byCarrier.get("org_b")!;
  assert.equal(b.status, "SKIPPED_NO_FUND_ACCOUNT");
  // Skipped carrier's line stays ACCRUED so it retries once setup completes.
  assert.equal(store.ledgerLines.get("ll_b1")!.status, "ACCRUED");

  // Total only counts the carrier that was actually paid.
  assert.equal(batch.totalNetToCarrierPaise, 50000);
  assert.deepEqual(batch.lineIds, ["ll_a1"]);
});

test("RAZORPAYX: multiple lines for one carrier aggregate into a single payout", async (t) => {
  const store = createStore();
  addOrg(store, "org_a", "fa_aaa");
  addLine(store, "ll_a1", "org_a", 30000);
  addLine(store, "ll_a2", "org_a", 45000);

  const { calls, restore } = mockFetch(() => ({ status: 200, json: { id: "pout_agg", status: "queued" } }));
  t.after(restore);

  const batch = await runTestPayoutBatch(store, { nowUtcMs: CUTOFF });

  assert.equal(calls.length, 1);
  assert.equal(calls[0]!.body.amount, 75000); // 30000 + 45000

  const a = batch.transfers[0]!;
  assert.equal(a.status, "PROCESSING"); // "queued" is in-flight, not yet processed
  assert.deepEqual(new Set(a.lineIds), new Set(["ll_a1", "ll_a2"]));
  assert.equal(store.ledgerLines.get("ll_a1")!.status, "PAID");
  assert.equal(store.ledgerLines.get("ll_a2")!.status, "PAID");
});

test("RAZORPAYX: provider error marks transfer FAILED and leaves lines ACCRUED to retry", async (t) => {
  const store = createStore();
  addOrg(store, "org_a", "fa_aaa");
  addLine(store, "ll_a1", "org_a", 50000);

  const { restore } = mockFetch(() => ({
    status: 400,
    json: { error: { description: "insufficient_balance" } },
  }));
  t.after(restore);

  const batch = await runTestPayoutBatch(store, { nowUtcMs: CUTOFF });

  const a = batch.transfers[0]!;
  assert.equal(a.status, "FAILED");
  assert.match(a.error ?? "", /payout_provider_failed/);
  assert.equal(store.ledgerLines.get("ll_a1")!.status, "ACCRUED");
  assert.equal(batch.totalNetToCarrierPaise, 0);
  assert.deepEqual(batch.lineIds, []);
});

const WEEK_MS = 7 * 24 * 3600000;

test("RAZORPAYX: a carrier stuck on an earlier week does not hold up another carrier's later week", async (t) => {
  const store = createStore();
  addOrg(store, "org_stuck"); // no fund account, so its first week is skipped on every run
  addOrg(store, "org_b", "fa_bbb");
  addLine(store, "ll_stuck1", "org_stuck", 40000, CUTOFF);
  addLine(store, "ll_b2", "org_b", 60000, CUTOFF + WEEK_MS);

  const { calls, restore } = mockFetch(() => ({ status: 200, json: { id: "pout_b2", status: "processed" } }));
  t.after(restore);

  await runTestPayoutBatch(store, { nowUtcMs: CUTOFF + WEEK_MS });

  assert.equal(calls.length, 1);
  assert.equal(calls[0]!.body.fund_account_id, "fa_bbb");
  assert.equal(store.ledgerLines.get("ll_b2")!.status, "PAID");
  assert.equal(store.ledgerLines.get("ll_stuck1")!.status, "ACCRUED");
});

test("RAZORPAYX: every payout carries an idempotency key, and a retry reuses it", async (t) => {
  const store = createStore();
  addOrg(store, "org_a", "fa_aaa");
  addLine(store, "ll_a1", "org_a", 50000);

  let attempts = 0;
  const { calls, restore } = mockFetch(() => {
    attempts += 1;
    return attempts === 1
      ? { status: 503, json: { error: { description: "upstream timeout" } } }
      : { status: 200, json: { id: "pout_retry", status: "processed" } };
  });
  t.after(restore);

  await runTestPayoutBatch(store, { nowUtcMs: CUTOFF });
  await runTestPayoutBatch(store, { nowUtcMs: CUTOFF + 60_000 });

  assert.equal(calls.length, 2);
  const firstKey = calls[0]!.headers["X-Payout-Idempotency"];
  assert.match(firstKey ?? "", /^[A-Za-z0-9_-]{4,36}$/); // RazorpayX's documented key format
  assert.equal(calls[1]!.headers["X-Payout-Idempotency"], firstKey);
  assert.deepEqual(calls[1]!.body, calls[0]!.body); // RazorpayX only honours a reused key for the same request
  assert.equal(store.ledgerLines.get("ll_a1")!.status, "PAID");
});

test("RAZORPAYX: a carrier who changes bank account gets a new idempotency key", async (t) => {
  const store = createStore();
  const org = addOrg(store, "org_a", "fa_old");
  addLine(store, "ll_a1", "org_a", 50000);

  const { calls, restore } = mockFetch(() => ({ status: 503, json: { error: { description: "upstream timeout" } } }));
  t.after(restore);

  await runTestPayoutBatch(store, { nowUtcMs: CUTOFF });
  store.organizations.set(org.id, { ...org, payoutFundAccountId: "fa_new" });
  await runTestPayoutBatch(store, { nowUtcMs: CUTOFF + 60_000 });

  // RazorpayX refuses a reused key with a different request, so the key must change with the account.
  assert.equal(calls.length, 2);
  assert.notEqual(calls[1]!.headers["X-Payout-Idempotency"], calls[0]!.headers["X-Payout-Idempotency"]);
});

test("RAZORPAYX: a carrier's idempotency key does not depend on other carriers", async (t) => {
  const store = createStore();
  addOrg(store, "org_a", "fa_aaa");
  addOrg(store, "org_b", "fa_bbb");
  addLine(store, "ll_a1", "org_a", 40000, CUTOFF);
  addLine(store, "ll_b2", "org_b", 60000, CUTOFF + WEEK_MS);

  let bAttempts = 0;
  const { calls, restore } = mockFetch((_url, body) => {
    if (body.fund_account_id === "fa_bbb" && ++bAttempts === 1) {
      return { status: 503, json: { error: { description: "upstream timeout" } } };
    }
    return { status: 200, json: { id: `pout_${body.fund_account_id}`, status: "processed" } };
  });
  t.after(restore);

  // First run: org_a is paid for week 1, org_b's week-2 attempt gets no answer. Second run: only org_b is due.
  await runTestPayoutBatch(store, { nowUtcMs: CUTOFF + WEEK_MS });
  await runTestPayoutBatch(store, { nowUtcMs: CUTOFF + WEEK_MS + 60_000 });

  const bKeys = calls.filter((c) => c.body.fund_account_id === "fa_bbb").map((c) => c.headers["X-Payout-Idempotency"]);
  assert.equal(bKeys.length, 2);
  assert.equal(bKeys[1], bKeys[0]);
  assert.equal(store.ledgerLines.get("ll_b2")!.status, "PAID");
});

test("RAZORPAYX: a carrier's payout history shows the week it was paid for", async (t) => {
  const store = createStore();
  const carrier = registerCompliantCarrier(store, {
    fullName: "History Owner", phone: "9000000077", orgDisplayName: "History Carrier",
    vehicleRegistrationNumber: "MH12AB0077", vehicleClass: "MEDIUM", vehicleCapacityKg: 1000,
  });
  store.organizations.set(carrier.org.id, { ...store.organizations.get(carrier.org.id)!, payoutFundAccountId: "fa_hist" });
  addOrg(store, "org_stuck"); // owed an earlier week and has no fund account
  addLine(store, "ll_stuck1", "org_stuck", 40000, CUTOFF);
  addLine(store, "ll_h2", carrier.org.id, 60000, CUTOFF + WEEK_MS);

  const { restore } = mockFetch(() => ({ status: 200, json: { id: "pout_h2", status: "processed" } }));
  t.after(restore);
  await runTestPayoutBatch(store, { nowUtcMs: CUTOFF + WEEK_MS });

  const history = pilotListCarrierPayoutBatches(store, carrier.user.id, carrier.org.id);
  assert.equal(history.length, 1);
  assert.equal(history[0]!.cutoffUtcMs, CUTOFF + WEEK_MS);
});

test("RAZORPAYX: a carrier owed two weeks is paid one week per run, oldest first", async (t) => {
  const store = createStore();
  const carrier = registerCompliantCarrier(store, {
    fullName: "Two Weeks Owner", phone: "9000000078", orgDisplayName: "Two Weeks Carrier",
    vehicleRegistrationNumber: "MH12AB0078", vehicleClass: "MEDIUM", vehicleCapacityKg: 1000,
  });
  store.organizations.set(carrier.org.id, { ...store.organizations.get(carrier.org.id)!, payoutFundAccountId: "fa_two" });
  addLine(store, "ll_w1", carrier.org.id, 30000, CUTOFF);
  addLine(store, "ll_w2", carrier.org.id, 45000, CUTOFF + WEEK_MS);

  const { calls, restore } = mockFetch(() => ({ status: 200, json: { id: "pout_two", status: "processed" } }));
  t.after(restore);

  await runTestPayoutBatch(store, { nowUtcMs: CUTOFF + WEEK_MS });
  assert.equal(calls.length, 1);
  assert.equal(calls[0]!.body.amount, 30000);
  assert.equal(store.ledgerLines.get("ll_w2")!.status, "ACCRUED");

  await runTestPayoutBatch(store, { nowUtcMs: CUTOFF + WEEK_MS + 60_000 });
  assert.equal(calls.length, 2);
  assert.equal(calls[1]!.body.amount, 45000);
  assert.notEqual(calls[1]!.headers["X-Payout-Idempotency"], calls[0]!.headers["X-Payout-Idempotency"]);

  const weeks = pilotListCarrierPayoutBatches(store, carrier.user.id, carrier.org.id).map((b) => b.cutoffUtcMs).sort();
  assert.deepEqual(weeks, [CUTOFF, CUTOFF + WEEK_MS]);
});

test("RAZORPAYX: a payout RazorpayX reports as failed, or with an unknown status, leaves the lines unpaid", async (t) => {
  for (const status of ["failed", "something_new"]) {
    const store = createStore();
    addOrg(store, "org_a", "fa_aaa");
    addLine(store, "ll_a1", "org_a", 50000);

    const { restore } = mockFetch(() => ({ status: 200, json: { id: "pout_f", status } }));
    t.after(restore);
    const batch = await runTestPayoutBatch(store, { nowUtcMs: CUTOFF });
    restore();

    assert.equal(batch.transfers[0]!.status, "FAILED", status);
    assert.equal(store.ledgerLines.get("ll_a1")!.status, "ACCRUED", status);
  }
});
