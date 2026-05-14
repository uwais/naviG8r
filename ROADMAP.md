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
- [x] **Customer OTP screen UX fix**: customer flow uses `/login?mode=customer` and renders OTP inside `CustomerScaffold`; after verify, **Continue to customer home** + bottom **Customer** tab route to **`/customer`** (scaffold uses `matchedLocation`, not a fake `/customer` path on login).
- [x] **B0.2 freight & pricing (shipped)**:
  - [x] Core: `computeFreightGrossPaise` — **shipment** pickup→drop km when both exist, else **lane** trip origin→destination km, else **weight-only**; env `FREIGHT_PAISE_PER_KM_*`, `FREIGHT_MIN_GROSS_PAISE`, `modelVersion` on breakdowns.
  - [x] `POST /v1/pilot/rates/estimate` (carrier pilot only) + **Publish** “Suggested freight” card (debounced).
  - [x] `POST /shipments/quote` extended + **Customer book** Quote shows **breakdown**; **`bookShipment` `grossPaise`** uses the same rules (aligned with quote when coords exist).
  - [x] Tests: `apps/api/src/freight.test.ts` + updates in `pilotDriver.test.ts`; docs in `docs/pilot-api.md` + README env notes.
- [x] **B0.1 Razorpay (repo wiring, test mode)**: `PAYMENT_PROVIDER=RAZORPAY` — order without capture on book, webhook updates, capture at POD, Flutter checkout; **`PERSISTENCE=DB`** Postgres via Prisma for optional persistence.
- [x] **Local dev verification**: `npm install` in `apps/api` then  
  `node --experimental-strip-types --test "apps/api/src/**/*.test.ts" "packages/**/src/**/*.test.ts"` (from repo root) — **all tests passing**.
- [x] **Render production deploy (Docker)**: API ships as a Web Service from repo root with `Dockerfile`; build fixed for Prisma (`npm install --ignore-scripts` then copy tree + `npx prisma generate`) and valid `apps/api/package.json` (no merge-conflict JSON).
- [x] **Hosted pilot API + Postgres**: `PERSISTENCE=DB` + `DATABASE_URL` on Render; env/runbook notes in `docs/RENDER.md`.
- [x] **Legacy HTML admin (`/admin`)** (still gated in production by `ENABLE_LEGACY_DEMO_SURFACE=1`):
  - OTP login (stores Bearer in `localStorage`), `GET /v1/auth/me`.
  - **Ops admin RBAC**: `MembershipRole` **`OPS_ADMIN`** + singleton **`PLATFORM`** org; `GET/POST/DELETE /v1/ops-admins` for DB-backed operator whitelist; admin UI to list / grant / revoke (revoke only for DB rows).
  - Optional bootstrap `OPS_ADMIN_PHONES` (comma-separated); first OTP verify **materializes** a DB `OPS_ADMIN` membership so the env list can be dropped after onboarding.
  - **POD / fail-refund**: logged-in **ops admin** can act on **any** shipment (not only customer-visible rows); customers remain org/phone scoped.
  - Admin header shows **Postgres (Prisma, PERSISTENCE=DB)** when not file-backed (fixes stray `Backed by null`).
- [x] **Android pilot packaging (partial)**: `applicationId` / namespace **`com.navig8r.pilot`**, app label **naviG8r**, release signing wired via `key.properties` + keystore (see `docs/android-option-a-apk-pilot.md`).

---

## A) Replace JSON file store with database persistence

### A1 — Choose DB + ORM + deployment shape (1 day)
- [x] **DB choice**: Postgres (hosted pilots).
- [x] **ORM choice**: Prisma.
- [x] **Migration strategy for pilot**: greenfield / `prisma db push` — **no** `store.json` importer in repo yet (not required pre-pilot).
- [ ] **Define environments**:
  - local dev (docker Postgres or local Postgres)
  - [ ] staging (hosted Postgres) — *optional; not a hard blocker if production pilot is the only hosted env today*
  - [x] production (hosted Postgres on Render — pilot Web Service)

### A2 — Define schema + indexes (0.5–1 day)
- [x] **Tables** (Prisma models): carriers, organizations, users, memberships, vehicles, driver profiles, OTP challenges, auth sessions, anchor trips, shipments, payments, ledger lines, payout batches — see `apps/api/prisma/schema.prisma`.
- [ ] **Indexes & uniqueness** (tune for query patterns):
  - `users.phone` unique
  - memberships unique `(user_id, org_id)`
  - shipments visibility helpers:
    - index `shipments.customer_org_id`
    - index `shipments.booked_by_phone`
  - list queries (createdAt desc) indexes where needed

### A3 — Persistence layer (2–4 days)
- [x] **DB mode** (`PERSISTENCE=DB`): `apps/api/src/persistenceDb.ts` loads/saves the full in-memory `Store` via Prisma (transactional replace). **FILE mode** unchanged (`DATA_FILE`).
- [ ] **Repositories / row-level ops**:
  - connection pooling tuning
  - replace “full snapshot” writes with targeted updates + transactions per use case
  - preserve current validation + error contracts (`ApiError` messages)
- [ ] **Id generation**: keep current id prefixes (`usr_`, `org_`, `trip_`, `shp_`, …) or migrate to UUIDs.
- [ ] **Atomicity** (with row-level layer):
  - booking reserves capacity + creates payment/shipment in one transaction
  - POD updates shipment + ledger entry transactionally
  - fail-refund reversals transactionally

### A4 — Migrations + bootstrapping (1–2 days)
- [x] **Schema apply**: `npx prisma db push` (no checked-in migration history required for pre-pilot greenfield).
- [ ] **Seed script** (optional) for demo data.
- [ ] **One-time importer** from `store.json` (if ever needed).

### A5 — Runtime config + roll-out (0.5–1 day)
- [x] **Env vars**:
  - `DATABASE_URL` when `PERSISTENCE=DB`
  - `DATA_FILE` when file mode (default)
- [x] **Feature flag**:
  - `PERSISTENCE=FILE|DB` (FILE is default when unset)
- [x] **Docs / ops**:
  - hosted Postgres + Render wiring — see `docs/RENDER.md` (Docker root, `AUTH_SECRET`, `OTP_DEBUG`, Razorpay, `ENABLE_LEGACY_DEMO_SURFACE`, optional `OPS_ADMIN_PHONES` bootstrap)

### A6 — Tests + verification (1–2 days)
- [x] **Baseline automated suite (local)**: from repo root, after `apps/api` **`npm install`**,  
  `node --experimental-strip-types --test "apps/api/src/**/*.test.ts" "packages/**/src/**/*.test.ts"` — **green** (freight, pilot/OTP, marketplace vertical slice, production demo gating, Razorpay webhook HMAC, payout schedule helpers, etc.).
- [x] **Service-level coverage (current tests)**: booking/org/payout behaviors exercised via `mvp.test.ts`, `pilotDriver.test.ts`, `freight.test.ts`, and related API tests (not yet a separate DB-backed suite).
- [x] **HTTP / integration coverage (current tests)**: `httpServer.test.ts` plus in-process flows in `mvp.test.ts` (extend when adding `PERSISTENCE=DB`-specific cases).
- [ ] **`PERSISTENCE=DB`**: optional CI or manual regression (Postgres round-trip, concurrent writes) beyond file-mode tests.
- [ ] **Data consistency hardening**: explicit stress/invariant tests for `reservedKg`/capacity and payout edge cases under load or races.

---

## B) Release pilot Android app to ~10 customer devices

---

## B0) Payments + pricing tracks (pilot-critical)

### B0.1 — Razorpay payments for customer bookings (2–5 days)
- [x] **Payment moment**: **authorize at checkout**, **capture at POD** (not pay-in-full capture at booking).
- [x] **Payment states** (server canonical): `CREATED` → `AUTHORIZED` → `CAPTURED` (plus `FAILED`, `REFUNDED`).
- [x] **Razorpay server integration** (test mode wiring in repo):
  - [ ] Operator: create Razorpay account + live keys when going live (test keys + dashboard webhook for dev).
  - [x] Env: `PAYMENT_PROVIDER=RAZORPAY`, `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET`
  - [x] **Booking** creates Razorpay order **`payment_capture: false`** (`attachRazorpayOrderForShipment`); dedicated `POST …/order` route not required — order is tied to **`POST /shipments/book`**.
  - [x] `POST /v1/payments/razorpay/webhook`: HMAC verified (`x-razorpay-signature`), updates persisted payment (`payment.authorized`, `payment.captured`, `payment.failed`).
  - [x] Webhook idempotency: handlers safe for duplicate delivery.
  - [x] **Capture** before POD ledger: `ensureRazorpayCapturedBeforePod`
  - [x] **Refund** path on carrier fail when authorized/captured (`failCarrierAndRefund`)
- [x] **Customer app checkout** (`razorpay_flutter`): after `POST /shipments/book`, open checkout when **`razorpayKeyId`** + **`payment.status`** `CREATED` + `razorpayOrderId`; success/fail snackbars + navigate on success (authorization; server state from webhook).
- [ ] UX: dedicated **retry payment** if checkout cancelled (client can re-call booking or future order endpoint).
- [x] **Security**: webhook signature verification (do not trust client alone).
- [ ] **Reconciliation** (optional): admin query Razorpay for mismatches.
- [x] **Tests**: webhook signature unit test (`razorpayPayments.test.ts`).
- [ ] **Tests**: double-webhook replay integration test against store (nice-to-have).

### B0.2 — Driver-side pricing help (rates by distance / weight)

**Baseline (historic):** Early booking price used only **`weightKg`**. **`AnchorTrip`** still has **no persisted rate field**. **Shipped:** `computeFreightGrossPaise` — when trip + booking have coordinates, **`grossPaise`** uses **shipment** pickup→drop km (preferred) or **lane** km, plus ₹5/kg; otherwise weight-only fallback. **`POST /v1/pilot/rates/estimate`** remains advisory lane samples for publishers.

#### B0.2a — Plan review (what we build first)

**Status:** Phases **1–4** are implemented in repo (booking totals **do** use distance+weight when geo allows). **B0.1** wiring (authorize→capture + webhook + Flutter checkout) is in repo; go-live still needs Razorpay **live** keys, dashboard webhook URL, reconciliation, and retry-payment UX.

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
- [x] **Branding (partial)**: Android **package id** `com.navig8r.pilot`, **display name** naviG8r.
- [ ] **Branding (remainder)**: launcher icon, splash / polish, store listing assets if needed.
- [ ] **Environments**: dev vs pilot base URL switch (and a visible “Env: Pilot” label).
- [ ] **Authentication UX**:
  - clear “Sign in required to view shipments”
  - persist Bearer token securely (already using secure storage; verify behavior)
- [ ] **Error handling**:
  - network/offline messaging
  - “unauthorized” recovery path (“Sign in again”)

### B2 — Build + signing + distribution (1–2 days)
- [ ] **Versioning**: set `version:` and Android versionCode/versionName deliberately per pilot drop.
- [x] **Signing (wired)**:
  - generate keystore (store securely; not committed)
  - configure `android/key.properties` (do not commit secrets)
  - [x] `build.gradle` uses release keystore when `key.properties` + `storeFile` present
- [ ] **Build artifact**: repeatable **release APK/AAB** command in CI or documented one-liner per release.
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
- [x] **Operator runbook (partial)**:
  - [x] Inspect trips/shipments/ledger via **`/admin`** (OTP + ops admin); Mark POD / Fail+refund; manage ops admins via UI + `/v1/ops-admins`
  - [ ] how to reset a user / support FAQs / DB ad-hoc queries beyond admin JSON dumps
- [ ] **Customer list**: 10 target installs with names/phones + status.

### B5 — “Day 0” test plan before sending to customers (0.5 day)
- [ ] Fresh install → OTP → browse → quote → book (anonymous + phone) → shipments list shows after OTP.
- [ ] Book logged-in customer org → shipments list shows by org.
- [ ] Shipment detail → POD simulation (if enabled) → refund (if enabled).
- [ ] Emulator + at least 1 physical Android device smoke test.

---

## C) Next execution steps (suggested order)

### Done recently (high level)

- [x] **Customer OTP navigation baseline**: `/login?mode=customer` + OTP in `CustomerScaffold`; **Customer** bottom tab and **Continue to customer home** (after successful verify) return to **`/customer`** (real `matchedLocation` so nav is not stuck on login).
- [x] **Payment decision**: **authorize at checkout, capture at POD** (Razorpay).
- [x] **Razorpay (test mode)** wired end-to-end: server order on book + webhook + Flutter checkout (live keys + dashboard webhook + retry UX still **B0.1** follow-ups).
- [x] **DB decision**: **Postgres + Prisma**; greenfield / `prisma db push` (no `store.json` importer).
- [x] **DB persistence feature flag**: **`PERSISTENCE=DB`** + file fallback (`DATA_FILE` when not DB).
- [x] **Production pilot deploy** on Render (Docker + Postgres + env from `docs/RENDER.md`).
- [x] **Admin + ops**: OTP-gated `/admin`, **ops admin** DB grants + API, POD/fail-refund across all shipments for ops admins.
- [x] **Android pilot packaging (partial)**: `com.navig8r.pilot`, naviG8r label, release signing pattern.

### What’s next (recommended priority)

1. **Pilot hardening — payments & money** (**B0.1**): Razorpay **live** keys when ready, dashboard **webhook URL** on the public API host, **retry payment** if customer abandons checkout; optional reconciliation. Remember **POD still requires payment `AUTHORIZED`** for real captures — admin “Mark POD” over `CREATED` only works for unauthenticated legacy demo POSTs, not for logged-in flows unless checkout completed (or you introduce an explicit ops-only payment bypass later).
2. **Pilot hardening — app** (**B1–B2**, **B5**): pilot **base URL** switch + visible env label; bump **versionCode** per drop; pick **distribution** (Firebase App Distribution vs internal track vs direct APK per `docs/android-option-a-apk-pilot.md`); **Google Maps** release restrictions (SHA-1 + package `com.navig8r.pilot`); emulator **RAM** for Maps + Razorpay WebView smoke.
3. **Product gap (called out earlier, still open)**: **driver-side POD / trip completion** in the app vs admin-only — design + API + UI when you move past “MVP admin only.”
4. **Data plane** (**A3–A4**, **A6**): Prisma **indexes** / uniqueness (`users.phone`, hot query paths); move off full-snapshot DB writes where it hurts; optional **CI** or manual **Postgres round-trip** regression beyond file-mode tests.
5. **Optional staging**: separate Render service + DB if you want pre-prod before touching production pilot data (**A1**).
6. **Observability** (**B3**): Crashlytics/Sentry + minimal analytics before widening beyond ~10 devices.
7. **10-device rollout** (**B4–B5**): customer list, onboarding doc, day-0 test script, weekly feedback triage.

### Still on the checklist (unchanged themes)

- [ ] **`flutter run` + device smoke**: full quote/book flow on emulator + physical device (also **B5**).
- [x] **B0.2 freight & pricing (phases 1–4)** — `rates/estimate`, **Publish** suggested freight, **Quote** breakdown + **`bookShipment` parity** when coords exist; tests + docs. **Still open:** optional eligible-trip ~₹ hints (**B0.2c**) + structured estimate logging/metrics.
- [ ] **Pilot build (completion)**: versioning cadence + chosen distribution channel + crash reporting (**B2**, **B3**).
- [ ] **10-device rollout** + weekly feedback triage.

