/**
 * Whether a trip's e-way bills let it start (owner, 23 Oct 2026, after tester Uwais: "E-way bill will be finalized
 * to enable trip start"). Every accepted booking needs a bill marked not needed, or a bill that has the trip's truck,
 * a valid-until time still ahead, and no ops result of PROBLEM. NaviG8r does not check every bill by hand: this
 * reads what was typed in, and a problem ops found when it looked a bill up on the portal also holds the trip.
 * The app mirrors this rule in eway_bill_start_gate.dart; change both together.
 */
import { assignedTruckNumber, portalTruckNumber } from "./tripAssignmentRules.ts";
import { isActiveEntity } from "./softDelete.ts";
import type { Store } from "./store.ts";
import type { AnchorTrip, Shipment } from "./types.ts";

export type EwayBillStartBlockReason = "no_bill" | "truck_missing" | "truck_differs" | "expired" | "problem";

/** Shipper names only: every carrier login, a driver included, already sees them. No money. */
export type ShipmentBlockingStart = { shipmentId: string; shipperName: string; reason: EwayBillStartBlockReason };

/**
 * Null when this booking's bill is final. A trip with no truck differs from any truck on a bill. The truck and its
 * valid-until time are saved together, so a bill with no valid-until time is one whose truck is not added yet.
 */
export function ewayBillStartBlockReason(shipment: Shipment, tripTruckNumber: string | undefined, nowUtcMs: number): EwayBillStartBlockReason | null {
  const bill = shipment.ewayBill;
  if (!bill) return "no_bill";
  if (bill.kind === "NOT_NEEDED") return null;
  if (!bill.truckNumber || bill.validUntilUtcMs == null) return "truck_missing";
  if (!tripTruckNumber || portalTruckNumber(bill.truckNumber) !== tripTruckNumber) return "truck_differs";
  if (bill.validUntilUtcMs <= nowUtcMs) return "expired";
  if (bill.check?.result === "PROBLEM") return "problem";
  return null;
}

/** The accepted, not deleted bookings on the trip whose bills are not final, in the order given. */
export function shipmentsBlockingStart(store: Store, trip: AnchorTrip, shipments: Shipment[], nowUtcMs: number): ShipmentBlockingStart[] {
  const tripTruckNumber = assignedTruckNumber(store, trip);
  const blocking: ShipmentBlockingStart[] = [];
  for (const shipment of shipments) {
    if (shipment.status !== "BOOKED" || !isActiveEntity(shipment)) continue;
    const reason = ewayBillStartBlockReason(shipment, tripTruckNumber, nowUtcMs);
    if (reason) blocking.push({ shipmentId: shipment.id, shipperName: shipment.customerOrgName, reason });
  }
  return blocking;
}
