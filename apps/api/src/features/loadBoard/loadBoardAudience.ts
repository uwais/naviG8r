/**
 * Who may use the Load Board (owner, 4 Nov 2026): a shipper company posts and sees its own loads; only the office of an
 * approved carrier (owner or dispatcher) sees the board and makes routes for it. Never a driver, never another shipper.
 */
import { AuthorizationError, effectivePermissions, legacyRoles, principalFor, type Principal } from "../../rbac.ts";
import { isActiveEntity } from "../../softDelete.ts";
import type { Store } from "../../store.ts";
import type { Notification } from "../../types.ts";

/** The carrier office: whoever may name a trip's truck and driver ("CARRIER" is the legacy role string). */
const CARRIER_OFFICE_ROLES = ["OWNER_DRIVER", "OWNER", "DISPATCHER", "CARRIER"];
const CARRIER_KINDS = ["CARRIER_SOLO", "CARRIER_FLEET", "CARRIER_LEGACY"];

function memberRoles(store: Store, userId: string, orgId: string) {
  const user = store.users.get(userId), org = store.organizations.get(orgId), membership = store.memberships.get(`${userId}:${orgId}`);
  if (!isActiveEntity(user) || !isActiveEntity(org) || !isActiveEntity(membership)) return null;
  const roles = store.membershipRoles.get(`${userId}:${orgId}`) ?? legacyRoles(membership!, org!);
  return { org: org!, subrole: membership!.role, roles, permissions: effectivePermissions(roles, membership!.role) };
}

/** An owner or dispatcher of an approved carrier, who may read notices. */
export function isApprovedCarrierOffice(store: Store, userId: string, orgId: string): boolean {
  const member = memberRoles(store, userId, orgId);
  return member != null && CARRIER_KINDS.includes(member.org.kind) && member.org.kycStatus === "APPROVED"
    && CARRIER_OFFICE_ROLES.includes(member.subrole) && member.roles.includes("CARRIER") && member.permissions.includes("notification.read");
}

/** A member of this shipper company who may read notices, as booking notices go today. */
export function isShipperMember(store: Store, userId: string, orgId: string): boolean {
  const member = memberRoles(store, userId, orgId);
  return member != null && member.org.kind === "CUSTOMER" && member.roles.includes("SHIPPER") && member.permissions.includes("notification.read");
}

/** The signed-in shipper whose company posts or reads its loads: the gate booking uses (an active shipper company, load.create). */
export function requirePostingShipper(store: Store): Principal {
  const principal = principalFor(store);
  const org = store.organizations.get(principal.organizationId);
  if (!principal.roles.includes("SHIPPER") || !principal.permissions.includes("load.create") || org?.kind !== "CUSTOMER" || !isActiveEntity(org)) {
    throw new AuthorizationError("forbidden");
  }
  return principal;
}

/** The signed-in owner or dispatcher of an approved carrier. Drivers, shippers and staff are refused. */
export function requireBoardViewer(store: Store): Principal {
  const principal = principalFor(store);
  if (!principal.roles.includes("CARRIER") || !CARRIER_OFFICE_ROLES.includes(principal.subrole)) throw new AuthorizationError("forbidden");
  if (!isApprovedCarrierOffice(store, principal.userId, principal.organizationId)) throw new AuthorizationError("carrier_compliance_required", 409);
  return principal;
}

/** A Load Board notice is shown, opened or pushed only while its recipient is still in the audience it was written for. */
export function postedLoadNoticeStillTheirs(store: Store, notification: Notification): boolean {
  const load = notification.postedLoadId ? store.postedLoads.get(notification.postedLoadId) : undefined;
  if (!load) return false;
  if (notification.data?.audience === "SHIPPER") {
    return notification.recipientOrgId === load.shipperOrgId && isShipperMember(store, notification.recipientUserId, notification.recipientOrgId);
  }
  return isApprovedCarrierOffice(store, notification.recipientUserId, notification.recipientOrgId);
}
