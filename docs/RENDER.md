## Deploy on Render (`uwais/naviG8r`)

> **How this repo deploys today (since 2026-09-04).** `render.yaml` is a
> `projects:` / `environments:` blueprint. All nine services in it use `runtime: image`
> and pull tagged images from GHCR; Render does not build from Git. Merging to `main`
> runs `.github/workflows/release.yml`, which builds `Dockerfile`,
> `Dockerfile.customer-web` and `Dockerfile.www`, pushes them to
> `ghcr.io/uwais/navig8r-api`, `ghcr.io/uwais/navig8r-customer-web` and
> `ghcr.io/uwais/navig8r-www`, then deploys the same image digests to alpha, beta and
> production in turn. The dashboard, Web Service and Static Site instructions below
> describe the older Git-built model. `render.yaml` notes that the existing production
> static customer-web and www services cannot have their runtime switched in place, so
> the `-image` services declared there are the migration targets for them. `README.md`
> and `docs/ARCHITECTURE.md` describe the release pipeline in more detail.

This API is a **single Node HTTP process** (`apps/api/src/index.ts`). Render runs it well as a **Web Service** (Docker recommended).

### What you get

- Public HTTPS URL like `https://navig8r-api.onrender.com`
- `PORT` is injected by Render (the app reads `process.env.PORT`)
- Health check: `GET /health`

---

### Option A — Deploy via Render Dashboard (fastest)

1. **New → Web Service** → connect GitHub repo `uwais/naviG8r`.
2. Choose:

- **Runtime**: **Docker**
- **Root directory** (if the API lives under a subfolder): set to the folder that contains `Dockerfile`, **`packages/`**, and **`apps/api/`** (in this repo all three sit at the **repository root**, so that is the root directory to use — there is no `logistics-mvp/` directory in the repo; `logistics-mvp` is the `name` field in the root `package.json`).
- **Dockerfile path**: `Dockerfile` (same directory as root above).
- **Instance type**: anything that stays awake for pilots (free tier sleeps; often painful for mobile demos)

The **`Dockerfile`** installs npm dependencies **inside `apps/api`** and copies **`packages/`** (shared TypeScript imports). If you point Docker at the wrong root or omit `packages/`, the build or runtime will fail.

#### Native Node (no Docker)

If you use Render’s **Node** runtime instead of Docker:

- **Root directory**: **`apps/api`** (the only `package.json` for the API).
- **Build command**: `npm install && npx prisma generate`
- **Start command**: `node --experimental-strip-types src/index.ts`

You must still expose **`packages/core`** to the process: either deploy from a layout where `apps/api` can resolve `../../../packages/core` (same as local), or switch to Docker.

1. **Environment variables** (Service → Environment):

- `**AUTH_SECRET`**: required (min 16 chars). Generate locally:
  - `openssl rand -hex 32`
- `**OTP_DEBUG`**: `0` for real pilots (only `1` for local dev convenience)
- `**DATA_FILE**` (recommended for persistence):
  - If you attach a **Render Disk**, mount it (example) at `/data` and set:
    - `DATA_FILE=/data/store.json`

1. **Disk (recommended)**

- Add a **Disk**, mount path `/data`, size 1GB (plan-dependent)
- Without a disk, the JSON store is **ephemeral** on redeploys/restarts.

1. Deploy, then verify:

```bash
curl -i "https://<your-service>.onrender.com/health"
```

1. Point Flutter `ApiConfig.baseUrl` to your Render URL (**https**).

---

### Option B — Deploy via Blueprint (`render.yaml`)

`render.yaml` is a `projects:` / `environments:` blueprint with three environments (alpha, beta, production) and nine services. Every service uses `runtime: image` and pulls from GHCR, so Render does not build from Git and there is no Dockerfile path to set.

1. In Render: **New → Blueprint** → select the repo and the branch holding `render.yaml`. That branch supplies the blueprint only; the services themselves run the GHCR images.
2. Create the Render registry credential named `ghcr-navig8r`; all nine services refer to it through `fromRegistryCreds`.
3. Set the `sync: false` secrets for each environment: `AUTH_SECRET`, `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET` on each API service (production also `RAZORPAYX_ACCOUNT_NUMBER`), `MAPS_API_KEY` on each customer-web service, and `VITE_TURNSTILE_SITE_KEY` on each www service.
4. Disks are declared in the blueprint — `navig8r-data-alpha`, `navig8r-data-beta` and `navig8r-data`, each 1GB at `/data` — and `DATA_FILE=/data/store.json` is already set on all three API services.


---

### Notes / limitations (pilot realism)

- **Cold starts / sleeping** on free/low tiers: mobile pilots will see timeouts unless you keep it warm or use a paid instance.
- **Background timer** (`setInterval` payout runner) runs inside the web process; if Render scales to multiple instances later, you’ll want a single scheduler—fine for MVP single instance.
- **Secrets**: never commit `AUTH_SECRET`; set only in Render env.

---

### Customer web (Flutter Static Site)

Render does **not** include Flutter. Use the repo build script (installs SDK, then `flutter build web`).

#### Dashboard settings

| Field | Value |
|--------|--------|
| **Service type** | Static Site |
| **Branch** | `main` |
| **Root directory** | *(repo root — folder with `scripts/` and `apps/driver_pilot/`)* |
| **Build command** | `bash scripts/render-build-customer-web.sh` |
| **Publish directory** | `apps/driver_pilot/build/web` |

**Environment variables** (Static Site → Environment):

- `API_BASE_URL` = `https://navig8r.onrender.com` (or your API URL)
- `FLUTTER_VERSION` = `3.22.3` (optional pin)
- `MAPS_API_KEY` = Google **Maps JavaScript API** key (HTTP referrer–restricted to this static site URL). Required for live tracking maps on web; build script injects it into `web/index.html`. It no longer reaches Dart code on web: since commit f96ccf9, `lib/maps_config.dart` exports `maps_config_web.dart` for web builds, and that file reads `window.__NAVI8R_CONFIG__.MAPS_API_KEY` rather than a `--dart-define`. The only thing that writes a `runtime-config.js` carrying `MAPS_API_KEY` is the customer-web container entrypoint (`docker/customer-web/entrypoint.sh`); on the static-site path `scripts/inject-maps-api-key.sh` rebuilds `web/index.html` from `web/index.template.html`, which has no `runtime-config.js` tag, so the map tiles render but Dart geocoding (forward and reverse address lookup) sees an empty key.

**Production URL:** `https://navig8r-customer.onrender.com` (Render service name may differ from the hostname; do not use `navig8r-customer-web.onrender.com` — that hostname is not assigned.)

**Google Cloud setup for web maps:** enable **Maps JavaScript API**, **Maps Static API**, and **Geocoding API** if using place search. Restrict the key to HTTP referrers such as `https://navig8r-customer.onrender.com/*` and `http://localhost:*`. Do not reuse the Android SDK key from `android/local.properties` (different restriction type).

**Local web dev with maps:**

```bash
# Key lives in apps/driver_pilot/.env.maps (gitignored) or android/local.properties
bash scripts/inject-maps-api-key.sh   # reads .env.maps automatically
cd apps/driver_pilot
flutter run -d chrome \
  --dart-define=API_BASE_URL=https://navig8r.onrender.com \
  --dart-define=MAPS_API_KEY="$MAPS_API_KEY"
```

Or export `MAPS_API_KEY` manually before `inject-maps-api-key.sh`.

First build may take **8–15 minutes** (Flutter SDK + web precache).

#### API CORS (required for hosted web)

After the static site deploys, set on the **API** service:

```
CORS_ALLOWED_ORIGINS=https://navig8r-customer.onrender.com
CUSTOMER_WEB_BASE_URL=https://navig8r-customer.onrender.com
```

`render.yaml` does not use these values. Each API service there sets its own
`CORS_ALLOWED_ORIGINS`: `https://navig8r-customer-web-alpha.onrender.com` on
`navig8r-api-alpha` (`render.yaml:72-73`), `https://navig8r-customer-web-beta.onrender.com` on
`navig8r-api-beta` (`render.yaml:151-152`), and `https://navig8r-customer-web-image.onrender.com`
on the production `navig8r-api` (`render.yaml:235-236`). `CUSTOMER_WEB_BASE_URL` is set on no
service anywhere in the repo, so unless it was set in the dashboard as the block above instructs,
tracking links fall back to the hard-coded default `https://navig8r-customer.onrender.com`
(`apps/api/src/integrationWebhooks.ts:70`). Which of the two a given environment is sending cannot
be read from this repository.

Localhost origins are already allowed for dev. Redeploy the API after changing env.

#### Blueprint (image-backed since 2026-09-04)

`render.yaml` no longer declares any static or Git-built service. It declares nine image
services across three environments: `navig8r-api-alpha`, `navig8r-customer-web-alpha`,
`navig8r-www-alpha`; the same three with `-beta`; and in production `navig8r-api`,
`navig8r-customer-web-image` and `navig8r-www-image` (the `-image` names are migration
targets, because an existing static service cannot have its runtime switched in place).

The customer-web container is built from `Dockerfile.customer-web`, serves the Flutter web
build with nginx on port 10000, and reads two required environment variables at container
start (`docker/customer-web/entrypoint.sh`):

- `API_UPSTREAM` — proxied at `/api/`. The Flutter build is compiled with
  `--dart-define=API_BASE_URL=/api`, so no absolute API URL is baked into the bundle.
- `MAPS_API_KEY` — substituted into `index.html` and also written to `runtime-config.js`
  as `window.__NAVI8R_CONFIG__.MAPS_API_KEY`.

  **This key is public.** `entrypoint.sh:16-20` writes it into
  `/usr/share/nginx/html/runtime-config.js`, and `docker/customer-web/nginx.conf.template`
  serves that directory with `try_files $uri`, so anyone can fetch
  `https://<host>/runtime-config.js` and read it in clear text. It is also sent as a `key`
  query parameter on browser calls to `https://maps.googleapis.com/maps/api/geocode/json`
  (`apps/driver_pilot/lib/google_geocoding.dart:41`), which is billable. Treat it as published,
  not secret: restrict it in Google Cloud, scope it to the Maps JavaScript and Geocoding APIs
  only, and use a **separate key per environment**, because alpha, beta and production are three
  different hostnames (`render.yaml:97`, `:176`, `:264`). The older guidance further up this file
  names referrer restrictions for the static site; whether an HTTP-referrer restriction is
  actually honoured for Geocoding web-service calls made from a browser is **not something this
  repository can settle, and it has not been checked against Google's documentation** — confirm
  the right restriction type before relying on it. A server-side secret must never be put in
  `runtime-config.js`.

The earlier static customer service at `https://navig8r-customer.onrender.com` is not part
of this blueprint any more.

---

### Troubleshooting

- **Service crashes immediately**: missing/short `AUTH_SECRET` (the API exits on startup).
- **502 / connection reset**: app not listening on `PORT` / wrong host — this repo binds `0.0.0.0` and uses `PORT`.
- **`ERR_MODULE_NOT_FOUND` for `@prisma/client`** (`persistenceDb.ts`): **`npm install` did not run in `apps/api`**, or production omitted dependencies. Fix:
  - **Docker**: use this repo’s root **`Dockerfile`** with root directory = the repository root (the folder containing `apps/api` and `packages`), **or** change your image so `RUN cd apps/api && npm install && npx prisma generate` runs before start.
  - **Heroku / Node buildpack**: set **project root** / **PROCFILE** so the build runs from **`apps/api`** (the only `package.json`), not the monorepo root with no install.
  - **`prisma` is a runtime dependency** in `apps/api/package.json` so `postinstall` → `prisma generate` works even when the host uses `npm install --omit=dev`.
- **Postgres**: set `PERSISTENCE=DB`, `DATABASE_URL`, and run migrations/schema (`npx prisma db push` once against that URL, or apply migrations in CI).
- **Static site `flutter: command not found`**: do not call `flutter` directly — use `bash scripts/render-build-customer-web.sh` as the build command.
- **Customer web tracking map grey/blank**: set `MAPS_API_KEY` on the static site (Maps JavaScript API, HTTP referrer restricted) and redeploy. For local Chrome, run `bash scripts/inject-maps-api-key.sh` after exporting the key. Check DevTools for `RefererNotAllowedMapError`.

