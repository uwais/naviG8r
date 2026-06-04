import assert from "node:assert/strict";
import test from "node:test";
import { createStore } from "./store.ts";
import type { Store } from "./store.ts";
import { runPayoutBatch } from "./services.ts";
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
    kind: "CARRIER",
    displayName: id,
    kycStatus: fundAccountId ? "APPROVED" : "SUBMITTED",
    createdAtUtcMs: CUTOFF,
    payoutFundAccountId: fundAccountId,
  };
  store.organizations.set(org.id, org);
  return org;
}

function addLine(store: Store, lineId: string, carrierId: string, netPaise: number): LedgerLine {
  const line: LedgerLine = {
    id: lineId,
    shipmentId: `shp_${lineId}`,
    carrierId,
    grossPaise: netPaise + 1000,
    commissionPaise: 1000,
    netToCarrierPaise: netPaise,
    podAtUtcMs: CUTOFF - 1000,
    firstPayoutEligibleAtUtcMs: CUTOFF - 1000,
    payoutBatchCutoffUtcMs: CUTOFF,
    status: "ACCRUED",
    createdAtUtcMs: CUTOFF - 1000,
    paidAtUtcMs: null,
  };
  store.ledgerLines.set(line.id, line);
  return line;
}

type FetchCall = { url: string; body: any };

function mockFetch(handler: (url: string, body: any) => { status: number; json: any }) {
  const calls: FetchCall[] = [];
  const original = globalThis.fetch;
  globalThis.fetch = (async (input: any, init?: any) => {
    const url = String(input);
    const body = init?.body ? JSON.parse(init.body) : {};
    calls.push({ url, body });
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

  const batch = await runPayoutBatch(store, { nowUtcMs: CUTOFF });

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

  const batch = await runPayoutBatch(store, { nowUtcMs: CUTOFF });

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

  const batch = await runPayoutBatch(store, { nowUtcMs: CUTOFF });

  const a = batch.transfers[0]!;
  assert.equal(a.status, "FAILED");
  assert.match(a.error ?? "", /insufficient_balance/);
  assert.equal(store.ledgerLines.get("ll_a1")!.status, "ACCRUED");
  assert.equal(batch.totalNetToCarrierPaise, 0);
  assert.deepEqual(batch.lineIds, []);
});
