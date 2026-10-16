/**
 * The carrier's transporter ID after sign-up: its owner changes or clears it, and shippers read it on their
 * shipments so they can name the carrier on the e-way bill (owner decision, 16 Oct 2026). The format check is in
 * transporterIdValidation.ts; who reads it is in the serializer, rbacResponses.ts.
 */
import { AuthorizationError, recordAudit, requirePermission } from "./rbac.ts";
import { ApiError } from "./services.ts";
import { isActiveEntity } from "./softDelete.ts";
import type { Store } from "./store.ts";
import type { Organization } from "./types.ts";
import { checkTransporterId } from "./transporterIdValidation.ts";

/** Body { transporterId: string | null }; null or a blank string clears it. A missing field is refused. */
export function setCarrierTransporterId(store: Store, input: Record<string, unknown>): Organization {
  const principal = requirePermission(store, "transporter_id.write");
  const org = store.organizations.get(principal.organizationId);
  if (!org || !isActiveEntity(org)) throw new AuthorizationError("not_found", 404);
  const checked = checkTransporterId(input.transporterId);
  if (!checked.ok) throw new ApiError("invalid_transporter_id", { detail: checked.detail, field: checked.field });
  const { transporterId: previous, ...withoutTransporterId } = org;
  const updated: Organization = checked.value ? { ...withoutTransporterId, transporterId: checked.value } : withoutTransporterId;
  store.organizations.set(org.id, updated);
  // State words only, like the other carrier profile changes: the audit log never holds the ID itself.
  recordAudit(store, "TRANSPORTER_ID_CHANGED", "organization", org.id, previous ? "SET" : "ABSENT", checked.value ? "SET" : "ABSENT");
  return updated;
}

/** ERP responses are written without the serializer, and their shape is a contract with other systems. */
export function withoutCarrierTransporterId<T extends { carrierTransporterId?: unknown }>(shipment: T): Omit<T, "carrierTransporterId"> {
  const copy = { ...shipment };
  delete copy.carrierTransporterId;
  return copy;
}
