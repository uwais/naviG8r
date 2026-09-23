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

The contact form posts to [FormSubmit](https://formsubmit.co) using their random string (not a naked email). Mail lands at `hello@navig8r.org`.

Until Cloudflare Turnstile is configured, submit uses **FormSubmit’s reCAPTCHA**. After Turnstile is set, contact stays on-page and skips that captcha screen. The site key is read from two places, in order: `window.__NAVI8R_CONFIG__.TURNSTILE_SITE_KEY`, which `docker/www/entrypoint.sh` writes into `runtime-config.js` at container start, then the build-time `VITE_TURNSTILE_SITE_KEY` (`src/main.js:2-7`). The container path is the one production uses.

Next backend if we leave FormSubmit: **Formspree** (Render integration). See [`docs/MARKETING_SITE.md`](../../docs/MARKETING_SITE.md).

## Preview vs production

1. Deploy the Render service for this site (see root `render.yaml`). There is no service named
   `navig8r-www`, and none of them is a Static Site any more: `render.yaml` declares
   `navig8r-www-alpha` (`:101`), `navig8r-www-beta` (`:180`) and `navig8r-www-image` (`:268`),
   all `runtime: image`, each pulling a `ghcr.io/uwais/navig8r-www` tag built by
   `Dockerfile.www`.
2. Share the `*.onrender.com` preview URL for design/copy sign-off.
3. Only after written approval, attach custom domain `navig8r.org` / `www.navig8r.org` in Render DNS.
