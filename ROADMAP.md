## logistics-mvp roadmap (checklist)

This is the execution checklist for taking the MVP from **file-backed JSON persistence** to a real database, and shipping an **Android pilot (~10 installs)** for customer feedback.

---

### What we’ve achieved (so far)

- [x] **Pilot OTP auth**: `POST /v1/auth/otp/start` + `POST /v1/auth/otp/verify` returns a Bearer token.
- [x] **Driver pilot flows**: register/login, publish anchor trip, list + view my trips.
- [x] **Customer marketplace**: browse trips, quote, book (quote supports pickup/drop + optional `anchorTripId` and returns a **breakdown**).
- [x] **Customer shipment visibility**:
  - [x] Org-scoped listing when booking as logged-in customer (`customerOrgId`).
  - [x] Anonymous booking linkage via phone (`customerPhone` → `Shipment.bookedByPhone`) visible after OTP with same phone.
- [x] **Production hardening**: legacy demo/admin routes gated behind `ENABLE_LEGACY_DEMO_SURFACE=1`; marketplace stays enabled.
- [x] **Android build unblockers**: Gradle/AGP alignment and dependency pinning for Flutter 3.22.x on macOS 13.
- [x] **Customer OTP screen UX fix**: customer flow uses `/login?mode=customer` and renders OTP inside `CustomerScaffold`.
- [x] **B0.2 freight & pricing (shipped)**:
  - [x] Core: `computeFreightGrossPaise` — **shipment** pickup→drop km when both exist, else **lane** trip origin→destination km, else **weight-only**; env `FREIGHT_PAISE_PER_KM_*`, `FREIGHT_MIN_GROSS_PAISE`, `modelVersion` on breakdowns.
  - [x] `POST /v1/pilot/rates/estimate` (carrier pilot only) + **Publish** “Suggested freight” card (debounced).
  - [x] `POST /shipments/quote` extended + **Customer book** Quote shows **breakdown**; **`bookShipment` `grossPaise`** uses the same rules (aligned with quote when coords exist).
  - [x] Tests: `apps/api/src/freight.test.ts` + updates in `pilotDriver.test.ts`; docs in `docs/pilot-api.md` + README env notes.

---

## A) Replace JSON file store with database persistence

### A1 — Choose DB + ORM + deployment shape (1 day)
- [ ] **DB choice**: Postgres (recommended for hosted pilots) vs SQLite (single-node only).
- [ ] **ORM choice**:
  - Option 1: Prisma (fast schema/migrations, good DX)
  - Option 2: Drizzle (lighter, explicit SQL-ish)
  - Option 3: Knex (minimal ORM)
- [ ] **Decide migration strategy**: one-time import from `store.json` vs “start fresh” for pilot environments.
- [ ] **Define environments**:
  - local dev (docker Postgres or local Postgres)
  - staging (hosted Postgres)
  - production (hosted Postgres)

### A2 — Define schema + indexes (0.5–1 day)
- [ ] **Tables**: `users`, `organizations`, `memberships`, `vehicles`, `driver_profiles`
- [ ] **Auth**: `otp_challenges`, `auth_sessions` (token revocation/expiry storage if needed)
- [ ] **Trips + shipments**: `anchor_trips`, `shipments`, `payments`
- [ ] **Ledger/payout**: `ledger_lines`, `payout_batches`
- [ ] **Indexes & uniqueness**:
  - `users.phone` unique
  - memberships unique `(user_id, org_id)`
  - shipments visibility helpers:
    - index `shipments.customer_org_id`
    - index `shipments.booked_by_phone`
  - list queries (createdAt desc) indexes where needed

### A3 — Persistence layer (2–4 days)
- [ ] **Add `apps/api/src/db/`**:
  - connection pooling
  - transaction helper
  - typed query layer/repositories
- [ ] **Replace `Store` access patterns**:
  - read/write functions in `services.ts` should use repositories instead of `store.*.get/set`
  - preserve current validation + error contracts (`ApiError` messages)
- [ ] **Id generation**: keep current id prefixes (`usr_`, `org_`, `trip_`, `shp_`, …) or migrate to UUIDs.
- [ ] **Atomicity**:
  - booking reserves capacity + creates payment/shipment in one transaction
  - POD updates shipment + ledger entry transactionally
  - fail-refund reversals transactionally

### A4 — Migrations + bootstrapping (1–2 days)
- [ ] **Create migrations** for all tables.
- [ ] **Seed script** (optional) for demo data.
- [ ] **One-time importer**:
  - parse existing `store.json`
  - insert rows in safe order (orgs → users → memberships → trips → shipments → ledger)
  - idempotency rules (re-run safe) or “one shot” CLI.

### A5 — Runtime config + roll-out (0.5–1 day)
- [ ] **Env vars**:
  - `DATABASE_URL`
  - remove/ignore `DATA_FILE` in DB mode
- [ ] **Feature flag**:
  - `PERSISTENCE=FILE|DB` temporarily during transition
- [ ] **Update `docs/`**:
  - how to run DB locally
  - how to migrate/import
  - Render deployment notes (Postgres + migrations)

### A6 — Tests + verification (1–2 days)
- [ ] **Service-level tests**: booking visibility (`bookedByPhone`), org scoping, payouts.
- [ ] **HTTP tests**: production gating, auth-required shipment endpoints.
- [ ] **Data consistency checks**: reservedKg/capacity invariants, payout schedule invariants.

---

## B) Release pilot Android app to ~10 customer devices

---

## B0) Payments + pricing tracks (pilot-critical)

### B0.1 — Razorpay payments for customer bookings (2–5 days)
- [ ] **Decide payment moment**:
  - Option A (simplest): pay at booking (customer pays full amount upfront)
  - Option B: authorize now, capture later (requires more states + edge cases)
- [ ] **Define payment states** (server canonical):
  - `created` → `authorized` → `captured` → `failed` → `refunded`
- [ ] **Razorpay server integration**:
  - [ ] Create Razorpay account + keys (test + live)
  - [ ] Add env vars: `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET`
  - [ ] Add API endpoints:
    - `POST /v1/payments/razorpay/order` (create order for a shipment booking)
    - `POST /v1/payments/razorpay/webhook` (verify signature, update payment status)
  - [ ] Persist payment records with idempotency (webhooks can repeat)
- [ ] **Customer app checkout**:
  - [ ] Add Razorpay Flutter SDK
  - [ ] Booking flow:
    - create shipment (or draft) → create Razorpay order → open checkout → confirm result → refresh shipment/payment
  - [ ] UX: handle cancel/failure and “retry payment”
- [ ] **Security + correctness**:
  - [ ] Verify webhook signatures (do not trust client payment success alone)
  - [ ] Reconciliation endpoint (optional): query Razorpay order/payment for debugging
- [ ] **Tests**:
  - [ ] webhook signature verification tests
  - [ ] double-delivery idempotency tests (same webhook twice)

### B0.2 — Driver-side pricing help (rates by distance / weight)

**Baseline (historic):** Early booking price used only **`weightKg`**. **`AnchorTrip`** still has **no persisted rate field**. **Shipped:** `computeFreightGrossPaise` — when trip + booking have coordinates, **`grossPaise`** uses **shipment** pickup→drop km (preferred) or **lane** km, plus ₹5/kg; otherwise weight-only fallback. **`POST /v1/pilot/rates/estimate`** remains advisory lane samples for publishers.

#### B0.2a — Plan review (what we build first)

**Status:** Phases **1–4** are implemented in repo (booking totals **do** use distance+weight when geo allows; Razorpay go-live still needs **B0.1** tuning/reconciliation).

| Phase | Scope | Outcome |
|-------|--------|--------|
| **1 — Estimator** | Server function + `POST /v1/pilot/rates/estimate` (Bearer: pilot on carrier org) | **[Done]** Returns `laneKm`, `samples[]` with `grossPaise` + `breakdown` per sample weight (pilot-only). |
| **2 — Driver UI** | `PublishTripScreen` calls estimate after origin/dest + vehicle class change | **[Done]** Debounced “Suggested freight” card (samples 100/250/500 kg); disclaimer that customer price may use shipment km. |
| **3 — Customer UI** | Extend `POST /shipments/quote` with pickup/drop + `weightKg` + optional `anchorTripId` | **[Done]** Response `quote.grossPaise` + `quote.breakdown`; customer app prints breakdown on Quote. |
| **4 — Canonical pricing** | `bookShipment` uses same freight model as quote | **[Done]** `grossPaise` reflects distance+weight when coords exist; tests + docs. Coordinate amounts with **B0.1** before live payments. |

**Not done (still optional):** per-trip price hints on **`CustomerEligibleTripsScreen`**; structured logging/metrics for estimates beyond `modelVersion` on payloads.

#### B0.2b — Distance definition (product choice)

- **Option A — Lane distance (driver-centric):** use trip `origin` → `destination` haversine km. Good for “what this truck run should earn per kg/km.”
- **Option B — Shipment distance (customer-centric):** use shipment `pickup` → `drop` km when quoting/booking (may differ from lane if detours matter).
- **Pilot recommendation:** estimator returns **both** with labels (`laneKm`, `shipmentKm` when coords exist) so driver and customer screens can highlight the relevant one without ambiguity.

#### B0.2c — Implementation checklist

- [x] **Define pricing model inputs**:
  - [x] lane distance (km) and/or shipment distance (km)
  - [x] `weightKg`
  - [x] `vehicleClass` (`SMALL|MEDIUM|LARGE`)
  - [x] optional minimum gross floor (**`FREIGHT_MIN_GROSS_PAISE`**) when distance is priced.
  - [ ] optional: distance cap, surcharge tiers _(not implemented yet)_
- [x] **Config knobs** (env — see `apps/api/src/config.ts` + `docs/pilot-api.md`):
  - [x] `FREIGHT_PAISE_PER_KM_SMALL` / `_MEDIUM` / `_LARGE`
  - [x] **`PRICE_PAISE_PER_KG`** (still the weight leg; default 500 paise/kg)
  - [x] **`FREIGHT_MIN_GROSS_PAISE`** optional floor
- [x] **Server**: **`computeFreightGrossPaise`** (+ `quoteShipmentMarketplace`, `pilotRatesEstimate`) + unit tests **`freight.test.ts`**.
- [x] **API**: `POST /v1/pilot/rates/estimate` — body `{ origin, destination, vehicleClass?, sampleWeightsKg?[] }`; response **`laneKm`**, **`samples[]`**, **`modelVersion`**.
- [x] **API (customer parity)**: `POST /shipments/quote` — `weightKg` + optional `pickup`/`drop` (+ optional **`anchorTripId`**); **`{ quote: { grossPaise, breakdown } }`** documented in **`docs/pilot-api.md`**.
- [x] **Driver pilot UI** (`PublishTripScreen`):
  - [x] Debounced **“Suggested freight”** after map pins / vehicle class (samples 100 / 250 / 500 kg).
  - [x] Copy explains lane-based estimate vs customer **shipment** distance (see pilot-api / README).
- [x] **Customer pilot UI** (`CustomerBookShipmentScreen`):
  - [x] **Quote** sends pickup/drop + optional `anchorTripId`; shows **breakdown** (mode, km, components, `modelVersion`).
- [ ] **`CustomerEligibleTripsScreen` (optional)**:
  - [ ] One-line “from ~₹…” per trip tile (needs default weight + shared estimator call).
- [ ] **Calibration / observability (lightweight)**:
  - [ ] Log estimate inputs + hashes (no PII); or metrics counter for tuning later.
  - [x] **`modelVersion`** on quote/estimate breakdowns.

#### B0.2d — UI impact summary (screens)

| App area | Screen / route | Was (before B0.2) | Now (shipped) |
|----------|-----------------|-----------------|---------------|
| **Driver** | `PublishTripScreen` (`/publish`) | Publish only; no pricing hints | **“Suggested freight”** card + `POST /v1/pilot/rates/estimate` (lane km samples); still **no stored rate** on `AnchorTrip` |
| **Driver** | `MyTripsScreen` / trip detail (`/trips`, `/trips/:id`) | List/detail only | _Unchanged;_ optional subtitle “Suggested range …” **not** built |
| **Driver** | `HomeScreen` quick actions | No pricing | _Unchanged;_ optional rate guide **deferred** |
| **Customer** | `CustomerBookShipmentScreen` (`/customer/book`) | Quote `{ weightKg }` only | Quote sends **pickup/drop** + optional **`anchorTripId`**; UI shows **`breakdown`**; matches **booking** totals when coords align |
| **Customer** | `CustomerEligibleTripsScreen` (`/customer/eligible`) | Eligible trips + navigate to book | _Unchanged;_ per-trip indicative ₹ **optional / not shipped** |

#### B0.2e — Risk / dependency notes

- **Canonical `grossPaise` changed** when trip + booking have usable coordinates — impacts **ledger, payouts, mocked capture, and future Razorpay**. Re-tune **`FREIGHT_PAISE_PER_KM_*`** and verify **`moneySplit`** / payout tests before live money (**B0.1**).
- If coordinates are missing, pricing **gracefully degrades** to **weight-only** (same spirit as legacy).

### B1 — “Pilot-ready” product basics (1–2 days)
- [ ] **Branding**: app name, icon, package id, launch screen.
- [ ] **Environments**: dev vs pilot base URL switch (and a visible “Env: Pilot” label).
- [ ] **Authentication UX**:
  - clear “Sign in required to view shipments”
  - persist Bearer token securely (already using secure storage; verify behavior)
- [ ] **Error handling**:
  - network/offline messaging
  - “unauthorized” recovery path (“Sign in again”)

### B2 — Build + signing + distribution (1–2 days)
- [ ] **Versioning**: set `version:` and Android versionCode/versionName.
- [ ] **Signing**:
  - generate keystore (store securely)
  - configure `android/key.properties` (do not commit secrets)
  - build **release APK/AAB**
- [ ] **Distribution method** (pick one):
  - Firebase App Distribution (recommended)
  - Google Play Internal Testing
  - Direct APK + manual install instructions (fastest but least managed)

### B3 — Telemetry + feedback loop (1–2 days)
- [ ] **Crash reporting**: Sentry or Firebase Crashlytics.
- [ ] **Analytics** (minimal events):
  - OTP start/verify success/failure
  - quote/book success/failure
  - shipments list viewed
  - shipment detail viewed
- [ ] **Feedback channel**:
  - WhatsApp group + escalation owner
  - in-app “Send feedback” deep link (mailto/WhatsApp)

### B4 — Pilot operations (0.5–1 day)
- [ ] **Onboarding doc** for customers:
  - install steps
  - OTP sign-in
  - book shipment with `customerPhone`
  - view shipments after sign-in
- [ ] **Runbook**:
  - how to reset a user
  - how to inspect shipments/trips (admin surface or DB queries)
  - support FAQs
- [ ] **Customer list**: 10 target installs with names/phones + status.

### B5 — “Day 0” test plan before sending to customers (0.5 day)
- [ ] Fresh install → OTP → browse → quote → book (anonymous + phone) → shipments list shows after OTP.
- [ ] Book logged-in customer org → shipments list shows by org.
- [ ] Shipment detail → POD simulation (if enabled) → refund (if enabled).
- [ ] Emulator + at least 1 physical Android device smoke test.

---

## C) Next execution steps (suggested order)

- [x] **Customer OTP navigation baseline**: `/login?mode=customer` + OTP in `CustomerScaffold` (see **What we’ve achieved**). _Further polish/home shortcuts still optional._
- [ ] **`flutter run` + device smoke**: full quote/book flow on emulator + physical device (also **B5**).
- [ ] **Payment decision**: Razorpay “pay at booking” vs “authorize then capture”.
- [ ] **Implement Razorpay (test mode)** end-to-end (server order + webhook + client checkout).
- [ ] **DB decision**: pick Postgres + ORM + migration strategy.
- [ ] **Implement DB persistence behind a feature flag** (`PERSISTENCE=DB`) and keep file mode for local fallback.
- [ ] **Staging deploy** with Postgres + migrations.
- [x] **B0.2 freight & pricing (phases 1–4)** — `rates/estimate`, **Publish** suggested freight, **Quote** breakdown + **`bookShipment` parity** when coords exist; tests + docs. **Still open:** optional eligible-trip ~₹ hints (**B0.2c**) + structured estimate logging/metrics.
- [ ] **Pilot build**: release signing + distribution + crash reporting.
- [ ] **10-device rollout** + weekly feedback triage.

