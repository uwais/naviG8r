# naviG8r codebase map

The document that lets someone who has never opened this repo find their way, change something,
and know whether it worked.

**What belongs in here:** anything a newcomer cannot work out in under five minutes by reading
the code — where things live, how to run them, the order of steps for a common change, and
traps that cost someone an afternoon. Not API reference (that is `docs/pilot-api.md`) and not
design rationale (that is `docs/ARCHITECTURE.md`).

Keep it current in the same commit as the change it describes. A wrong map is worse than none,
because it gets trusted.

Last verified against the tree at commit `0fc4ad0`.

---

## 1. Layout

### Top level

| Path | What lives here | Why |
|---|---|---|
| `apps/api/` | The entire backend — REST API, ops portal HTML, payments, payouts, ERP integration | One Node process; no build step, TypeScript is executed directly |
| `apps/driver_pilot/` | One Flutter app serving driver, carrier and customer personas | Ships as an Android APK and as the customer web portal from the same source |
| `apps/www/` | Public marketing site at navig8r.org | Separate stack (Vite) because it shares nothing with the product |
| `packages/core/` | Payout schedule arithmetic | Pure, dependency-free, heavily tested — kept apart so money math can be reasoned about alone |
| `integrations/adapters/generic/` | Reference doc for mapping a shipper ERP onto the API | No code; a contract description |
| `scripts/` | Render build scripts, Maps key injection, ERP smoke test | Called by Render, not by developers |
| `docs/` | All long-form documentation | See the index in `README.md` |
| `Dockerfile`, `render.yaml` | Deployment for all three services | `render.yaml` is the blueprint; the Dockerfile builds the API only |

### `apps/api/src/` — the backend

Roughly 8,600 lines including tests. Two files hold most of it.

| File | Lines | Responsibility |
|---|---|---|
| `services.ts` | 1936 | All domain logic: onboarding, trips, booking, pricing, POD, ledger, payouts, tracking. 64 exported symbols. **Holds many concerns — see the split proposal in `docs/IMPROVEMENTS.md`.** |
| `httpServer.ts` | 1602 | The whole HTTP surface. A hand-rolled `node:http` handler with an if-chain over `url.pathname`. Also contains ~420 lines of inline HTML/JS for the `/admin` and `/ops` portals. |
| `persistenceDb.ts` | 486 | Postgres load and save via Prisma. **Covers 13 of the store's 18 collections.** |
| `integrationServices.ts` | 436 | ERP connections, API keys, load intake, idempotency |
| `types.ts` | 337 | Every domain type and status union. Read this first. |
| `integrationWebhooks.ts` | 312 | Outbound webhook queue, signing, retry with backoff |
| `integrationHttp.ts` | 273 | The `/v1/integrations/*` routes |
| `persistence.ts` | 234 | JSON file load and save, with versioned migrations V1 to V4 |
| `auth.ts` | 162 | OTP challenge lifecycle and HMAC bearer tokens |
| `razorpayPayouts.ts` | 126 | RazorpayX contact, fund account, and payout creation |
| `integrationAuth.ts` | 102 | Integration key hashing, parsing, scope checks, webhook signing |
| `razorpayPayments.ts` | 94 | Razorpay order creation and capture |
| `razorpayWebhook.ts` | 89 | Inbound Razorpay signature verification |
| `store.ts` | 66 | The in-memory `Store` type — 18 `Map` collections |
| `index.ts` | 66 | Boot: load store, start server, start two background timers |
| `config.ts` | 44 | Commission, pricing constants, payout schedule, tracking staleness |
| `prisma/schema.prisma` | 158 | 13 Postgres models |
| `*.test.ts` | ~1900 | 15 test files, 47 tests |

### `apps/driver_pilot/lib/` — the Flutter app

Roughly 7,000 lines. Three files hold 78% of it.

| File | Lines | Responsibility |
|---|---|---|
| `driver_flow.dart` | 2221 | 18 driver and carrier screens plus the driver shell and route table |
| `customer_flow.dart` | 2149 | 11 customer screens, two private tab widgets, and the customer route table |
| `main.dart` | 1151 | App bootstrap and the `go_router` config — **plus a legacy "pilot lab" surface of 6 more screens that duplicates the driver flow** |
| `location_editor.dart` | 494 | Map-based address and coordinate picker |
| `pilot_api.dart` | 353 | Dio HTTP client, token storage, error formatting |
| `customer_layout.dart` | 132 | Responsive shell: navigation rail at ≥900px, bottom nav below |
| `customer_session.dart` | 109 | Customer auth state, drives router refresh |
| `google_geocoding.dart` | 97 | Address to coordinate lookup |
| `driver_theme.dart` | 75 | App theme (navy `#122C53`) |
| `driver_session.dart` | 72 | Driver auth state |
| `customer_checkout*.dart` | 119 | Razorpay checkout, split web/mobile by conditional import |
| `pilot_api_dns*.dart` | 31 | Platform-conditional DNS handling |

### `apps/www/` — the marketing site

| File | Lines | Responsibility |
|---|---|---|
| `src/styles.css` | 1265 | The entire design system and every page style |
| `src/main.js` | 434 | Nav behaviour, form handling, bot guards |
| `index.html` | — | The whole single-page site |
| `public/brand/` | — | Logo set in light, dark and monochrome variants |

---

## 2. Entry points

| What | Command | Result when it worked |
|---|---|---|
| **API** | `export AUTH_SECRET=$(openssl rand -hex 32)` then `node --experimental-strip-types apps/api/src/index.ts` from the repo root | Logs `API listening on 0.0.0.0:3000`; `curl localhost:3000/health` returns JSON naming the persistence mode and payment provider |
| **Tests** | `node --experimental-strip-types --test "packages/**/src/**/*.test.ts" "apps/**/src/**/*.test.ts"` | `pass 53`, `fail 0` |
| **Driver app** | `cd apps/driver_pilot && flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000` | App opens at `/driver` |
| **Customer web** | Same app with `flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:3000` | App opens at `/customer` — `kIsWeb` picks the shell |
| **Marketing site** | `cd apps/www && npm run dev` | Vite dev server |
| **Ops portal** | Browse to `http://localhost:3000/ops` | Login box; needs an ops-admin phone |
| **Legacy admin** | `http://localhost:3000/admin` | Full data dump. Requires `ENABLE_LEGACY_DEMO_SURFACE=1` in production |

Node **22 or newer is mandatory**. See gotcha 1.

---

## 3. Change recipes

### Add a new API endpoint

1. Write the domain function in `apps/api/src/services.ts`. It takes `store` as its first
   argument and throws `ApiError` for expected failures.
2. Add the route to the if-chain in `apps/api/src/httpServer.ts`. Match on
   `method === "GET" && url.pathname === "/v1/..."`. Order matters — the first match wins.
3. Decide the auth. `requireUserId(req, store)` for a logged-in user, then `assertOpsAgent`
   for ops-only. For public marketplace routes, also add the path to
   `publicMarketplaceRouteAllowed` (`httpServer.ts:297`) or it will 403 in production.
4. Call `await persist()` after any write, or the change is lost on restart.
5. Add a test in `apps/api/src/*.test.ts` following the existing pattern.
6. Document it in `docs/pilot-api.md`.

**Worked when:** the new test passes and `curl` against a locally running API returns what you
expect with and without a bearer token.

### Add a field to a domain entity

This one has four places and missing any of them fails silently.

1. `apps/api/src/types.ts` — add the field to the type.
2. `apps/api/src/persistence.ts` — make sure `dumpStore` and the `hydrateStoreV4` path carry
   it. If the shape changed incompatibly, add a V5 and a migration.
3. `apps/api/src/persistenceDb.ts` — add it to both `loadStoreFromDatabase` and
   `saveStoreToDatabase`.
4. `apps/api/prisma/schema.prisma` — add the column, then `cd apps/api && npx prisma db push`.

**Worked when:** set the field, restart the API, and read it back — in *both* persistence
modes. Testing only the default file mode is how the DB path drifted in the first place.

### Add a screen to the customer app

1. Add the widget to `apps/driver_pilot/lib/customer_flow.dart`.
2. Register the route in `customerFlowRoutes()` in the same file.
3. Wrap the body in `CustomerScaffold` so it inherits the responsive shell.
4. If it needs API data, add the call to `apps/driver_pilot/lib/pilot_api.dart`.

**Worked when:** the route loads on both a narrow window (bottom nav) and a wide one (rail).

### Change freight pricing

1. Edit the constants in `apps/api/src/config.ts`, or the formula in
   `computeFreightGrossPaise` (`services.ts:1033`).
2. **Bump `FREIGHT_MODEL_VERSION`** in `config.ts`. It is returned on every quote so a past
   price can be explained later; changing the formula without bumping it makes old quotes
   unexplainable.
3. Update `apps/api/src/freight.test.ts`.

**Worked when:** `POST /shipments/quote` returns the new numbers and the new `modelVersion` in
the breakdown.

### Add an ERP webhook event

1. Emit it from the relevant lifecycle point in `services.ts`.
2. Add the event type and payload shape in `apps/api/src/integrationWebhooks.ts`.
3. Document it in `docs/erp-integration.md` and
   `integrations/adapters/generic/README.md`.

**Worked when:** `scripts/test-erp-integration.sh` still passes and the event appears in
`GET /v1/integrations/events`.

---

## 4. Gotchas

Each of these has cost someone real time, or will.

**1. Node 20 fails with no useful message.**
The API runs TypeScript directly via `node --experimental-strip-types`, a flag that does not
exist before Node 22.6. On Node 20 you get exactly `node: bad option:
--experimental-strip-types` and nothing else. There is no `engines` field and no `.nvmrc`, so
nothing warns you. *Consequence: an hour lost before anyone thinks to check the Node version.*

**2. `PERSISTENCE=DB` silently drops the entire ERP integration subsystem.**
The in-memory store has 18 collections. `persistenceDb.ts` handles 13. The five it does not
touch are `integrationConnections`, `integrationApiKeys`, `integrationIdempotency`,
`integrationEvents` and `integrationWebhookDeliveries` — the whole ERP feature. File-mode
persistence handles all five. Production runs file mode today (`render.yaml` sets `DATA_FILE`
and never sets `PERSISTENCE=DB`), so this data is durable right now. *Consequence: the day
someone switches to Postgres, every restart wipes partner API keys, webhook subscriptions,
idempotency records and pending deliveries, with no error.*

**3. Public routes return whole domain objects, so a new field is public by default.**
`GET /anchor-trips` is allowlisted as public (`httpServer.ts:297`) and returns
`{ ...trip, carrierDisplayName }` — the entire `AnchorTrip`, including `lastLiveLocation`. Any
field added to `AnchorTrip` is immediately world-readable. *Consequence: driver GPS is exposed
today (see C0 in `docs/IMPROVEMENTS.md`), and the next field added will be too unless the route
is changed to project explicitly.* The same shape applies to `shipmentWithCarrierDisplay`.

**4. The Flutter app defaults to production.**
`kDefaultBaseUrl` in `pilot_api.dart:10` is `https://navig8r.onrender.com`. Forget
`--dart-define=API_BASE_URL` and your test bookings land in live data. *Consequence: fake
shipments in the real store.*

**5. Rotating `AUTH_SECRET` logs out every user and breaks every ERP key.**
It signs session tokens *and* salts the hash for integration API keys
(`integrationAuth.ts:16`). *Consequence: rotating it as routine hygiene silently breaks every
partner integration until keys are reissued.*

**6. `packages/core` is imported by relative path, not as a package.**
`import ... from "../../../packages/core/src/payoutSchedule.ts"`. The npm `workspaces`
declaration does not participate. *Consequence: moving `apps/api` breaks the import, and the
Dockerfile must copy `packages/` to the exact matching depth.*

**7. `ALLOW_X_USER_ID=1` is a complete authentication bypass and is not gated on `NODE_ENV`.**
It makes `requireUserId` accept an `x-user-id` header with no token, across ~20 authenticated
routes including ops-admin ones (`httpServer.ts:284`). *Consequence: setting it anywhere
reachable hands over every account.*

**8. Route order in `httpServer.ts` is load-bearing.**
It is a linear if-chain, so a broad `startsWith` match placed above a specific one shadows it
permanently, with no error. *Consequence: a new route that never fires and no clue why.*

**9. Two background timers run in every process.**
`index.ts` starts a payout batch runner every 60s and a webhook delivery runner every 30s.
Neither has a re-entrancy guard, and webhook delivery is sequential with a 30s timeout each.
*Consequence: scaling to two Render instances races both runners; and ten dead webhook
endpoints take 300s, so runs overlap and deliver duplicates.*

**10. `main.dart` contains a second, older set of driver screens.**
`PilotScaffold`, `HomeScreen`, `RegisterScreen`, `LoginScreen`, `MyTripsScreen`,
`TripDetailScreen` and `PublishTripScreen` are a legacy "pilot lab" surface at `/pilot-lab`,
`/register`, `/trips` and `/publish`. They duplicate the `driver_flow.dart` screens and are not
linked from either shell. *Consequence: you fix a bug in the wrong copy.*

**11. `docs/` claims things the deployment does not do.**
`ROADMAP.md` states Postgres is live in production, but `render.yaml` sets `DATA_FILE` and never
sets `PERSISTENCE=DB` or `DATABASE_URL`. *Consequence: reasoning about production from the
roadmap gives the wrong answer.* Trust `render.yaml` and the Render dashboard.

---

## 5. Conventions

- **Money is always integer paise.** Never floats. `moneySplit` uses `Math.floor` for
  commission so rounding always favours the carrier.
- **Time is always UTC milliseconds** in storage, named `...UtcMs`. IST conversion happens only
  in `packages/core/src/payoutSchedule.ts`.
- **IDs are prefixed** so a bare ID is self-describing in a log: `usr_` user, `org_`
  organization, `car_` legacy carrier, `veh_` vehicle, `trip_` anchor trip, `shp_` shipment,
  `payin_` customer payment, `pay_` payout batch, `led_` ledger line, `otp_` OTP challenge,
  `ses_` session, `evt_` integration event, `intconn_` integration connection, `intkey_`
  integration API key, `whd_` webhook delivery.
- **Status values are string unions in `types.ts`**, not enums. Add new values there first.
- **Errors** are `ApiError` with a machine-readable code (`phase_a_not_eligible`) plus a detail
  object. The client formats them; the server never writes user-facing prose.
- **Branches** are `feature/`, `fix/`, or `docs/`. PRs squash-merge into `main` with a
  `(#NN)` suffix. `main` deploys to Render, so never push to it directly.
