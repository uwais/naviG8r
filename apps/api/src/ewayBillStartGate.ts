/**
 * Whether a trip's e-way bills let it start (owner, 23 Oct 2026, after tester Uwais: "E-way bill will be finalized
 * to enable trip start"). Every accepted booking needs a bill marked not needed, or a bill that has the trip's truck,
 * a valid-until time still ahead, and no ops result of PROBLEM. Nobody at naviG8r checks bills by hand: this reads
 * only what was typed in. The app mirrors this rule in eway_bill_start_gate.dart; change both together.
 */
import { assignedTruckNumber, portalTruckNumber } from "./tripAssignmentRules.ts";
import type { Store } from "./store.ts";
import type { AnchorTrip, Shipment } from "./types.ts";

export type EwayBillStartBlockReason = "no_bill" | "truck_missing" | "truck_differs" | "expired" | "problem";

/** Shipper names only: every carrier login, a driver included, already sees them. No money. */
export type ShipmentBlockingStart = { shipmentId: string; shipperName: string; reason: EwayBillStartBlockReason };

/** Null when this booking's bill is final. A trip with no truck differs from any truck on a bill. */
export function ewayBillStartBlockReason(shipment: Shipment, tripTruckNumber: string | undefined, nowUtcMs: number): EwayBillStartBlockReason | null {
  const bill = shipment.ewayBill;
  if (!bill) return "no_bill";
  if (bill.kind === "NOT_NEEDED") return null;
  if (!bill.truckNumber) return "truck_missing";
  if (!tripTruckNumber || portalTruckNumber(bill.truckNumber) !== tripTruckNumber) return "truck_differs";
  if (bill.validUntilUtcMs == null || bill.validUntilUtcMs <= nowUtcMs) return "expired";
  if (bill.check?.result === "PROBLEM") return "problem";
  return null;
}

/** The accepted bookings on the trip whose bills are not final, in the order given. */
export function shipmentsBlockingStart(store: Store, trip: AnchorTrip, shipments: Shipment[], nowUtcMs: number): ShipmentBlockingStart[] {
  const tripTruckNumber = assignedTruckNumber(store, trip);
  const blocking: ShipmentBlockingStart[] = [];
  for (const shipment of shipments) {
    if (shipment.status !== "BOOKED") continue;
    const reason = ewayBillStartBlockReason(shipment, tripTruckNumber, nowUtcMs);
    if (reason) blocking.push({ shipmentId: shipment.id, shipperName: shipment.customerOrgName, reason });
  }
  return blocking;
}
