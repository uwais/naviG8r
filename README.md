# naviG8r

**Intercity full-truckload freight, from load to ledger.** An asset-light, India-first
marketplace that connects shippers who need capacity with carriers who have it, then carries
the job all the way through tracking, proof of delivery, and carrier settlement.

> Built for SMEs who outgrew WhatsApp brokers.

Marketing site: [navig8r.org](https://navig8r.org) · API: `https://navig8r.onrender.com` ·
Customer web: `https://navig8r-customer.onrender.com`

---

## The problem

Indian intercity road freight is a large, fragmented market that still runs on phone calls,
WhatsApp groups, and a broker's private spreadsheet. A shipper with recurring loads has no
open view of who has a truck going their way next Tuesday. A carrier with a half-empty truck
on a return leg has no open view of who needs it. Price is a negotiation, not a calculation.
Payment is a follow-up, not a process.

naviG8r puts capacity and demand in the same place, prices the move with arithmetic instead
of haggling, and settles the carrier on a published schedule.

## The core idea: anchor trips

Most freight marketplaces are built around **loads** — a shipper posts a job and brokers bid.
naviG8r inverts it and is built around **anchor trips**.

A carrier publishes a trip they are already running: route, departure window, vehicle class,
and available capacity in kilograms. Shippers then book *into* that trip, consuming part of its
capacity. One trip can carry several shipments.

This matters because it sells the capacity that already exists rather than creating new demand
for it, which is what makes the model asset-light. It also means pricing can be computed
against a known lane, and a carrier can fill a return leg instead of running it empty.

**Phase A constraint.** A shipment can only be booked onto a trip if its pickup is within 15 km
of the trip's origin and its drop within 15 km of the trip's destination. This keeps the first
version to true lane-matching and deliberately excludes detours and multi-stop routing. Both
radii are tunable (`PHASE_A_MAX_PICKUP_KM`, `PHASE_A_MAX_DROP_KM`).

## Who it is for

| Persona | The job they hire naviG8r for | Surface they use |
|---|---|---|
| **Shipper / customer** | GST-registered SMEs shipping on repeat. Find a truck for a known lane, know the price before committing, see where the goods are. | Customer web portal, or ERP integration |
| **Carrier** | Owner-operators and small fleets. Get reliable demand for trips already being run, get paid on a schedule. | Android driver app |
| **Driver** | Run the assigned trip, share location, capture proof of delivery. | Android driver app |
| **Ops admin** | Review deliveries, release payment after POD, run payout batches. | Web ops portal |
| **Shipper ERP** | Push loads and receive lifecycle events without a human retyping them. | Machine-to-machine API + webhooks |

## How it works: from load to ledger in four moves

```
  1 PUBLISH / REQUEST        2 MATCH & BOOK           3 TRACK & PROVE          4 SETTLE
  ─────────────────────      ──────────────────       ─────────────────        ──────────
  Carrier publishes an       Shipper gets a priced    Driver starts the trip   Ops releases
  anchor trip: route,        quote with a breakdown,  and shares live GPS.     after POD.
  window, vehicle class,     then books. Capacity     Shipper and ERP see      Customer payment
  capacity in kg.            is reserved and payment  status events. POD is    captures. Carrier
                             authorization begins.    captured on delivery.    earnings accrue to
  Shipper browses, or                                                          the ledger and pay
  pushes a load from ERP.                                                      out on schedule.
```

**Money moves in a deliberate order.** Booking *authorizes* the customer's payment but does not
capture it. Capture happens at proof of delivery — the customer is charged when the goods
actually arrive. That is the Razorpay path. Under the default `PAYMENT_PROVIDER=MOCK` the payment
is written `CAPTURED` at booking and the sequence never runs (`services.ts:1592`,
`razorpayPayments.ts:6`), so only beta and production exercise it. The carrier's earnings then accrue to a ledger and are paid on a published
schedule rather than whenever someone gets around to it.

### The commercial model, as implemented

| Parameter | Value | Where it lives |
|---|---|---|
| Platform commission | 10% of gross | `COMMISSION_BPS = 1000` in `apps/api/src/config.ts` |
| Weight component | ₹5 per kg | `PRICE_PAISE_PER_KG = 500` |
| Distance component | ₹15 / ₹20 / ₹25 per km for SMALL / MEDIUM / LARGE | `DEFAULT_FREIGHT_PAISE_PER_KM` |
| Payout hold | POD date + 7 calendar days (IST) | `packages/core/src/payoutSchedule.ts` |
| Payout cutoff | Wednesday 18:00 IST, weekly | `PAYOUT_BATCH_SCHEDULE` |

Pricing uses shipment pickup-to-drop distance when both coordinates are known, falls back to
the trip's lane distance, and falls back again to weight-only. Every quote returns a breakdown
and a `modelVersion` so a price can be explained after the fact. All amounts are integer
**paise**; there are no floats in money.

---

## What is in this repository

A single monorepo holding three applications that ship as four deployable artifacts: the API,
customer-web and marketing-site container images, plus the Android APK.

| Path | What it is | Stack |
|---|---|---|
| `apps/api/` | The whole backend: REST API, ops portal, payments, payouts, ERP integration | Node 22.6+, TypeScript run directly via `--experimental-strip-types`, no build step |
| `apps/driver_pilot/` | One Flutter binary serving driver, carrier and customer personas | Flutter 3.22.x, `go_router`, `dio` |
| `apps/www/` | Public marketing site | Vite, vanilla JS + CSS |
| `packages/core/` | Payout schedule arithmetic, shared by the API | TypeScript, zero dependencies |
| `integrations/adapters/generic/` | Reference mapping for connecting a shipper ERP | Documentation |
| `scripts/` | Render build scripts, the Maps key injector, the release-pipeline helpers (`wait-for-release.sh`, `promote-image-tag.sh`), the alpha and beta release gates (`alpha-integration.mjs`, `beta-smoke.mjs`) and an ERP smoke test | Bash and Node ESM |
| `docs/` | Deep documentation — see the index below | Markdown |

The Flutter app ships two ways from the same source: an **Android APK** for drivers and
carriers, and a **static web build** for the customer portal. `kIsWeb` decides which shell
loads at startup.

## Project status — read this before trusting a demo

This is a **pre-pilot build**. The transaction path works end to end and is covered by tests,
but several things a real pilot needs are deliberately still stubs. Being precise about which
is which:

**Working and tested** (60/60 tests pass — verified by running the suite on Node 24):

- Carrier onboarding, anchor trip publishing, freight estimation
- Customer browse, quote with breakdown, book, capacity reservation
- Razorpay authorize-at-booking and capture-at-POD, plus webhook handling (Razorpay path only — see above)
- Live GPS tracking from driver to customer — but the same positions are also served
  unauthenticated, see the first gap below
- POD, ops release, ledger accrual, weekly payout batching
- Shipper ERP API with idempotency, polling, and signed webhooks with retry

**Known gaps that block a real pilot:**

| Gap | Consequence | Evidence |
|---|---|---|
| **Live trip GPS is public** | `GET /anchor-trips` is allowlisted past the production guard and returns whole trip objects, including `lastLiveLocation`, to anyone with the URL and no token. | `apps/api/src/httpServer.ts:300`, `apps/api/src/types.ts:152`; `docs/IMPROVEMENTS.md` C0 |
| **A user cannot log out or close their own account** | There is no `POST /v1/auth/logout` and no self-serve deletion, while both registration routes are open. The only revocation is `DELETE /v1/ops/users`, which needs an ops token, so signing up is one call and signing out is a support request. Sessions last `SESSION_TTL_MS`, 30 days by default. | `apps/api/src/httpServer.ts:503`, `:540`, `:805`; `docs/IMPROVEMENTS.md` H4 |
| **The ops release gate is bypassable** | `POST /shipments/:id/pod` is allowlisted past the production guard and captures payment, writes the carrier ledger line and marks the shipment `DELIVERED` in one unauthenticated call, so the "ops releases after POD" control described above does not hold on that route. | `apps/api/src/httpServer.ts:311`; `docs/IMPROVEMENTS.md` C0d |
| **No SMS provider** | OTP codes are generated but never delivered. With `OTP_DEBUG=0` nobody can log in; with `OTP_DEBUG=1` the code is returned in the API response to anyone who knows a phone number. | `apps/api/src/types.ts:91` — "mock SMS. Replace with real SMS + rate limits in production." |
| **No OTP rate limiting** | A six-digit code with a ten-minute window and unlimited attempts is brute-forceable. | No throttle exists in `apps/api/src/auth.ts` |
| **Carrier payouts are bookkeeping-only outside production** | `PAYOUTS_MODE=BOOKKEEPING` flips ledger lines to PAID without moving money. Only production sets `RAZORPAYX`. | `render.yaml` |
| **Persistence is a JSON file everywhere** | No environment sets `PERSISTENCE=DB`, so the Postgres path is built but unused. It also drops the whole ERP subsystem if switched on. | `render.yaml`; `docs/IMPROVEMENTS.md` C2 |
| **The test suite does not run on pull requests** | `release.yml` triggers on `push: main` and `workflow_dispatch`, so tests run after the merge. `docker-image.yml` and `docker-publish.yml` do run on pull requests, but they only build the API image. Nothing typechecks, and no workflow analyses or tests the Flutter app. | `.github/workflows/release.yml`, `.github/workflows/docker-image.yml`, `.github/workflows/docker-publish.yml` |
| **Alpha and beta serve an unauthenticated data dump** | `NODE_ENV` is set to the environment name, which disables the production guards. `GET /v1/users` returns every user and phone number on both. | `docs/IMPROVEMENTS.md` C5 |

`ROADMAP.md` is the authoritative execution checklist (62 top-level items done, 46 open at time of
writing). `docs/IMPROVEMENTS.md` lists specific defects found by review, ranked.

---

## Quick start

### Prerequisites

**Node 22.6 or newer is required and is not optional.** The API runs TypeScript directly with
`node --experimental-strip-types`, a flag that does not exist before Node 22.6. On Node 20 you
get `node: bad option: --experimental-strip-types` with no further hint. The repo declares no
`engines` field and ships no `.nvmrc`, so nothing warns you.

```bash
node --version   # must be >= 22.6
```

Flutter 3.22.x is needed only for the mobile and customer-web surfaces.

### Run the API

```bash
git clone https://github.com/uwais/naviG8r.git
cd naviG8r/apps/api && npm install   # installs Prisma + Razorpay SDK, runs prisma generate
cd ../..

export AUTH_SECRET="$(openssl rand -hex 32)"   # required, minimum 16 chars, API exits without it
export OTP_DEBUG=1                             # local only: returns the OTP in the response

node --experimental-strip-types apps/api/src/index.ts
```

The API listens on `http://localhost:3000`. Check it with `curl localhost:3000/health`, which
reports the active persistence mode and payment provider. The ops portal is at `/ops` and the
legacy admin console at `/admin`.

With `OTP_DEBUG=1` the login code is a fixed `123456` unless you override `OTP_FIXED_CODE`.

### Run the tests

```bash
node --experimental-strip-types --test "packages/**/src/**/*.test.ts" "apps/**/src/**/*.test.ts"
```

60 tests, no database or network required — they run against the in-memory store.

### Run the Flutter app

```bash
cd apps/driver_pilot
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000     # Android emulator to host
flutter run --dart-define=API_BASE_URL=http://192.168.x.x:3000  # physical device on LAN
```

**Careful:** if you omit `--dart-define=API_BASE_URL`, the app defaults to the *production* API
(`apps/driver_pilot/lib/pilot_api.dart:11`). Test bookings will land in live data.

### Run the marketing site

```bash
cd apps/www && npm install && npm run dev
```

## Configuration

Every environment variable the API reads. Nothing here has a safe default that is also a
production-correct default.

| Variable | Required | Default | What it does |
|---|---|---|---|
| `AUTH_SECRET` | **Yes** | none — API exits | HMAC key for session tokens and integration key hashing. Minimum 16 chars. Rotating it invalidates every session **and** every ERP API key at once. |
| `PORT` | No | `3000` | Listen port |
| `NODE_ENV` | No | `production` (baked into the image) | Anything other than the exact string `production` opens the legacy demo surface, disables the CORS allowlist, and allows plain-`http://` partner webhook URLs. `render.yaml` overrides it to `alpha` / `beta` on those environments, which is how they end up wide open. See C5. |
| `PERSISTENCE` | No | in-memory | `DB` switches to Postgres via Prisma |
| `DATA_FILE` | No | `./data/store.json` | Path to the JSON snapshot when not using `DB`. The default is **relative to the container's working directory**, so an unset value writes into the ephemeral image layer and the store is destroyed on every deploy. Always set it to a path on a mounted disk. See PR #102 in `docs/IMPROVEMENTS.md`. |
| `DATABASE_URL` | With `PERSISTENCE=DB` | none | Postgres connection string |
| `OTP_DEBUG` | No | off | `1` returns the OTP in the API response. Never set in production. |
| `OTP_FIXED_CODE` | No | `123456` | The code used when `OTP_DEBUG=1` |
| `OTP_TTL_MS` | No | 10 minutes | OTP validity window |
| `SESSION_TTL_MS` | No | 30 days | Bearer token lifetime |
| `ENABLE_LEGACY_DEMO_SURFACE` | No | off | `1` re-enables unauthenticated demo and admin routes in production |
| `ALLOW_X_USER_ID` | No | off | **Debug only.** `1` accepts an `x-user-id` header as identity with no token. This is a complete authentication bypass across every authenticated route and it is *not* gated on `NODE_ENV`. Never set it anywhere reachable. |
| `CUSTOMER_WEB_BASE_URL` | No | `https://navig8r-customer.onrender.com` | Base for tracking URLs sent to ERP partners. `render.yaml` sets it on no environment, so unless it is set in the Render dashboard — which `docs/RENDER.md` tells the operator to do by hand — every environment falls back to this one host. Which of the two any deployed environment uses is not visible from this repository, though the value `docs/RENDER.md` prescribes is this same host. If the fallback is what is running, alpha and beta send partners links to a host that is neither of their own portals (`navig8r-customer-web-alpha.onrender.com`, `navig8r-customer-web-beta.onrender.com`) nor the production portal service declared in `render.yaml`, `navig8r-customer-web-image.onrender.com`. See `docs/IMPROVEMENTS.md`. |
| `PHASE_A_MAX_PICKUP_KM` | No | `15` | Max distance from a trip's origin to an acceptable pickup |
| `PHASE_A_MAX_DROP_KM` | No | `15` | Max distance from a trip's destination to an acceptable drop |
| `CORS_ALLOWED_ORIGINS` | For browser clients | reflects origin outside production | Comma-separated allowlist; `*` supported |
| `PAYMENT_PROVIDER` | No | `MOCK` | `RAZORPAY` enables real test-mode charging of customers |
| `RAZORPAY_KEY_ID` / `RAZORPAY_KEY_SECRET` | With Razorpay | none | Razorpay API credentials |
| `RAZORPAY_WEBHOOK_SECRET` | With Razorpay | none | Verifies `x-razorpay-signature` |
| `PAYOUTS_MODE` | No | `BOOKKEEPING` | `RAZORPAYX` makes real carrier disbursements. Independent of `PAYMENT_PROVIDER`. |
| `RAZORPAYX_ACCOUNT_NUMBER` | With RazorpayX | none | Source account for payouts |
| `RAZORPAYX_PAYOUT_MODE` | No | `IMPS` | `IMPS` / `NEFT` / `RTGS` / `UPI` |
| `FREIGHT_PAISE_PER_KM_SMALL` / `_MEDIUM` / `_LARGE` | No | 1500 / 2000 / 2500 | Per-km rate override by vehicle class |
| `FREIGHT_MIN_GROSS_PAISE` | No | `0` (no floor) | Minimum charge when distance is priced |
| `OPS_ADMIN_PHONES` | No | none | Comma-separated bootstrap list; materialized into the DB on first login |
| `RELEASE_SHA` | No | `unknown` | Baked into the image by the release pipeline and reported by `GET /health`. The smoke tests assert it matches the commit they deployed. |

The two static services read their own variables at container start, not build time:
`API_UPSTREAM` and `MAPS_API_KEY` for customer-web, `PORTAL_URL` and `VITE_TURNSTILE_SITE_KEY`
for www. They take two different routes. `API_UPSTREAM` is substituted into the nginx
`proxy_pass` directive and never reaches the browser. The other three are written into a
generated `runtime-config.js` that sets one global, `window.__NAVI8R_CONFIG__`, loaded by the
page before the app bundle; `MAPS_API_KEY` is additionally substituted over the
`__MAPS_API_KEY__` placeholder in customer-web's `index.html`. The two customer-web variables
are not optional — `docker/customer-web/entrypoint.sh` lines 4-5 guard them with
`: "${VAR:?...}"` under `set -eu`, so the entrypoint exits non-zero if either is unset. The www
entrypoint defaults both of its values to the empty string instead.

`PAYMENT_PROVIDER` governs charging the **customer**. `PAYOUTS_MODE` governs paying the
**carrier**. They are independent and are a common source of confusion.

## Deployment

Merging to `main` does not deploy. It starts a pipeline
(`.github/workflows/release.yml`) that builds three images once and promotes the **same digests**
through three environments:

```
merge -> npm test -> build 3 images (GHCR, tagged by commit SHA)
      -> alpha   + integration test (real OTP login)
      -> beta    + smoke test (/health only)
      -> manual approval
      -> production
```

Render pulls tagged images from GHCR; it no longer builds from Git.

| Environment | API | Payments | Payouts | Purpose |
|---|---|---|---|---|
| alpha | `navig8r-api-alpha` | mock | bookkeeping | Automated integration tests |
| beta | `navig8r-api-beta` | Razorpay test | bookkeeping | UAT |
| production | `navig8r-api` | Razorpay live | RazorpayX | Live |

Each API service mounts a 1 GB disk at `/data` and sets `DATA_FILE=/data/store.json`.

**Two things to know before you rely on this.** Alpha and beta are public hostnames and, because
`NODE_ENV` is set to the environment name, they do **not** enforce the production guards — the
unauthenticated `/v1/users` dump is reachable on both. And production's customer-web and www are
still the older static services; `render.yaml` carries `-image` variants as migration targets that
have not been cut over. The first is written up in [`docs/IMPROVEMENTS.md`](docs/IMPROVEMENTS.md) as
C5; the second is described in the header comment of `render.yaml`.

Secrets are marked `sync: false` and set in the Render dashboard, never committed. See
`docs/RENDER.md` for the runbook and `docs/DEPLOY.md` for hosting notes.

## Documentation

| Document | What it answers |
|---|---|
| [`docs/CODEBASE_MAP.md`](docs/CODEBASE_MAP.md) | Where does everything live, and how do I change it? Start here. |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | How is the system built, and why this way? |
| [`docs/IMPROVEMENTS.md`](docs/IMPROVEMENTS.md) | What should we fix, in what order? |
| [`docs/pilot-api.md`](docs/pilot-api.md) | Full REST reference for the pilot apps |
| [`docs/erp-integration.md`](docs/erp-integration.md) | Shipper ERP integration contract |
| [`docs/RENDER.md`](docs/RENDER.md) | Deploying the API to Render |
| [`docs/DEPLOY.md`](docs/DEPLOY.md) | Hosting notes |
| [`docs/android-option-a-apk-pilot.md`](docs/android-option-a-apk-pilot.md) | Building and distributing the signed APK |
| [`docs/MARKETING_SITE.md`](docs/MARKETING_SITE.md) | Marketing site and custom domains |
| [`ROADMAP.md`](ROADMAP.md) | The execution checklist |

## Contributing

`main` is the release branch — merging to it starts the pipeline that ends in production. Never
push to it directly.

1. Branch from `main` using the existing prefixes: `feature/`, `fix/`, or `docs/`.
2. Keep the change scoped to one concern.
3. Run the test suite before opening the PR.
4. Open a pull request into `main` and request review. Squash-merge; the merge commit
   convention is a sentence plus `(#NN)`.
5. Update the documentation in the same PR as the change it describes. A wrong map is worse
   than no map, because it gets trusted.

**The test suite does not run on your PR.** `.github/workflows/release.yml` triggers on
`push: main` and `workflow_dispatch`, so the suite runs after the merge, not before it.
`docker-image.yml` and `docker-publish.yml` do run on pull requests, but they only build the
API Docker image. Run `npm test` yourself — a red merge stops the release
pipeline at the build step and leaves `main` broken. Adding a `pull_request:` trigger and a
required status check is a four-line change; see M5 in `docs/IMPROVEMENTS.md`.
