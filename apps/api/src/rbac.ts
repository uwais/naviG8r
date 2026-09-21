import { AsyncLocalStorage } from "node:async_hooks";
import { randomUUID } from "node:crypto";
import type { Store } from "./store.ts";
import type { Membership, Organization, Shipment } from "./types.ts";
import { isActiveEntity } from "./softDelete.ts";

export const ROLES = ["SHIPPER", "CARRIER", "OPS", "FINANCE", "ADMIN"] as const;
export type Role = typeof ROLES[number];
export const ROLE_PERMISSIONS = {
  SHIPPER: ["organization.profile.read", "organization.member.invite", "load.create", "load.read", "pod.accept", "payment.read", "payment.checkout", "kyc.status_read", "audit.read", "integration.manage"],
  CARRIER: ["organization.profile.read", "organization.member.invite", "load.read", "trip.publish", "load.status_update", "carrier.offer_accept", "pod.upload", "payment.read", "bank_account.create_token", "kyc.status_read", "audit.read"],
  OPS: ["organization.profile.read", "load.create", "load.read", "trip.publish", "load.status_update", "pod.upload", "payment.read", "kyc.status_read", "kyc.verify", "audit.read"],
  FINANCE: ["organization.profile.read", "load.read", "payment.read", "payment.capture", "payment.refund", "settlement.release", "kyc.status_read", "audit.read"],
  ADMIN: ["organization.profile.read", "load.read", "payment.read", "user.role_manage", "kyc.status_read", "audit.read"],
} as const;
export type Permission = typeof ROLE_PERMISSIONS[Role][number];
export const PERMISSIONS: readonly string[] = [...new Set(Object.values(ROLE_PERMISSIONS).flat())];
export type AuditEvent = {
  id: string; actorUserId: string; actorOrganizationId: string; effectiveActorId?: string;
  action: string; resourceType: string; resourceId: string; previousState?: string;
  newState?: string; reasonCode?: string; requestId: string; timestamp: number;
  source: "USER" | "OPS_ASSISTED" | "SYSTEM";
};
export type Principal = {
  userId: string; organizationId: string; roles: Role[]; subrole: string;
  internal: boolean; permissions: string[]; membershipActive: boolean;
};
export type RequestContext = { principal?: Principal; reason?: string; effectiveActorId?: string; requestId: string; system?: boolean };
export const authorizationContext = new AsyncLocalStorage<RequestContext>();
export class AuthorizationError extends Error {
  status: number;
  constructor(message: string, status = 403) { super(message); this.status = status; }
}
export function compatibleRole(role: string, org: Organization): role is Role {
  return (role === "SHIPPER" && org.kind === "CUSTOMER") ||
    (role === "CARRIER" && ["CARRIER_SOLO", "CARRIER_FLEET", "CARRIER_LEGACY"].includes(org.kind)) ||
    (["OPS", "FINANCE", "ADMIN"].includes(role) && org.kind === "PLATFORM");
}
export function legacyRoles(m: Membership, org: Organization): Role[] {
  const mapping: Record<string, Role[]> = { CUSTOMER_ADMIN: ["SHIPPER"], CUSTOMER_MEMBER: ["SHIPPER"], OWNER_DRIVER: ["CARRIER"], OWNER: ["CARRIER"], DISPATCHER: ["CARRIER"], DRIVER: ["CARRIER"], OPS_AGENT: ["OPS"], OPS_ADMIN: ["ADMIN", "OPS"], FINANCE: ["FINANCE"], ADMIN: ["ADMIN"], OPS: ["OPS"], SHIPPER: ["SHIPPER"], CARRIER: ["CARRIER"] };
  return (mapping[m.role] ?? []).filter(r => compatibleRole(r, org));
}
export function effectivePermissions(roles: Role[], subrole: string): string[] {
  return [...new Set(roles.flatMap(r => [...(ROLE_PERMISSIONS[r] ?? [])]))].filter(p => {
    if (p === "organization.member.invite") return ["CUSTOMER_ADMIN", "OWNER_DRIVER", "OWNER", "DISPATCHER"].includes(subrole);
    if (p === "integration.manage") return subrole === "CUSTOMER_ADMIN";
    if (p === "bank_account.create_token") return ["OWNER_DRIVER", "OWNER"].includes(subrole);
    return true;
  });
}
export function resolvePrincipal(store: Store, userId: string, organizationId?: string | null): Principal {
  const user = store.users.get(userId);
  if (!user || !isActiveEntity(user)) throw new AuthorizationError("unauthorized", 401);
  const current = authorizationContext.getStore()?.principal;
  if (current && current.userId !== userId) throw new AuthorizationError("forbidden");
  const selected = current?.organizationId ?? organizationId;
  const memberships = [...store.memberships.values()].filter(m => m.userId === userId && isActiveEntity(m) && isActiveEntity(store.organizations.get(m.orgId)));
  const m = selected ? memberships.find(m => m.orgId === selected) : memberships.length === 1 ? memberships[0] : undefined;
  if (!m) throw new AuthorizationError(!selected && memberships.length > 1 ? "active_organization_required" : "membership_inactive", !selected && memberships.length > 1 ? 400 : 403);
  const org = store.organizations.get(m.orgId)!;
  const key = `${m.userId}:${m.orgId}`;
  const assigned = store.membershipRoles.get(key) ?? legacyRoles(m, org);
  const roles = assigned.filter(r => compatibleRole(r, org));
  return { userId, organizationId: org.id, roles, subrole: m.role, internal: org.kind === "PLATFORM", membershipActive: true, permissions: effectivePermissions(roles, m.role) };
}
export function principalFor(store: Store, userId?: string): Principal {
  const p = authorizationContext.getStore()?.principal;
  if (!userId && !p) throw new AuthorizationError("unauthorized", 401);
  return resolvePrincipal(store, userId ?? p!.userId, p?.organizationId);
}
export type Resource = { customerOrgId?: string; carrierId?: string; orgId?: string; inactiveAtUtcMs?: number | null; status?: string; podAtUtcMs?: number | null; podAcceptedAtUtcMs?: number | null };
export function visible(p: Principal, r: Resource | undefined): boolean {
  if (!r || !isActiveEntity(r)) return false;
  if (p.internal) return p.roles.some(r => ["OPS", "FINANCE", "ADMIN"].includes(r));
  return (p.roles.includes("SHIPPER") && r.customerOrgId === p.organizationId) ||
    (p.roles.includes("CARRIER") && r.carrierId === p.organizationId) || r.orgId === p.organizationId;
}
export function paymentReady(s: Resource | undefined, now = Date.now()): boolean {
  if (!s || !["PENDING_RELEASE", "DELIVERED"].includes(s.status ?? "")) return false;
  if (!Number.isFinite(s.podAtUtcMs) || s.podAtUtcMs! < 0 || s.podAtUtcMs! > now) return false;
  return (Number.isFinite(s.podAcceptedAtUtcMs) && s.podAcceptedAtUtcMs! >= s.podAtUtcMs! && s.podAcceptedAtUtcMs! <= now) || now >= s.podAtUtcMs! + 48 * 60 * 60 * 1000;
}
export function authorize(p: Principal | undefined, permission: string, resource?: Resource, now = Date.now()): boolean {
  if (!p?.membershipActive || !p.organizationId || !p.roles.length || p.roles.some(r => !ROLES.includes(r)) || !PERMISSIONS.includes(permission)) return false;
  if (!effectivePermissions(p.roles, p.subrole).includes(permission) || !p.permissions.includes(permission)) return false;
  if (resource && !visible(p, resource)) return false;
  if (["load.read", "pod.upload", "pod.accept", "carrier.offer_accept", "load.status_update", "payment.capture", "payment.refund"].includes(permission) && !resource) return false;
  if (permission === "payment.capture" && !paymentReady(resource, now)) return false;
  return true;
}
export function requirePermission(store: Store, permission: Permission, resource?: Resource, userId?: string): Principal {
  const p = principalFor(store, userId);
  if (resource && !visible(p, resource)) throw new AuthorizationError("not_found", 404);
  if (!authorize(p, permission, resource)) throw new AuthorizationError(permission === "payment.capture" && p.permissions.includes(permission) ? "payment_hold_active" : "forbidden");
  return p;
}
export function requireAssistance(store: Store, p: Principal, carrierId?: string): void {
  if (!p.roles.includes("OPS")) return;
  const c = authorizationContext.getStore();
  if (!c?.reason || !/^[A-Z][A-Z0-9_]{2,63}$/.test(c.reason) || !c.effectiveActorId) throw new AuthorizationError("assistance_attribution_required", 400);
  const member = store.memberships.get(`${c.effectiveActorId}:${carrierId}`);
  if (!member || !isActiveEntity(member) || !isActiveEntity(store.users.get(member.userId))) throw new AuthorizationError("invalid_effective_actor", 400);
}
export function recordAudit(store: Store, action: string, resourceType: string, resourceId: string, previousState?: string, newState?: string): void {
  const c = authorizationContext.getStore();
  if (!c?.principal && !c?.system) throw new AuthorizationError("audit_actor_required");
  const event: AuditEvent = { id: randomUUID(), actorUserId: c.principal?.userId ?? "system:payout", actorOrganizationId: c.principal?.organizationId ?? "org_platform_ops", action, resourceType, resourceId, previousState, newState, reasonCode: c.reason && /^[A-Z][A-Z0-9_]{2,63}$/.test(c.reason) ? c.reason : undefined, effectiveActorId: c.effectiveActorId, requestId: c.requestId, timestamp: Date.now(), source: c.system ? "SYSTEM" : c.principal?.roles.includes("OPS") && c.effectiveActorId ? "OPS_ASSISTED" : "USER" };
  store.auditEvents.set(event.id, event);
}
export function migrateAuthorization(store: Store): void {
  for (const m of store.memberships.values()) {
    const org = store.organizations.get(m.orgId);
    const key = `${m.userId}:${m.orgId}`;
    if (org && !store.membershipRoles.has(key)) store.membershipRoles.set(key, isActiveEntity(m) && isActiveEntity(org) ? legacyRoles(m, org) : []);
  }
  for (const s of store.shipments.values()) {
    if (s.customerOrgId || !s.bookedByUserId) continue;
    const memberships = [...store.memberships.values()].filter(m => m.userId === s.bookedByUserId && isActiveEntity(m) && store.organizations.get(m.orgId)?.kind === "CUSTOMER" && isActiveEntity(store.organizations.get(m.orgId)));
    if (memberships.length === 1) store.shipments.set(s.id, { ...s, customerOrgId: memberships[0]!.orgId });
  }
}
export function acceptPod(store: Store, shipmentId: string): Shipment {
  const s = store.shipments.get(shipmentId);
  if (!s) throw new AuthorizationError("not_found", 404);
  const p = requirePermission(store, "pod.accept", s);
  if (s.status !== "PENDING_RELEASE" || !s.podAtUtcMs) throw new AuthorizationError("pod_not_pending", 409);
  if (s.podAcceptedAtUtcMs) return s;
  const updated = { ...s, podAcceptedAtUtcMs: Date.now(), podAcceptedByUserId: p.userId };
  store.shipments.set(s.id, updated);
  recordAudit(store, "POD_ACCEPTED", "shipment", s.id, "PENDING", "ACCEPTED");
  return updated;
}
