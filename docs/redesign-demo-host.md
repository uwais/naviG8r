# Redesign demo host

A practice server that testers open from a link in a phone-width browser. Nobody has to build anything or hold any
keys. One free Render web service runs it from `Dockerfile.demo`.

## What it is

- **A practice server, not the real one.** It runs the API with fake accounts, fake shipments, and mock payments or
  Razorpay test payments (see "Test payments" below). No real money moves. Never type real names, numbers or
  addresses. Anyone with the link can sign in as any demo account and see everything entered.
- **One stuck request can stall the demo for everyone, for a minute or more.** The server handles one request at a
  time, so a slow or broken request from anyone holds up the rest. A fix exists in an open pull request.
- **Data resets to the seed every time the service wakes.** The seed comes from `scripts/rbac-manual.mjs`, the same
  data the team practises on locally. Anything a tester changes is lost when the service sleeps, restarts or is
  redeployed.
- **The sign-in code shows on screen.** Enter a demo phone number and tap Send code. The six-digit code appears as
  "Debug OTP" and is already filled in. No text message is sent.
- **The e-way bill portal button opens the practice portal** on the same site (`/demo/eway-portal`), not the
  government one.
- **It refuses to start** if `NODE_ENV` is `production` or `beta`, if `DATABASE_URL` is set, or if
  `RAZORPAY_KEY_SECRET` is set while `RAZORPAY_KEY_ID` does not start with `rzp_test_`. Live Razorpay keys are
  refused; only test keys are taken.
- **It sends no webhooks.** No address a tester saves is ever called. The ERP integration's test ping is refused with
  "The practice server does not send webhooks."; the app does not know that answer yet, so it shows its own
  could-not-send sentence.
- **Sign-in tokens are signed with a new random secret at every start**, not the fixed one in the repository.

## Using it

Open `https://<service-name>.onrender.com/` on a phone, or in a desktop browser narrowed to phone width. The team's
link is in Slack, not here: this repository is public, and every visitor spends the demo's Maps quota.

To switch accounts, tap the company name at the top of the app, then Sign out.

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
7. **Environment variables:** add `MAPS_API_KEY` (see below), and the three Razorpay test settings only if you
   want test payments (see "Test payments"). Do not add `NODE_ENV` or `DATABASE_URL`: the server refuses to start
   with either. `PORT` is set by Render.
8. Optional: set the health check path to `/api/health`.
9. Create the service. When the deploy finishes, open the `onrender.com` link it shows.

What you should see: the sign-in screen at `/`, and `{"ok":true,...,"paymentProvider":"mock"}` at `/api/health`
(`"razorpay"` once the test keys are in).

### Test payments (Razorpay test keys)

Rishabh's decision, 21 Oct 2026: the demo may take Razorpay **test** keys, so testers go through the real payment
screen with Razorpay's test cards and UPI. Test mode moves no money.

To turn them on, copy these three settings from the beta service into the demo service, under **Environment**, then
deploy:

| Setting | What it is |
|---|---|
| `RAZORPAY_KEY_ID` | The test key ID. Must start with `rzp_test_`. |
| `RAZORPAY_KEY_SECRET` | Its secret. |
| `RAZORPAY_WEBHOOK_SECRET` | The secret Razorpay's webhook calls are checked with. |

Only test keys are taken: the server refuses to start if `RAZORPAY_KEY_SECRET` is set and `RAZORPAY_KEY_ID` does not
start with `rzp_test_`, so live keys are refused. With both keys the server uses Razorpay; with no keys, payments stay
mock. Keep the values in Render only.

### Putting a new commit on the demo

The team's service has auto-deploy off, because each build compiles the Flutter app (about 4 minutes on 20 Oct).
After pushing to the branch, open the service in Render and choose **Manual Deploy**, then **Deploy latest commit**.
Changing `MAPS_API_KEY` also needs a deploy, because the server writes the key into the page when it starts.

### The Maps key

The key reaches the page only through the `MAPS_API_KEY` variable in Render. The server writes it into the page when
it starts, and no key is ever committed. Without a key the app still works, but the map does not load and place
search shows its no-key sentence.

The key is visible in the page by design: anyone who opens the demo can read it. Rishabh decides the setup. The
recommended one:

- **A separate key used only by this demo.**
- **API restriction:** Maps JavaScript API and Geocoding API only.
- **Application restriction:** none.
- **A daily quota cap** in Google Cloud on each of the two APIs, for example 500 Geocoding requests a day.

Why no website restriction: place search calls Google's Geocoding web service straight from the browser. Google's
security guidance (developers.google.com/maps/api-security-best-practices) puts the Geocoding web service under
IP-address restrictions and the Maps JavaScript API under website restrictions. A website-restricted key will most
likely load the map but have place search refused. That is from the docs, not tried.

The trade-off: with no application restriction, anyone who copies the key can call those two APIs from anywhere. The
API restriction limits what they can call, and the quota cap limits how much it can cost. Because the key serves only
this demo, it can be deleted or replaced without touching anything else.

## Running the same server locally

`node --experimental-strip-types scripts/rbac-manual.mjs` still starts the plain practice API on
`127.0.0.1:3139`. To serve a web build beside it, as the hosted one does, set `RBAC_MANUAL_WEB_DIR` to a
`flutter build web` folder. The web build must have been built with `--dart-define=API_BASE_URL=/api`.
`RBAC_MANUAL_HOST` and `RBAC_MANUAL_PORT` change where it listens.
