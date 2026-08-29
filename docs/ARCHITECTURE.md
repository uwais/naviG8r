# naviG8r architecture

How the system is put together, and why it is shaped this way.

**On sourcing.** Where a rationale is stated in the code or the existing docs, it is quoted or
cited. Where it is not, it is marked *inferred* — a reading of the code, not a claim about what
anyone intended. Correct anything marked inferred if you know better; that is why it is labelled.

Verified against commit `0fc4ad0`.

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

Three services deploy from `main` to Render (Singapore): the API as a Docker web service, and
two static sites (customer web, marketing).

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
  layer, so a policy change means editing every call site. `requireUserId` appears ~20 times.
- **Route discovery requires reading 1,600 lines.** There is no route table to print.

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
| **In-memory + JSON file** (default) | `DATA_FILE` set, `PERSISTENCE` unset | `persistence.ts` — full snapshot written to a temp file then renamed |
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

The deployed blueprint (`render.yaml`) sets `DATA_FILE` and does not set `PERSISTENCE=DB`, so
production runs the file store today — despite `ROADMAP.md` stating Postgres is live. Note that
the blueprint is not the last word: a variable added in the Render dashboard would not appear
here. `GET /health` settles it empirically, since it reports the mode the process is actually
running in (`httpServer.ts:378-384`):

```
curl -s https://navig8r.onrender.com/health
# {"ok":true,"persistence":"file"|"db","paymentProvider":"mock"|"razorpay"}
```

Run that before trusting either this document or the roadmap on the question.

---

## 4. Domain model

### Entities

| Entity | Notes |
|---|---|
| `Organization` | The unit of ownership. `kind` is `CARRIER_SOLO`, `CARRIER_FLEET`, `CUSTOMER`, `CARRIER_LEGACY`, or the singleton `PLATFORM` |
| `User` | A person, identified by a 10-digit Indian mobile number |
| `Membership` | Joins a user to an org with a role. Keyed `${userId}:${orgId}` |
| `Vehicle`, `DriverProfile` | Carrier-side detail; one profile per user in the pilot |
| `AnchorTrip` | Published capacity: route, window, vehicle class, `capacityKg`, `reservedKg` |
| `Shipment` | One booking against a trip |
| `Payment` | The customer-side charge |
| `LedgerLine` | The carrier-side earning |
| `PayoutBatch` | A settlement run |
| `IntegrationConnection`, `IntegrationApiKey`, `IntegrationEvent`, `IntegrationWebhookDelivery` | ERP subsystem |
| `Carrier` | **Deprecated.** Marked legacy in `types.ts:30`; superseded by `Organization` |

Roles: `OWNER_DRIVER`, `OWNER`, `DISPATCHER`, `DRIVER`, `CUSTOMER_ADMIN`, `CUSTOMER_MEMBER`,
`OPS_ADMIN`, `OPS_AGENT`.

### State machines

```
AnchorTrip:   OPEN ──> FULL ──> IN_PROGRESS ──> COMPLETED
                 └───────────────┘
              (FULL when reservedKg meets capacityKg)

Shipment:     PENDING_CARRIER_ACCEPT ──> BOOKED ──> PENDING_RELEASE ──> DELIVERED
                                            └──> FAILED_CARRIER_REFUNDED

Payment:      CREATED ──> AUTHORIZED ──> CAPTURED
                 └──> FAILED      └──> REFUNDED

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

*Stated rationale, from the README:* "authorize at checkout, capture at POD". *Inferred:* it
means a customer is never charged for freight that did not arrive, and the platform is not
holding customer money it may have to refund.

### Units and rounding

Everything is integer **paise**. `moneySplit` (`services.ts:138`) computes
`commission = Math.floor(gross * 1000 / 10000)` and gives the carrier the remainder — so
sub-paise rounding always favours the carrier, never the platform. That is a defensible default
and worth keeping deliberate.

### Two independent switches

`PAYMENT_PROVIDER` governs charging the customer (`MOCK` or `RAZORPAY`). `PAYOUTS_MODE` governs
paying the carrier (`BOOKKEEPING` or `RAZORPAYX`). They are unrelated and either can be enabled
without the other. Under `BOOKKEEPING`, ledger lines flip `ACCRUED → PAID` and a transfer record
is written, but **no money leaves the account** — this is the current production setting.

### The payout schedule

`packages/core/src/payoutSchedule.ts` is the cleanest file in the repo and deserves its
isolation. The rule: POD's IST calendar date, plus 7 calendar days, at IST midnight; then the
next weekly cutoff (Wednesday 18:00 IST) at or after that instant.

It uses a fixed `+05:30` offset rather than a timezone library. This is **correct, not a
shortcut** — India has never observed DST, which the file states explicitly and the tests cover
(month overflow, same-week vs next-week cutoff). Do not "fix" this by adding a tz dependency.

---

## 6. Authentication

### People: OTP then HMAC bearer token

1. `POST /v1/auth/otp/start` with a phone number creates a challenge with a 6-digit code and a
   10-minute TTL.
2. `POST /v1/auth/otp/verify` consumes the challenge and issues a token.
3. The token is `base64url(JSON payload).base64url(HMAC-SHA256(payload, AUTH_SECRET))`, holding
   `{v, sid, uid, exp}` with a 30-day default lifetime.

Verification checks the HMAC with `crypto.timingSafeEqual` after a length check, then looks the
session up in the store and re-checks expiry and revocation.

The server-side session lookup is the good part of this design: unlike a stateless JWT, a token
*can* be invalidated before it expires. **But nothing uses it.** `revokedAtUtcMs` is initialised
to `null` (`auth.ts:145`) and read on every verify (`auth.ts:158`), and no code path anywhere
ever sets it. There is no logout endpoint and no revoke endpoint. In practice a leaked token is
valid for its full 30-day lifetime with no way to kill it short of rotating `AUTH_SECRET`, which
also breaks every ERP partner key. The mechanism is built; the door is missing.

*Inferred rationale for rolling this rather than using a JWT library:* one fewer dependency for
a token format that never leaves this system.

Two gaps, both acknowledged in the code (`types.ts:85` — "mock SMS. Replace with real SMS + rate
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
token at all (`httpServer.ts:284`). It is off by default and not set in `render.yaml`, but it is
**not** gated on `NODE_ENV`, unlike the legacy demo surface right beside it. Given it fronts
~20 authenticated routes including ops-admin ones, it should carry the same production guard.

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

Sessions live in `driver_session.dart` and `customer_session.dart` as `Listenable`s wired to
`GoRouter`'s `refreshListenable`, so auth changes drive redirects. Tokens are held in
`flutter_secure_storage` and injected by a Dio interceptor. State is otherwise `setState` — no
state management library. At this size that is a reasonable choice, though the three
2,000-line screen files are where it starts to hurt.

Live tracking: the driver posts a location at most every 30s
(`driver_flow.dart:1451`); the server treats a ping as "live" for 15 minutes
(`TRIP_TRACKING_STALE_MS`); ERP location webhooks are throttled to one per 5 minutes.

---

## 9. Known architectural risks

Ordered by consequence. Detail and suggested fixes are in `docs/IMPROVEMENTS.md`.

| Risk | Why it matters |
|---|---|
| DB mode drops the ERP subsystem | Blocks the roadmap's own Postgres migration |
| No SMS delivery or OTP rate limiting | Blocks onboarding a single real pilot user |
| `ALLOW_X_USER_ID` has no production guard | One env var from total account takeover |
| Unescaped org name in the ops portal | Stored XSS against operators (open PR #87) |
| Two unguarded in-process timers | The API cannot be scaled horizontally |
| No CI | Nothing enforces the 53 passing tests |
| `services.ts` and `httpServer.ts` hold many concerns | Every change touches a 1,600–1,900 line file |
| Doc and deployment disagree on persistence | Reasoning about production from docs misleads |
