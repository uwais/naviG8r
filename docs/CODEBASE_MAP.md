# naviG8r codebase map

The document that lets someone who has never opened this repo find their way, change something,
and know whether it worked.

**What belongs in here:** anything a newcomer cannot work out in under five minutes by reading
the code — where things live, how to run them, the order of steps for a common change, and
traps that cost someone an afternoon. Not API reference (that is `docs/pilot-api.md`) and not
design rationale (that is `docs/ARCHITECTURE.md`).

Keep it current in the same commit as the change it describes. A wrong map is worse than none,
because it gets trusted.

Last verified against the tree at commit `f96ccf9` (2026-09-15).

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
| `scripts/` | Render build scripts, Maps key injection, image promotion, release smoke tests, ERP smoke test | Mostly called by Render and by GitHub Actions. `test-erp-integration.sh` and `promote-image-tag.sh` have no caller in the repository and are run by hand. `inject-maps-api-key.sh` has one — `render-build-customer-web.sh:37` runs it, and that script is the documented Render build command for the static customer-web site (`docs/RENDER.md:103`) |
| `docs/` | All long-form documentation | See the index in `README.md` |
| `.github/workflows/` | CI and the release pipeline | `release.yml` is the one that matters. `docker-image.yml` and `docker-publish.yml` are earlier attempts that still fire — both on every push and PR to `main`, and `docker-publish.yml` also on `v*.*.*` tags and nightly at 20:44 UTC — each rebuilding the API `Dockerfile`. Off PRs, `docker-publish.yml` pushes and cosign-signs that image under `ghcr.io/<owner>/<repo>`, a different name from the `navig8r-*` images the release pipeline promotes. `bootstrap-ghcr.yml` is `workflow_dispatch` only |
| `docker/` | nginx config and entrypoints for the two static images | Runtime config injection — these files decide what the browser actually gets |
| `Dockerfile`, `Dockerfile.customer-web`, `Dockerfile.www` | One image per service | All three services are now image-backed; the API Dockerfile is the original |
| `render.yaml` | Three environments (alpha, beta, production) | Declarative blueprint. **Render does not build from Git any more** — it pulls tagged images from GHCR |
| `package.json`, `tsconfig.json` | Root workspace manifest and the shared TypeScript config | `test` and `dev:api` are the only root scripts. The `workspaces` declaration is not used for imports — see gotcha 6. `tsconfig.json` is `noEmit` and nothing runs `tsc` — see gotcha 14 |
| `ROADMAP.md` | The MVP execution checklist, phases A to D | Parts of it are out of date about production — see gotcha 11 |

### `apps/api/src/` — the backend

Roughly 9,200 lines including tests. Two files hold most of it.

| File | Lines | Responsibility |
|---|---|---|
| `services.ts` | 2277 | All domain logic: onboarding, trips, booking, pricing, POD, ledger, payouts, tracking. 67 exported symbols. **Holds many concerns — see the split proposal in `docs/IMPROVEMENTS.md`.** |
| `httpServer.ts` | 1695 | The whole HTTP surface. A hand-rolled `node:http` handler with an if-chain over `url.pathname`. Also contains roughly 590 lines of inline HTML/JS across two portal functions (`opsPortalHtml` at 124-262, the `/admin` document at 902-1355). |
| `persistenceDb.ts` | 532 | Postgres load and save via Prisma. **Covers 13 of the store's 18 collections.** |
| `integrationServices.ts` | 436 | ERP connections, API keys, load intake, idempotency |
| `types.ts` | 343 | Every domain type and status union. Read this first. |
| `integrationWebhooks.ts` | 312 | Outbound webhook queue, signing, retry with backoff |
| `integrationHttp.ts` | 273 | The `/v1/integrations/*` routes |
| `persistence.ts` | 234 | JSON file load and save, with versioned migrations V1 to V4 |
| `auth.ts` | 167 | OTP challenge lifecycle and HMAC bearer tokens |
| `razorpayPayouts.ts` | 126 | RazorpayX contact, fund account, and payout creation |
| `integrationAuth.ts` | 102 | Integration key hashing, parsing, scope checks, webhook signing |
| `razorpayPayments.ts` | 94 | Razorpay order creation and capture |
| `razorpayWebhook.ts` | 89 | Inbound Razorpay signature verification |
| `store.ts` | 66 | The in-memory `Store` type — 18 `Map` collections |
| `index.ts` | 66 | Boot: load store, start server, start two background timers |
| `config.ts` | 44 | Commission, pricing constants, payout schedule, tracking staleness |
| `apps/api/prisma/schema.prisma` | 178 | 13 Postgres models. Note the path — it is beside `src/`, not inside it |
| `softDelete.ts` | 21 | Tombstone helpers: `isActiveEntity`, `markInactive`. Tiny, and load-bearing — see C6 |
| `*.test.ts` | ~2310 | 17 test files, 54 tests (plus 1 file and 6 tests in `packages/core`) |

### `apps/driver_pilot/lib/` — the Flutter app

Roughly 7,160 lines. Three files hold 78% of it.

| File | Lines | Responsibility |
|---|---|---|
| `driver_flow.dart` | 2305 | 18 driver and carrier screens plus the driver shell and route table |
| `customer_flow.dart` | 2149 | 11 customer screens, two private tab widgets, and the customer route table |
| `main.dart` | 1151 | App bootstrap and the `go_router` config — **plus a legacy "pilot lab" surface of 6 more screens that duplicates the driver flow** |
| `location_editor.dart` | 494 | Map-based address and coordinate picker |
| `pilot_api.dart` | 359 | Dio HTTP client, token storage, error formatting |
| `customer_layout.dart` | 132 | Responsive shell: navigation rail at ≥900px, bottom nav below |
| `customer_session.dart` | 109 | Customer auth state, drives router refresh |
| `google_geocoding.dart` | 97 | Address to coordinate lookup |
| `driver_theme.dart` | 75 | App theme (navy `#122C53`) |
| `driver_session.dart` | 102 | Driver auth state |
| `customer_checkout*.dart` | 119 | Razorpay checkout, split web/mobile by conditional import |
| `pilot_api_dns*.dart` | 31 | Platform-conditional DNS handling |
| `maps_config*.dart` | 37 | Geocoding API key for the Dart HTTP calls, split web/native by conditional export. Web reads `window.__NAVI8R_CONFIG__.MAPS_API_KEY` at runtime; native keeps the `--dart-define` compile-time constant |

### `apps/www/` — the marketing site

| File | Lines | Responsibility |
|---|---|---|
| `src/styles.css` | 1253 | The entire design system and every page style |
| `src/main.js` | 551 | Nav behaviour, form handling, bot guards |
| `index.html` | — | The whole single-page site |
| `public/brand/` | — | Logo set in light, dark and monochrome variants |
| `vite.config.js` | 11 | Build config: `publicDir: "public"`, output to `dist/`, which is what `Dockerfile.www` copies |

---

## 2. Entry points

| What | Command | Result when it worked |
|---|---|---|
| **API** | `export AUTH_SECRET=$(openssl rand -hex 32)` then `node --experimental-strip-types apps/api/src/index.ts` from the repo root | Logs `API listening on 0.0.0.0:3000`; `curl localhost:3000/health` returns JSON naming the persistence mode and payment provider |
| **Tests** | `npm test` from the repo root | `pass 60`, `fail 0` (54 API + 6 core) |
| **Driver app** | `cd apps/driver_pilot && flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000` | App opens at `/driver` |
| **Customer web** | Same app with `flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:3000` | App opens at `/customer` — `kIsWeb` picks the shell |
| **Marketing site** | `cd apps/www && npm run dev` | Vite dev server |
| **Ops portal** | Browse to `http://localhost:3000/ops` | Login box; needs an ops-admin phone |
| **Legacy admin** | `http://localhost:3000/admin` | Full data dump. Requires `ENABLE_LEGACY_DEMO_SURFACE=1` in production |

Node **22.6 or newer is mandatory** — `--experimental-strip-types` does not exist before that. See gotcha 1.

### The three deployed environments

There is no longer one deployment. `render.yaml` declares three, and they differ in ways that
change how the API behaves — not just which database it points at.

| | alpha | beta | production |
|---|---|---|---|
| API | `navig8r-api-alpha` | `navig8r-api-beta` | `navig8r-api` |
| `NODE_ENV` | `alpha` | `beta` | `production` |
| Payments | `MOCK` | `RAZORPAY` (test keys) | `RAZORPAY` (live) |
| Payouts | `BOOKKEEPING` | `BOOKKEEPING` | `RAZORPAYX` |
| `OTP_DEBUG` | `1` | `0` | `0` |
| Legacy demo surface | Open | **Open** — see gotcha 12 | Closed |
| Purpose | Automated integration tests | UAT | Live |

**Alpha and beta are not private.** They are public `.onrender.com` hostnames with no network
restriction. See gotcha 12 for what that exposes.

---

## 3. Change recipes

### Add a new API endpoint

1. Write the domain function in `apps/api/src/services.ts`. It takes `store` as its first
   argument and throws `ApiError` for expected failures.
2. Add the route to the if-chain in `apps/api/src/httpServer.ts`. Match on
   `method === "GET" && url.pathname === "/v1/..."`. Order matters — the first match wins.
   Partner endpoints under `/v1/integrations/` do not go here. `httpServer.ts:882` hands that
   whole prefix to `handleIntegrationRoutes` in `apps/api/src/integrationHttp.ts`, which
   authenticates with an integration key — `Authorization: Bearer nvg8r_{keyId}_{secret}`, or
   the `X-Api-Key` and `X-Api-Secret` pair — and checks scopes instead of using a user
   session. That handler answers 404 itself for any `/v1/integrations/` path it does not
   match, so a route added to the `httpServer.ts` chain below the delegation never fires —
   see gotcha 8.
3. Decide the auth. `requireUserId(req, store)` for a logged-in user, then `assertOpsAgent`
   for ops-only. For public marketplace routes, also add the path to
   `publicMarketplaceRouteAllowed` (`httpServer.ts:299`) or it will 403 in production.
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
   `computeFreightGrossPaise` (`services.ts:1374`).
2. **Bump `FREIGHT_MODEL_VERSION`** in `config.ts`. It is returned on every quote so a past
   price can be explained later; changing the formula without bumping it makes old quotes
   unexplainable.
3. Update `apps/api/src/freight.test.ts`.

**Worked when:** `POST /shipments/quote` returns the new numbers and the new `modelVersion` in
the breakdown.

### Add an ERP webhook event

1. Emit it with `emitIntegrationEvent(store, { eventType, shipmentId })` from the relevant
   lifecycle point — `services.ts` for most of the shipment lifecycle,
   `integrationServices.ts` (`createIntegrationLoad`) for the ERP-created path.
2. Add the event name to the `IntegrationEventType` union in `apps/api/src/types.ts`. Miss
   this and the `emitIntegrationEvent` call is a type error, because the parameter is typed
   to that union. `buildIntegrationEventPayload` in `apps/api/src/integrationWebhooks.ts`
   builds the same payload shape for every event type, so it needs no change unless the new
   event carries fields no existing event does.
3. Document it in `docs/erp-integration.md` and
   `integrations/adapters/generic/README.md`.

**Worked when:** `scripts/test-erp-integration.sh` still passes and the event appears in
`GET /v1/integrations/events`.

---

### Ship a change to production

There is no deploy button and pushing to `main` does not deploy. One pipeline
(`.github/workflows/release.yml`) walks a single image through all three environments.

```
  PR ---> merge to main
             |
             v
        [ test ]  npm ci && npm test on Node 22
             |    (a red suite stops everything here)
             v
        [ build ] three images -> GHCR, tagged with the commit SHA
             |    RELEASE_SHA is baked in and reported by GET /health
             v
        [ alpha ]  deploy -> wait -> scripts/alpha-integration.mjs
             |     real OTP login against navig8r-api-alpha
             v
        [ beta ]   deploy -> wait -> scripts/beta-smoke.mjs
             |     checks /health only: ok, paymentProvider, release
             v
     ( manual approval: GitHub environment "production" )
             |
             v
      [ production ]  same image digests, promoted not rebuilt
```

1. Open a PR. **Tests do not run on it** — see gotcha 14. Run `npm test` yourself.
2. Merge. Watch the `NaviG8r Release` action.
3. Confirm the right build actually landed: `curl -s <env>/health` and check `release` matches
   the commit SHA. That comparison is what the smoke scripts automate, and it is the reason
   `RELEASE_SHA` exists.
4. Approve the production step in the GitHub Actions UI when alpha and beta are green.

**What the gates do and do not cover.** Alpha exercises a real OTP login and `/v1/pilot/me`.
Beta checks three fields on `/health` and nothing else — no booking, no payment, no payout. So
the only automated thing standing between a merge and production money handling is a health
check plus a human clicking approve.

**The `wait` in the diagram is `scripts/wait-for-release.sh`.** Deploying is asynchronous: the
deploy hook call returns before the new image is serving, so the alpha and beta jobs poll until
they see the new build. Six calls in `.github/workflows/release.yml` (lines 161, 168, 175 for
alpha and 242, 249, 256 for beta) check `/health` on the API and `/release.json` on customer-web
and www, every 30s for up to 900s, until the response body contains the commit SHA. On timeout
the script prints `Timed out waiting for Alpha API` and fails the job — that is this script, not
a failing test. The production job has no wait step.

**Rolling back** means re-pointing the environment tag at an earlier digest
(`scripts/promote-image-tag.sh`) — not reverting the commit and waiting for a rebuild.

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
`GET /anchor-trips` is allowlisted as public (`httpServer.ts:300`) and returns
`{ ...trip, carrierDisplayName }` — the entire `AnchorTrip`, including `lastLiveLocation`. Any
field added to `AnchorTrip` is immediately world-readable. *Consequence: driver GPS is exposed
today (see C0 in `docs/IMPROVEMENTS.md`), and the next field added will be too unless the route
is changed to project explicitly.* The same shape applies to `shipmentWithCarrierDisplay`.

**4. The Flutter app defaults to production.**
`kDefaultBaseUrl` in `pilot_api.dart:11` is `https://navig8r.onrender.com`. Forget
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
routes including ops-admin ones (`httpServer.ts:285`). *Consequence: setting it anywhere
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
`/register`, `/trips` and `/publish`. They duplicate the `driver_flow.dart` screens, and the
driver shell links straight to them: `DriverWelcomeScreen`, the builder for `/driver`, carries an
ungated "Developer lab" button (`driver_flow.dart:199`) that navigates to `/pilot-lab`.
*Consequence: you fix a bug in the wrong copy, and a driver on a release build can walk into the
legacy surface from the first screen.*

**11. `docs/` claims things the deployment does not do.**
`ROADMAP.md` states Postgres is live in production, but `render.yaml` sets `DATA_FILE` and never
sets `PERSISTENCE=DB` or `DATABASE_URL`. *Consequence: reasoning about production from the
roadmap gives the wrong answer.* Trust `render.yaml` and the Render dashboard.

**12. `NODE_ENV` is the environment name AND the security switch, so alpha and beta run wide open.**
Three protections are keyed off `NODE_ENV !== "production"`: the legacy demo surface
(`httpServer.ts:321`), the CORS origin allowlist (`:92`), and the HTTPS requirement on partner
webhook URLs (`integrationServices.ts:98`). `render.yaml` sets `NODE_ENV` to `alpha` and `beta`
on those environments, so all three are off there. Beta sets `ENABLE_LEGACY_DEMO_SURFACE: "0"`
and it does nothing — line 321 short-circuits before reading it. *Consequence:
`curl https://navig8r-api-beta.onrender.com/v1/users` returns every user and phone number on the
UAT environment, unauthenticated, while the blueprint reads as if it were switched off.* See C5.

**13. The Maps key reaches Dart web code through one generated line, and only the container writes the file it points at.**
The Maps JS `<script>` gets its key at container start (`docker/customer-web/entrypoint.sh:12`
`sed`s `__MAPS_API_KEY__` into `index.html`). Since f96ccf9 the Dart `kMapsApiKey` is a
conditional export (`maps_config.dart:7-8`): native builds keep the compile-time
`String.fromEnvironment` (`maps_config_native.dart:5`), and web builds get a runtime getter that
reads `window.__NAVI8R_CONFIG__.MAPS_API_KEY` (`maps_config_web.dart:4-24`). The customer-web
container writes that global into `runtime-config.js` (`docker/customer-web/entrypoint.sh:16-20`)
and `web/index.html:22` loads it, so the image-backed customer web resolves the Dart key at
runtime. Two things follow. `--dart-define=MAPS_API_KEY` no longer reaches web code at all, so the
define in `scripts/render-build-customer-web.sh:44` is dead, as is its omission from
`Dockerfile.customer-web:29-31`. And nothing outside the container writes `runtime-config.js` — it
is not checked in under `apps/driver_pilot/web/` — while `scripts/inject-maps-api-key.sh:29`
regenerates `index.html` from `web/index.template.html`, which was never given the
`runtime-config.js` tag. *Consequence: on the static Render build (`render-build-customer-web.sh:37`
runs that script) and on a local `flutter run -d chrome`, `kMapsApiKey` is empty and address
autocomplete and geocoding silently do nothing; both call sites early-return
(`driver_flow.dart:1609`, `location_editor.dart:413`). Committing a regenerated `index.html` would
break the container path too, by removing the only line that loads the key.* See C7.

**14. Tests run after the merge, not before it.**
`.github/workflows/release.yml`, the only workflow that runs `npm test`, triggers on `push` to
`main` and on `workflow_dispatch` — never on `pull_request`. The two workflows that do fire on a
PR (`docker-image.yml`, `docker-publish.yml`) only build an image. *Consequence: a PR merges
green-looking, `main` goes red, and the deploy halts at the `build` job — after the merge, when
whoever did it has moved on.* Nothing runs `tsc`, `flutter analyze` or `flutter test` anywhere;
the only Dart CI compiles is the `flutter build web --release` inside `Dockerfile.customer-web`,
and that also happens after the merge, in the `build` job.

**15. Render no longer builds from Git.**
All three production services are declared `runtime: image` against `ghcr.io/uwais/navig8r-*`.
Pushing to `main` does not deploy; it builds images and walks them through alpha, beta, then a
manual approval. *Consequence: editing a service's build command in the Render dashboard changes
nothing, and a hotfix cannot be shipped by pushing — it goes through the whole pipeline.*
**16. `MAPS_API_KEY` is a hard requirement of the customer-web image, not a feature flag.**
`docker/customer-web/entrypoint.sh:5` is `: "${MAPS_API_KEY:?MAPS_API_KEY must be set}"` under
`set -eu` (`:2`), so an unset key exits the script at line 5 — before it renders
`/etc/nginx/conf.d/default.conf` from the template (`:7-9`) and before it writes
`runtime-config.js` (`:16-20`). `Dockerfile.customer-web:42` installs that script as
`/docker-entrypoint.d/99-navig8r.sh`, so it runs inside the stock nginx entrypoint.
`render.yaml` gives `API_UPSTREAM` a literal value on all three environments but marks
`MAPS_API_KEY` `sync: false` (`:97`, `:176`, `:264`), so a newly created environment has no
value until someone sets it in the Render dashboard. *Consequence: the navi8r nginx config is
never rendered and `/api` is never proxied — not the blank map you would expect from a missing
Maps key.* The nginx entrypoint runs `/docker-entrypoint.d/*.sh` under `set -e`, so the
container start should fail outright, but that was not verified against a running container.

**17. The static customer-web build strips the runtime Maps config the Dart code now depends on.**
`maps_config.dart:7-8` conditionally exports `maps_config_web.dart` on web, and that
file reads **only** `window.__NAVI8R_CONFIG__.MAPS_API_KEY` — there is no `String.fromEnvironment`
in it at all. The global comes from `runtime-config.js`, which
`docker/customer-web/entrypoint.sh:16-20` writes at container start and
`apps/driver_pilot/web/index.html:22` loads. But `web/index.template.html` does not carry that
`<script>` tag, and `scripts/inject-maps-api-key.sh:29` (`cp "$TEMPLATE" "$INDEX"`) overwrites
`index.html` from the template on every run — which `scripts/render-build-customer-web.sh:37`
does before `flutter build web` at `:46`. `Dockerfile.customer-web` never calls that script, so
the image keeps the tag. *Consequence: the image build works and the static Render build now has
no Dart Maps key at all, even though `render-build-customer-web.sh:43-45` still passes
`--dart-define=MAPS_API_KEY` to code that ignores it. Trip-city look-up
(`driver_flow.dart:1609`) and reverse geocoding on marker drag (`location_editor.dart:413`) both
early-return on an empty key with no error, and so does `reverseLatLng`
(`google_geocoding.dart:73`). Only the Look up button reports anything — `forwardAddress` returns
`GeocodeOutcome.fail("NO_API_KEY", ...)` at `google_geocoding.dart:36`. The same overwrite hits the local web dev recipe in `docs/RENDER.md:120`.*
Fix either file: add the `runtime-config.js` tag to `index.template.html`, or stop the script
overwriting `index.html`.

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
  integration API key, `whd_` webhook delivery. One more value is produced in the same format
  without naming an entity: `mock_` is the `providerRef` written on a payment when
  `PAYMENT_PROVIDER` is not `RAZORPAY` (`services.ts:1594`).
- **Status values are string unions in `types.ts`**, not enums. Add new values there first.
- **Errors** are `ApiError` with a machine-readable code (`phase_a_not_eligible`) plus a detail
  object. The client formats them; the server never writes user-facing prose.
- **Per-environment browser config arrives at container start, through one shared global.** Both
  static images write `/usr/share/nginx/html/runtime-config.js` from their entrypoint and set
  `window.__NAVI8R_CONFIG__`: `MAPS_API_KEY` for customer-web
  (`docker/customer-web/entrypoint.sh:16-20`), `TURNSTILE_SITE_KEY` and `PORTAL_URL` for www
  (`docker/www/entrypoint.sh:4-9`). The page loads that file before the app bundle
  (`apps/driver_pilot/web/index.html:22`, `apps/www/index.html:485`) and the readers are
  `apps/driver_pilot/lib/maps_config_web.dart` and `apps/www/src/main.js:2`. To add a browser
  setting, extend the entrypoint and the reader together. **Anything you put there is public** —
  nginx serves the web root with `try_files $uri`, so `runtime-config.js` is fetchable at a fixed
  URL by anyone. It is for per-environment values the browser needs, never for a server-side
  secret. Build-time injection still exists
  alongside it and is not interchangeable: `Dockerfile.customer-web:31` bakes
  `--dart-define=API_BASE_URL=/api` into the image, and `apps/www/src/main.js:5` falls back to
  `import.meta.env.VITE_TURNSTILE_SITE_KEY`. A value fixed at build time is the same in alpha,
  beta and production; only the entrypoint route can differ between them.
- **Branches** have no enforced prefix: of the 92 branches on `origin`, 80 are `cursor/`, seven
  have no prefix, and there are two `fix/`, one `feature/`, one `docs/` and one `chore/`.
  **Merges** are mixed — 18 of the 82 commits on `main` are `Merge pull request #NN` commits and
  15 are squashes carrying a `(#NN)` suffix. Pushing to `main` starts the release pipeline in
  `.github/workflows/release.yml`, so never push to it directly. See gotcha 15.
