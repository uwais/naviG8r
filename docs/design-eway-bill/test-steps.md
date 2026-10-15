# E-way bill demo: how to start it

All data is synthetic and local. Nothing here touches beta or production. The steps themselves live in one place
only, the guide page the demo server serves, so they cannot drift from what the apps show.

## Start (from the repo folder, Node 24 and Flutter 3.22.3 first on the path)

1. Server, with the practice portal switched on:
   `EWAY_DEMO_PORTAL=1 OTP_PHONE_START_LIMIT=1000 OTP_IP_START_LIMIT=1000 RBAC_MANUAL_PORT=3139 node --experimental-strip-types scripts/rbac-manual.mjs`
   Right: a table of 13 accounts (the last is 8000000013, a second carrier A driver), then
   "Open http://127.0.0.1:3139/ops".
2. Web app (shipper, and the carrier stand-in), from `apps/driver_pilot`:
   `flutter build web --release --no-web-resources-cdn --dart-define=API_BASE_URL=http://127.0.0.1:3139 --dart-define=EWAY_PORTAL=http://127.0.0.1:3139/demo/eway-portal`
   then, from the repo folder, `node scripts/serve-mobile-rbac.mjs`. Right: the app opens at
   http://127.0.0.1:8087/#/customer/login.
3. Carrier and driver on the Android emulator (optional), from `apps/driver_pilot`:
   `flutter run -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:3139 --dart-define=EWAY_PORTAL=http://10.0.2.2:3139/demo/eway-portal`
   Never run it without `API_BASE_URL`: it would hit production. Without `EWAY_PORTAL` the portal link goes to the
   real government site. Right: with `EWAY_PORTAL` set, the button reads "Open the practice e-way bill portal";
   only a build pointing at https://ewaybillgst.gov.in says "government".

Then open http://127.0.0.1:3139/demo/eway-guide. It has the steps for shipper, carrier, ops and driver, in order.
The truck and driver per trip (scope: `trip-assignment-scope.md`) is its Step 5, and what a driver must not see is
at the end of its Step 4.

Restarting the server resets everything: shipments, sign-ins and the practice portal's bills.

## What is real and what is pretend

Real: the app, its format checks, the server's rules on who may see and change what, and the ops page. Pretend:
the practice portal under `/demo/eway-portal`. It is served only when `EWAY_DEMO_PORTAL=1`, says on every page that
it is not the government site, and keeps its bills in memory. The real portal cannot send data back to naviG8r,
so in the demo, as in real use, people copy details from the portal and paste them into the app. The practice
portal follows the real rules on who may generate, update the vehicle, extend and cancel, and computes validity
from distance; the guide page lists which rules come from the notifications and which are assumed. Its sign-in
(choose Supplier, Transporter or Someone else, no password, no captcha) and the typed distance are pretend.

## Known limits

- The carrier on a phone returns to the app by switching apps and pasting. There is no automatic return.
- A restart wipes the practice portal's bills. Only the two seeded bills, on load-a-with-bill and load-a-with-truck, come back.
- The practice portal holds 500 bills; past that, each new bill drops the oldest one (never a seeded bill).
- A practice-portal form whose body has not fully arrived within 5 seconds is dropped.

## Stop

Ctrl+C the server; stop the static server (`lsof -nP -iTCP:8087 -sTCP:LISTEN`, then `kill <pid>`).
