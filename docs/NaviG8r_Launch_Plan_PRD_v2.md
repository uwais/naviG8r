# NaviG8r Launch Plan — Gap Analysis, Technical Design & Roadmap

**Compared against:** PRD v2.0 (Ground-Truthed & Revised, Aug 2026)  
**Codebase baseline:** `main` / logistics-mvp pilot (API + Flutter driver/customer + ERP v1)  
**Audience:** founders, eng, ops, investors  
**Status:** planning document — not a commitment to build every PRD Phase 3 item before first paid trips

---

## 0. Verdict

The repo is a **working freight marketplace pilot**, not a greenfield. Core trip commerce already exists: carrier publish → customer quote/book → accept → GPS track → driver POD → ops release → ledger → payout batch.

That vertical is **misaligned with PRD v2 payment architecture**. Today we **authorize shipper payment at booking** (Razorpay) and capture at POD. The PRD explicitly rejects advance-style payment for Indian SME FTL and requires **Track A Rupifi BNPL** and/or **Track B post-delivery NACH**, with NaviG8r holding **zero receivables**.

**Credible launch** is therefore:

1. **Keep** the marketplace + tracking + POD + ERP generic API spine.  
2. **Replace/extend** checkout into PRD payment tracks (NACH first if Rupifi partnership lag; Rupifi when partner ready).  
3. **Add** the trust stack the broker has today: GST KYC, WhatsApp lifecycle, dispute window, document artifacts, real SMS OTP.  
4. **Defer** TMS SaaS subscriptions, AI SaaS, insurance marketplace, multi-corridor density, and microservices until after a closed Delhi–Mumbai pilot proves CPR-Month and collections.

North-star for “product launch” in this plan: **Closed commercial pilot** — 10 GST shippers + 15 carriers on Delhi–Mumbai, **≥100 completed, paid, rated trips**, fill rate ≥30%, NACH/Rupifi collections working, NPS ≥30. That matches PRD Phase 0 exit, not Series A.

---

## 1. Current state (what exists)

### 1.1 Architecture today

| Layer | Reality |
|-------|---------|
| API | Single Node HTTP process (`apps/api`) — not microservices |
| App | Flutter `apps/driver_pilot` — driver Android + customer web/mobile |
| Data | In-memory `Store` + optional `PERSISTENCE=DB` (Prisma/Postgres full-snapshot sync) or `DATA_FILE` JSON |
| Deploy | Render Docker Web Service + Postgres + Flutter static site (`docs/RENDER.md`, `render.yaml`) |
| Payments (shipper) | `MOCK` or Razorpay **authorize at book → capture at POD** |
| Payments (carrier) | Ledger + T+7 / Wed cutoff; `BOOKKEEPING` or `RAZORPAYX` |
| Integrations | Generic ERP REST + HMAC webhooks (`docs/erp-integration.md`) |
| Ops | OTP-gated HTML `/admin` + ops release queue; `OPS_ADMIN` RBAC |

### 1.2 Capability inventory vs PRD surfaces

Legend: **Done** · **Partial** · **Mock** · **Missing**

#### Shipper (PRD §6A)

| Capability | Status | Evidence |
|------------|--------|----------|
| Org signup + multi-user | **Partial** | Customer register + member invite; no GSTIN NIC validation |
| Load post / browse / book | **Done** | Marketplace quote/book + eligible trips; ERP `POST /v1/integrations/loads` |
| Carrier match view before confirm | **Partial** | Browse open trips; no rating/performance scores |
| Live tracking map | **Done** | GPS pings + `GET /shipments/:id/tracking`; customer web maps |
| POD visibility | **Partial** | Status/timestamps; no photo vault / OTP-at-receiver UX in portal |
| Payment without advance (Rupifi/NACH) | **Missing** | Opposite model: authorize at checkout |
| WhatsApp lifecycle | **Missing** | Docs mention WhatsApp feedback only |
| Trip history / docs vault | **Partial** | List/detail; LR/e-way/POD URL not first-class |
| Load templates | **Missing** | — |
| Market rate from cleared trips | **Missing** | Distance/weight estimator only (`FREIGHT_*`) |
| Ratings mandatory | **Missing** | — |
| In-app chat | **Missing** | — |
| Dispute within 48h | **Missing** | Ops release exists; shipper dispute flow does not |
| GST invoice auto-gen | **Missing** | — |
| TMS-lite analytics | **Missing** | — |
| Tally/Zoho named connectors | **Missing** | Generic API **Done** (adapter layer planned in ROADMAP §D2) |

#### Carrier (PRD §6B)

| Capability | Status | Evidence |
|------------|--------|----------|
| Signup + vehicle + org | **Done** | Pilot register/login; vehicle class/capacity |
| KYC Digilocker / licence | **Missing** | `kycStatus` enum only |
| Publish capacity / anchor routes | **Done** | `publishAnchorTrip` + Flutter publish |
| Load feed / accept | **Done** | Carrier shipments + accept |
| Start trip + GPS | **Done** | Start trip, location report, auto-complete rules |
| Driver POD | **Done** | `POST .../driver-pod` → `PENDING_RELEASE` |
| Offline POD / Hindi UI | **Missing** | English-first pilot UI |
| Payout ledger / setup | **Partial** | Earnings/ledger APIs; RazorpayX optional; PRD wants T+3 not T+7 |
| Ratings / chat / return loads | **Missing** | — |

#### Admin (PRD §6C)

| Capability | Status | Evidence |
|------------|--------|----------|
| Master data view | **Partial** | HTML admin dumps trips/shipments/ledger |
| KYC approval queue | **Missing** | — |
| Manual match override | **Partial** | Ops can intervene; no dedicated matching console |
| POD / release queue | **Done** | Pending-release + release endpoints + admin UI |
| Payout ops | **Partial** | Run batch; no NACH failure console |
| Dispute queue | **Missing** | — |
| Fraud / health metrics / Rupifi reconciliation | **Missing** | CPR-Month not instrumented |

#### Platform / NFR (PRD §7)

| Capability | Status | Evidence |
|------------|--------|----------|
| API-first REST | **Partial** | One monolith; OpenAPI not published |
| Real SMS OTP | **Mock** | `OTP_DEBUG` / in-memory codes |
| Event bus (Kafka/SQS) | **Missing** | In-process webhook worker |
| PII vault / DPDP deletion | **Missing** | — |
| Multi-AZ / 99.9% SLA | **Partial** | Single Render service; free tier sleep risk on Hobby |
| Row-level DB transactions | **Partial** | Full-store Prisma replace — race risk under load |

### 1.3 What to keep (leverage, don’t rebuild)

- Marketplace booking + capacity reservation  
- Authorize/capture plumbing (reuse for deposits/exceptions; adapters for Rupifi settlement)  
- Driver GPS + customer tracking URL (ERP webhooks already emit `tracking.url`)  
- Driver POD → ops release gate (seed of dispute reserve)  
- Generic ERP integration (anti-leakage foundation before Tally adapter)  
- Flutter dual surface (carrier app + customer web)  
- RazorpayX payout path  
- Ops admin RBAC bootstrap  

---

## 2. Gap analysis (what remains)

### 2.1 Launch blockers (must close before “commercial pilot”)

| ID | Gap | Why it blocks | PRD ref |
|----|-----|---------------|---------|
| L1 | No Track A/B payment | Advance auth loses SME shippers; PRD forbids NaviG8r as lender | §4 |
| L2 | Mock OTP / no SMS | Cannot onboard real Delhi operators | §6 / §7.4 |
| L3 | No GSTIN verification | ICP requires GST; Rupifi/NACH need it | §3, §6A |
| L4 | No shipper dispute window | Trust + collections; ops release alone is not enough | §4.1 Track B |
| L5 | POD without artifacts | Photo/OTP evidence required for disputes & insurance later | §6A/B |
| L6 | No lifecycle notifications | Brokers win on WhatsApp; silent portal loses ops | §6A |
| L7 | Persistence races + schema lag | Full-snapshot DB writes unsafe under concurrent book/POD; Prisma schema also omits integration maps/external metadata — **DB mode can drop ERP keys/webhooks on persist** | ROADMAP A3, erp docs |
| L8 | Live money not productionized | Test Razorpay keys; retry UX; webhook URL; live RazorpayX | ROADMAP B0.1 |
| L9 | Driver/app pilot hygiene | Env label, crash reporting, distribution for 10–25 devices | ROADMAP B1–B5 |
| L10 | Ratings absent | CPR-Month definition includes “rated” | PRD North Star |

### 2.2 Phase 1 differentiators (after pilot proves CPR)

| ID | Gap | Notes |
|----|-----|-------|
| P1 | Tally / Zoho named adapters | Generic API exists; Hub adapters next |
| P2 | Load templates + rate intelligence | Needs ≥30 cleared trips/lane |
| P3 | TMS-lite shipper analytics | Charge only after value is obvious |
| P4 | Digilocker / deeper carrier KYC | Beyond `kycStatus` |
| P5 | In-app masked chat | WhatsApp-assisted OK in Phase 1 if logged |
| P6 | Hindi (then TA/TE) carrier UI | Vernacular for driver adoption |
| P7 | Insurance referral embed | Referral only — not principal |
| P8 | Working-capital referral | Credlix/TReDS — post-delivery |

### 2.3 Explicitly deferred (do not staff pre-launch)

- Own freight financing / NBFC / early-pay float product  
- PTL/LTL / cross-dock  
- AI SaaS subscription / demand forecasting (Month 18+)  
- Microservices + Kafka rewrite  
- Multi-corridor national density  
- Intracity competition with Porter  

### 2.4 Payment model gap (detail)

```
TODAY:  Book → Razorpay authorize → trip → POD → capture → T+7 ledger → payout batch
PRD:    Book → (Rupifi approve OR NACH ready) → trip → POD → 48h dispute →
        collect (Rupifi settles NaviG8r T+1 OR NACH debit) → carrier T+3
```

**Implication:** Launch engineering’s critical path is a **Payment Orchestrator** that can run Track A and Track B without rewriting trip state machine. Existing `PaymentStatus` enum and Razorpay capture path become one adapter among several.

---

## 3. High-level technical design

### 3.1 Design principles

1. **One system of record** — trip/shipment/payment/dispute states live in API DB; WhatsApp is a channel, not the ledger.  
2. **Adapter boundaries** — `PaymentProvider`, `KycProvider`, `NotifyProvider`, `ErpAdapter` interfaces; no Rupifi types in core trip logic.  
3. **Evolve the monolith** — modular packages inside `apps/api` first; extract services only when queue/latency forces it.  
4. **Ops-assisted Phase 0** — human override for match, release, and collections with audit trail.  
5. **Row-level persistence before scale** — replace full-store Prisma sync before 100 concurrent writers.

### 3.2 Target modular architecture (still one deployable)

```
┌─────────────┐  ┌──────────────┐  ┌─────────────┐
│ Customer Web│  │ Carrier App  │  │ Ops Console │
│ (Flutter)   │  │ (Flutter)    │  │ (Admin v2)  │
└──────┬──────┘  └──────┬───────┘  └──────┬──────┘
       │                │                 │
       └────────────────┼─────────────────┘
                        ▼
              ┌───────────────────┐
              │  NaviG8r API      │
              │  (Node monolith)  │
              ├───────────────────┤
              │ Auth / RBAC       │
              │ Trip & Matching   │
              │ Documents         │
              │ Disputes          │
              │ Payment Orchestr. │──► Rupifi | eNACH | Razorpay | RazorpayX
              │ Notify            │──► SMS | WhatsApp | Email
              │ Integration Hub   │──► Generic REST + Tally/Zoho adapters
              │ Analytics export  │
              └─────────┬─────────┘
                        ▼
                   Postgres
```

### 3.3 Domain model extensions (additive)

| Entity | Purpose |
|--------|---------|
| `ShipperCompliance` | GSTIN, PAN, verification status, NIC check timestamps |
| `PaymentMandate` | eNACH token, max amount, bank last4, status |
| `CreditLine` | Rupifi line id, limit, available, partner status |
| `PaymentIntent` | Track A/B/exception; amount; attempt log |
| `Dispute` | shipmentId, reason, evidence URLs, window ends, resolution |
| `DocumentObject` | type (POD_PHOTO, LR, EWB, GST_INVOICE), storage key, SHA |
| `Rating` | shipmentId, raterRole, score, tags |
| `NotificationOutbox` | channel, template, payload, delivery state |

Shipment status machine stays; add **payment readiness** and **dispute** as parallel state machines so trip progress is not blocked by partner outages (circuit breaker → Track B fallback per PRD §7.3).

### 3.4 Payment Orchestrator

**Interfaces**

- `assessCheckout(shipper, amount) → { track: A|B|EXCEPTION, instruments[] }`  
- `authorizeDispatch(shipment) → ok | block` (no truck move without readiness)  
- `onPodAccepted(shipment)` → open dispute window; schedule collection  
- `onDisputeWindowClosed(shipment)` → NACH debit or finalize Rupifi invoice  
- `onFundsReceived(shipment)` → mark platform settled; enqueue carrier payable  
- `disburseCarrier(payable)` → RazorpayX / bookkeeping  

**Track A (Rupifi)**  
Checkout draws credit → partner pays NaviG8r per commercial terms → carrier paid from operating float / settlement → shipper repays partner. NaviG8r never books shipper AR.

**Track B (eNACH via Razorpay/Cashfree)**  
Mandate at onboarding → POD → 48h dispute → debit → on success, carrier payable eligible (target **T+3**, migrate from T+7 once float funded).

**EXCEPTION**  
Manual advance / Razorpay authorize only for whitelist ops cases (legacy path), audited.

### 3.5 Dispute & POD design

1. Driver submits POD + photo (+ optional receiver OTP).  
2. Shipment → `PENDING_RELEASE`; documents stored (S3/R2).  
3. Shipper notified (WhatsApp + in-app); **48h** clock starts.  
4. Shipper **Accept** → release early; **Dispute** → hold collection & carrier pay; ops queue.  
5. Timeout with no dispute → auto-accept → collection.  
6. Ops resolution writes adjustment + audit.

This upgrades today’s ops-only release into PRD-compliant dispute reserve without discarding existing endpoints.

### 3.6 Notifications

Template-driven outbox:

| Event | Channel |
|-------|---------|
| OTP | SMS (primary) |
| Booked / accepted / started / POD / dispute / debit fail | WhatsApp Business |
| Ops escalations | WhatsApp + email |

Provider: MSG91/Twilio SMS + Gupshup/Wati WhatsApp. Failures retry via outbox; never block trip transitions.

### 3.7 Compliance & KYC

- GSTIN validate via public/NIC APIs at shipper org create.  
- Carrier: PAN + bank account for payout; Digilocker licence in Phase 1.  
- DPDP: consent flags, export/delete endpoints before widening PII collection.

### 3.8 Data plane hardening

| Now | Target before 100 trips/day |
|-----|-----------------------------|
| Full `Store` snapshot to Postgres | Per-aggregate repositories + transactions |
| Optional indexes | Unique phone, shipment org/phone indexes |
| Single instance timers | Explicit job runner (cron) for NACH retries, webhook retry, payout |

### 3.9 Admin Console v2

Replace HTML toy console incrementally:

1. Queues: KYC, POD review, disputes, NACH failures, payouts  
2. Shipment timeline + document viewer  
3. Metrics: CPR-Month, fill rate, match time, NACH fail %, dispute %  

Flutter web or lightweight React is fine; **API contracts first**.

### 3.10 ERP path (anti-leakage)

| Stage | Work |
|-------|------|
| Now | Generic loads + webhooks (shipped) |
| Launch+ | First shipper live on generic API |
| Phase 1 | Tally XML/bridge adapter → LoadIntent; Zoho Books webhook |
| Later | Busy/Marg/SAP; voucher write-back |

### 3.11 Security & environments

- Staging Render service + DB (separate from pilot prod)  
- Secrets only in Render; no OTP_DEBUG in prod  
- Webhook HMAC already patterned (Razorpay, ERP) — reuse for Rupifi/NACH  
- Workspace **Pro** on Render when teammates need dashboard access (Hobby = 1 seat)

---

## 4. Realistic project roadmap

Assumptions: **2–3 engineers + founder ops**, Delhi–Mumbai only, partnership time for Rupifi/NACH sandboxes is on the critical path.

### Phase A — Pilot hardening (≈ 4–6 weeks)

**Goal:** Safe closed pilot on *current* money rails while building Track B in parallel.

| Workstream | Deliverables |
|------------|--------------|
| Money live | Live Razorpay keys, webhook URL, retry payment UX, RazorpayX or controlled bookkeeping with clear ops SOP |
| Auth | Real SMS OTP; rate limits; disable debug codes in prod |
| App | Env banner, crash reporting, versioned APK/Firebase distribution, driver POD photo upload |
| Data | Indexes + start row-level writes for book/POD/payment; extend Prisma schema for integration entities before relying on `PERSISTENCE=DB` in ERP pilots |
| Ops | Runbook; Day-0 test script; 10 shipper / 15 carrier target list |
| Metrics | Log CPR inputs (completed / paid / rated once ratings land) |

**Exit:** 10–20 internal/friendly trips end-to-end on production without data loss.

### Phase B — PRD payment + trust spine (≈ 6–10 weeks) — *true launch critical path*

| Workstream | Deliverables |
|------------|--------------|
| Track B | eNACH mandate onboarding, debit after dispute window, failure protocol (T+5/T+8/T+10) |
| Track A | Rupifi sandbox → production adapter (can slip if partner delayed; Track B still launches) |
| Dispute | 48h window, shipper accept/dispute UI, ops resolution queue |
| GSTIN | Required on customer org; block book if invalid |
| Notify | WhatsApp templates for lifecycle + debit failures |
| Docs | Object storage for POD/LR; URLs on shipment |
| Ratings | Mandatory post-delivery for shipper + carrier |
| Payout | Move eligible pay to ~T+3 once float reserved (seed WC) |

**Exit (Product Launch):** ≥100 CPR trips; fill rate ≥30%; NACH success ≥93% or Rupifi live for ≥5 shippers; NPS ≥30; no advance required for standard ICP.

### Phase C — Phase 1 productization (≈ 3–4 months post-launch)

| Workstream | Deliverables |
|------------|--------------|
| ERP | Tally adapter + 50 ERP-originated loads |
| Shipper | Load templates, lane analytics (TMS-lite soft launch) |
| Carrier | Hindi UI, Digilocker KYC, return-load suggestions (rule-based) |
| Corridor | Delhi–Kolkata / Delhi–Chandigarh after density on Delhi–Mumbai |
| Growth | Insurance referral; Credlix referral button |

**Exit:** Path to ~1,200 trips/month economics; seed raise triggers from PRD §10.2.

### Phase D — Scale / Series A prep (Month 12–20)

TMS paid tier, Zoho, performance scores with statistical floors, working-capital referrals, AI only as ops-assist — **not** billed AI SaaS until data moat exists (PRD §8).

---

## 5. Ordered backlog (engineering)

### P0 — next 30 days

1. SMS OTP provider integration  
2. POD photo upload + storage  
3. Payment retry + live Razorpay/webhook production checklist  
4. GSTIN field + validation on customer org  
5. Prisma indexes + transactional book/POD path (start); include integration tables in schema; capacity reservation locking  
6. Crashlytics + pilot distribution  
7. Ops runbook + Day-0 script  

### P0/P1 — days 30–90 (launch)

8. Payment Orchestrator skeleton + EXCEPTION rail (current Razorpay)  
9. eNACH mandate + debit job + admin failure queue  
10. Dispute entity + 48h timer + shipper UI  
11. WhatsApp notification outbox  
12. Ratings  
13. Carrier payout timing aligned to collections  
14. Rupifi adapter (parallel; not gate if Track B ships)  

### P1 — post-launch

15. Tally adapter  
16. Load templates  
17. Admin console v2 queues  
18. Hindi carrier strings  
19. Lane rate estimates from cleared GTV  
20. TMS-lite dashboard  

---

## 6. Credible launch plan (operating narrative)

### What “launched” means

Not “every PRD checkbox.” It means a **Delhi NCR GST SME** can:

1. Onboard with GSTIN + NACH (or Rupifi),  
2. Book FTL on Delhi–Mumbai against verified carriers,  
3. Track the truck live,  
4. See POD evidence,  
5. Raise a dispute within 48h or auto-settle,  
6. Pay without advance handshake credit from a broker,  
7. While carriers get paid on a published schedule they trust.

### Resourcing sketch

| Role | Focus |
|------|-------|
| Eng 1 | Payment orchestrator + NACH/Rupifi |
| Eng 2 | Trip/POD/dispute + persistence hardening |
| Eng 3 / founder-tech | Flutter UX, WhatsApp, pilot ops tooling |
| Founder ops | Carrier density Delhi–Mumbai, shipper LOIs, partner BD |

### Capital alignment (from PRD §10, mapped to this plan)

- **Pre-seed ₹60–80L:** Phase A–B build + ~₹1Cr path to Track B float (size float to volume; don’t treat as lending book).  
- **Seed $500K–$750K:** Trigger after Phase B exit metrics — funds Phase C corridor + sales + float growth.  

### Risk register (execution)

| Risk | Mitigation |
|------|------------|
| Rupifi delayed | Launch on Track B alone |
| NACH fail rate >7% | Strict GST + bureau threshold; suspend orgs fast |
| Liquidity chicken-egg | Supply-first: 50 carriers before broad shipper open |
| Scope creep into TMS/AI | Freeze Phase C features until 100 CPR |
| Render Hobby single-seat | Upgrade workspace to Pro when hiring ops/eng |
| DB snapshot corruption | Prioritize A3 repositories before marketing push |

### Success dashboard (weekly in pilot)

- CPR-Month  
- Fill rate  
- Time-to-match  
- NACH fail % / Rupifi approval %  
- Dispute %  
- Manual ops overrides count  
- Carrier activation %  

---

## 7. Summary map — PRD phase vs this plan

| PRD phase | This plan | Outcome |
|-----------|-----------|---------|
| Phase 0 pre-seed build | Phase A + B | Commercial pilot launch |
| Phase 1 seed | Phase C | Density + Tally + TMS-lite |
| Phase 2–3 | Phase D | $1M ARR path / Series A |

---

## 8. Document control

| Item | Value |
|------|-------|
| Related PRD | `docs/NaviG8r_PRD_v2.docx` / `scripts/generate-prd-v2.js` |
| Related checklists | `ROADMAP.md`, `docs/erp-integration.md`, `docs/pilot-api.md` |
| Owner | Uwais Khan / NaviG8r |
| Next review | After Phase A exit (first 10–20 prod trips) |
