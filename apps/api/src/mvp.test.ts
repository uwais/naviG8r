import assert from "node:assert/strict";
import test from "node:test";
import { computePayoutBatchAssignment, utcMsFromIstWallParts } from "../../../packages/core/src/payoutSchedule.ts";
import { PAYOUT_BATCH_SCHEDULE } from "./config.ts";
import { createStore, pruneEmptyPayoutBatches } from "./store.ts";
import { bookShipment, acceptCarrierShipment, markPodDelivered, publishAnchorTrip, registerSoloOwnerOperatorDriver, runPayoutBatch } from "./services.ts";

test("vertical slice: publish trip -> book (capture) -> POD -> ledger -> weekly batch pays after cutoff", async () => {
  const store = createStore();
  const driver = registerSoloOwnerOperatorDriver(store, {
    fullName: "Carrier One",
    phone: "9100000100",
    orgDisplayName: "Carrier One",
    vehicleRegistrationNumber: "HR10",
    vehicleClass: "MEDIUM",
    vehicleCapacityKg: 5000,
  });
  const trip = publishAnchorTrip(store, {
    carrierId: driver.org.id,
    originCity: "Gurugram",
    destCity: "Jaipur",
    windowStart: "2026-04-24T00:00:00+05:30",
    windowEnd: "2026-04-25T23:59:59+05:30",
    vehicleClass: "MEDIUM",
    capacityKg: 1000,
  });

  const shipment = bookShipment(store, {
    anchorTripId: trip.id,
    customerOrgName: "ACME Manufacturing",
    weightKg: 200,
    pickupAddress: "Sector 44, Gurugram",
    dropAddress: "Sitapura, Jaipur",
  });

  acceptCarrierShipment(store, { shipmentId: shipment.id, userId: driver.user.id });

  const pay = store.payments.get(shipment.paymentId);
  assert.equal(pay?.status, "CAPTURED");
  assert.equal(store.anchorTrips.get(trip.id)?.reservedKg, 200);

  // POD at IST: Mar 21, 2024 00:00
  const podAtUtcMs = utcMsFromIstWallParts(2024, 2, 21, 0, 0, 0, 0);
  const out = markPodDelivered(store, { shipmentId: shipment.id, podAtUtcMs });

  const expected = computePayoutBatchAssignment(podAtUtcMs, PAYOUT_BATCH_SCHEDULE);
  assert.equal(out.ledgerLine.firstPayoutEligibleAtUtcMs, expected.firstPayoutEligibleAtUtcMs);
  assert.equal(out.ledgerLine.payoutBatchCutoffUtcMs, expected.payoutBatchCutoffUtcMs);

  // Before cutoff: not paid, and the dry run must not insert a store row.
  const before = await runPayoutBatch(store, { nowUtcMs: expected.payoutBatchCutoffUtcMs - 1 });
  assert.equal(before.totalNetToCarrierPaise, 0);
  assert.equal(before.lineIds.length, 0);
  assert.equal(store.payoutBatches.size, 0);
  assert.equal(store.ledgerLines.get(out.ledgerLine.id)?.status, "ACCRUED");

  // At/after cutoff: paid
  const after = await runPayoutBatch(store, { nowUtcMs: expected.payoutBatchCutoffUtcMs });
  assert.equal(after.totalNetToCarrierPaise, out.ledgerLine.netToCarrierPaise);
  assert.equal(store.ledgerLines.get(out.ledgerLine.id)?.status, "PAID");

  // Default mode is bookkeeping: provider + a single per-carrier transfer is recorded.
  assert.equal(after.provider, "BOOKKEEPING");
  assert.equal(after.transfers.length, 1);
  assert.equal(after.transfers[0]!.status, "BOOKKEEPING_PAID");
  assert.equal(after.transfers[0]!.carrierId, out.ledgerLine.carrierId);
  assert.equal(after.transfers[0]!.netToCarrierPaise, out.ledgerLine.netToCarrierPaise);
  assert.equal(store.payoutBatches.size, 1);
});

test("empty payout-batch ticks are not stored; prune drops heartbeat rows only", async () => {
  const store = createStore();
  const empty = await runPayoutBatch(store, { nowUtcMs: Date.now() });
  assert.equal(empty.lineIds.length, 0);
  assert.equal(empty.transfers.length, 0);
  assert.equal(store.payoutBatches.size, 0);

  store.payoutBatches.set("pay_heartbeat", {
    id: "pay_heartbeat",
    cutoffUtcMs: 1,
    createdAtUtcMs: 1,
    totalNetToCarrierPaise: 0,
    lineIds: [],
    provider: "BOOKKEEPING",
    transfers: [],
  });
  store.payoutBatches.set("pay_failed_provider", {
    id: "pay_failed_provider",
    cutoffUtcMs: 1,
    createdAtUtcMs: 1,
    totalNetToCarrierPaise: 0,
    lineIds: [],
    provider: "RAZORPAYX",
    transfers: [
      {
        carrierId: "org_a",
        netToCarrierPaise: 50000,
        lineIds: ["ll_a1"],
        status: "FAILED",
        error: "insufficient_balance",
      },
    ],
  });
  store.payoutBatches.set("pay_real", {
    id: "pay_real",
    cutoffUtcMs: 1,
    createdAtUtcMs: 1,
    totalNetToCarrierPaise: 100,
    lineIds: ["ll_1"],
    provider: "BOOKKEEPING",
    transfers: [{ carrierId: "org_a", netToCarrierPaise: 100, lineIds: ["ll_1"], status: "BOOKKEEPING_PAID" }],
  });

  assert.equal(pruneEmptyPayoutBatches(store), 1);
  assert.equal(store.payoutBatches.has("pay_heartbeat"), false);
  assert.equal(store.payoutBatches.has("pay_failed_provider"), true);
  assert.equal(store.payoutBatches.has("pay_real"), true);
});

