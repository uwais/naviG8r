# NaviG8r marketing site (`apps/www`)

Public marketing site for **navig8r.org** (preview first; custom domain only after sign-off).

## Local

```bash
cd apps/www
npm install
npm run dev
```

## Build

```bash
cd apps/www
npm install
npm run build
# output: apps/www/dist
```

## Contact form

The contact form posts AJAX to [Formspree](https://formspree.io) → `hello@navig8r.org`.

Set `FORMSPREE_FORM_ID` (runtime, Docker) or `VITE_FORMSPREE_FORM_ID` (Vite build) to the id from `https://formspree.io/f/<id>`. Prefer the runtime env so the sync bootstrap can set `form.action` before the module loads (avoids a silent same-origin POST). Until it is set, submit asks visitors to email `hello@` instead of calling a dead backend.

Bot check: Cloudflare Turnstile when `VITE_TURNSTILE_SITE_KEY` is set; otherwise checkbox + math. See [`docs/MARKETING_SITE.md`](../../docs/MARKETING_SITE.md).

## Preview vs production

1. Deploy the Render static service `navig8r-www` (see root `render.yaml`).
2. Share the `*.onrender.com` preview URL for design/copy sign-off.
3. Only after written approval, attach custom domain `navig8r.org` / `www.navig8r.org` in Render DNS.
