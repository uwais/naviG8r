# Shipper ERP integration (v1)

NaviG8r lets shippers create loads from their ERP and receive carrier, tracking, and payment writebacks without re-keying in the customer portal. v1 is **ERP-agnostic**: a generic REST API plus signed webhooks and poll endpoints for reconciliation.

## Overview

| Direction | Mechanism |
|-----------|-----------|
| ERP → NaviG8r | `POST /v1/integrations/loads` (idempotent by `externalLoadId`) |
| NaviG8r → ERP | Signed webhooks (real-time) + poll APIs (fallback) |
| Admin | Customer portal **Integrations** page (`/customer/integrations`) for API keys, webhook URL, delivery log |

Base URL (production): `https://navig8r.onrender.com`

Customer tracking deep link (included in API responses and webhooks):

`https://navig8r-customer.onrender.com/#/customer/shipments/{shipmentId}`

## Authentication

Integration routes require machine-to-machine credentials scoped to your **CUSTOMER** org.

### Option A — Bearer token (recommended)

```
Authorization: Bearer nvg8r_{keyId}_{secret}
```

Create keys in the customer portal (**Integrations → Create key**). The full token is shown **once** at creation.

### Option B — Header pair

```
X-Api-Key: {keyId}
X-Api-Secret: {secret}
```

### Scopes

| Scope | Access |
|-------|--------|
| `loads:write` | Create loads |
| `loads:read` | Poll loads, shipments, tracking, events |
| `webhooks:manage` | Portal webhook settings (Bearer OTP, not integration key) |

Cross-org access is rejected. Revoked keys return `401 integration_unauthorized`.

## Inbound — create load from ERP

### `POST /v1/integrations/loads`

**Headers (optional):** `Idempotency-Key: {uuid}` — safe retries; duplicates return the existing shipment (`200`).

A request body over 1 MB answers `413 payload_too_large`, here and on the portal settings routes under `/v1/pilot/customer/integrations`.

**Body:**

```json
{
  "externalLoadId": "ERP-DO-4421",
  "weightKg": 500,
  "pickupAddress": "Sector 44, Gurugram",
  "dropAddress": "Sitapura, Jaipur",
  "pickup": { "lat": 28.47, "lng": 77.03 },
  "drop": { "lat": 26.90, "lng": 75.82 },
  "lanePreference": "auto_match",
  "metadata": {
    "poNumber": "PO-9912",
    "costCenter": "CC-LOG-01"
  }
}
```

| Field | Required | Notes |
|-------|----------|-------|
| `externalLoadId` | Yes | Unique per org; idempotency key for ERP primary key |
| `weightKg` | Yes | Same semantics as portal booking |
| `pickupAddress`, `dropAddress` | Yes | Human-readable addresses |
| `pickup`, `drop` | Recommended | Geo for lane matching and tracking |
| `lanePreference` | No | `auto_match` (default) or `explicit` with `anchorTripId` |
| `metadata` | No | Free-form strings echoed in webhooks |

**Success (`201` created / `200` duplicate):**

```json
{
  "created": true,
  "shipmentId": "shp_...",
  "status": "PENDING_CARRIER_ACCEPT",
  "externalLoadId": "ERP-DO-4421",
  "carrierDisplayName": "Raj Logistics",
  "grossPaise": 523420,
  "trackingUrl": "https://navig8r-customer.onrender.com/#/customer/shipments/shp_...",
  "checkoutRequired": false
}
```

When `paymentPolicy` is `portal_checkout` and Razorpay is enabled, `checkoutRequired: true` plus `razorpayKeyId` / order refs may be present for human completion in the portal.

**Errors:**

| HTTP | `error` | Meaning |
|------|---------|---------|
| 422 | `no_eligible_lane` | No open trip matches; retry later or pass `anchorTripId` |
| 400 | `external_load_id_required` | Missing ERP id |
| 401 | `integration_unauthorized` | Invalid or revoked key |

## Poll APIs (reconciliation)

All require `loads:read`.

| Endpoint | Purpose |
|----------|---------|
| `GET /v1/integrations/loads?externalLoadId=` | Lookup by ERP id |
| `GET /v1/integrations/loads?updatedSince={utcMs}` | Delta sync (cursor: `updatedAtUtcMs`) |
| `GET /v1/integrations/shipments/:id` | Full snapshot (shipment, trip, payment, tracking) |
| `GET /v1/integrations/shipments/:id/tracking` | Live tracking payload |
| `GET /v1/integrations/events?sinceEventId=` | Missed webhook recovery |

Poll responses use the same canonical JSON shape as webhook payloads.

## Outbound webhooks

Configure **HTTPS** callback URL in the portal. Before each call NaviG8r resolves the host once and connects only to the addresses that answer gave, so the name is not looked up a second time; the host name still goes in the `Host` header and the TLS certificate check (`integrationWebhookAddress.ts`). If the name does not resolve, or any address it gets is loopback, private, shared, link-local (cloud metadata), multicast, documentation (`192.0.2.0/24`, `198.51.100.0/24`, `203.0.113.0/24`), benchmarking (`198.18.0.0/15`), reserved (`192.0.0.0/24`, `240.0.0.0/4`), site-local (`fec0::/10`) or an IPv6 form that carries an IPv4 address (`::/96`, `64:ff9b::/96`, `2002::/16`), the call is not made and the delivery fails with the one sentence "This webhook address is not on the public internet, so it was not called." Redirects are not followed: a `3xx` answer is a failed delivery. For a failed delivery the delivery log keeps at most the first 500 characters of the answer, and NaviG8r reads at most 4 KB of it. Only with `NODE_ENV=test` (tests and the local practice server) may a webhook go to an address on this machine or a private network.

NaviG8r signs the raw body:

```
X-NaviG8r-Signature: {hex_hmac_sha256}
```

Verify with your per-connection webhook secret (shown once when created or after **Rotate secret**).

### Event types

| Event | When | ERP relevance |
|-------|------|---------------|
| `load.created` | Book (integration or portal) | Freight estimate, NaviG8r shipment id |
| `load.payment_authorized` | Razorpay authorized | Payment commitment |
| `load.carrier_assigned` | At book | Carrier on dispatch record |
| `load.carrier_accepted` | Carrier accepts | Confirmed carrier |
| `load.in_transit` | Trip started | Departed |
| `load.location_updated` | GPS ping (max 1 / 5 min) | Optional ETA |
| `load.pod_submitted` | Driver POD | Delivery proof |
| `load.delivered` | Ops release | Final cost for AP |
| `load.cancelled` | Carrier fail + refund | Refund status |
| `integration.test` | Portal test ping | Endpoint validation |

### Payload shape (`eventVersion: "2026-06-01"`)

```json
{
  "eventId": "evt_...",
  "eventVersion": "2026-06-01",
  "eventType": "load.delivered",
  "occurredAtUtcMs": 1710000000000,
  "sequence": 7,
  "orgId": "org_...",
  "externalLoadId": "ERP-DO-4421",
  "shipment": {
    "id": "shp_...",
    "status": "DELIVERED",
    "weightKg": 500,
    "pickupAddress": "...",
    "dropAddress": "...",
    "grossPaise": 523420,
    "carrierDisplayName": "Raj Logistics"
  },
  "trip": {
    "id": "...",
    "status": "COMPLETED",
    "originCity": "...",
    "destCity": "...",
    "startedAtUtcMs": 1710000000000,
    "completedAtUtcMs": 1710100000000
  },
  "carrier": {
    "name": "Raj Logistics",
    "vehicleNumber": "HR26AB9999",
    "driverName": "Driver Name"
  },
  "tracking": { "url": "...", "isLive": false, "lastLocation": null },
  "pod": { "podAtUtcMs": 1710000000000, "notes": "..." },
  "payment": { "status": "CAPTURED", "amountPaise": 523420, "provider": "RAZORPAY" },
  "metadata": { "poNumber": "PO-9912" }
}
```

`carrier.vehicleNumber` is the truck the carrier assigned to the trip, as registered, when the trip has one. Otherwise
it is the primary truck of whoever started the trip (or accepted the load), else the carrier's first truck.
`carrier.driverName` is still whoever started the trip.

The truck's position (`tracking.lastLocation` here, `liveLocation` from `GET /shipments/:id/tracking`) is sent only
while the shipment is `BOOKED` and its trip is `IN_PROGRESS`, the same rule as the shipper app; otherwise it is `null`.
The `trip` object in poll responses never carries the position or the driver's user ids.

### Retries

Failed deliveries retry with exponential backoff (1m, 5m, 30m, 2h, 24h; max 10 attempts), then status `DEAD`. Use the portal delivery log or `GET /events` to reconcile.

## Payment policies

Every connection starts as `portal_checkout`. Only NaviG8r platform staff (`OPS` or `ADMIN`) can change it, through `POST /v1/ops/organizations/:orgId/erp-payment-policy` with body `{ "paymentPolicy": "portal_checkout" | "erp_preauthorized" }` and the staff bearer token. It answers `200 { "orgId", "paymentPolicy" }`; each change writes an audit row `ERP_PAYMENT_POLICY_CHANGED` (resource `organization`, previous and new policy, the staff user as actor), and setting the current policy again writes none. Refusals: `401` without a bearer token, `403 forbidden` for anyone but platform `OPS` or `ADMIN` (`FINANCE` too), `404 not_found` for an organisation that is not an active shipper, `400 invalid_payment_policy` for any other value. There is no ops page for it. The shipper portal shows the policy read-only ("Set by NaviG8r staff.") and its save (`PATCH /v1/pilot/customer/integrations/connection`) takes `webhookUrl` and `displayName`; a `paymentPolicy` other than the current one answers `403 forbidden` and saves nothing, and an unknown value answers `400 invalid_payment_policy`.

| Policy | Behavior |
|--------|----------|
| `portal_checkout` | Load created; customer completes Razorpay in web portal if required |
| `erp_preauthorized` | ERP confirms payment separately; NaviG8r books without portal checkout |

## Field mapping cheat sheet

| ERP concept | Inbound | Writeback |
|-------------|---------|-----------|
| Load / dispatch # | `externalLoadId` | Echoed in every webhook |
| Pickup / delivery | `pickupAddress`, `dropAddress`, geo | Same + `load.in_transit` |
| Weight | `weightKg` | Same |
| Carrier | — (assigned at book) | `carrierDisplayName` on `load.carrier_assigned` |
| Freight | — (quoted at book) | `grossPaise`; final on `load.delivered` |
| Tracking | — | `tracking.url` |
| POD / delivery date | — | `pod.podAtUtcMs` |
| Payment | — | `payment.status` |
| PO / cost center | `metadata.*` | Echoed in webhooks |

## Verification

### Automated tests (CI / local)

From repo root:

```bash
# All API tests including ERP integration
node --experimental-strip-types --test apps/api/src/*.test.ts

# ERP-focused only
node --experimental-strip-types --test \
  apps/api/src/integration.test.ts \
  apps/api/src/integrationHttp.test.ts \
  apps/api/src/integrationWebhooks.test.ts
```

| Test file | Coverage |
|-----------|----------|
| `integration.test.ts` | Service-layer idempotency, events, auth headers, webhook payload fields |
| `integrationHttp.test.ts` | Real HTTP: `POST /v1/integrations/loads`, portal `/v1/pilot/customer/integrations/*` |
| `integrationWebhooks.test.ts`, `integrationWebhookAddress.test.ts` | A local listener: HMAC signature, retry backoff on failed delivery, the call goes to the checked address with no second lookup; addresses not on the public internet and names that do not resolve are not called, redirects are not followed, a failed answer is read only up to 4 KB |

Flutter widget tests:

```bash
cd apps/driver_pilot && flutter test test/customer_integrations_screen_test.dart
```

### Live smoke script (curl)

Against a running API with `OTP_DEBUG=1` (or known OTP):

```bash
BASE_URL=https://navig8r.onrender.com bash scripts/test-erp-integration.sh
# local:
BASE_URL=http://127.0.0.1:3000 bash scripts/test-erp-integration.sh
```

The script registers customer + carrier, creates an integration key, saves the webhook address (not the payment policy, which only staff set), posts a load, verifies idempotency, and polls loads/events. It stops at the first reply that is not 2xx (curl 7.76 or later, for `--fail-with-body`), so a run on a server that already has these phones registered stops at the first register.

## Environment (operators)

| Variable | Purpose |
|----------|---------|
| `CUSTOMER_WEB_BASE_URL` | Tracking links in API/webhook payloads (default: Render customer static site) |
| `CORS_ALLOWED_ORIGINS` | Portal browser origins only; integration API is server-to-server |

## Named ERP adapters

After pilot selection, thin adapters map ERP-specific fields to this generic API. See [`integrations/adapters/generic/`](../integrations/adapters/generic/README.md) for the reference mapping template and iPaaS notes.
