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
- **Dockerfile path**: `./Dockerfile`
- **Instance type**: anything that stays awake for pilots (free tier sleeps; often painful for mobile demos)

1. **Environment variables** (Service → Environment):

- `**AUTH_SECRET`**: required (min 16 chars). Generate locally:
  - `openssl rand -hex 32`
- `**OTP_DEBUG**`: `0` for real pilots (only `1` for local dev convenience)
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

### Troubleshooting

- **Service crashes immediately**: missing/short `AUTH_SECRET` (the API exits on startup).
- **502 / connection reset**: app not listening on `PORT` / wrong host — this repo binds `0.0.0.0` and uses `PORT`.

