# Generic ERP adapter (reference)

This folder documents how any ERP, TMS, or iPaaS (Celigo, Boomi, Zoho Flow, Make, n8n) connects to NaviG8r **without** custom server code in the core API.

Named adapters (Tally, Zoho, SAP, etc.) are thin configuration layers on top of these mappings.

## Architecture

```
ERP / middleware ──POST /v1/integrations/loads──► NaviG8r API
ERP / middleware ◄── HMAC webhook POST ─────────── NaviG8r outbox
ERP / middleware ──GET poll (optional)──────────► NaviG8r API
```

**Phase 2 Integration Hub** (optional middleware): stateless ERP connectors map native formats (XML/JSON/CSV) → canonical **`LoadIntent`**, then call the generic API. The Hub should **not** duplicate auth, deduplication, or webhook retries — those live in the NaviG8r API.

Core booking, carrier assignment, and payment logic stay in NaviG8r. The adapter only translates field names and orchestrates retries.

---

## Canonical LoadIntent ↔ NaviG8r API

Hub connectors produce **`LoadIntent`**; the adapter maps it to **`POST /v1/integrations/loads`**. Org scope comes from the integration Bearer token — **do not** send `shipper_org_id` in the body.

### LoadIntent (canonical inbound)

```json
{
  "source_erp": "tally",
  "erp_reference": "SO-2261",
  "origin": {
    "address": "Naraina Industrial, Delhi",
    "gstin": "07AABCS1429B1ZP",
    "lat": 28.641,
    "lng": 77.132
  },
  "destination": {
    "address": "APMC Vashi, Mumbai",
    "gstin": "27AABCS1429B1ZQ",
    "lat": 19.066,
    "lng": 73.001
  },
  "cargo": {
    "description": "FMCG – Packaged Goods",
    "weight_kg": 8000,
    "invoice_value_inr": 420000
  },
  "required_by": "2026-06-15",
  "ewb_required": true,
  "shipper_org_id": "ORG-291"
}
```

### Mapping table (LoadIntent → API)

| LoadIntent field | NaviG8r API field | Notes |
|------------------|-------------------|--------|
| `source_erp` | `metadata.sourceErp` + connection `externalSource` | Set on connection at key creation; echo in metadata for traceability |
| `erp_reference` | `externalLoadId` | Required; idempotent per org |
| `origin.address` | `pickupAddress` | Required |
| `origin.lat` / `origin.lng` | `pickup.lat`, `pickup.lng` | Improves lane auto-match |
| `origin.gstin` | `metadata.originGstin` | No first-class field yet; pass-through |
| `destination.address` | `dropAddress` | Required |
| `destination.lat` / `destination.lng` | `drop.lat`, `drop.lng` | Improves lane auto-match |
| `destination.gstin` | `metadata.destGstin` | Pass-through |
| `cargo.weight_kg` | `weightKg` | Required |
| `cargo.description` | `metadata.cargoDescription` | Pass-through |
| `cargo.invoice_value_inr` | `metadata.invoiceValueInr` | Pass-through; e-way threshold logic **not** in API yet |
| `required_by` | `metadata.requiredBy` | Pass-through; lane scoring by date **planned** |
| `ewb_required` | `metadata.ewbRequired` | Pass-through; no auto e-way check yet |
| `shipper_org_id` | *(omit)* | Resolved from integration token → `ctx.orgId` |

### Example transform (LoadIntent → POST body)

```javascript
function loadIntentToNavig8rBody(intent) {
  return {
    externalLoadId: intent.erp_reference,
    weightKg: intent.cargo.weight_kg,
    pickupAddress: intent.origin.address,
    dropAddress: intent.destination.address,
    pickup: { lat: intent.origin.lat, lng: intent.origin.lng },
    drop: { lat: intent.destination.lat, lng: intent.destination.lng },
    lanePreference: "auto_match",
    metadata: {
      sourceErp: intent.source_erp,
      originGstin: intent.origin.gstin,
      destGstin: intent.destination.gstin,
      cargoDescription: intent.cargo.description,
      invoiceValueInr: String(intent.cargo.invoice_value_inr),
      requiredBy: intent.required_by,
      ewbRequired: String(intent.ewb_required),
    },
  };
}
```

---

## Flat ERP write-back ↔ NaviG8r webhooks

Hub subscribers listen for **`load.delivered`** (and earlier lifecycle events) and flatten the nested webhook into ERP-native fields.

### Target flat payload (trip delivered)

```json
{
  "erp_reference": "SO-2261",
  "carrier_name": "Suresh Roadways",
  "vehicle_number": "MH12AB4321",
  "driver_name": "Arjun Singh",
  "lr_number": "SR/2026/4892",
  "tracking_url": "https://navig8r-customer-web.onrender.com/#/customer/shipments/shp_...",
  "ewb_number": "2312840912",
  "dispatched_at": "2026-06-08T06:15:00Z",
  "delivered_at": "2026-06-10T11:30:00Z",
  "pod_url": "https://cdn.example.com/pod.pdf",
  "freight_amount_inr": 42000
}
```

### Mapping table (webhook → flat write-back)

| Flat ERP field | NaviG8r webhook source | Status |
|----------------|------------------------|--------|
| `erp_reference` | `externalLoadId` | ✅ |
| `carrier_name` | `carrier.name` or `shipment.carrierDisplayName` | ✅ |
| `vehicle_number` | `carrier.vehicleNumber` | ✅ (from carrier org vehicle / driver primary vehicle) |
| `driver_name` | `carrier.driverName` | ✅ (trip starter or accepting driver) |
| `tracking_url` | `tracking.url` | ✅ |
| `dispatched_at` | `trip.startedAtUtcMs` → ISO UTC on `load.in_transit` / `load.delivered` | ✅ |
| `delivered_at` | `pod.podAtUtcMs` → ISO UTC on `load.delivered` | ✅ |
| `freight_amount_inr` | `shipment.grossPaise / 100` or `payment.amountPaise / 100` | ✅ |
| `lr_number` | `metadata.lrNumber` | ⚠️ metadata pass-through only |
| `ewb_number` | `metadata.ewbNumber` | ⚠️ metadata pass-through only |
| `pod_url` | — | ❌ not yet (POD is timestamp + notes only) |

### Example flatten (`load.delivered`)

```javascript
function flattenDeliveredWebhook(evt) {
  const msToIso = (ms) => (ms != null ? new Date(ms).toISOString() : null);
  return {
    erp_reference: evt.externalLoadId,
    carrier_name: evt.carrier?.name ?? evt.shipment?.carrierDisplayName,
    vehicle_number: evt.carrier?.vehicleNumber ?? null,
    driver_name: evt.carrier?.driverName ?? null,
    tracking_url: evt.tracking?.url,
    dispatched_at: msToIso(evt.trip?.startedAtUtcMs),
    delivered_at: msToIso(evt.pod?.podAtUtcMs),
    freight_amount_inr: Math.round((evt.shipment?.grossPaise ?? 0) / 100),
    lr_number: evt.metadata?.lrNumber ?? null,
    ewb_number: evt.metadata?.ewbNumber ?? null,
  };
}
```

---

## Legacy inbound mapping (ERP field names)

| ERP field (example) | NaviG8r field | Transform |
|---------------------|---------------|-----------|
| `LoadNumber` / `DocNo` | `externalLoadId` | String, unique per org |
| `Weight` | `weightKg` | Numeric kg |
| `ShipFrom.Address` | `pickupAddress` | String |
| `ShipTo.Address` | `dropAddress` | String |
| `ShipFrom.Lat`, `ShipFrom.Lng` | `pickup.lat`, `pickup.lng` | Optional but improves lane match |
| `ShipTo.Lat`, `ShipTo.Lng` | `drop.lat`, `drop.lng` | Optional |
| `PONumber` | `metadata.poNumber` | String |
| `CostCenter` | `metadata.costCenter` | String |
| `GLCode` | `metadata.glCode` | String |

**Idempotency:** Always send the same `externalLoadId` for a given ERP document. Use `Idempotency-Key` header on retries.

**Lane selection:** Default `lanePreference: "auto_match"`. If NaviG8r returns `422 no_eligible_lane`, either wait and retry or let ops publish more anchor trips, then retry with the same `externalLoadId`.

## Outbound event types

| NaviG8r event | Typical ERP writeback |
|---------------|----------------------|
| `load.created` | Create/update freight line; store NaviG8r `shipment.id` |
| `load.carrier_assigned` | Set carrier name on dispatch |
| `load.carrier_accepted` | Mark carrier confirmed |
| `load.in_transit` | Set status in-transit; **`trip.startedAtUtcMs`** = dispatch time |
| `load.delivered` | Post final freight cost; delivery timestamp from `pod.podAtUtcMs` |
| `load.cancelled` | Reverse or flag cancelled load |
| `load.payment_authorized` / captured | Update AP / payment status |

**Reconciliation:** Nightly job: `GET /v1/integrations/loads?updatedSince={lastSyncMs}` or `GET /v1/integrations/events?sinceEventId={cursor}`.

## iPaaS recipe (generic)

1. **Trigger:** ERP creates or updates a dispatch order (webhook, poll, or file drop).
2. **Transform:** Map to LoadIntent, then to `POST /v1/integrations/loads` body (see above).
3. **HTTP:** POST to NaviG8r with integration Bearer token; store returned `shipmentId` back on ERP record.
4. **Inbound webhook handler:** Verify `X-NaviG8r-Signature`; flatten lifecycle events to ERP fields.
5. **Error handling:** On 422, queue retry; on 401, alert ops (key rotation).

## Example curl (create load)

```bash
curl -sS -X POST "https://navig8r.onrender.com/v1/integrations/loads" \
  -H "Authorization: Bearer nvg8r_KEYID_SECRET" \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: erp-do-4421-v1" \
  -d '{
    "externalLoadId": "ERP-DO-4421",
    "weightKg": 500,
    "pickupAddress": "Sector 44, Gurugram",
    "dropAddress": "Sitapura, Jaipur",
    "pickup": { "lat": 28.47, "lng": 77.03 },
    "drop": { "lat": 26.90, "lng": 75.82 },
    "metadata": { "poNumber": "PO-9912" }
  }'
```

## Example webhook verification (Node.js)

```javascript
import crypto from "node:crypto";

function verifyNavig8rWebhook(rawBody, signatureHeader, secret) {
  const expected = crypto.createHmac("sha256", secret).update(rawBody).digest("hex");
  return crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(signatureHeader ?? ""));
}
```

## Next adapters (post-pilot)

| ERP | Inbound | Writeback notes |
|-----|---------|-----------------|
| Tally | XML/JSON bridge → LoadIntent → API | Voucher-ready freight fields |
| Zoho Inventory/Books | Zoho Flow custom function | Zoho webhook subscriber |
| SAP / NetSuite / Dynamics | iPaaS maps to LoadIntent | Standard webhook + poll |

Each named adapter adds only **field mapping config** and optional middleware — not a fork of NaviG8r booking logic.
