import { randomUUID } from "node:crypto";
import { authorizationContext, resolvePrincipal, acceptPod, type Role } from "../src/rbac.ts";
import type { Store } from "../src/store.ts";
import { bookShipment, registerSoloOwnerOperatorDriver, registerCustomerOrgAdmin, submitDriverPod, releasePaymentAndDeliver, runPayoutBatch } from "../src/services.ts";
import { assignedTruckNumber } from "../src/tripAssignmentRules.ts";

export function internalUser(store: Store, role: Role, id = `test-${role}`) {
  const orgId = "test-platform";
  store.organizations.set(orgId, { id: orgId, kind: "PLATFORM", displayName: "Synthetic platform", kycStatus: "APPROVED", createdAtUtcMs: 1 });
  const user = { id, phone: String(9000000000 + store.users.size), fullName: `Synthetic ${role}`, createdAtUtcMs: 1 };
  store.users.set(id, user);
  store.memberships.set(`${id}:${orgId}`, { userId: id, orgId, role, createdAtUtcMs: 1 });
  store.membershipRoles.set(`${id}:${orgId}`, [role]);
  return { user, orgId, userId: id };
}
export function asUser<T>(store: Store, userId: string, fn: () => T, orgId?: string): T {
  return authorizationContext.run({ principal: resolvePrincipal(store, userId, orgId), requestId: randomUUID() }, fn);
}
export function asFinance<T>(store: Store, fn: () => T): T {
  const { userId, orgId } = internalUser(store, "FINANCE");
  return asUser(store, userId, fn, orgId);
}
export function registerCompliantCarrier(store: Store, params: Parameters<typeof registerSoloOwnerOperatorDriver>[1]) {
  const out = registerSoloOwnerOperatorDriver(store, params);
  store.organizations.set(out.org.id, { ...out.org, kycStatus: "APPROVED" });
  return out;
}
/** Authenticated shipper fixture for existing domain tests, without bypassing policy. */
export function bookTestShipment(store: Store, params: Parameters<typeof bookShipment>[1]) {
  let org = params.customerOrg && store.organizations.get(params.customerOrg.id);
  let userId = params.bookedByUserId;
  if (org) userId ??= [...store.memberships.values()].find(m => m.orgId === org!.id)?.userId;
  if (!org && userId) {
    const m = [...store.memberships.values()].find(m => m.userId === userId && store.organizations.get(m.orgId)?.kind === "CUSTOMER");
    if (m) org = store.organizations.get(m.orgId);
  }
  if (!org) {
    const customer = registerCustomerOrgAdmin(store, { fullName: "Synthetic buyer", phone: String(8000000000 + store.users.size), orgDisplayName: params.customerOrgName });
    org = customer.org; userId = customer.user.id;
  }
  return asUser(store, userId!, () => bookShipment(store, { ...params, customerOrg: { id: org!.id, displayName: org!.displayName }, bookedByUserId: userId }), org.id);
}
/** A carrier confirms delivery with a photo. Tests that are not about the photo record one with no file behind it. */
export function addTestPodPhoto(store: Store, shipmentId: string): void {
  const shipment = store.shipments.get(shipmentId)!;
  store.shipments.set(shipmentId, { ...shipment, podPhotos: [{ id: randomUUID(), contentType: "image/jpeg", bytes: 1, sha256: "synthetic", uploadedAtUtcMs: 1, uploadedByUserId: "synthetic" }] });
}
/**
 * A final e-way bill, so the trip can start: the trip's truck, valid for three more days, or a statement that none
 * is needed when the trip has no truck. Tests about the start rule itself write their own bills.
 */
export function addFinalTestEwayBill(store: Store, shipmentId: string): void {
  const shipment = store.shipments.get(shipmentId)!;
  const truckNumber = assignedTruckNumber(store, store.anchorTrips.get(shipment.anchorTripId));
  const entered = { enteredAtUtcMs: 1, enteredByUserId: "synthetic" };
  const ewayBill = truckNumber
    ? { kind: "BILL" as const, billNumber: "123456789012", truckNumber, validUntilUtcMs: Date.now() + 3 * 86400000, ...entered }
    : { kind: "NOT_NEEDED" as const, notNeededReason: "BELOW_THRESHOLD" as const, ...entered };
  store.shipments.set(shipmentId, { ...shipment, ewayBill });
}
/**
 * Puts a shipment's trip on the way without the start's own checks, since proof of delivery waits for the start.
 * A trip already on the way or finished is left as it is. Tests about the start rule itself start the trip.
 */
export function startTestTrip(store: Store, shipmentId: string): void {
  const trip = store.anchorTrips.get(store.shipments.get(shipmentId)!.anchorTripId)!;
  if (trip.status !== "OPEN" && trip.status !== "FULL") return;
  store.anchorTrips.set(trip.id, { ...trip, status: "IN_PROGRESS", startedAtUtcMs: Date.now() });
}
export async function deliverTestShipment(store: Store, params: { shipmentId: string; podAtUtcMs?: number }) {
  const shipment = store.shipments.get(params.shipmentId)!;
  const carrier = [...store.memberships.values()].find(m => m.orgId === shipment.carrierId)!;
  startTestTrip(store, shipment.id);
  addTestPodPhoto(store, shipment.id);
  submitDriverPod(store, { shipmentId: shipment.id, userId: carrier.userId });
  if (params.podAtUtcMs != null) store.shipments.set(shipment.id, { ...store.shipments.get(shipment.id)!, podAtUtcMs: params.podAtUtcMs });
  const shipper = [...store.memberships.values()].find(m => m.orgId === shipment.customerOrgId)!;
  asUser(store, shipper.userId, () => acceptPod(store, shipment.id), shipper.orgId);
  return asFinance(store, () => releasePaymentAndDeliver(store, { shipmentId: shipment.id }));
}
export function runTestPayoutBatch(store: Store, params: Parameters<typeof runPayoutBatch>[1]) { return asFinance(store, () => runPayoutBatch(store, params)); }
