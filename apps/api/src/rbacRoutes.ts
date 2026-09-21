import type http from "node:http";
import { randomUUID } from "node:crypto";
import type { Store } from "./store.ts";
import { verifyBearer } from "./auth.ts";
import { authorizationContext, AuthorizationError, resolvePrincipal, requirePermission, visible, type Permission } from "./rbac.ts";

const rules: [string, RegExp, Permission][] = [
  ["GET", /^\/v1\/pilot\/me$/, "organization.profile.read"],
  ["PATCH", /^\/v1\/pilot\/me\/vehicle$/, "load.status_update"],
  ["GET", /^\/v1\/pilot\/anchor-trips(?:\/[^/]+)?$/, "load.read"],
  ["POST", /^\/v1\/pilot\/anchor-trips$/, "trip.publish"],
  ["POST", /^\/v1\/pilot\/anchor-trips\/[^/]+\/(?:start|complete|location)$/, "load.status_update"],
  ["POST", /^\/v1\/pilot\/rates\/estimate$/, "trip.publish"],
  ["GET", /^\/v1\/pilot\/carrier\/shipments$/, "load.read"],
  ["POST", /^\/v1\/pilot\/carrier\/shipments\/[^/]+\/accept$/, "carrier.offer_accept"],
  ["POST", /^\/v1\/pilot\/carrier\/drivers\/invite$/, "organization.member.invite"],
  ["GET", /^\/v1\/pilot\/carrier\/(?:earnings|ledger|payout-batches)$/, "payment.read"],
  ["POST", /^\/v1\/pilot\/carrier\/payout-setup$/, "bank_account.create_token"],
  ["POST", /^\/v1\/pilot\/customer\/members\/invite$/, "organization.member.invite"],
  ["GET", /^\/v1\/pilot\/customer\/members$/, "organization.member.invite"],
  ["*", /^\/v1\/pilot\/customer\/integrations(?:\/.*)?$/, "integration.manage"],
  ["GET", /^\/shipments(?:\/[^/]+(?:\/tracking)?)?$/, "load.read"],
  ["POST", /^\/shipments\/book$/, "load.create"],
  ["POST", /^\/shipments\/[^/]+\/driver-pod$/, "pod.upload"],
  ["POST", /^\/shipments\/[^/]+\/accept-pod$/, "pod.accept"],
  ["POST", /^\/shipments\/[^/]+\/fail-refund$/, "payment.refund"],
  ["GET", /^\/ops\/shipments(?:\/[^/]+)?$/, "load.read"],
  ["POST", /^\/ops\/shipments\/[^/]+\/release$/, "payment.capture"],
  ["POST", /^\/payout-batches\/run$/, "settlement.release"],
  ["GET", /^\/payout-batches$/, "payment.read"],
  ["GET", /^\/carriers\/[^/]+\/ledger$/, "payment.read"],
  ["POST", /^\/v1\/payments\/razorpay\/confirm$/, "payment.checkout"],
  ["*", /^\/v1\/(?:ops-admins|ops\/users|roles)(?:\/[^/]+)?$/, "user.role_manage"],
  ["GET", /^\/v1\/(?:users|orgs)$/, "user.role_manage"],
  ["POST", /^\/v1\/organizations\/[^/]+\/kyc$/, "kyc.verify"],
  ["GET", /^\/v1\/audit$/, "audit.read"],
];
export function guardRequest(req: http.IncomingMessage, store: Store, url: URL): void {
  const method = req.method ?? "GET", path = url.pathname;
  if (method === "OPTIONS") return;
  if (method === "GET" && ["/health", "/ops", "/admin", "/workflow", "/v1/customer/eligible-anchor-trips"].includes(path)) return;
  if (method === "GET" && /^\/anchor-trips(?:\/[^/]+)?$/.test(path)) return;
  if (method === "POST" && ["/shipments/quote", "/v1/auth/otp/start", "/v1/auth/otp/verify", "/v1/pilot/driver/register", "/v1/pilot/customer/register", "/v1/pilot/customer/users/register", "/v1/payments/razorpay/webhook"].includes(path)) return;
  if (path.startsWith("/v1/integrations/")) return; // separately authenticated service principal
  const token = /^Bearer\s+(.+)$/i.exec(String(req.headers.authorization ?? ""))?.[1] ?? null;
  if (path === "/v1/auth/me" && method === "GET") { verifyBearer(store, token); return; }
  if (path === "/v1/pilot/driver/login" || /\/shipments\/[^/]+\/pod$/.test(path) || path === "/carriers" || (path === "/anchor-trips" && method !== "GET")) throw new AuthorizationError("legacy_route_retired", 410);
  const rule = rules.find(([m, pattern]) => (m === "*" || m === method) && pattern.test(path));
  if (!rule) throw new AuthorizationError("not_found", 404);
  const { userId } = verifyBearer(store, token);
  const organizationId = req.headers["x-organization-id"];
  if (organizationId !== undefined && typeof organizationId !== "string") throw new AuthorizationError("invalid_organization", 400);
  const p = resolvePrincipal(store, userId, organizationId);
  const context = authorizationContext.getStore()!;
  context.principal = p;
  context.reason = typeof req.headers["x-reason-code"] === "string" ? req.headers["x-reason-code"] : undefined;
  context.effectiveActorId = typeof req.headers["x-effective-actor-id"] === "string" ? req.headers["x-effective-actor-id"] : undefined;
  const orgId = url.searchParams.get("orgId");
  if (orgId && orgId !== p.organizationId) throw new AuthorizationError("not_found", 404);
  let resource;
  const shipmentId = /^\/(?:ops\/)?shipments\/([^/]+)/.exec(path)?.[1] ?? /^\/v1\/pilot\/carrier\/shipments\/([^/]+)/.exec(path)?.[1];
  if (shipmentId && !["book", "pending-release", "delivered"].includes(shipmentId)) resource = store.shipments.get(shipmentId);
  const tripId = /^\/v1\/pilot\/anchor-trips\/([^/]+)/.exec(path)?.[1];
  if (tripId) resource = store.anchorTrips.get(tripId);
  if ((tripId || (shipmentId && !["book", "pending-release", "delivered"].includes(shipmentId))) && !resource) throw new AuthorizationError("not_found", 404);
  if (resource && !visible(p, resource)) throw new AuthorizationError("not_found", 404);
  if (!p.permissions.includes(rule[2])) throw new AuthorizationError("forbidden");
  if ((path.startsWith("/ops/") || path === "/payout-batches" || path.startsWith("/carriers/")) && !p.internal) throw new AuthorizationError("forbidden");
  if ((path === "/payout-batches" || path.startsWith("/carriers/")) && !p.roles.includes("FINANCE")) throw new AuthorizationError("forbidden");
  if (resource) requirePermission(store, rule[2], resource);
}
export function requestContext() { return { requestId: randomUUID() }; }
