# E-way bill demo: how to start it

All data is synthetic and local. Nothing here touches beta or production. The demo's steps live in the guide page
the demo server serves, so they cannot drift from what the apps show. The one exception is the truck chosen at
acceptance and the transporter ID (16 Oct 2026), whose steps are at the end of this page until the guide has them.

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

## Truck at acceptance and the transporter ID (16 Oct 2026)

Start as above. The carrier is the web app at http://127.0.0.1:8087/#/driver or the emulator; the shipper is the
web app at http://127.0.0.1:8087/#/customer/login. Carrier A's seeded trips already name trucks, so step 4 publishes
one that does not. 29TRNSP1234A1Z7 is the transporter ID the practice portal's Transporter sign-in uses.

1. **Owner adds the transporter ID.** Carrier app, sign in as 8000000003, open Profile. Under Transporter ID type
   `29 trnsp 1234 a1z7` and tap Save transporter ID. (If an ID is already saved, tap Change transporter ID first.)
   Right: "Transporter ID saved.", the field closes and 29TRNSP1234A1Z7 shows as plain text with a Change
   transporter ID button, still there after leaving Profile and opening it again. Wrong: a line starting "HTTP",
   the ID still in an open field, or nothing shown when you come back.
2. **A wrong one is refused.** Tap Change transporter ID, type `12345`, tap Save transporter ID. Right: "A transporter ID is 15 letters and
   digits, starting with two digits: your GSTIN, or the TRANSIN from the e-way bill portal. Leave it empty if you do
   not have one." Tap Cancel: the field closes and 29TRNSP1234A1Z7 shows again. Leave Profile and open it again:
   still 29TRNSP1234A1Z7. Wrong: "Transporter ID saved.", or "HTTP 400".
3. **A driver does not see it.** Sign in as 8000000009 and open Profile. Right: no Transporter ID heading or field.
   Wrong: the ID shown anywhere.
4. **Owner publishes a trip with no truck.** Sign in as 8000000003, open Publish, set an origin and a destination,
   tap Publish trip, then open the trip from Loads. Right: the Truck and driver card says "No truck or driver is
   assigned to this trip yet." Wrong: a truck already named.
5. **Shipper books it.** Shipper app, sign in as 8000000001, open Trips, tap Book this lane on the lane from step 4,
   fill it in and tap Book & pay, then open the new shipment. Right: it is awaiting carrier acceptance and its E-way
   bill card has no "For the e-way bill" box. Wrong: the box before the carrier accepts.
6. **Owner cancels.** Carrier app as 8000000003, open Shipments, tap Accept on the new booking. Right: a sheet "Which
   truck carries this trip?" listing KA01AB1234 and KA02XY9999, neither chosen, with Accept with this truck greyed
   out. Tap Cancel. Right: the sheet closes and the booking still shows Accept. Wrong: "Booking accepted."
7. **Owner accepts with a truck.** Tap Accept again, choose KA02XY9999, tap Accept with this truck. Right: "Booking
   accepted." The sheet closes. Then open Loads and tap the trip (not the booking) to open the trip screen; its
   Truck and driver card says "Truck: KA02XY9999. Driver: not
   assigned." Wrong: no truck on the trip.
8. **Shipper sees the box.** Shipper app, open the shipment (pull down to refresh). Right: under "No e-way bill added
   yet." a box "For the e-way bill" with "Truck: KA02XY9999" and "Transporter ID: 29TRNSP1234A1Z7", each with Copy,
   and "On the portal, enter this transporter ID so your carrier can change the truck later. Validity starts when the
   first truck is entered, so enter the truck on loading day, before the goods move. If the goods are already on the
   way, enter the truck now." Tap Copy beside the transporter ID and paste into any text field. Right: exactly 29TRNSP1234A1Z7, and "Copied transporter ID". Wrong:
   no box, or the label pasted with the value.
9. **Both parts in one portal visit.** Tap Open the practice e-way bill portal, choose Supplier, then Generate a new
   e-way bill. Fill every field with these values:
   A.1 GSTIN of Supplier `29ABCDE1234F1Z5` (the shipper's own; the practice portal refuses any other while you
   are signed in as Supplier); A.2 `560099`; A.3 GSTIN of Recipient `33AAACT5678L1Z2`; A.4 `600032`; A.5 Document
   Number `SYN/2026/102`; A.6 today; A.7 `75000`; A.8 HSN `8471`; A.9 Supply; Approximate distance (km) `350`;
   B.1 Vehicle Number `KA02XY9999`; Transporter ID `29TRNSP1234A1Z7`. Tap Generate e-way bill. Back in the app tap
   Add e-way bill and enter the four details the portal shows: bill number, bill date, GSTIN of whoever made the bill
   `29ABCDE1234F1Z5`, invoice number `SYN/2026/102`. Tap Save e-way bill. Right:
   the box is still there. Tap Add truck. Right: Truck number already reads KA02XY9999, with "Filled in from the truck
   on this trip. Change it if the e-way bill shows a different truck." Choose the valid-until the portal showed and
   tap Save truck. Right: the box goes, the bill shows Truck: KA02XY9999, and no sentence says the trucks differ.
10. **The next booking is one tap.** As the shipper, book the same lane again; as the owner, tap Accept on it. Right:
    no sheet, "Booking accepted." at once, because the trip now names its truck. (A driver login never gets the sheet;
    the seeded drivers only see trips that already name a truck, so the widget tests cover that case. They also cover
    a carrier with no trucks, whose sheet says so and offers Accept without a truck: the seed's Carrier B has no
    trucks but is not approved, so it cannot accept.)
11. **No transporter ID.** As the owner, on Profile tap Change transporter ID, clear the field and tap Save
    transporter ID ("No transporter ID
    is saved now."). As the shipper, open the booking from step 10. Right: the box shows the truck only, and "Your
    carrier has not added a transporter ID yet; ask them for one. Without a transporter ID on the bill, only whoever
    made the bill can change the truck. Validity starts when the first truck is entered, so enter the truck on loading
    day, before the goods move. If the goods are already on the way, enter the truck now." Wrong: an empty Transporter
    ID line.
12. **Sign-up and the portal's truck form.** Sign out of the carrier app, tap Register as new carrier, fill it in with
    a new 10-digit phone, vehicle registration `up 1 345` and Transporter ID (optional) `12345`, tap Create carrier &
    continue. Right: the sentence from step 2 and no code screen. Change the ID to `27AAAAA0000A1Z5`, tap again,
    verify the phone, publish a trip and open it from Loads. Right: "Truck: UP010345." on its card, and Profile shows
    27AAAAA0000A1Z5. Wrong: UP1345 or "up 1 345" on the card.
13. **A two-digit district typed with spaces.** Still as that new carrier, on Profile change Vehicle registration to
    `mh 12 345` and tap Save vehicle, then open the trip from Loads again. Right: "Truck: MH120345." Wrong: MH012345.
14. **The office is told which truck the trip kept.** As 8000000003, publish another trip as in step 4; as the
    shipper, book it as in step 5. As the owner, open that trip from Loads, choose KA01AB1234 and any driver in Truck
    and driver, and tap Save. Then tap Accept beside the booking on the same screen: the sheet still asks, because the
    screen has not reloaded. Choose KA02XY9999 and tap Accept with this truck. Right: "This trip already has truck
    KA01AB1234, so the booking was accepted with it. To change the truck, use Truck and driver on the trip screen."
    Tap OK. Right: "Booking accepted." and the card still says Truck: KA01AB1234. Wrong: only "Booking accepted.", or
    KA02XY9999 on the card.
15. **The box goes once the driver confirms delivery.** As 8000000003, open the trip from step 4 in Loads and, for
    each booking on it, tap Confirm delivery, then Confirm POD. As the shipper, open the booking from step 10 and pull
    down to refresh. Right: no "For the e-way bill" box. Wrong: the box, or "on loading day" anywhere on the card.
