# Marketing site — navig8r.org

## Status: **APPROVED FOR PROD** (2026-08-16)

Owner sign-off received. Ship by merging this work to `main`, deploying Render service `navig8r-www`, then attaching DNS at OpenSRS.

| Item | Value |
|------|--------|
| App | `apps/www` (Vite static) |
| Render service | `navig8r-www` |
| Deploy branch | `main` (after merge) |
| Contact | In-page form → [Formspree](https://formspree.io) → `hello@navig8r.org` |
| Explore CTA | Human check gate → `https://navig8r-customer.onrender.com/` |
| Registrar | OpenSRS |
| Logo / brand | Typographic wordmark in layout; official files in `apps/www/public/brand/` for selective manual use |
| Claims | Soft / professional; do not overstate unshipped features |
| Domains | `navig8r.org` + `www.navig8r.org` |
| Bot guard | Contact: Turnstile when `VITE_TURNSTILE_SITE_KEY` is set, else checkbox + math. Explore: same. |

## Contact form (Formspree)

FormSubmit (`formsubmit.co`) was retired after a multi-day Cloudflare **522 origin timeout** outage (Nov 2026) that blocked every marketing-site submission. Contact now posts AJAX to **Formspree** and stays on-page.

### One-time Formspree setup

1. Create a free account at [formspree.io](https://formspree.io) (or use the [Render Formspree integration](https://render.com/docs/formspree)).
2. New form → notification email **`hello@navig8r.org`**.
3. Copy the form id from the endpoint `https://formspree.io/f/<FORM_ID>`.
4. On each `navig8r-www*` Render service → **Environment**, set:
   - `FORMSPREE_FORM_ID` = `<FORM_ID>` (runtime; preferred for image deploys)
   - optional: enable Formspree dashboard reCAPTCHA / domain allowlist for `navig8r.org` + `www.navig8r.org` + `*.onrender.com`
5. Redeploy (image services pick up env on restart; static builds need a rebuild only if you use `VITE_FORMSPREE_FORM_ID` instead).

Until `FORMSPREE_FORM_ID` is set, submit shows a mailto fallback message instead of posting to a dead backend.

**Turnstile (optional):** set `VITE_TURNSTILE_SITE_KEY` / runtime `TURNSTILE_SITE_KEY`. Without it, contact uses the on-page checkbox + math challenge.

## Explore portal human check

Explore portal still requires a human check before redirect.

1. Optional: create a free [Cloudflare Turnstile](https://developers.cloudflare.com/turnstile/) site widget.
2. Allow hostnames: `navig8r-www.onrender.com`, `navig8r.org`, `www.navig8r.org`, and `localhost`.
3. On Render → **navig8r-www** → **Environment**, add:
   - `VITE_TURNSTILE_SITE_KEY` = Turnstile **site** key
4. Redeploy.

Without the key, Explore uses a checkbox + simple math challenge, honeypot, and minimum interaction time.


## Sign-off checklist

- [x] Logo / brand assets OK for v1 (selective manual later)
- [x] `hello@navig8r.org` mailbox active
- [x] Registrar noted (OpenSRS)
- [x] Soft claims policy confirmed
- [x] Explore CTA → customer portal confirmed
- [x] Preview approved for production
- [ ] PR merged to `main` + Render deploy green
- [ ] Custom domains added on Render `navig8r-www`
- [ ] OpenSRS DNS records live + TLS issued
- [ ] `FORMSPREE_FORM_ID` set on `navig8r-www*` + contact submit → mail at `hello@navig8r.org`

## Production cutover (Render + OpenSRS)

### Note: Blueprint vs dashboard

If Render → **Blueprints** says you have no Blueprint instances, that only means you never applied `render.yaml` as IaC. Your existing `navig8r-api` / `navig8r-customer-web` services can still be **dashboard-created** in the same workspace. You do **not** need a Blueprint to ship `navig8r-www`.

**Recommended for v1:** create a **Static Site** manually (same path as customer-web).  
Optional later: **New → Blueprint** → connect this repo to adopt `render.yaml` for future syncs (match existing service names carefully to avoid duplicates).

### 1. Create `navig8r-www` (manual Static Site)

In the **same Render workspace** as your API / customer web:

1. **New → Static Site**
2. Connect repo `uwais/naviG8r`, branch **`main`** (merge PR #88 first if not merged)
3. Settings:
   - **Name:** `navig8r-www`
   - **Build command:** `bash scripts/render-build-www.sh`
   - **Publish directory:** `apps/www/dist`
4. Deploy and confirm the `*.onrender.com` URL loads the marketing site.

SPA fallback (if a deep link 404s): Static Site → **Redirects/Rewrites** → rewrite `/*` → `/index.html` (source: rewrite).

### 2. Attach custom domains (Render Dashboard)

On **navig8r-www** → **Settings** → **Custom Domains**:

1. Add **`www.navig8r.org`**
2. Add **`navig8r.org`** (apex)
3. Copy the DNS targets Render displays (exact values can vary by account). Typical pattern:

| Host (OpenSRS) | Type | Target (example — use Render’s values) |
|----------------|------|----------------------------------------|
| `www` | CNAME | `navig8r-www.onrender.com` *(or the hostname Render shows)* |
| `@` (apex) | ALIAS / ANAME / or A records | Exactly as Render lists for apex |

If OpenSRS has no ALIAS/ANAME for apex, use the **A** records Render provides for the root domain, or CNAME-flattening if your DNS plan supports it.

### 3. OpenSRS DNS

1. Log in to OpenSRS → domain **navig8r.org** → DNS management.
2. Add/update the records from step 2.
3. Remove conflicting old A/CNAME records for `@` / `www` if any.
4. Wait for propagation (often minutes; up to 24–48h worst case).
5. Back in Render, wait until both domains show **Verified** / certificate **Issued**.

### 4. Post-cutover checks

- [ ] `https://www.navig8r.org` loads
- [ ] `https://navig8r.org` loads (and redirects or serves same site as preferred)
- [ ] Contact form: submit once via Formspree; confirm mail at `hello@`
- [ ] Mobile + desktop smoke on Products / Contact
- [ ] Optional: set preferred canonical to `https://navig8r.org` or `www` consistently

## Brand logos (manual / selective)

Official logo files are in **`apps/www/public/brand/`** but **not wired site-wide**.  
Update one surface at a time later: see [`apps/www/public/brand/README.md`](../apps/www/public/brand/README.md).

## Local preview

```bash
cd apps/www && npm install && npm run dev
```
