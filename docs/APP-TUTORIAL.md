# The driver app, end to end

A tutorial for the Android app in `apps/driver_pilot/`: what it does, how to run it, what
every screen is, and what will break while you click through it.

Issues are named here only as far as you will trip over them. The evidence for each one lives
in [`UX-REVIEW.md`](UX-REVIEW.md); the fix list you tick off lives in
[`APP-BACKLOG.md`](APP-BACKLOG.md). Neither is repeated here.

Everything below was checked against the source at commit `9cc20cc` on `main` — PR #107 as
merged, including `d116988`, the hardening uwais added on top. Line numbers are that commit's.
Where something is unchecked, it says so.

---

## In sixty seconds

- **What it is** — one Flutter binary; the route decides whether you get the driver app, the
  customer web app, or the legacy developer lab. Android is driver and carrier only. [§1](#1-what-this-app-actually-is)
- **To run it** — three exports (Flutter 3.22.3, JDK 17, Node 24), API in one terminal,
  `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000` in another. Omit that define
  and you are pointed at production. [§2](#2-running-it)
- **The shape** — five bottom-nav tabs inside a `ShellRoute`, hidden for anyone not attached to
  a carrier. Fourteen driver routes, one of them dead. [§3](#3-the-map)
- **The landing** — resolves who you are into four states before offering anything, so a fleet
  driver is never told to register a business. [§4](#4-the-landing-and-why-it-has-four-states)
- **The flow** — OTP sign-in, then either publish-and-run-your-own-lane, or wait to be added to
  someone's fleet. [§5](#5-the-two-journeys)
- **The interface** — four colour tokens and no type scale, so screens improvise. [§6](#6-the-interface-as-it-stands)
- **What breaks** — publish is pre-loaded with a real bookable lane, nothing confirms anything,
  and a failed earnings fetch renders ₹0. [§7](#7-what-will-bite-you-roughly-in-the-order-you-will-hit-it)
- **On the go** — `https://navig8r-customer.onrender.com/#/driver` works today, tested. The iOS
  simulator is a Mac app and is not a route to your phone. [§8](#8-using-it-away-from-the-desk)

---

## 1. What this app actually is

One Flutter binary wearing three faces. Which one you get is decided by the route, not by a
build flag:

| Face | Entry route | Who it is for |
|---|---|---|
| Driver and carrier | `/driver` | The Android app. Drivers and carrier owners |
| Customer | `/customer` | The web app. Shippers booking freight |
| Developer lab | `/pilot-lab` | Legacy test harness, kept on purpose |

`main.dart:84` routes `/` to `/customer` on web and `/driver` everywhere else. So on Android
you land in the driver app; in a browser you land in the customer app unless you ask for
`/#/driver` explicitly.

**Android is driver-and-carrier only.** There is deliberately no customer entry point on the
phone. Customers use the web.

The app talks to the Node API in `apps/api`. Base URL resolution, `pilot_api.dart:13-22`:

| Where | Base URL |
|---|---|
| `--dart-define=API_BASE_URL=...` given | whatever you passed |
| Web, no define | `/api` (relative — needs a host that proxies it) |
| Anything else, no define | `https://navig8r.onrender.com` — **production** |

That last row is the trap. Omit the define on the emulator and your test bookings land in
live data.

---

## 2. Running it

Three things are wrong with this machine out of the box, and all three have to be fixed in
the shell you run from. Verified 2026-09-16.

```bash
# Flutter is not on PATH. 3.22.3 matches what CI builds with.
export PATH="$HOME/flutter-sdks/3.22.3/bin:$PATH"

# Android Studio bundles JDK 25; the repo pins Gradle 8.7, which reads up to Java 22.
# Without this, assembleDebug dies with "Unsupported class file major version 69"
# before a single line of Dart is compiled.
# `flutter config --jdk-dir` is accepted, shows up in `flutter config --list`, and does
# nothing. JAVA_HOME is what takes effect.
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
export PATH="$JAVA_HOME/bin:$PATH"

# The API needs Node 24 (--experimental-strip-types). Node 20 is the default and cannot run it.
export PATH="/opt/homebrew/opt/node@24/bin:$PATH"
```

**Terminal one, the API:**

```bash
export AUTH_SECRET=$(openssl rand -hex 32)
export OTP_DEBUG=1        # no SMS provider exists; this returns the OTP in the response
npm run dev:api
```

**Terminal two, the app:**

```bash
cd apps/driver_pilot
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000
```

`10.0.2.2` is how the Android emulator reaches the host machine. On a physical phone over
Wi-Fi, use the Mac's LAN IP instead.

The emulator `emulator-5554` (Pixel, API 37) already exists. Hot reload is `r`, hot restart
`R`, quit `q`.

Baseline so you know whether you broke something: `flutter analyze` gives 28 issues and 0
errors, `flutter test` 6 of 6 passing.

> `flutter pub get` rewrites nine tracked generated files plus two `Podfile`s. Stage explicit
> paths. Never `git add -A` in this repo.

---

## 3. The map

Everything under `/driver` sits inside a `ShellRoute` (`driver_flow.dart:2502`), so the bottom
nav stays mounted and does not rebuild between tabs.

**Bottom nav, five tabs** (`:127-143`): Home · Shipments · Loads · Publish · Profile.

The nav is hidden in exactly one case (`:2509`):

```dart
final hideNav = path == "/driver" && !DriverSession.hasCarrierOrg;
```

That is the point of the rebuilt landing — someone who is not attached to a carrier sees no
tabs, because none of them would work for them.

| Route | Screen | Reached by |
|---|---|---|
| `/driver` | `DriverWelcomeScreen` | launch, Home tab |
| `/driver/shipments` | `DriverShipmentsScreen` | Shipments tab |
| `/driver/shipment/:id` | `DriverShipmentDetailScreen` | tapping a shipment |
| `/driver/shipment/:id/pod` | `DriverPodScreen` | Confirm delivery |
| `/driver/loads` | `DriverLoadsScreen` | Loads tab |
| `/driver/publish` | `DriverPublishTripScreen` | Publish tab |
| `/driver/profile` | `DriverProfileScreen` | Profile tab |
| `/driver/trip/:id/active` | `DriverActiveTripScreen` | Track on a running load |
| `/driver/fleet` | `DriverFleetInviteScreen` | Profile |
| `/driver/earnings` | `DriverEarningsScreen` | Profile |
| `/driver/payout-setup` | `DriverPayoutSetupScreen` | Earnings |
| `/driver/payout-history` | `DriverPayoutHistoryScreen` | Earnings |
| `/driver/track` | `DriverTrackScreen` | **nothing. Unreachable** |
| `/driver/onboarding/phone` · `/otp` · `/register` · `/join` | sign-in and sign-up | outside the shell, no nav |

`/driver/track` is registered and dead: nav index 3 goes to Publish and nothing pushes it.

---

## 4. The landing, and why it has four states

`DriverWelcomeScreen` resolves who you are before it offers you anything
(`driver_flow.dart:156`):

```dart
enum DriverWelcomeState { checking, signedOut, noCarrier, offline }
```

On open it calls `DriverSession.refresh()` with a 6-second timeout (`:189`), then checks for a
stored token with a 3-second timeout (`:232`), and picks a state from the result. Those run in
sequence, so on an emulator with no reachable API the spinner can sit for **about nine seconds**
before anything else appears. That is expected, not a hang.

| State | When | What you see |
|---|---|---|
| `checking` | while those calls run | spinner, "Checking your account" |
| `signedOut` | no token, or the server rejected it | "Drivers and carriers" · Sign in with mobile number · two intent cards |
| `noCarrier` | signed in, attached to no carrier | "You are signed in, but not attached to a carrier yet" |
| `offline` | had a token, the check failed | "Could not check your account" · Try again |

The signed-out state ranks one primary action above two "New here?" cards:

- **Sign in with mobile number** — the filled button, because most opens are returning users
- **I own a truck or transport business** — goes to `/driver/onboarding/register`
- **I drive for a transport company** — goes to `/driver/onboarding/join`
- **Developer lab** — a text button at the bottom, to `/pilot-lab`

The `noCarrier` state ranks **Check again** above **Register my own carrier business** on
purpose. Waiting to be added is the correct path for an employed driver; registering a
business is the one they must not take. The old landing offered five near-peer buttons and
pushed exactly the wrong one at them.

---

## 5. The two journeys

### Owner-operator — someone with their own truck

```
/driver  ->  onboarding/phone  ->  onboarding/otp  ->  onboarding/register
                                                            |
                          +---------------------------------+
                          v
     Publish a lane  ->  Loads  ->  Start  ->  Active trip  ->  Shipment  ->  POD  ->  Earnings
```

1. **Sign in.** `POST /v1/auth/otp/start` with the phone number returns a `challengeId`, and
   when the API runs with `OTP_DEBUG=1` also a `debugCode` — which the app types into the code
   field for you (`driver_flow.dart:543`). `POST /v1/auth/otp/verify` returns an
   `accessToken`. Before it is stored, `DriverSession.clear()` wipes any residual identity
   (`:563-570`, added in `d116988`) — without that, a sign-in on a shared phone could inherit
   the previous driver's `lastRegisteredOrgId`. Then the token is written under the key
   `access_token` via `flutter_secure_storage`.
2. **After verify** the app branches on `DriverSession.hasCarrierOrg`: a carrier goes straight
   to `/driver/loads`, everyone else back to `/driver`, which then explains itself.
3. **Register the carrier.** `POST /v1/pilot/driver/register` creates the org.
4. **Publish a lane.** `POST /v1/pilot/anchor-trips` from the Publish tab.
5. **Loads.** `GET /v1/pilot/anchor-trips`, filterable by vehicle class and status, sorted
   in-progress first, then open, full, completed, newest first within each.
6. **Start.** The Start button appears when `canStart` is true (`:1355`):
   `hasBookings && status != "IN_PROGRESS" && status != "COMPLETED"`, where `hasBookings` is
   just `reservedKg > 0`. `POST /v1/pilot/anchor-trips/{id}/start`.
7. **Active trip.** Posts GPS to `/v1/pilot/anchor-trips/{id}/location` while that screen is
   on top — and only while it is on top.
8. **Confirm delivery.** `POST /shipments/{id}/driver-pod`.
9. **Earnings and payouts,** two taps deep behind Profile.

### Fleet driver — someone who drives for a company

Much shorter, and the case the old landing got wrong:

1. Sign in the same way, or use **I drive for a transport company** to create the account.
2. Land on `/driver` in the `noCarrier` state, with the bottom nav hidden.
3. Copy your number, send it to your owner or dispatcher, and tap **Check again** once they
   have added you.
4. Once `hasCarrierOrg` flips true, the shell rebuilds, the nav appears, and you get Loads and
   Shipments.

`DriverSession.listenable` is what makes step 4 work without a restart: `main.dart` passes it
to the router's `refreshListenable`, so the shell re-evaluates when the session changes.

---

## 6. The interface as it stands

`driver_theme.dart` is the whole design system, and it is four colours:

| Token | Hex | Used for |
|---|---|---|
| `navy` | `#122C53` | primary, headings, filled buttons |
| `background` | `#F4F7FA` | scaffold |
| `border` | `#E2E8F0` | card and input outlines |
| `muted` | `#64748B` | secondary text **inside white cards only** — 4.76:1 |
| `mutedOnBackground` | `#52607A` | secondary text on the scaffold — 5.90:1 |

`muted` on `background` is 4.43:1, which fails WCAG AA for normal text. That is why the second
token exists, and why `widget_test.dart` computes the ratio rather than asserting a hex value.

Componentry is consistent where the theme reaches: white cards with a 16px radius and a hairline
border, 12px-radius buttons, 14px-radius filled inputs, pill chips, a white nav bar with a navy
12%-opacity indicator.

It stops at the theme's edge. There is no type scale and no spacing scale in `ThemeData`, so
every screen invents its own font sizes inline, and error text is a bare `Colors.red` at
3.42:1 — the text a driver most needs to read, at the lowest contrast in the app.

Two notes for anyone extending it. The scaffold is a cool blue-grey, not the warm off-white
the workspace design rules call for — this is the app's existing brand and changing it is a
decision, not a fix. And there is not one `Semantics` widget in the app, so icon-only buttons
are unlabelled for screen readers.

---

## 7. What will bite you, roughly in the order you will hit it

Each links to the fix on the backlog.

- **Publish ships pre-filled with a real, bookable lane.** One unguarded tap on a nav tab
  publishes it, and nothing can withdraw it. Clear the form before you demo.
  [why](UX-REVIEW.md#23-the-publish-form-ships-pre-filled-with-a-real-bookable-lane)
- **Timestamps are typed by hand.** Publish asks for `2026-05-12T00:00:00+05:30` in a text
  field, on a phone. There is no date picker. [why](UX-REVIEW.md#26-publish-field-labels-are-raw-api-parameter-names)
- **Nothing in the app asks "are you sure".** Accept, start, POD and publish are all one tap
  and all irreversible. There is not a single `showDialog` in 2,554 lines. [why](UX-REVIEW.md#22-there-is-not-one-confirmation-dialog-in-the-entire-driver-app)
- **You accept a load without seeing what it pays.** The price is not on the accept card, and
  the tap through to the screen that shows it is disabled for exactly those rows.
  [why](UX-REVIEW.md#21-a-carrier-accepts-a-binding-load-without-ever-seeing-what-it-pays)
- **Start appears on reserved kilos, not on an accepted shipment**, so the list offers an
  action the trip screen then refuses with a raw error. [why](UX-REVIEW.md#journeys)
- **The POD screen names nothing.** No customer, no address, no amount — just a paragraph, an
  optional Notes box and Confirm POD. It is called proof of delivery and the only thing it can
  send is free text: there is no camera, no picker, no signature pad anywhere in the app.
  [why](UX-REVIEW.md#journeys)
- **After POD the shipment screen still says pending** and still offers Confirm delivery.
  Tapping again returns a raw error. [why](UX-REVIEW.md#journeys)
- **Earnings shows ₹0 when the fetch fails.** `_load()` is `try`/`finally` with no `catch`
  (`driver_flow.dart:2132-2142`) and the render falls back to `?? 0` (`:2147-2148`), so a dead
  network is indistinguishable from having earned nothing. Payout history has the same bug and
  says "No payout batches yet". [why](UX-REVIEW.md#24-a-failed-request-tells-the-driver-they-have-earned-nothing)
- **Every error is a raw API code.** Two of them tell the driver to redeploy the API with CORS
  enabled. [why](UX-REVIEW.md#210-every-error-a-driver-sees-is-a-raw-api-code)
- **Location is shared only while the active-trip screen is on top.** The 30-second interval
  the customer is promised is real (`driver_flow.dart:1779` throttles to exactly that); the
  duration is not. Background the app and the updates stop. A denied permission is a bare
  `return` — no message, and the screen goes on claiming GPS is being shared.
  [why](UX-REVIEW.md#29-location-is-shared-only-while-one-screen-is-on-top)
- **A payout renders as `₹1250000`,** not grouped the Indian way. [why](UX-REVIEW.md#journeys)
- **Two different screens both say "Proof of delivery" in the app bar.** The title is a prefix
  match on `/driver/shipment/` (`driver_flow.dart:29`), so the shipment detail screen wears the
  POD screen's title before you have opened POD at all.
- **The Verify code screen has no way back.** Its only text button is Resend code
  (`:616`); the onboarding routes navigate with `context.go`, so there is no pop history and no
  automatic back arrow. Hardware back is the only exit.
- **`hasCarrierOrg` can be true for someone with no carrier org.**
  `firstCarrierOrgIdFromPilotMe` (`pilot_api.dart:100-116`) looks for a `CARRIER_SOLO`,
  `CARRIER_FLEET` or `CARRIER_LEGACY` org, and if it finds none falls back to **the first
  organization of any kind** (`:111-114`). That is the gate the nav, the landing state and three
  money screens all turn on.

One more, outside the app and above all of these: an invited fleet driver can redirect the
whole carrier's weekly payouts to their own bank account. It is an API authorization bug, it
is unfixed, and it is recorded at the bottom of [`APP-BACKLOG.md`](APP-BACKLOG.md).

---

## 8. Using it away from the desk

### The web build — the one that works today

Same binary, same `/driver` routes, in a browser. Tested 2026-09-16 from a desktop browser:

```
https://navig8r-customer.onrender.com/#/driver
```

| Check | Result |
|---|---|
| Page loads, Flutter scene mounts | yes |
| `/api/health` from that origin | `200 {"ok":true,...,"release":"f96ccf98..."}` |
| `/api/v1/pilot/me` while signed out | `401 unauthorized` — endpoint reachable |
| `https://navig8r-customer-web-image.onrender.com` | `404 Not Found` — not cut over yet |

Two things to know. The `#/driver` is not optional: the bare host redirects to `/customer` on
web. And what is deployed there is release `f96ccf9`, which is current `main` — the **old**
five-button landing. The rebuilt one ships when #107 merges and the release pipeline redeploys.

Why it has to be that host and not any static server: the Docker build compiles with
`--dart-define=API_BASE_URL=/api` (`Dockerfile.customer-web:30-31`) and nginx proxies `/api/`
to the API (`docker/customer-web/nginx.conf.template:12-13`). Serving `build/web` from a plain
static server renders the UI and 404s every request — verified locally on port 8099.

Not checked: whether it behaves on iPhone Safari specifically. The mechanism is sound and the
desktop test passed, but nobody has opened it on the phone.

### The iOS simulator

Not a route to using this on the go: an iOS simulator is a Mac application. It runs on the
Mac, never on the iPhone. And this app cannot use it yet without setup work — verified state
of `apps/driver_pilot/ios/`:

| Thing | State |
|---|---|
| Bundle identifier | `com.example.driverPilot` — placeholder, must change to install on a device |
| Deployment target | iOS 12.0 |
| Google Maps key in `AppDelegate.swift` | absent — maps would be blank |
| `Podfile.lock` | missing; pods have never been installed |

Compare Android, which is properly configured: `applicationId = "com.navig8r.pilot"`.

### Installing on a real iPhone

Possible, not quick: Xcode, CocoaPods, a bundle id you own, a Maps key, and a signing identity.
A free Apple ID works but re-provisions every 7 days. This is a project, not an afternoon.

### An Android phone

If you have one, it is the cheapest real-device path: USB debugging on, then
`flutter run --dart-define=API_BASE_URL=http://<mac-lan-ip>:3000`.

One caveat if you plan to hand someone an APK: `android/app/build.gradle:80` falls back to the
**debug** signing config when no keystore is configured, so a "release" build is debug-signed
unless you set one up.

---

## 9. Known gaps in this tutorial

- Nothing here was verified by watching the app run end to end. The claims are read from the
  source at `9cc20cc` and from the two live HTTP checks in section 8.
- The screen-by-screen field lists in section 5 name the endpoints, not every rendered field.
- `docs/android-option-a-apk-pilot.md` predates this and is wrong in one dangerous place: it
  says `http://10.0.2.2:3000` is "already default in `lib/main.dart`". It is not. The default
  is production, and the constant lives in `pilot_api.dart:11`.
