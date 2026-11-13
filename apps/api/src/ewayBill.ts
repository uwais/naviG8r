/**
 * The e-way bill record on a shipment: the shipper types it in, ops checks it by hand on the
 * government portal, carriers read it. naviG8r never makes, changes or verifies a bill itself.
 * Format checks are in ewayBillValidation.ts; what each role may see is in ewayBillVisibility.ts.
 */
import { AuthorizationError, recordAudit, requirePermission } from "./rbac.ts";
import { ApiError, shipmentWithCarrierDisplay } from "./services.ts";
import { isActiveEntity } from "./softDelete.ts";
import type { Store } from "./store.ts";
import type { EwayBill, EwayBillProblemReason, Shipment } from "./types.ts";
import { checkEwayBillDetails, checkEwayBillStatement, checkEwayBillTruck } from "./ewayBillValidation.ts";

const PROBLEM_REASONS: readonly string[] = ["NOT_FOUND", "CANCELLED", "DETAILS_DO_NOT_MATCH", "OTHER"];

/** Changes stay open until delivery is accepted (brief section 8). */
function lockedForChanges(shipment: Shipment): boolean {
  return shipment.status === "DELIVERED" || shipment.status === "FAILED_CARRIER_REFUNDED" || shipment.podAcceptedAtUtcMs != null;
}

function lockedError(): ApiError {
  return new ApiError("eway_bill_locked", { detail: "This shipment is already delivered, so its e-way bill can no longer be changed." }, 409);
}

function findShipment(store: Store, shipmentId: string): Shipment {
  const shipment = store.shipments.get(shipmentId);
  if (!shipment) throw new AuthorizationError("not_found", 404);
  return shipment;
}

/** Audit rows hold state words only, never typed text. */
function stateWord(bill: EwayBill | undefined): string {
  return bill?.kind ?? "ABSENT";
}

export function saveEwayBill(store: Store, shipmentId: string, input: Record<string, unknown>): Shipment {
  const shipment = findShipment(store, shipmentId);
  const principal = requirePermission(store, "eway_bill.write", shipment);
  if (lockedForChanges(shipment)) throw lockedError();
  const now = Date.now();
  const entered = { enteredAtUtcMs: now, enteredByUserId: principal.userId };
  let bill: EwayBill;
  if (input.kind === "BILL") {
    const checked = checkEwayBillDetails(input, now);
    if (!checked.ok) throw new ApiError("invalid_eway_bill", { detail: checked.detail, field: checked.field });
    // The truck belongs to the bill on the portal: keep it through an edit of the same bill, drop it for a different one.
    const before = shipment.ewayBill;
    const truck = before?.kind === "BILL" && before.billNumber === checked.value.billNumber && before.truckNumber && before.validUntilUtcMs && before.truckEnteredByUserId
      ? { truckNumber: before.truckNumber, validUntilUtcMs: before.validUntilUtcMs, truckEnteredByUserId: before.truckEnteredByUserId }
      : {};
    bill = { kind: "BILL", ...checked.value, ...truck, ...entered };
  } else if (input.kind === "NOT_NEEDED") {
    const checked = checkEwayBillStatement(input);
    if (!checked.ok) throw new ApiError("invalid_eway_bill", { detail: checked.detail, field: checked.field });
    bill = { kind: "NOT_NEEDED", notNeededReason: checked.value.reason, ...(checked.value.note ? { notNeededNote: checked.value.note } : {}), ...entered };
  } else {
    throw new ApiError("invalid_eway_bill", { detail: "Choose whether you are adding an e-way bill or saying none is needed.", field: "kind" });
  }
  // A new record has no check: editing always clears what ops saw.
  const updated: Shipment = { ...shipment, ewayBill: bill, updatedAtUtcMs: now };
  store.shipments.set(updated.id, updated);
  recordAudit(store, bill.kind === "BILL" ? "EWAY_BILL_ENTERED" : "EWAY_BILL_NOT_NEEDED_STATED", "shipment", updated.id, stateWord(shipment.ewayBill), bill.kind);
  return updated;
}

/**
 * Part B: the truck and the valid-until time, typed in after the shipper added the truck to the bill on the portal.
 * Only the shipper does it; the carrier and its drivers read it (owner decision, 18 Oct 2026).
 * Any change clears ops' check, like every other detail.
 */
export function addEwayBillTruck(store: Store, shipmentId: string, input: Record<string, unknown>): Shipment {
  const shipment = findShipment(store, shipmentId);
  const principal = requirePermission(store, "eway_bill.add_truck", shipment);
  if (lockedForChanges(shipment)) throw lockedError();
  const bill = shipment.ewayBill;
  if (bill?.kind !== "BILL") {
    throw new ApiError("eway_bill_not_entered", { detail: "The shipper has not added an e-way bill to this shipment yet." }, 409);
  }
  // The carrier can still change the truck until it accepts, so a truck added now could be the wrong one.
  if (shipment.status === "PENDING_CARRIER_ACCEPT") {
    throw new ApiError("carrier_not_accepted", { detail: "Add the truck once the carrier accepts." }, 409);
  }
  const now = Date.now();
  const checked = checkEwayBillTruck(input, now);
  if (!checked.ok) throw new ApiError("invalid_eway_truck", { detail: checked.detail, field: checked.field });
  const next: EwayBill = { ...bill, ...checked.value, truckEnteredByUserId: principal.userId };
  delete next.check;
  const updated: Shipment = { ...shipment, ewayBill: next, updatedAtUtcMs: now };
  store.shipments.set(updated.id, updated);
  recordAudit(store, "EWAY_BILL_TRUCK_ADDED", "shipment", updated.id, bill.truckNumber ? "TRUCK_ADDED" : "NO_TRUCK", "TRUCK_ADDED");
  return updated;
}

export function removeEwayBill(store: Store, shipmentId: string): Shipment {
  const shipment = findShipment(store, shipmentId);
  requirePermission(store, "eway_bill.write", shipment);
  if (lockedForChanges(shipment)) throw lockedError();
  // The truck is on the road with the bill once the trip starts (owner, 23 Oct 2026); editing it stays allowed.
  const tripStatus = store.anchorTrips.get(shipment.anchorTripId)?.status;
  if (tripStatus === "IN_PROGRESS" || tripStatus === "COMPLETED") {
    throw new ApiError("trip_started", { detail: "The trip has started, so the e-way bill cannot be removed." }, 409);
  }
  if (!shipment.ewayBill) return shipment;
  const updated: Shipment = { ...shipment, updatedAtUtcMs: Date.now() };
  delete updated.ewayBill;
  store.shipments.set(updated.id, updated);
  recordAudit(store, "EWAY_BILL_REMOVED", "shipment", updated.id, stateWord(shipment.ewayBill), "ABSENT");
  return updated;
}

/** Ops records what it saw on the portal. Last writer wins, as with carrier review. */
export function checkEwayBill(store: Store, shipmentId: string, input: Record<string, unknown>): Shipment {
  const shipment = findShipment(store, shipmentId);
  const principal = requirePermission(store, "eway_bill.check", shipment);
  if (lockedForChanges(shipment)) throw lockedError();
  const bill = shipment.ewayBill;
  if (bill?.kind !== "BILL") {
    throw new ApiError("eway_bill_not_entered", { detail: "This shipment has no e-way bill entered to check." }, 409);
  }
  const result = input.result;
  const problemReason = input.problemReason;
  if (result !== "FOUND" && result !== "PROBLEM") {
    throw new ApiError("invalid_eway_check", { detail: "Say whether you found the bill or found a problem.", field: "result" });
  }
  if (result === "PROBLEM" && !PROBLEM_REASONS.includes(String(problemReason))) {
    throw new ApiError("invalid_eway_check", { detail: "Choose what the problem is.", field: "problemReason" });
  }
  // The check names the bill ops looked up, so it cannot land on one the shipper replaced after the list loaded.
  if (input.billNumber !== bill.billNumber) {
    throw new ApiError("eway_bill_changed", { detail: "The shipper changed this bill after your list loaded. Reload and look it up again." }, 409);
  }
  const now = Date.now();
  const check: NonNullable<EwayBill["check"]> = {
    result,
    ...(result === "PROBLEM" ? { problemReason: problemReason as EwayBillProblemReason } : {}),
    checkedAtUtcMs: now,
    checkedByUserId: principal.userId,
  };
  const updated: Shipment = { ...shipment, ewayBill: { ...bill, check }, updatedAtUtcMs: now };
  store.shipments.set(updated.id, updated);
  const previous = bill.check ? (bill.check.problemReason ? `PROBLEM_${bill.check.problemReason}` : "FOUND") : "UNCHECKED";
  recordAudit(store, "EWAY_BILL_CHECKED", "shipment", updated.id, previous, check.problemReason ? `PROBLEM_${check.problemReason}` : "FOUND");
  return updated;
}

/** The three lists ops works from, oldest booking first. Delivered and refunded shipments are left out. */
export function listEwayBillsForOps(store: Store): { toCheck: Shipment[]; missing: Shipment[]; notNeeded: Shipment[] } {
  requirePermission(store, "eway_bill.check");
  const open = [...store.shipments.values()]
    .filter((s) => isActiveEntity(s) && !lockedForChanges(s))
    .sort((a, b) => a.createdAtUtcMs - b.createdAtUtcMs || a.id.localeCompare(b.id))
    .map((s) => shipmentWithCarrierDisplay(store, s));
  return {
    toCheck: open.filter((s) => s.ewayBill?.kind === "BILL" && !s.ewayBill.check),
    missing: open.filter((s) => !s.ewayBill && (s.status === "PENDING_CARRIER_ACCEPT" || s.status === "BOOKED")),
    notNeeded: open.filter((s) => s.ewayBill?.kind === "NOT_NEEDED"),
  };
}
