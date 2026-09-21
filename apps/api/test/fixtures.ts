import { randomUUID } from "node:crypto";
import { authorizationContext, resolvePrincipal, acceptPod, type Role } from "../src/rbac.ts";
import type { Store } from "../src/store.ts";
import { bookShipment, registerSoloOwnerOperatorDriver, registerCustomerOrgAdmin, submitDriverPod, releasePaymentAndDeliver, runPayoutBatch } from "../src/services.ts";

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
export async function deliverTestShipment(store: Store, params: { shipmentId: string; podAtUtcMs?: number }) {
  const shipment = store.shipments.get(params.shipmentId)!;
  const carrier = [...store.memberships.values()].find(m => m.orgId === shipment.carrierId)!;
  submitDriverPod(store, { shipmentId: shipment.id, userId: carrier.userId });
  if (params.podAtUtcMs != null) store.shipments.set(shipment.id, { ...store.shipments.get(shipment.id)!, podAtUtcMs: params.podAtUtcMs });
  const shipper = [...store.memberships.values()].find(m => m.orgId === shipment.customerOrgId)!;
  asUser(store, shipper.userId, () => acceptPod(store, shipment.id), shipper.orgId);
  return asFinance(store, () => releasePaymentAndDeliver(store, { shipmentId: shipment.id }));
}
export function runTestPayoutBatch(store: Store, params: Parameters<typeof runPayoutBatch>[1]) { return asFinance(store, () => runPayoutBatch(store, params)); }
