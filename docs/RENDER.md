## Deploy on Render (`uwais/naviG8r`)

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
- **Root directory** (if the API lives under a subfolder): set to the folder that contains `Dockerfile`, **`packages/`**, and **`apps/api/`** (for this repo that is typically **`logistics-mvp`**).
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

1. In Render: **New → Blueprint** → select repo/branch.
2. Set `AUTH_SECRET` in the dashboard when prompted (it is `sync: false` in `render.yaml`).
3. Ensure Disk mount matches `DATA_FILE=/data/store.json` (configure in dashboard if not created by blueprint).

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

First build may take **8–15 minutes** (Flutter SDK + web precache).

#### API CORS (required for hosted web)

After the static site deploys, copy its URL (e.g. `https://navig8r-customer-web.onrender.com`) and on the **API** service set:

```
CORS_ALLOWED_ORIGINS=https://navig8r-customer-web.onrender.com
```

Localhost origins are already allowed for dev. Redeploy the API after changing env.

#### Blueprint

`render.yaml` includes a `navig8r-customer-web` static service with the same build command and publish path.

---

### Troubleshooting

- **Service crashes immediately**: missing/short `AUTH_SECRET` (the API exits on startup).
- **502 / connection reset**: app not listening on `PORT` / wrong host — this repo binds `0.0.0.0` and uses `PORT`.
- **`ERR_MODULE_NOT_FOUND` for `@prisma/client`** (`persistenceDb.ts`): **`npm install` did not run in `apps/api`**, or production omitted dependencies. Fix:
  - **Docker**: use this repo’s **`logistics-mvp/Dockerfile`** with root directory = folder containing `apps/api` and `packages`, **or** change your image so `RUN cd apps/api && npm install && npx prisma generate` runs before start.
  - **Heroku / Node buildpack**: set **project root** / **PROCFILE** so the build runs from **`apps/api`** (the only `package.json`), not the monorepo root with no install.
  - **`prisma` is a runtime dependency** in `apps/api/package.json` so `postinstall` → `prisma generate` works even when the host uses `npm install --omit=dev`.
- **Postgres**: set `PERSISTENCE=DB`, `DATABASE_URL`, and run migrations/schema (`npx prisma db push` once against that URL, or apply migrations in CI).
- **Static site `flutter: command not found`**: do not call `flutter` directly — use `bash scripts/render-build-customer-web.sh` as the build command.

