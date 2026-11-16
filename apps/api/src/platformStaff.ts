/** NaviG8r staff (ADMIN, OPS, FINANCE on the platform organisation), listed and added by an admin from the staff pages. */
import type { Store } from "./store.ts";
import { isActiveEntity } from "./softDelete.ts";
import { AuthorizationError, legacyRoles, recordAudit, requirePermission, type Role } from "./rbac.ts";
import { findUserByPhone, storedCountryCode } from "./phone.ts";
import { registerCustomerUser } from "./services.ts";
import { reason as requireReasonCode, setInternalAccess } from "./dashboard.ts";

export const STAFF_ROLES: readonly Role[] = ["ADMIN", "OPS", "FINANCE"];

export type StaffMember = { userId: string; fullName: string; countryCode: string; phoneLastFour: string; roles: Role[] };

function rolesOf(store: Store, userId: string, orgId: string): Role[] {
  const membership = store.memberships.get(`${userId}:${orgId}`), org = store.organizations.get(orgId);
  if (!membership || !org || !isActiveEntity(membership)) return [];
  return store.membershipRoles.get(`${userId}:${orgId}`) ?? legacyRoles(membership, org);
}

function staffMember(store: Store, userId: string, orgId: string): StaffMember {
  const user = store.users.get(userId)!;
  // Only the last four digits: the page needs to tell people apart, not to call them.
  return { userId, fullName: user.fullName, countryCode: storedCountryCode(user.countryCode), phoneLastFour: user.phone.slice(-4), roles: rolesOf(store, userId, orgId) };
}

/** Everyone holding at least one role in the acting admin's platform organisation. */
export function listStaff(store: Store): StaffMember[] {
  const p = requirePermission(store, "user.role_manage");
  if (!p.internal) throw new AuthorizationError("forbidden");
  return [...store.memberships.values()]
    .filter((m) => m.orgId === p.organizationId && isActiveEntity(m) && isActiveEntity(store.users.get(m.userId)))
    .map((m) => staffMember(store, m.userId, p.organizationId))
    .filter((s) => s.roles.length > 0)
    .sort((a, b) => a.fullName.localeCompare(b.fullName));
}

function staffRoles(raw: unknown, allowNone: boolean): Role[] {
  if (!Array.isArray(raw) || raw.some((r) => !STAFF_ROLES.includes(r)) || (!allowNone && raw.length === 0))
    throw new AuthorizationError("invalid_role", 400);
  return [...new Set(raw)] as Role[];
}

/**
 * Adds a person as staff by phone, making their account first if the number has none. A number that already
 * belongs to a shipper or carrier is refused: a second organisation would change what that person's app does.
 */
export function addStaff(store: Store, input: { fullName?: unknown; phone?: unknown; countryCode?: unknown; roles?: unknown }): StaffMember {
  const p = requirePermission(store, "user.role_manage");
  if (!p.internal) throw new AuthorizationError("forbidden");
  // Checked before an account is made, so a refused request leaves nothing behind.
  requireReasonCode();
  const roles = staffRoles(input.roles, false);
  // The country is never assumed, so a US number is never read as an Indian one.
  if (input.countryCode == null || input.countryCode === "") throw new AuthorizationError("invalid_country_code", 400);
  let user = findUserByPhone(store, input.phone, input.countryCode);
  if (user && !isActiveEntity(user)) throw new AuthorizationError("account_inactive", 409);
  if (user) {
    const elsewhere = [...store.memberships.values()].some((m) =>
      m.userId === user!.id && m.orgId !== p.organizationId && isActiveEntity(m) &&
      isActiveEntity(store.organizations.get(m.orgId)) && store.organizations.get(m.orgId)!.kind !== "PLATFORM");
    if (elsewhere) throw new AuthorizationError("staff_number_has_customer_account", 409);
  } else {
    user = registerCustomerUser(store, { fullName: String(input.fullName ?? ""), phone: String(input.phone ?? ""), countryCode: String(input.countryCode) }).user;
    recordAudit(store, "STAFF_USER_CREATED", "user", user.id, "ABSENT", "CREATED");
  }
  setInternalAccess(store, { userId: user.id, roles });
  return staffMember(store, user.id, p.organizationId);
}

/** Changes a staff member's roles; no roles removes them. The last admin cannot be removed. */
export function changeStaffRoles(store: Store, userId: string, input: { roles?: unknown }): StaffMember {
  const p = requirePermission(store, "user.role_manage");
  if (!p.internal) throw new AuthorizationError("forbidden");
  const roles = staffRoles(input.roles, true);
  if (!store.memberships.has(`${userId}:${p.organizationId}`)) throw new AuthorizationError("not_found", 404);
  setInternalAccess(store, { userId, roles });
  return staffMember(store, userId, p.organizationId);
}
