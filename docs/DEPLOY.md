## Push to GitHub

This folder is intended to be the **git repository root** (`logistics-mvp/`).

### 1) Create an empty GitHub repo
On GitHub: **New repository** → name it (example) `logistics-mvp` → **do not** add a README/license/gitignore (avoids merge friction).

### 2) Initialize git + first commit (local)

```bash
cd "/Users/uwais/.cursor/projects/empty-window/logistics-mvp"
git init
git add -A
git commit -m "Initial commit: logistics MVP API, pilot auth, Flutter driver scaffold"
```

### 3) Add remote + push

```bash
git branch -M main
git remote add origin https://github.com/uwais/naviG8r.git
git push -u origin main
```

If you use SSH:

```bash
git remote add origin git@github.com:uwais/naviG8r.git
git push -u origin main
```

---

## Hosting externally

### Important: Vercel vs this Node API
The current API (`apps/api/src/index.ts`) is a **long-lived Node HTTP server** with **on-disk JSON persistence** (`DATA_FILE`).

**Vercel is optimized for serverless + static assets**, not a persistent filesystem server. To run this API “as-is” on Vercel you would need a **non-trivial refactor** (serverless handlers + external DB/object storage).

### Practical recommendation
- **API (Node)**: deploy to **Fly.io**, **Render**, **Railway**, or a small **VM** (all support long-running processes + disks/volumes).
- **Vercel**: use for **marketing site**, **docs**, or a **Flutter Web** build — not the raw Node server unless refactored.

### If you still want Vercel later
Typical approach:
- Move persistence to **Postgres** (or similar)
- Split HTTP routes into **serverless functions** or use a framework adapter supported by Vercel
- Remove background `setInterval` payout runner → use **cron** / external scheduler

### Render (this repo)
See `docs/RENDER.md` (includes `Dockerfile` + optional `render.yaml`).

---

## Flutter Android APK (Option A)
See `docs/android-option-a-apk-pilot.md`.
