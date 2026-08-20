import assert from "node:assert/strict";
import test from "node:test";
import { createStore } from "./store.ts";
import {
  pilotListCarrierPayoutBatches,
  registerSoloOwnerOperatorDriver,
  runPayoutBatch,
} from "./services.ts";
import type { LedgerLine } from "./types.ts";

const CUTOFF = 1_700_000_000_000;

function addLine(carrierId: string, lineId: string, netPaise: number): LedgerLine {
  return {
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
}

test("pilot payout history hides other carriers in the same settlement batch", async () => {
  const store = createStore();
  const a = registerSoloOwnerOperatorDriver(store, {
    fullName: "Carrier A",
    phone: "9100000101",
    orgDisplayName: "Carrier A",
    vehicleRegistrationNumber: "HR01A",
    vehicleClass: "MEDIUM",
    vehicleCapacityKg: 5000,
  });
  const b = registerSoloOwnerOperatorDriver(store, {
    fullName: "Carrier B",
    phone: "9100000102",
    orgDisplayName: "Carrier B",
    vehicleRegistrationNumber: "HR01B",
    vehicleClass: "MEDIUM",
    vehicleCapacityKg: 5000,
  });

  store.ledgerLines.set("ll_a", addLine(a.org.id, "ll_a", 10_000));
  store.ledgerLines.set("ll_b", addLine(b.org.id, "ll_b", 999_999));

  const batch = await runPayoutBatch(store, { nowUtcMs: CUTOFF });
  assert.equal(batch.transfers.length, 2);
  assert.equal(batch.totalNetToCarrierPaise, 1_009_999);
  assert.equal(batch.lineIds.length, 2);

  const forA = pilotListCarrierPayoutBatches(store, a.user.id, a.org.id);
  assert.equal(forA.length, 1);
  assert.equal(forA[0]!.totalNetToCarrierPaise, 10_000);
  assert.deepEqual(forA[0]!.lineIds, ["ll_a"]);
  assert.equal(forA[0]!.transfers.length, 1);
  assert.equal(forA[0]!.transfers[0]!.carrierId, a.org.id);
  assert.equal(forA[0]!.transfers[0]!.netToCarrierPaise, 10_000);
  assert.equal(
    forA[0]!.transfers.some((t) => t.carrierId === b.org.id),
    false,
  );
  assert.equal(forA[0]!.lineIds.includes("ll_b"), false);

  const forB = pilotListCarrierPayoutBatches(store, b.user.id, b.org.id);
  assert.equal(forB.length, 1);
  assert.equal(forB[0]!.totalNetToCarrierPaise, 999_999);
  assert.deepEqual(forB[0]!.lineIds, ["ll_b"]);
  assert.equal(forB[0]!.transfers[0]!.carrierId, b.org.id);

  assert.throws(
    () => pilotListCarrierPayoutBatches(store, a.user.id, b.org.id),
    (e: Error) => e.message === "membership_not_found",
  );
});
