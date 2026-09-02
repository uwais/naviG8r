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

Until Cloudflare Turnstile is configured (`VITE_TURNSTILE_SITE_KEY`), submit uses **FormSubmit’s reCAPTCHA**. After Turnstile is set, contact stays on-page and skips that captcha screen.

Next backend if we leave FormSubmit: **Formspree** (Render integration). See [`docs/MARKETING_SITE.md`](../../docs/MARKETING_SITE.md).

## Preview vs production

1. Deploy the Render static service `navig8r-www` (see root `render.yaml`).
2. Share the `*.onrender.com` preview URL for design/copy sign-off.
3. Only after written approval, attach custom domain `navig8r.org` / `www.navig8r.org` in Render DNS.
