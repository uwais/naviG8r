import { createHash } from "node:crypto";
import type { Store } from "./store.ts";
import { isActiveEntity } from "./softDelete.ts";
import {
  assertAdminRemains,
  authorizationContext,
  AuthorizationError,
  principalFor,
  requirePermission,
  legacyRoles,
  compatibleRole,
  recordAudit,
  ROLES,
  type Role,
  type Permission,
} from "./rbac.ts";
import { serializeResponse } from "./rbacResponses.ts";
import { payoutsMode } from "./razorpayPayouts.ts";

const select = (row: object, fields: string[]) =>
  Object.fromEntries(
    fields
      .filter((k) => k in row)
      .map((k) => [k, (row as Record<string, unknown>)[k]]),
  );
export const dashboardPermissions: Record<string, Permission> = {
  carriers: "directory.read",
  organizations: "directory.read",
  users: "user.role_manage",
  memberships: "user.role_manage",
  vehicles: "fleet.read",
  drivers: "fleet.read",
  trips: "load.read",
  shipments: "load.read",
  ledger: "payment.read",
  payouts: "payment.read",
  members: "trip.publish",
};

/** Every collection has its own permission and explicit projection, even for internal users. */
export function dashboardList(
  store: Store,
  section: string,
  query: URLSearchParams,
) {
  const p = principalFor(store);
  const permission = dashboardPermissions[section];
  if (!p.internal || !permission || !p.permissions.includes(permission))
    throw new AuthorizationError("forbidden");
  if (["ledger", "payouts"].includes(section) && !p.roles.includes("FINANCE"))
    throw new AuthorizationError("forbidden");
  const inactive = query.get("inactive") === "true";
  if (inactive && !p.roles.includes("ADMIN"))
    throw new AuthorizationError("forbidden");
  const active = (row: { inactiveAtUtcMs?: number | null }) =>
    inactive || isActiveEntity(row);
  const activeOrg = (orgId: string) =>
    inactive || isActiveEntity(store.organizations.get(orgId));
  const limit = Number(query.get("limit") ?? 25),
    offset = Number(query.get("offset") ?? 0);
  if (
    !Number.isInteger(limit) ||
    limit < 1 ||
    limit > 100 ||
    !Number.isInteger(offset) ||
    offset < 0
  )
    throw new AuthorizationError("invalid_pagination", 400);
  let rows: Record<string, unknown>[];
  switch (section) {
    case "carriers":
    case "organizations":
      rows = [...store.organizations.values()]
        .filter(
          (o) =>
            active(o) &&
            (section !== "carriers" || o.kind.startsWith("CARRIER_")),
        )
        .map((o) =>
          select(o, [
            "id",
            "displayName",
            "kind",
            "kycStatus",
            "createdAtUtcMs",
            "inactiveAtUtcMs",
          ]),
        );
      break;
    case "users":
      rows = [...store.users.values()]
        .filter(active)
        .map((u) =>
          select(u, [
            "id",
            "fullName",
            "phone",
            "createdAtUtcMs",
            "inactiveAtUtcMs",
          ]),
        );
      break;
    case "memberships":
    case "members": {
      const target = query.get("targetOrgId");
      if (
        section === "members" &&
        (!target ||
          !isActiveEntity(store.organizations.get(target)) ||
          store.organizations.get(target)?.kind === "PLATFORM")
      )
        throw new AuthorizationError("target_organization_required", 400);
      rows = [...store.memberships.values()]
        .filter(
          (m) =>
            active(m) &&
            activeOrg(m.orgId) &&
            isActiveEntity(store.users.get(m.userId)) &&
            (!target || m.orgId === target),
        )
        .map((m) => ({
          ...select(m, [
            "userId",
            "orgId",
            "role",
            "createdAtUtcMs",
            "inactiveAtUtcMs",
          ]),
          fullName: store.users.get(m.userId)?.fullName,
          roles:
            store.membershipRoles.get(`${m.userId}:${m.orgId}`) ??
            legacyRoles(m, store.organizations.get(m.orgId)!),
        }));
      break;
    }
    case "vehicles":
      rows = [...store.vehicles.values()]
        .filter((v) => active(v) && activeOrg(v.orgId))
        .map((v) =>
          select(v, [
            "id",
            "orgId",
            "registrationNumber",
            "vehicleClass",
            "capacityKg",
            "inactiveAtUtcMs",
          ]),
        );
      break;
    case "drivers":
      rows = [...store.driverProfiles.values()]
        .filter(
          (v) =>
            active(v) &&
            activeOrg(v.orgId) &&
            isActiveEntity(store.users.get(v.userId)),
        )
        .map((v) => ({
          ...select(v, [
            "userId",
            "orgId",
            "primaryVehicleId",
            "inactiveAtUtcMs",
          ]),
          fullName: store.users.get(v.userId)?.fullName,
        }));
      break;
    case "trips":
      rows = [...store.anchorTrips.values()]
        .filter((v) => active(v) && activeOrg(v.carrierId))
        .map((v) => serializeResponse(v) as Record<string, unknown>);
      break;
    case "shipments":
      rows = [...store.shipments.values()]
        .filter((v) => active(v) && activeOrg(v.carrierId))
        .map((v) => serializeResponse(v) as Record<string, unknown>);
      break;
    case "ledger":
      rows = [...store.ledgerLines.values()]
        .filter((v) => active(v) && activeOrg(v.carrierId))
        .map((v) =>
          select(v, [
            "id",
            "shipmentId",
            "carrierId",
            "status",
            "grossPaise",
            "commissionPaise",
            "netToCarrierPaise",
            "createdAtUtcMs",
            "paidAtUtcMs",
          ]),
        );
      break;
    case "payouts":
      rows = [...store.payoutBatches.values()].map((v) => ({
        ...select(v, [
          "id",
          "cutoffUtcMs",
          "createdAtUtcMs",
          "totalNetToCarrierPaise",
          "lineIds",
          "provider",
        ]),
        transfers: v.transfers?.map((t) =>
          select(t, ["carrierId", "netToCarrierPaise", "lineIds", "status"]),
        ),
      }));
      break;
    default:
      throw new AuthorizationError("not_found", 404);
  }
  const q = (query.get("q") ?? "").trim().toLowerCase(),
    status = query.get("status");
  rows = rows.filter(
    (r) =>
      (!status || r.status === status || r.kycStatus === status) &&
      (!q || JSON.stringify(r).toLowerCase().includes(q)),
  );
  rows.sort((a, b) =>
    String(a.id ?? `${a.orgId}:${a.userId}`).localeCompare(
      String(b.id ?? `${b.orgId}:${b.userId}`),
    ),
  );
  return {
    items: rows.slice(offset, offset + limit),
    total: rows.length,
    offset,
    limit,
    ...(section === "payouts" ? { mode: payoutsMode() } : {}),
  };
}

function reason() {
  if (
    !/^[A-Z][A-Z0-9_]{2,63}$/.test(
      authorizationContext.getStore()?.reason ?? "",
    )
  )
    throw new AuthorizationError("reason_required", 400);
}

/** Request ID gives a durable, store-backed retry key without a new database table. */
export function onboardCarrier(
  store: Store,
  input: { displayName?: unknown; ownerUserId?: unknown; requestId?: unknown },
) {
  const p = requirePermission(store, "carrier.onboard");
  reason();
  const displayName = String(input.displayName ?? "").trim(),
    ownerUserId = String(input.ownerUserId ?? ""),
    requestId = String(input.requestId ?? "");
  if (
    !displayName ||
    displayName.length > 150 ||
    !/^[a-zA-Z0-9_-]{8,80}$/.test(requestId)
  )
    throw new AuthorizationError("invalid_carrier_input", 400);
  if (!isActiveEntity(store.users.get(ownerUserId)))
    throw new AuthorizationError("owner_not_found", 404);
  const id =
    "org_onboard_" +
    createHash("sha256")
      .update(`${p.organizationId}:${p.userId}:${requestId}`)
      .digest("hex")
      .slice(0, 32);
  const existing = store.organizations.get(id),
    key = `${ownerUserId}:${id}`;
  if (existing) {
    if (
      !isActiveEntity(existing) ||
      existing.displayName !== displayName ||
      !isActiveEntity(store.memberships.get(key))
    )
      throw new AuthorizationError("request_id_conflict", 409);
    return { org: existing, created: false };
  }
  const org = {
    id,
    kind: "CARRIER_FLEET" as const,
    displayName,
    kycStatus: "NOT_STARTED" as const,
    createdAtUtcMs: Date.now(),
  };
  store.organizations.set(id, org);
  store.memberships.set(key, {
    userId: ownerUserId,
    orgId: id,
    role: "OWNER",
    createdAtUtcMs: org.createdAtUtcMs,
  });
  store.membershipRoles.set(key, ["CARRIER"]);
  recordAudit(
    store,
    "CARRIER_ONBOARDED",
    "organization",
    id,
    "ABSENT",
    "NOT_STARTED",
  );
  recordAudit(store, "ROLE_ASSIGNED", "membership", key, "ABSENT", "CARRIER");
  return { org, created: true };
}

/** Internal membership creation is explicit; the legacy grant endpoint remains compatible. */
export function setInternalAccess(
  store: Store,
  input: { userId?: unknown; roles?: unknown },
) {
  const p = requirePermission(store, "user.role_manage");
  reason();
  const userId = String(input.userId ?? ""),
    org = store.organizations.get(p.organizationId)!;
  if (!p.internal || !isActiveEntity(store.users.get(userId)))
    throw new AuthorizationError("not_found", 404);
  if (
    !Array.isArray(input.roles) ||
    input.roles.some((r) => !ROLES.includes(r) || !compatibleRole(r, org))
  )
    throw new AuthorizationError("invalid_role", 400);
  const roles = [...new Set(input.roles)] as Role[],
    key = `${userId}:${org.id}`,
    membership = store.memberships.get(key);
  if (membership && !isActiveEntity(membership))
    throw new AuthorizationError("membership_inactive", 409);
  assertAdminRemains(store, userId, org.id, roles);
  const before =
    store.membershipRoles.get(key) ??
    (membership ? legacyRoles(membership, org) : []);
  if (!membership)
    store.memberships.set(key, {
      userId,
      orgId: org.id,
      role: "OPS_AGENT",
      createdAtUtcMs: Date.now(),
    });
  store.membershipRoles.set(key, roles);
  for (const r of before.filter((r) => !roles.includes(r)))
    recordAudit(store, "ROLE_REMOVED", "membership", key, r, "REMOVED");
  for (const r of roles.filter((r) => !before.includes(r)))
    recordAudit(store, "ROLE_ASSIGNED", "membership", key, "ABSENT", r);
  return { userId, orgId: org.id, roles };
}
