# AGENTS.md

## Cursor Cloud specific instructions

This is the **NaviG8r / logistics-mvp** monorepo (npm workspaces): an India-first B2B
freight marketplace. Money is in integer **paise**. Surfaces:

- `apps/api` — Node REST backend (the core product). Native TypeScript, **no build step**
  (run with `node --experimental-strip-types`). Requires **Node 22+** (VM has Node 22).
- `apps/www` — Vite marketing site for navig8r.org (static, vanilla JS/CSS).
- `apps/driver_pilot` — Flutter app: **driver** (Android, default route `/driver`) and
  **customer** shipper portal (web, default route `/customer`) from one codebase.
- `packages/core` — shared payout-schedule math (IST T+7, weekly Wed 18:00 IST cutoff).

The update script runs `npm install` at the repo root, which installs all Node workspaces
and runs `prisma generate` (via `apps/api` postinstall). The **Flutter SDK is NOT installed
by the update script** (too heavy for startup infra) — see the Flutter section below to set
it up on demand.

### Backend API (`apps/api`) — required, always runnable here

- Run from repo root: `npm run dev:api` (i.e. `node --experimental-strip-types apps/api/src/index.ts`).
  Listens on `http://localhost:3000`; health at `GET /health`.
- **`AUTH_SECRET` (min 16 chars) is required or the process exits on startup.** Generate one:
  `export AUTH_SECRET="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"`.
- For local/E2E testing set `export OTP_DEBUG=1` — then `POST /v1/auth/otp/start` returns a
  `debugCode`, and the OTP defaults to `OTP_FIXED_CODE` (default `123456`). This is the only
  way to log in without a real SMS provider.
- Persistence defaults to an in-memory store snapshotted to a JSON file (`DATA_FILE`, default
  `./data/store.json`); **no database is needed**. Postgres is optional (`PERSISTENCE=DB` +
  `DATABASE_URL`, then `cd apps/api && npx prisma db push`).
- Payments default to `MOCK` (captured at booking); Razorpay/RazorpayX are optional and need
  test keys. See `README.md` and `docs/pilot-api.md` for the full env-var and endpoint list.
- Two in-process timers run inside the API (payout batch ~60s, integration webhook delivery
  ~30s) — there is **no separate worker service**.
- API endpoint/flow reference: `docs/pilot-api.md`. A full E2E happy path is: driver register
  (`POST /v1/pilot/driver/register`) → OTP verify → publish trip (`POST /v1/pilot/anchor-trips`)
  → customer quote/book (`POST /shipments/quote|book`) → carrier accept → trip start → POD.

### Tests & marketing site — standard commands

- Tests (Node built-in runner, no server needed): `npm test` from repo root.
- Marketing site: `cd apps/www && npm run dev` (Vite; scripts in `apps/www/package.json`).
  `npm run build` outputs `apps/www/dist`. The contact form posts to external FormSubmit and
  is not wired for local delivery.

### Flutter driver/customer app (`apps/driver_pilot`) — heavier, on-demand setup

- The Flutter SDK is not preinstalled. Install the repo-pinned version (see
  `scripts/render-build-customer-web.sh`): `git clone https://github.com/flutter/flutter.git -b 3.22.3 --depth 1 "$HOME/flutter"`,
  then `export PATH="$HOME/flutter/bin:$PATH"`, `flutter config --enable-web`, `flutter precache --web`.
- Fetch deps: `cd apps/driver_pilot && flutter pub get`.
- **Customer web** (runs in the VM's Chrome): build with the API URL baked in —
  `flutter build web --release --dart-define=API_BASE_URL=http://localhost:3000`, then serve
  `build/web` (e.g. `python3 -m http.server 8080`) and open `http://localhost:8080/`.
  Loading `/` client-side-routes to `/customer`.
- **Google Maps panels render an error box unless `MAPS_API_KEY` is provided** at build time
  (`--dart-define=MAPS_API_KEY=...`). This is expected/optional and does not affect the rest
  of the customer flow (browse/quote/book still work).
- Browser → local API works because the API allows localhost origins when **not** in
  production (`NODE_ENV` unset). For a hosted API you must set `CORS_ALLOWED_ORIGINS`.
- Non-obvious business rule: booking rejects pickup/drop that are too far (~15 km detour) from
  the anchor trip's origin/destination, so use pickup/drop near the selected lane's endpoints
  when testing a full booking (a plain quote has no such restriction).
- Android/driver mode needs an Android SDK + emulator (not set up here); see
  `apps/driver_pilot/bootstrap.sh` and `docs/android-option-a-apk-pilot.md`.
