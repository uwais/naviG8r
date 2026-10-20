# Redesign demo host

A practice server that testers open from a link in a phone-width browser. Nobody has to build anything or hold any
keys. One free Render web service runs it from `Dockerfile.demo`.

## What it is

- **A practice server, not the real one.** It runs the API with fake accounts, fake shipments and mock payments.
  No real money moves and no real data is kept.
- **Data resets to the seed every time the service wakes.** The seed comes from `scripts/rbac-manual.mjs`, the same
  data the team practises on locally. Anything a tester changes is lost when the service sleeps, restarts or is
  redeployed.
- **The sign-in code shows on screen.** Enter a demo phone number and tap Send code. The six-digit code appears as
  "Debug OTP" and is already filled in. No text message is sent.
- **The e-way bill portal button opens the practice portal** on the same site (`/demo/eway-portal`), not the
  government one.
- **It refuses to start** if `NODE_ENV` is `production` or `beta`, or if `RAZORPAY_KEY_SECRET` or `DATABASE_URL` is
  set. Payments are always mock.

## Using it

Open `https://<service-name>.onrender.com/` on a phone, or in a desktop browser narrowed to phone width.

| Phone | Signs in as |
|---|---|
| 8000000001 | Shipper admin (Synthetic Shipper A) |
| 8000000003 | Carrier owner (Synthetic Carrier A) |
| 8000000009 | Driver A, carrier A |
| 8000000013 | Driver B, carrier A |
| 8000000005 | Ops |
| 8000000006 | Finance |

The ops page is at `https://<service-name>.onrender.com/ops/beta`. The current page is at `/ops`.

## Free tier behaviour (from Render's docs, render.com/docs/free, read 19 Oct 2026)

- The service spins down after 15 minutes with no incoming traffic.
- The next visit wakes it, which takes about one minute. The first page load waits for that.
- The filesystem is ephemeral. Local files are lost on every redeploy, restart or spin-down, so the data goes back
  to the seed.
- Each workspace gets 750 free instance hours a month. If they run out, Render suspends free services until the
  next month.

## Setting it up on Render (one person, once)

1. In the Render dashboard choose **New**, then **Web Service**.
2. Connect the naviG8r GitHub repository.
3. **Branch:** `feat/mobile-redesign`, or the branch this work lands on.
4. **Language / runtime:** Docker.
5. **Dockerfile path:** `Dockerfile.demo`. Leave the build context as the repository root.
6. **Instance type:** Free.
7. **Environment variables:** add only `MAPS_API_KEY` (see below). Do not add `NODE_ENV`, `RAZORPAY_KEY_SECRET` or
   `DATABASE_URL`. The server refuses to start with any of them. `PORT` is set by Render.
8. Optional: set the health check path to `/api/health`.
9. Create the service. When the deploy finishes, open the `onrender.com` link it shows.

What you should see: the sign-in screen at `/`, and `{"ok":true,...,"paymentProvider":"mock"}` at `/api/health`.

### The Maps key

The key reaches the page only through the `MAPS_API_KEY` variable in Render. The server writes it into the page when
it starts, and no key is ever committed. Without a key the app still works, but the map does not load and place
search shows its no-key sentence.

Use a separate browser key for this service:

- **Application restriction:** websites (HTTP referrers): `https://<service-name>.onrender.com/*`.
- **API restriction:** Maps JavaScript API and Geocoding API only.

Caution, not yet tried: place search calls Google's Geocoding web service straight from the browser. Google's
security guidance (developers.google.com/maps/api-security-best-practices) pairs the Geocoding API with IP-address
restrictions, not website restrictions. A website-restricted key may therefore show the map but have place search
refused. If that happens, tell whoever owns the key. Do not loosen it without their decision.

## Running the same server locally

`node --experimental-strip-types scripts/rbac-manual.mjs` still starts the plain practice API on
`127.0.0.1:3139`. To serve a web build beside it, as the hosted one does, set `RBAC_MANUAL_WEB_DIR` to a
`flutter build web` folder. The web build must have been built with `--dart-define=API_BASE_URL=/api`.
`RBAC_MANUAL_HOST` and `RBAC_MANUAL_PORT` change where it listens.
