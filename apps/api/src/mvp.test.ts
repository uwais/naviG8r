import assert from "node:assert/strict";
import test from "node:test";
import { computePayoutBatchAssignment, utcMsFromIstWallParts } from "../../../packages/core/src/payoutSchedule.ts";
import { PAYOUT_BATCH_SCHEDULE } from "./config.ts";
import { createStore } from "./store.ts";
import { bookShipment, createCarrier, markPodDelivered, publishAnchorTrip, runPayoutBatch } from "./services.ts";

test("vertical slice: publish trip -> book (capture) -> POD -> ledger -> weekly batch pays after cutoff", () => {
  const store = createStore();
  const carrier = createCarrier(store, "Carrier One");
  const trip = publishAnchorTrip(store, {
    carrierId: carrier.id,
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

  const pay = store.payments.get(shipment.paymentId);
  assert.equal(pay?.status, "CAPTURED");
  assert.equal(store.anchorTrips.get(trip.id)?.reservedKg, 200);

  // POD at IST: Mar 21, 2024 00:00
  const podAtUtcMs = utcMsFromIstWallParts(2024, 2, 21, 0, 0, 0, 0);
  const out = markPodDelivered(store, { shipmentId: shipment.id, podAtUtcMs });

  const expected = computePayoutBatchAssignment(podAtUtcMs, PAYOUT_BATCH_SCHEDULE);
  assert.equal(out.ledgerLine.firstPayoutEligibleAtUtcMs, expected.firstPayoutEligibleAtUtcMs);
  assert.equal(out.ledgerLine.payoutBatchCutoffUtcMs, expected.payoutBatchCutoffUtcMs);

  // Before cutoff: not paid
  const before = runPayoutBatch(store, { nowUtcMs: expected.payoutBatchCutoffUtcMs - 1 });
  assert.equal(before.totalNetToCarrierPaise, 0);
  assert.equal(store.ledgerLines.get(out.ledgerLine.id)?.status, "ACCRUED");

  // At/after cutoff: paid
  const after = runPayoutBatch(store, { nowUtcMs: expected.payoutBatchCutoffUtcMs });
  assert.equal(after.totalNetToCarrierPaise, out.ledgerLine.netToCarrierPaise);
  assert.equal(store.ledgerLines.get(out.ledgerLine.id)?.status, "PAID");
});

