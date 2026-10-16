import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { authorizationContext } from "../../rbac.ts";
import { createApp } from "../../httpServer.ts";
import { loadStoreFromDisk } from "../../persistence.ts";
import { runPayoutBatch } from "../../services.ts";
import type { LedgerLine, Organization } from "../../types.ts";

test("serialized persistence failure restores nested Store state before a later save", async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "navig8r-mutation-test-"));
  const filePath = path.join(dir, "store.json");
  let failNextPersist = true;
  const app = await createApp({
    dataFilePath: filePath,
    beforePersist: () => {
      if (failNextPersist) {
        failNextPersist = false;
        throw new Error("injected_persistence_failure");
      }
    },
  });
  const deliveryMap = app.store.integrationWebhookDeliveries;
  const delivery = {
    id: "delivery-1",
    eventId: "event-1",
    orgId: "org-1",
    connectionId: "connection-1",
    webhookUrl: "https://example.invalid/hook",
    payloadJson: "{}",
    status: "PENDING" as const,
    attempts: 0,
    nextRetryAtUtcMs: 1,
    lastHttpStatus: null,
    lastError: null,
    deliveredAtUtcMs: null,
    createdAtUtcMs: 1,
    updatedAtUtcMs: 1,
  };
  const originalDelivery = structuredClone(delivery);
  app.store.integrationWebhookDeliveries.set(delivery.id, delivery);

  await assert.rejects(app.runSerialized(async () => {
    const current = app.store.integrationWebhookDeliveries.get(delivery.id)!;
    current.attempts = 4;
    current.status = "DEAD";
    current.lastError = "temporary mutation";
    app.store.notificationSequence = 17;
    await app.persist();
  }), /injected_persistence_failure/);

  assert.equal(app.store.integrationWebhookDeliveries, deliveryMap, "rollback preserves Store map identity");
  assert.deepEqual(app.store.integrationWebhookDeliveries.get(delivery.id), originalDelivery);
  assert.equal(app.store.notificationSequence, 0);

  await app.runSerialized(async () => {
    app.store.notificationSequence = 1;
    await app.persist();
  });

  const reloaded = loadStoreFromDisk(filePath);
  assert.equal(reloaded.notificationSequence, 1);
  assert.deepEqual(reloaded.integrationWebhookDeliveries.get(delivery.id), originalDelivery);
  fs.rmSync(dir, { recursive: true, force: true });
});

test("a failed save after a RazorpayX payout does not pay the same lines again", async () => {
  const previous = {
    PAYOUTS_MODE: process.env.PAYOUTS_MODE,
    RAZORPAY_KEY_ID: process.env.RAZORPAY_KEY_ID,
    RAZORPAY_KEY_SECRET: process.env.RAZORPAY_KEY_SECRET,
    RAZORPAYX_ACCOUNT_NUMBER: process.env.RAZORPAYX_ACCOUNT_NUMBER,
  };
  process.env.PAYOUTS_MODE = "RAZORPAYX";
  process.env.RAZORPAY_KEY_ID = "rzp_test_dummy";
  process.env.RAZORPAY_KEY_SECRET = "dummy_secret";
  process.env.RAZORPAYX_ACCOUNT_NUMBER = "2323230000000000";
  const originalFetch = globalThis.fetch;
  const payoutCalls: string[] = [];
  globalThis.fetch = (async (input: RequestInfo | URL) => {
    const url = String(input);
    if (url.endsWith("/payouts")) payoutCalls.push(url);
    return new Response(JSON.stringify({ id: "pout_once", status: "processed" }), {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  }) as typeof fetch;

  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "navig8r-payout-rollback-"));
  const filePath = path.join(dir, "store.json");
  let failNextPersist = true;
  try {
    const app = await createApp({
      dataFilePath: filePath,
      beforePersist: () => {
        if (failNextPersist) {
          failNextPersist = false;
          throw new Error("injected_persistence_failure");
        }
      },
    });
    const cutoff = 1_700_000_000_000;
    const org: Organization = {
      id: "org_a",
      kind: "CARRIER_FLEET",
      displayName: "org_a",
      kycStatus: "APPROVED",
      createdAtUtcMs: cutoff,
      payoutFundAccountId: "fa_aaa",
    };
    app.store.organizations.set(org.id, org);
    const line: LedgerLine = {
      id: "ll_a1",
      shipmentId: "shp_ll_a1",
      carrierId: org.id,
      grossPaise: 51000,
      commissionPaise: 1000,
      netToCarrierPaise: 50000,
      podAtUtcMs: cutoff - 1000,
      firstPayoutEligibleAtUtcMs: cutoff - 1000,
      payoutBatchCutoffUtcMs: cutoff,
      status: "ACCRUED",
      createdAtUtcMs: cutoff - 1000,
      paidAtUtcMs: null,
    };
    app.store.shipments.set(line.shipmentId, {
      id: line.shipmentId,
      anchorTripId: "test-trip",
      carrierId: org.id,
      customerOrgName: "Synthetic",
      customerOrgId: "test-shipper",
      weightKg: 1,
      pickupAddress: "A",
      dropAddress: "B",
      status: "DELIVERED",
      grossPaise: line.grossPaise,
      commissionPaise: line.commissionPaise,
      netToCarrierPaise: line.netToCarrierPaise,
      paymentId: "test-payment",
      podAtUtcMs: cutoff - 49 * 3600000,
      firstPayoutEligibleAtUtcMs: line.firstPayoutEligibleAtUtcMs,
      payoutBatchCutoffUtcMs: cutoff,
      createdAtUtcMs: 1,
      updatedAtUtcMs: 1,
    });
    app.store.ledgerLines.set(line.id, line);

    await assert.rejects(app.runSerialized(() => authorizationContext.run({ system: true, requestId: "payout-save-fails" }, async () => {
      const batch = await runPayoutBatch(app.store, { nowUtcMs: cutoff });
      if (batch.lineIds.length > 0) await app.persist();
      return batch;
    })), /injected_persistence_failure/);

    assert.equal(payoutCalls.length, 1);
    assert.equal(app.store.ledgerLines.get(line.id)?.status, "PAID");
    assert.equal([...app.store.payoutBatches.values()].some((batch) => batch.transfers.some((transfer) => transfer.providerPayoutId === "pout_once")), true);

    await app.runSerialized(() => authorizationContext.run({ system: true, requestId: "payout-save-retries" }, async () => {
      await runPayoutBatch(app.store, { nowUtcMs: cutoff + 60_000 });
      await app.persist();
    }));

    assert.equal(payoutCalls.length, 1, "the next batch must not create another provider payout");
    const reloaded = loadStoreFromDisk(filePath);
    assert.equal(reloaded.ledgerLines.get(line.id)?.status, "PAID");
    assert.equal([...reloaded.payoutBatches.values()].some((batch) => batch.transfers.some((transfer) => transfer.providerPayoutId === "pout_once")), true);
  } finally {
    globalThis.fetch = originalFetch;
    for (const [key, value] of Object.entries(previous)) {
      if (value == null) delete process.env[key];
      else process.env[key] = value;
    }
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test("runSerialized keeps concurrent mutation jobs in order", async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "navig8r-mutation-order-"));
  const app = await createApp({ dataFilePath: path.join(dir, "store.json") });
  const order: string[] = [];
  await Promise.all([
    app.runSerialized(async () => {
      order.push("first:start");
      await new Promise(resolve => setTimeout(resolve, 10));
      order.push("first:end");
    }),
    app.runSerialized(() => order.push("second")),
  ]);
  assert.deepEqual(order, ["first:start", "first:end", "second"]);
  fs.rmSync(dir, { recursive: true, force: true });
});
