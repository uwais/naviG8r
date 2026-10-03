import { registerCompliantCarrier, runTestPayoutBatch } from "../test/fixtures.ts";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { loadStoreFromDisk, saveStoreToDisk } from "./persistence.ts";
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

type FetchCall = { url: string; body: any; headers: Record<string, string>; signal?: AbortSignal };

function mockFetch(handler: (url: string, body: any) => { status: number; json: any }) {
  const calls: FetchCall[] = [];
  const original = globalThis.fetch;
  globalThis.fetch = (async (input: any, init?: any) => {
    const url = String(input);
    const body = init?.body ? JSON.parse(init.body) : {};
    calls.push({ url, body, headers: init?.headers ?? {}, signal: init?.signal });
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
  assert.ok(calls[0]!.signal instanceof AbortSignal); // every request can be cut off; the 30-second value is not tested
  assert.equal(store.ledgerLines.get("ll_a1")!.status, "PAID");
});

test("RAZORPAYX: after a lost reply, a bank change resends the same request instead of starting a second payout", async (t) => {
  const store = createStore();
  const org = addOrg(store, "org_a", "fa_old");
  addLine(store, "ll_a1", "org_a", 50000);

  const { calls, restore } = mockFetch(() => ({ status: 503, json: { error: { description: "upstream timeout" } } }));
  t.after(restore);

  await runTestPayoutBatch(store, { nowUtcMs: CUTOFF });
  store.organizations.set(org.id, { ...org, payoutFundAccountId: "fa_new" });
  await runTestPayoutBatch(store, { nowUtcMs: CUTOFF + 60_000 });

  // The first request may have gone through, so the retry must be the identical request.
  assert.equal(calls.length, 2);
  assert.equal(calls[1]!.headers["X-Payout-Idempotency"], calls[0]!.headers["X-Payout-Idempotency"]);
  assert.deepEqual(calls[1]!.body, calls[0]!.body);
  assert.equal(calls[1]!.body.fund_account_id, "fa_old");
});

test("RAZORPAYX: after a definite failure, the next run starts a new request on the current bank account", async (t) => {
  for (const finalStatus of ["failed", "rejected", "cancelled", "reversed"]) {
    const store = createStore();
    const org = addOrg(store, "org_a", "fa_old");
    addLine(store, "ll_a1", "org_a", 50000);

    let attempts = 0;
    const { calls, restore } = mockFetch(() => (++attempts === 1
      ? { status: 200, json: { id: "pout_failed", status: finalStatus } }
      : { status: 200, json: { id: "pout_new", status: "processed" } }));
    t.after(restore);

    await runTestPayoutBatch(store, { nowUtcMs: CUTOFF });
    assert.equal(store.ledgerLines.get("ll_a1")!.payoutAttemptKey, undefined, finalStatus);
    store.organizations.set(org.id, { ...org, payoutFundAccountId: "fa_new" });
    await runTestPayoutBatch(store, { nowUtcMs: CUTOFF + 60_000 });
    restore();

    assert.equal(calls.length, 2, finalStatus);
    assert.notEqual(calls[1]!.headers["X-Payout-Idempotency"], calls[0]!.headers["X-Payout-Idempotency"], finalStatus);
    assert.equal(calls[1]!.body.fund_account_id, "fa_new", finalStatus);
    assert.equal(store.ledgerLines.get("ll_a1")!.status, "PAID", finalStatus);
  }
});

test("RAZORPAYX: a carrier deactivated while another carrier's request is in flight is not paid", async (t) => {
  for (const deactivated of ["ledger line", "organization"]) {
    const store = createStore();
    addOrg(store, "org_a", "fa_aaa");
    const orgB = addOrg(store, "org_b", "fa_bbb");
    addLine(store, "ll_a1", "org_a", 50000);
    addLine(store, "ll_b1", "org_b", 60000);

    const { calls, restore } = mockFetch((_url, body) => {
      if (body.fund_account_id === "fa_aaa") {
        // Ops deactivates carrier B while carrier A's request is in flight.
        if (deactivated === "ledger line") {
          const b = store.ledgerLines.get("ll_b1")!;
          store.ledgerLines.set(b.id, { ...b, inactiveAtUtcMs: CUTOFF, inactiveReason: "test" });
        } else {
          store.organizations.set(orgB.id, { ...orgB, inactiveAtUtcMs: CUTOFF, inactiveReason: "test" });
        }
      }
      return { status: 200, json: { id: `pout_${body.fund_account_id}`, status: "processed" } };
    });
    t.after(restore);
    await runTestPayoutBatch(store, { nowUtcMs: CUTOFF });
    restore();

    assert.deepEqual(calls.map((c) => c.body.fund_account_id), ["fa_aaa"], deactivated);
    assert.equal(store.ledgerLines.get("ll_b1")!.status, "ACCRUED", deactivated);
    if (deactivated === "ledger line") assert.equal(store.ledgerLines.get("ll_b1")!.inactiveAtUtcMs, CUTOFF);
  }
});

test("RAZORPAYX: after a lost reply, a line that joins the same week waits for that request's answer", async (t) => {
  const store = createStore();
  addOrg(store, "org_a", "fa_aaa");
  addLine(store, "ll_a1", "org_a", 50000);

  let attempts = 0;
  const { calls, restore } = mockFetch(() => (++attempts === 1
    ? { status: 503, json: { error: { description: "upstream timeout" } } }
    : { status: 200, json: { id: `pout_${attempts}`, status: "processed" } }));
  t.after(restore);

  await runTestPayoutBatch(store, { nowUtcMs: CUTOFF });
  addLine(store, "ll_a2", "org_a", 20000); // released late, same week
  await runTestPayoutBatch(store, { nowUtcMs: CUTOFF + 60_000 });

  assert.equal(calls[1]!.headers["X-Payout-Idempotency"], calls[0]!.headers["X-Payout-Idempotency"]);
  assert.equal(calls[1]!.body.amount, 50000);
  assert.equal(store.ledgerLines.get("ll_a1")!.status, "PAID");
  assert.equal(store.ledgerLines.get("ll_a2")!.status, "ACCRUED");

  await runTestPayoutBatch(store, { nowUtcMs: CUTOFF + 120_000 });
  assert.equal(calls[2]!.body.amount, 20000);
  assert.notEqual(calls[2]!.headers["X-Payout-Idempotency"], calls[0]!.headers["X-Payout-Idempotency"]);
  assert.equal(store.ledgerLines.get("ll_a2")!.status, "PAID");
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

test("RAZORPAYX: a payout RazorpayX reports as failed leaves the lines unpaid and clears the record", async (t) => {
  const store = createStore();
  addOrg(store, "org_a", "fa_aaa");
  addLine(store, "ll_a1", "org_a", 50000);

  const { restore } = mockFetch(() => ({ status: 200, json: { id: "pout_f", status: "failed" } }));
  t.after(restore);
  const batch = await runTestPayoutBatch(store, { nowUtcMs: CUTOFF });

  assert.equal(batch.transfers[0]!.status, "FAILED");
  assert.equal(store.ledgerLines.get("ll_a1")!.status, "ACCRUED");
  assert.equal(store.ledgerLines.get("ll_a1")!.payoutAttemptKey, undefined);
});

test("RAZORPAYX: an unknown status counts as in progress, because a resend would only replay the saved answer", async (t) => {
  const store = createStore();
  addOrg(store, "org_a", "fa_aaa");
  addLine(store, "ll_a1", "org_a", 50000);

  const { calls, restore } = mockFetch(() => ({ status: 200, json: { id: "pout_u", status: "something_new" } }));
  t.after(restore);
  const warn = t.mock.method(console, "warn", () => {});

  const batch = await runTestPayoutBatch(store, { nowUtcMs: CUTOFF });
  await runTestPayoutBatch(store, { nowUtcMs: CUTOFF + 60_000 });

  assert.equal(batch.transfers[0]!.status, "PROCESSING");
  assert.equal(store.ledgerLines.get("ll_a1")!.status, "PAID");
  assert.equal(store.ledgerLines.get("ll_a1")!.payoutAttemptKey, undefined);
  assert.equal(calls.length, 1); // nothing is sent again
  // The transfer does not keep the raw status, so the log must.
  assert.equal(warn.mock.calls.length, 1);
  assert.deepEqual(warn.mock.calls[0]!.arguments, ["payout_status_undocumented", { carrierId: "org_a", providerPayoutId: "pout_u", status: "something_new" }]);
});

test("RAZORPAYX: a store restored from before a payout rebuilds the same key, so RazorpayX recognises it", async (t) => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "payout-restore-"));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const backup = path.join(dir, "backup.json");

  const live = createStore();
  addOrg(live, "org_a", "fa_aaa");
  addLine(live, "ll_a1", "org_a", 50000);
  saveStoreToDisk(backup, live); // a backup taken before the payout

  const { calls, restore } = mockFetch(() => ({ status: 200, json: { id: "pout_once", status: "processed" } }));
  t.after(restore);
  await runTestPayoutBatch(live, { nowUtcMs: CUTOFF });

  const restored = loadStoreFromDisk(backup); // the payout is missing from the restored data
  await runTestPayoutBatch(restored, { nowUtcMs: CUTOFF + 60_000 });

  assert.equal(calls[1]!.headers["X-Payout-Idempotency"], calls[0]!.headers["X-Payout-Idempotency"]);
  assert.deepEqual(calls[1]!.body, calls[0]!.body); // RazorpayX refuses a reused key with a different body
  assert.equal(restored.ledgerLines.get("ll_a1")!.status, "PAID");
});

test("RAZORPAYX: after a failure on the same bank account, the next request still gets a new key", async (t) => {
  for (const firstReply of [
    { status: 200, json: { id: "pout_x", status: "reversed" } },
    { status: 400, json: { error: { description: "refused" } } },
  ]) {
    const store = createStore();
    addOrg(store, "org_a", "fa_aaa");
    addLine(store, "ll_a1", "org_a", 50000);

    let attempts = 0;
    const { calls, restore } = mockFetch(() => (++attempts === 1 ? firstReply : { status: 200, json: { id: "pout_ok", status: "processed" } }));
    t.after(restore);
    await runTestPayoutBatch(store, { nowUtcMs: CUTOFF });
    await runTestPayoutBatch(store, { nowUtcMs: CUTOFF + 60_000 });
    restore();

    assert.notEqual(calls[1]!.headers["X-Payout-Idempotency"], calls[0]!.headers["X-Payout-Idempotency"], String(firstReply.status));
    assert.equal(store.ledgerLines.get("ll_a1")!.status, "PAID");
  }
});

test("RAZORPAYX: the request is recorded and saved before it is sent, and so is a resend", async (t) => {
  const store = createStore();
  addOrg(store, "org_a", "fa_aaa");
  addLine(store, "ll_a1", "org_a", 50000);

  const events: string[] = [];
  const { restore } = mockFetch(() => {
    events.push("sent");
    return events.length === 2
      ? { status: 503, json: { error: { description: "upstream timeout" } } }
      : { status: 200, json: { id: "pout_s", status: "processed" } };
  });
  t.after(restore);
  const saveBeforePayout = async () => {
    events.push(store.ledgerLines.get("ll_a1")!.payoutAttemptKey ? "saved with record" : "saved without record");
  };

  await runTestPayoutBatch(store, { nowUtcMs: CUTOFF, saveBeforePayout });
  await runTestPayoutBatch(store, { nowUtcMs: CUTOFF + 60_000, saveBeforePayout });

  assert.deepEqual(events, ["saved with record", "sent", "saved with record", "sent"]);
  assert.equal(store.ledgerLines.get("ll_a1")!.status, "PAID");
});

test("RAZORPAYX: if that save fails, nothing is sent, and the next run treats the request as new", async (t) => {
  const store = createStore();
  addOrg(store, "org_a", "fa_aaa");
  addLine(store, "ll_a1", "org_a", 50000);

  const events: string[] = [];
  const { calls, restore } = mockFetch(() => {
    events.push("sent");
    return { status: 400, json: { error: { description: "fund account is not active" } } };
  });
  t.after(restore);

  const failed = await runTestPayoutBatch(store, { nowUtcMs: CUTOFF, saveBeforePayout: async () => { throw new Error("disk full"); } });
  assert.equal(calls.length, 0);
  assert.equal(failed.transfers[0]!.error, "save_failed_before_payout");
  assert.equal(store.ledgerLines.get("ll_a1")!.payoutAttemptKey, undefined); // nothing went out, so nothing to resend

  // RazorpayX sees the request for the first time, so its refusal counts as one, instead of pinning the record.
  await runTestPayoutBatch(store, { nowUtcMs: CUTOFF + 60_000, saveBeforePayout: async () => { events.push("saved"); } });
  assert.deepEqual(events, ["saved", "sent"]);
  assert.equal(store.ledgerLines.get("ll_a1")!.payoutAttemptKey, undefined);
  assert.equal(store.ledgerLines.get("ll_a1")!.payoutFailedAttempts, 1);
});

test("RAZORPAYX: a brand-new request that times out or loses its connection is kept, and resent unchanged", async (t) => {
  const lostReplies = [
    { name: "timeout", error: () => new DOMException("The operation was aborted due to timeout", "TimeoutError"), cause: undefined },
    { name: "connection reset", error: () => new TypeError("fetch failed", { cause: Object.assign(new Error("read ECONNRESET"), { code: "ECONNRESET" }) }), cause: "ECONNRESET" },
  ];
  for (const lost of lostReplies) {
    const store = createStore();
    addOrg(store, "org_a", "fa_aaa");
    addLine(store, "ll_a1", "org_a", 50000);

    const { calls, restore } = mockFetch(() => {
      if (calls.length === 1) throw lost.error();
      return { status: 200, json: { id: "pout_t", status: "processed" } };
    });
    t.after(restore);
    const logged = t.mock.method(console, "error", () => {});

    await runTestPayoutBatch(store, { nowUtcMs: CUTOFF });
    assert.ok(store.ledgerLines.get("ll_a1")!.payoutAttemptKey, lost.name); // RazorpayX may have created it
    await runTestPayoutBatch(store, { nowUtcMs: CUTOFF + 60_000 });
    const loggedCause = (logged.mock.calls[0]!.arguments[1] as { cause?: string }).cause;
    logged.mock.restore();
    restore();

    assert.equal(calls[1]!.headers["X-Payout-Idempotency"], calls[0]!.headers["X-Payout-Idempotency"], lost.name);
    assert.deepEqual(calls[1]!.body, calls[0]!.body, lost.name);
    assert.equal(store.ledgerLines.get("ll_a1")!.status, "PAID", lost.name);
    assert.equal(loggedCause, lost.cause, lost.name);
  }
});

test("RAZORPAYX: a resend whose save fails keeps its record, so a bank change meanwhile still resends the same request", async (t) => {
  const store = createStore();
  const org = addOrg(store, "org_a", "fa_old");
  addLine(store, "ll_a1", "org_a", 50000);

  const { calls, restore } = mockFetch(() => (calls.length === 1
    ? { status: 503, json: { error: { description: "upstream timeout" } } }
    : { status: 200, json: { id: "pout_k", status: "processed" } }));
  t.after(restore);

  await runTestPayoutBatch(store, { nowUtcMs: CUTOFF }); // no clear answer, so the record is kept
  await runTestPayoutBatch(store, { nowUtcMs: CUTOFF + 60_000, saveBeforePayout: async () => { throw new Error("disk full"); } });
  assert.equal(calls.length, 1); // the resend was not sent
  store.organizations.set(org.id, { ...org, payoutFundAccountId: "fa_new" });
  await runTestPayoutBatch(store, { nowUtcMs: CUTOFF + 120_000 });

  assert.equal(calls[1]!.headers["X-Payout-Idempotency"], calls[0]!.headers["X-Payout-Idempotency"]);
  assert.equal(calls[1]!.body.fund_account_id, "fa_old");
  assert.equal(store.ledgerLines.get("ll_a1")!.status, "PAID");
});

test("RAZORPAYX: after a restart, an unanswered request is resent with the same key", async (t) => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "payout-attempt-"));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const file = path.join(dir, "store.json");

  const before = createStore();
  addOrg(before, "org_a", "fa_aaa");
  addLine(before, "ll_a1", "org_a", 50000);

  let attempts = 0;
  const { calls, restore } = mockFetch(() => (++attempts === 1
    ? { status: 503, json: { error: { description: "upstream timeout" } } }
    : { status: 200, json: { id: "pout_r", status: "processed" } }));
  t.after(restore);

  await runTestPayoutBatch(before, { nowUtcMs: CUTOFF, saveBeforePayout: async () => saveStoreToDisk(file, before) });
  const after = loadStoreFromDisk(file); // the process restarts before its end-of-run save
  await runTestPayoutBatch(after, { nowUtcMs: CUTOFF + 60_000 });

  assert.equal(calls[1]!.headers["X-Payout-Idempotency"], calls[0]!.headers["X-Payout-Idempotency"]);
  assert.equal(after.ledgerLines.get("ll_a1")!.status, "PAID");
});

test("RAZORPAYX: when RazorpayX refuses a brand-new request, the next run starts fresh on the current bank account", async (t) => {
  const store = createStore();
  const org = addOrg(store, "org_a", "fa_bad");
  addLine(store, "ll_a1", "org_a", 50000);

  let attempts = 0;
  const { calls, restore } = mockFetch(() => (++attempts === 1
    ? { status: 400, json: { error: { description: "fund account is not active" } } }
    : { status: 200, json: { id: "pout_ok", status: "processed" } }));
  t.after(restore);

  await runTestPayoutBatch(store, { nowUtcMs: CUTOFF });
  assert.equal(store.ledgerLines.get("ll_a1")!.payoutAttemptKey, undefined); // nothing was created
  store.organizations.set(org.id, { ...org, payoutFundAccountId: "fa_fixed" });
  await runTestPayoutBatch(store, { nowUtcMs: CUTOFF + 60_000 });

  assert.notEqual(calls[1]!.headers["X-Payout-Idempotency"], calls[0]!.headers["X-Payout-Idempotency"]);
  assert.equal(calls[1]!.body.fund_account_id, "fa_fixed");
  assert.equal(store.ledgerLines.get("ll_a1")!.status, "PAID");
});

test("RAZORPAYX: a refused resend, or a timeout, conflict or rate limit on a new request, keeps the request for the next run", async (t) => {
  const store = createStore();
  addOrg(store, "org_a", "fa_aaa");
  addLine(store, "ll_a1", "org_a", 50000);

  // 503 on the first send (no clear answer), 400 on the resend (it may still exist), then success.
  const replies = [503, 400, 200];
  const { calls, restore } = mockFetch(() => {
    const status = replies[calls.length - 1]!;
    return status === 200 ? { status, json: { id: "pout_ok", status: "processed" } } : { status, json: { error: { description: "nope" } } };
  });
  t.after(restore);

  for (let run = 0; run < 3; run++) await runTestPayoutBatch(store, { nowUtcMs: CUTOFF + run * 60_000 });
  assert.equal(new Set(calls.map((c) => c.headers["X-Payout-Idempotency"])).size, 1);
  assert.equal(store.ledgerLines.get("ll_a1")!.status, "PAID");

  restore();
  for (const status of [408, 409, 429]) {
    const limited = createStore();
    addOrg(limited, "org_b", "fa_bbb");
    addLine(limited, "ll_b1", "org_b", 40000);
    const { restore: restoreLimited } = mockFetch(() => ({ status, json: { error: { description: "try again" } } }));
    t.after(restoreLimited);
    await runTestPayoutBatch(limited, { nowUtcMs: CUTOFF });
    restoreLimited();
    assert.ok(limited.ledgerLines.get("ll_b1")!.payoutAttemptKey, String(status)); // not a refusal
  }
});
