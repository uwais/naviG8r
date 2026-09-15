# naviG8r architecture

How the system is put together, and why it is shaped this way.

**On sourcing.** Where a rationale is stated in the code or the existing docs, it is quoted or
cited. Where it is not, it is marked *inferred* — a reading of the code, not a claim about what
anyone intended. Correct anything marked inferred if you know better; that is why it is labelled.

Verified against commit `f96ccf9`.

---

## 1. System context

```
   ┌────────────────┐        ┌──────────────────┐        ┌──────────────────┐
   │  Shipper ERP   │        │  Customer (web)  │        │ Carrier / Driver │
   │  (machine)     │        │  Flutter web     │        │ Flutter Android  │
   └───────┬────────┘        └────────┬─────────┘        └────────┬─────────┘
           │ x-api-key                │ Bearer (OTP)              │ Bearer (OTP)
           │ POST /v1/integrations/*  │                           │
           └──────────────┬───────────┴───────────────────────────┘
                          │  HTTPS / JSON
                 ┌────────▼─────────────────────────────────┐
                 │  navig8r-api  (single Node 22 process)   │
                 │                                          │
                 │  httpServer.ts  -> services.ts           │
                 │       │              │                   │
                 │       │              └── packages/core   │
                 │       │                  (payout dates)  │
                 │  ┌────▼──────────────────────────┐       │
                 │  │ Store: 18 in-memory Maps      │       │
                 │  └────┬──────────────────┬───────┘       │
                 │       │ file mode        │ DB mode       │
                 │  ┌────▼─────┐      ┌─────▼──────┐        │
                 │  │store.json│      │  Postgres  │        │
                 │  │ (1GB disk)│     │  (Prisma)  │        │
                 │  └──────────┘      └────────────┘        │
                 │                                          │
                 │  timers: payout batch 60s,               │
                 │          webhook delivery 30s            │
                 └───────┬──────────────────────┬───────────┘
                         │                      │
                  ┌──────▼──────┐        ┌──────▼─────────┐
                  │  Razorpay   │        │  Partner ERP   │
                  │  RazorpayX  │        │  webhook URL   │
                  └─────────────┘        └────────────────┘
                  charge customer,        signed outbound
                  pay carrier             lifecycle events
```

Three services run on Render (Singapore) — the API, the customer web portal, and the marketing
site — and each exists three times over, once per environment (alpha, beta, production).

### Why the release model changed

Until 2026-09 Render built each service from `main` on push: the API from a Dockerfile, the other
two as static sites from a build script. That is gone. All nine services are now `runtime: image`,
pulling tagged images from GHCR, and GitHub Actions owns the pipeline.

*Rationale stated in `render.yaml`:* "The release identity is the exact image digest." A build
per environment means three different artifacts and no guarantee that what passed UAT is what
went live. Building once and promoting the same digest through alpha, beta and production makes
the thing you tested and the thing you shipped provably identical. `RELEASE_SHA` is baked into
the image at build time and echoed by `GET /health`, so every gate can assert it is talking to
the build it thinks it is — that is what `scripts/alpha-integration.mjs` and `beta-smoke.mjs`
check first.

**What was given up.** Four things, and they are not small:

- **A hotfix now takes the full pipeline.** There is no way to push a one-line fix straight to
  production; it builds, deploys to alpha, runs integration tests, deploys to beta, waits for a
  human, then deploys. Rolling back is faster than rolling forward — re-point the environment tag
  at an earlier digest with `scripts/promote-image-tag.sh`.
- **Three times the Render surface to keep in sync.** Nine services, three sets of environment
  variables. The `OTP_DEBUG` drift that caused PR #100, and the `DATA_FILE` drift behind #102,
  are now three times as likely.
- **`NODE_ENV` stopped being a boolean.** Setting it to the environment name silently disabled
  three production guards on alpha and beta. See C5 — this is the clearest cost of the change and
  it was almost certainly not intended.
- **The static services cannot be converted in place.** `render.yaml` carries
  `navig8r-customer-web-image` and `navig8r-www-image` as parallel migration targets, so
  production is mid-cutover: the API is image-backed, the two front ends are not yet. C7 has
  already fired, in the opposite direction — since `f96ccf9` the image path resolves the Maps key
  at runtime and the static build is the one that has lost it. See C7.

*Inferred rationale for the manual approval gate on production only:* alpha and beta are
recoverable, production moves real money.

---

## 2. The shape of the backend

### One process, no build step

The API is a single Node process that executes TypeScript directly via
`node --experimental-strip-types`. There is no bundler, no `tsc` build output, and no dev-server
layer. `tsconfig.json` sets `noEmit: true` — it exists for type checking only.

*Inferred rationale:* it removes an entire build stage from every deploy and every local run, at
the cost of pinning the project to Node 22.6+. For a pilot-stage codebase run by two or three
people that trade looks reasonable. The cost is real though, and it is not written down anywhere
a newcomer will see it — see gotcha 1 in `docs/CODEBASE_MAP.md`.

### A hand-rolled router, not a framework

`httpServer.ts` is a `node:http` request handler containing a long if-chain over
`url.pathname`. There is no Express, Fastify, or Hono.

What this buys: zero framework dependencies, and the whole request path is readable in one file.

What it costs, concretely:

- **Route order is load-bearing.** A broad `startsWith` above a specific match shadows it
  silently.
- **Every route repeats its own auth, body parsing and error handling.** There is no middleware
  layer, so a policy change means editing every call site. `requireUserId` is called at 23 separate call sites.
- **Route discovery requires reading 1,695 lines.** There is no route table to print.

*Inferred:* this was the right call at 10 routes and is now carrying about 50. It is the leading
candidate for the first structural refactor — see `docs/IMPROVEMENTS.md`.

### Two background timers

`index.ts` starts two `setInterval` loops in-process:

| Timer | Period | Does |
|---|---|---|
| Payout batch runner | 60s | `runPayoutBatch` — sweeps eligible ledger lines into a batch |
| Webhook delivery runner | 30s | `processPendingWebhookDeliveries` — drains the outbox |

There is no external scheduler or queue. *Inferred rationale:* one process, one deployable, no
extra infrastructure to pay for or operate at pilot scale.

**The architectural constraint this creates is that the API cannot be scaled horizontally as
written.** Both timers run in every instance, neither has a re-entrancy guard, and both mutate
shared state. Two instances means two payout runners racing on the same ledger. This is worth
knowing *before* someone raises the Render instance count to handle load.

---

## 3. Persistence: two implementations of one interface

The store is 18 in-memory `Map`s (`store.ts`). Everything reads and writes those Maps
synchronously; persistence is a load at boot and a save after each write.

| Mode | Trigger | Implementation |
|---|---|---|
| **In-memory + JSON file** (default) | `PERSISTENCE` is anything other than the exact string `DB`. `DATA_FILE` is optional and falls back to `./data/store.json` | `persistence.ts` — full snapshot written to a temp file then renamed |
| **Postgres** | `PERSISTENCE=DB` + `DATABASE_URL` | `persistenceDb.ts` — Prisma, 13 models |

The JSON writer is correctly atomic: `writeFileSync` to `${path}.tmp` then `renameSync`
(`persistence.ts:231-233`). The format is versioned V1 through V4 with forward migrations, so
older snapshots still load.

*Inferred rationale:* "everything in memory, snapshot to disk" is the simplest thing that
survives a restart, and at pilot volumes (tens of shipments) a full serialize per write costs
nothing measurable.

**Where it stops working.** Every write serializes the entire store synchronously, blocking the
event loop. That is a scale ceiling, not a bug — but it is an undocumented one.

### The divergence that matters

The two implementations are not equivalent. `persistence.ts` handles all 18 collections;
`persistenceDb.ts` handles 13. The five it omits are exactly the ERP integration subsystem:
`integrationConnections`, `integrationApiKeys`, `integrationIdempotency`, `integrationEvents`,
`integrationWebhookDeliveries`.

This means **`PERSISTENCE=DB` silently discards the entire ERP feature on every restart.** No
error, no warning. Since roadmap section A is about moving to Postgres and section D shipped the
ERP integration, these two workstreams currently contradict each other. This is the highest-value
thing to fix in the codebase.

The deployed blueprint (`render.yaml`) sets `DATA_FILE` on all three environments and sets
`PERSISTENCE=DB` on none of them, so every environment runs the file store today — despite
`ROADMAP.md:27` marking "Hosted pilot API + Postgres: `PERSISTENCE=DB` + `DATABASE_URL` on Render"
as done. Note that
the blueprint is not the last word: a variable added in the Render dashboard would not appear
here. `GET /health` settles it empirically, since it reports the mode the process is actually
running in (`httpServer.ts:380-387`):

```
curl -s https://navig8r.onrender.com/health
# {"ok":true,"persistence":"file"|"db","paymentProvider":"mock"|"razorpay","release":"<RELEASE_SHA, or unknown>"}
```

Run that before trusting either this document or the roadmap on the question.

---

## 4. Domain model

### Entities

| Entity | Notes |
|---|---|
| `Organization` | The unit of ownership. `kind` is `CARRIER_SOLO`, `CARRIER_FLEET`, `CUSTOMER`, `CARRIER_LEGACY`, or the singleton `PLATFORM` |
| `User` | A person, identified by a 10-digit Indian mobile number |
| `OtpChallenge` | A login code from the mock SMS flow. `PENDING`, `CONSUMED` or `EXPIRED` |
| `AuthSession` | A bearer session for a user, with `expiresAtUtcMs` and `revokedAtUtcMs` |
| `Membership` | Joins a user to an org with a role. Keyed `${userId}:${orgId}` |
| `Vehicle`, `DriverProfile` | Carrier-side detail; one profile per user in the pilot |
| `AnchorTrip` | Published capacity: route, window, vehicle class, `capacityKg`, `reservedKg` |
| `Shipment` | One booking against a trip |
| `Payment` | The customer-side charge |
| `LedgerLine` | The carrier-side earning |
| `PayoutBatch` | A settlement run |
| `IntegrationConnection`, `IntegrationApiKey`, `IntegrationIdempotencyRecord`, `IntegrationEvent`, `IntegrationWebhookDelivery` | ERP subsystem |
| `Carrier` | **Deprecated.** Marked `@deprecated` at `types.ts:37`; superseded by `Organization` |

Roles: `OWNER_DRIVER`, `OWNER`, `DISPATCHER`, `DRIVER`, `CUSTOMER_ADMIN`, `CUSTOMER_MEMBER`,
`OPS_ADMIN`, `OPS_AGENT`.

### State machines

```
AnchorTrip:   OPEN ──> FULL ──> IN_PROGRESS ──> COMPLETED
                 └───────────────┘
              (FULL when reservedKg meets capacityKg)

Shipment:     PENDING_CARRIER_ACCEPT ──> BOOKED ──> PENDING_RELEASE ──> DELIVERED
                        └───────────────────┴──> FAILED_CARRIER_REFUNDED

Payment:      CREATED ──> AUTHORIZED ──> CAPTURED
              (RAZORPAY only; a MOCK payment is created directly in CAPTURED)
              FAILED:   from CREATED or AUTHORIZED, via the razorpay payment.failed webhook
              REFUNDED: from CAPTURED only for MOCK; from CREATED, AUTHORIZED,
                        CAPTURED or FAILED for RAZORPAY

LedgerLine:   ACCRUED ──> PAID
```

The shipment and payment machines are deliberately coupled: `BOOKED` corresponds to
`AUTHORIZED`, and the transition to `PENDING_RELEASE` (POD submitted) is what permits `CAPTURED`.

---

## 5. Money

**The ordering is the design.** Booking authorizes but does not capture. Capture happens at
proof of delivery. Carrier payout happens on a published schedule after that.

```
  book          POD              ops release        POD+7d, next Wed 18:00 IST
   │             │                    │                       │
   ▼             ▼                    ▼                       ▼
AUTHORIZE ──> capture allowed ──> CAPTURED ──> ledger ACCRUED ──> PAID
(customer                         (customer     (carrier          (batch)
 committed,                        charged)      earns)
 not charged)
```

*Stated rationale, from `docs/pilot-api.md`:* "authorize at checkout, capture at POD". *Inferred:* it
means a customer is never charged for freight that did not arrive, and the platform is not
holding customer money it may have to refund.

### Units and rounding

Everything is integer **paise**. `moneySplit` (`services.ts:141`) computes
`commission = Math.floor(gross * 1000 / 10000)` and gives the carrier the remainder — so
sub-paise rounding always favours the carrier, never the platform. That is a defensible default
and worth keeping deliberate.

### Two independent switches

`PAYMENT_PROVIDER` governs charging the customer (`MOCK` or `RAZORPAY`). `PAYOUTS_MODE` governs
paying the carrier (`BOOKKEEPING` or `RAZORPAYX`). They are unrelated and either can be enabled
without the other. Under `BOOKKEEPING`, ledger lines flip `ACCRUED → PAID` and a transfer record
is written, but **no money leaves the account** — this is the alpha and beta setting. Production
declares `PAYOUTS_MODE=RAZORPAYX` (`render.yaml:233-234`), the setting under which `runPayoutBatch` (`services.ts:2160`) calls the live RazorpayX payouts API (`razorpayPayouts.ts:79`). Whether money actually moves is not something this repository can show. The credentials are all `sync: false` (`render.yaml:239-246`), so they come from the Render dashboard and may be test keys or absent entirely; carriers with no fund account are skipped and their lines left `ACCRUED` (`services.ts:2212-2214`); and a batch only runs when an Ops Admin calls `POST /payout-batches/run`.

### The payout schedule

`packages/core/src/payoutSchedule.ts` is the cleanest file in the repo and deserves its
isolation. The rule: POD's IST calendar date, plus 7 calendar days, at IST midnight; then the
next weekly cutoff (Wednesday 18:00 IST) at or after that instant.

It uses a fixed `+05:30` offset rather than a timezone library. This is **correct, not a
shortcut** — IST has no DST, which the file states explicitly (`payoutSchedule.ts:7`) and the tests cover
(month overflow, same-week vs next-week cutoff). Do not "fix" this by adding a tz dependency.

---

## 6. Authentication

### People: OTP then HMAC bearer token

1. `POST /v1/auth/otp/start` with a phone number creates a challenge with a 6-digit code and a
   10-minute TTL.
2. `POST /v1/auth/otp/verify` consumes the challenge and issues a token.
3. The token is `<payloadB64>.<sigB64>`, where `payloadB64` is the base64url JSON payload and
   `sigB64` is `base64url(HMAC-SHA256(payloadB64, AUTH_SECRET))` — the MAC covers the encoded
   string, not the raw JSON (`auth.ts:46`). The payload holds `{v, sid, uid, exp}` with a
   30-day default lifetime.

Verification checks the HMAC with `crypto.timingSafeEqual` after a length check, then looks the
session up in the store and re-checks expiry and revocation.

The server-side session lookup is the good part of this design: unlike a stateless JWT, a token
*can* be invalidated before it expires. As of the ops soft-delete work, one thing finally uses it.
`revokedAtUtcMs` is initialised to `null` (`auth.ts:148`), read on every verify (`auth.ts:161`),
and set in exactly one place — `opsDeleteUser` (`services.ts:714`), which revokes every session
belonging to a user it deactivates. `verifyBearer` also rejects a session whose user is tombstoned
(`auth.ts:165`), so revocation holds even if a session row were missed.

That leaves the mechanism working but reachable through a single, very blunt door. There is still
no logout endpoint, and no way to revoke one session: signing a driver out means deactivating their
account, which cascades a tombstone across their org, vehicles, trips, shipments and ledger lines,
and cannot be undone through the API. See H4 in `docs/IMPROVEMENTS.md`.

*Inferred rationale for rolling this rather than using a JWT library:* one fewer dependency for
a token format that never leaves this system.

Two gaps, both acknowledged in the code (`types.ts:91` — "mock SMS. Replace with real SMS + rate
limits in production"):

- **No SMS provider.** Codes are generated and never delivered.
- **No rate limiting** on OTP start or verify. A 6-digit code with a 10-minute window and
  unlimited attempts is brute-forceable.

### Machines: prefixed API keys

ERP clients present `nvg8r_<keyId>_<secret>` as a bearer token, or `x-api-key` plus
`x-api-secret`. The secret is stored only as `sha256(secret + ":" + AUTH_SECRET)`
(`integrationAuth.ts:16`) — never in plaintext. Keys carry scopes, checked by
`assertIntegrationScope`.

The coupling to `AUTH_SECRET` is the notable consequence: rotating it invalidates every session
*and* every partner key simultaneously.

### The bypass

`ALLOW_X_USER_ID=1` makes `requireUserId` accept an `x-user-id` header as identity with no
token at all (`httpServer.ts:285`). It is off by default and not set in `render.yaml`, but it is
**not** gated on `NODE_ENV`, unlike the legacy demo surface right beside it. Given it fronts
23 authenticated call sites including ops-admin ones, it should carry the same production guard.

---

## 7. ERP integration

The design is a conventional and well-chosen one for this problem.

**Inbound.** `POST /v1/integrations/loads` takes an external load, applies idempotency so a
retrying ERP cannot double-book, and auto-matches it to an open anchor trip on the same lane.

**Outbound.** Lifecycle events are written to an outbox (`IntegrationWebhookDelivery`) rather
than delivered inline. A timer drains it with exponential backoff (1m, 5m, 30m, 2h, 24h; 10
attempts, then `DEAD`). Payloads are signed HMAC-SHA256 into `x-navig8r-signature`.

Choosing an outbox over inline HTTP is the right call — it keeps a slow partner endpoint from
blocking a booking, and makes delivery recoverable. `GET /v1/integrations/events` exists for
partners to reconcile anything they missed.

Three gaps in an otherwise sound design:

- **No replay protection.** The signature covers the body but not a timestamp, so a captured
  delivery can be replayed forever. The convention elsewhere (Stripe, Svix) is to sign
  `timestamp.body` and have the receiver reject stale timestamps.
- **No SSRF guard.** `webhookUrl` is only checked for an `https://` prefix in production. A
  partner can point it at a private address and have the API fetch it.
- **Sequential delivery.** The drain loop awaits each POST with a 30s timeout, in a 30s timer
  with no re-entrancy guard.

---

## 8. The Flutter app: one binary, three personas

`apps/driver_pilot` builds both the Android driver APK and the customer web portal.
`main.dart` picks the shell with `kIsWeb`: web starts at `/customer`, mobile at `/driver`.
Routing is `go_router`, with each persona contributing its own route list
(`driverFlowRoutes()`, `customerFlowRoutes()`).

*Inferred rationale:* the API client, models, auth handling and theme are shared, so one
codebase avoids maintaining two. The cost is that the customer web bundle ships the driver
code and vice versa, and that a change to shared plumbing must be regression-tested on both.

Platform-specific behaviour is handled with Dart conditional imports rather than runtime
branching — `customer_checkout.dart` resolves to `_web` or `_mobile`, and `pilot_api_dns.dart`
likewise. This is idiomatic Dart and the right mechanism.
`maps_config.dart` is the third instance, and the one worth knowing about, because the two sides
get the key from different places. It resolves to `maps_config_native.dart`, whose `kMapsApiKey`
is a compile-time `String.fromEnvironment("MAPS_API_KEY")` (`maps_config_native.dart:5-8`), or to
`maps_config_web.dart`, whose `kMapsApiKey` is a getter reading
`window.__NAVI8R_CONFIG__.MAPS_API_KEY` at runtime (`maps_config_web.dart:4-24`).
`docker/customer-web/entrypoint.sh:16-20` writes that global into `runtime-config.js` when the
container starts, and `web/index.html:22` loads it ahead of `flutter_bootstrap.js`. Before
`f96ccf9` the Dart key was compile-time only, so only the Maps JavaScript `<script>` tag — which
the same entrypoint already patched with `sed` (`entrypoint.sh:12-13`) — could vary per
environment. The geocoding key the Dart code uses now varies with it, off the same promoted image.


Sessions live in `driver_session.dart` and `customer_session.dart`. Only `CustomerSession` exposes
a `Listenable` (`customer_session.dart:8`), and it is the only thing wired to `GoRouter`'s
`refreshListenable` (`main.dart:78`); its real consumer is the `ListenableBuilder` around the
customer shell in `CustomerScaffold` (`customer_flow.dart:86`), because none of the three
`redirect:` callbacks in the app (`customer_flow.dart:39`, `main.dart:83`, `main.dart:87`) reads
session state — they branch on a constant, on `kIsWeb`, and on a query parameter. `DriverSession`
is a static holder with no notification mechanism (`driver_session.dart:4`). Tokens are held in

`flutter_secure_storage` and injected by a Dio interceptor. State is otherwise `setState` — no
state management library. At this size that is a reasonable choice, though the two screen files
over 2,000 lines — `driver_flow.dart` (2,305) and `customer_flow.dart` (2,149) — are where it
starts to hurt.

Live tracking: the driver posts a location at most every 30s
(`driver_flow.dart:1535`); the server treats a ping as "live" for 15 minutes
(`TRIP_TRACKING_STALE_MS`); ERP location webhooks are throttled to one per 5 minutes.

---

## 9. Known architectural risks

Ordered by consequence. Detail and suggested fixes are in `docs/IMPROVEMENTS.md`.

| Risk | Why it matters |
|---|---|
| `NODE_ENV` is both a label and a security switch | Alpha and beta serve an unauthenticated user dump (C5) |
| The file store's default path is inside the container | A missing `DATA_FILE` wipes the store every deploy (PR #102) |
| Soft-delete does not reach the marketplace | Tombstoned carriers' trips stay bookable (C6 / PR #106) |
| DB mode drops the ERP subsystem | Blocks the roadmap's own Postgres migration |
| No SMS delivery or OTP rate limiting | Blocks onboarding a single real pilot user |
| `ALLOW_X_USER_ID` has no production guard | One env var from total account takeover |
| Unescaped org name in the ops portal | Stored XSS against operators (open PR #87) |
| Two unguarded in-process timers | The API cannot be scaled horizontally |
| The test suite runs after the merge, not on the PR | Nothing stops a red commit reaching `main`. `docker-image.yml` does run on pull requests, but it only builds the API image — it never runs `npm test` |
| Nothing typechecks, and nothing runs Flutter | `strict: true` is decorative; 7,160 lines of Dart in `apps/driver_pilot/lib` unchecked |
| `services.ts` and `httpServer.ts` hold many concerns | Every change touches a 1,700–2,300 line file |
| Doc and deployment disagree on persistence | Reasoning about production from docs misleads |
