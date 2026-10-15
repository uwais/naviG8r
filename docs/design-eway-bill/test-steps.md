# E-way bill demo: steps to try it yourself

All data is synthetic and local. Nothing here touches beta or production. The shipper and ops steps need only a
browser. The carrier step is optional (an emulator) and has a browser stand-in.

## Start (once, from the repo folder, Node 24 and Flutter 3.22.3 first on the path)

1. Start the server: `OTP_PHONE_START_LIMIT=1000 OTP_IP_START_LIMIT=1000 RBAC_MANUAL_PORT=3139 node --experimental-strip-types scripts/rbac-manual.mjs`.
   Right: a table of 12 accounts, then "Open http://127.0.0.1:3139/ops". Restarting resets every change.
2. Build the shipper app: `cd apps/driver_pilot && flutter build web --release --no-web-resources-cdn --dart-define=API_BASE_URL=http://127.0.0.1:3139`.
3. Serve it from the repo folder: `node scripts/serve-mobile-rbac.mjs`. Right: the app opens at http://127.0.0.1:8087/#/customer/login.

## A. Shipper adds a bill

4. Sign in with 8000000001 (Send code fills the code, then Verify and continue). Open My shipments, then the first
   "Accepted" one, or go straight to http://127.0.0.1:8087/#/customer/shipments/load-a-booked.
   Right: under the progress list, a card "E-way bill", "No e-way bill added yet.", two buttons of equal weight
   ("Add e-way bill", "No e-way bill needed") and the link "Open the government e-way bill portal".
   Wrong: either button looks chosen, or any text says the truck cannot start.
5. Tap "Add e-way bill". Right: a note saying all four details are needed and that naviG8r does not make or
   change e-way bills; four fields; under GSTIN and invoice number, "Used only by naviG8r ops to find the bill on
   the portal."
6. Tap "Save e-way bill" with nothing filled. Right: "Fill in all four details to save." Nothing is sent.
7. Type `1234`, choose any date (future dates are greyed out), type `X` as GSTIN and `Y` as invoice number, Save.
   Right: a plain sentence from the server ("The e-way bill number is 12 digits."), never "HTTP 400". What you
   typed is still there.
8. Fix them: number `9876 5432 1098`, GSTIN `29abcde1234f1z5`, invoice `SYN/2026/002`. Right: the card now shows
   the number in groups of four, the date, the GSTIN in capitals, the invoice number and "Entered by you. Not
   checked yet." with Edit and Remove e-way bill.

## B. Ops checks it

9. Open http://127.0.0.1:3139/ops/beta, sign in with 8000000005. Right: the strip shows "E-way bills to check 2"
   (yours and a seeded one) and "Missing e-way bills 1".
10. In "E-way bills to check", find your shipment. Right: the four details, each with Copy, a link "Open the
    government portal" (opens ewaybillgst.gov.in in a new tab), "Mark as found on the portal" and "Report a
    problem". Wrong: any button is already pressed.
11. Press "Report a problem" then "Confirm problem" without choosing. Right: it asks you to choose; nothing
    changes. Choose "Not found on the portal", Confirm. Right: the result appears inside the row and says it was
    recorded.
12. Back in the shipper app, refresh the shipment (pull down or reopen it). Right: "Ops could not find this bill on
    the portal on 14 Oct 2026. Check the details here and on the portal." Nothing says "verified".

## C. Editing clears the check

13. Tap Edit, change the invoice number, Save. Right: before Save it said "Changing these details clears the
    check."; after Save the line is "Entered by you. Not checked yet." and ops lists it again under "to check".
14. On ops, choose "Mark as found on the portal". On the shipper card the line becomes "Ops saw this bill on the
    government portal on [date]. It may have changed since."

## D. Not needed, and removing

15. Tap Remove e-way bill. Right: back to "No e-way bill added yet." Then "No e-way bill needed". Right: three
    reasons, none selected; Save says "Choose why no e-way bill is needed." until you choose; "Other" asks for
    words.
16. Save with "Other" and a few words. Right: "You said no e-way bill is needed: [your words]." with Change and
    Remove e-way bill; on ops it appears under "Shipper says no e-way bill is needed" in the Missing card.

## E. What a carrier sees (optional)

17. Carrier app on the emulator: `flutter run -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:3139`
    (never without the define: it would hit production). Sign in with 8000000003, Shipments, the booked one.
    Right: a read-only "E-way bill" card: the number in groups of four and the ops line, plus "Shown as the
    shipper entered it. naviG8r has not made or changed this bill, and has not checked the truck or the
    expiry." The bill date, GSTIN and invoice number do not appear. No buttons.
    Wrong: any of those three details shows, or any button on the card.
18. Add the bill as the shipper BEFORE the carrier opens the screen: carrier screens do not refresh by
    themselves; go back to the list and open it again to see a change.
19. On a small phone the detail screen scrolls; the Accept or Confirm buttons stay reachable.

## Stop

20. Ctrl+C the server; stop the static server (`lsof -nP -iTCP:8087 -sTCP:LISTEN`, then `kill <pid>`).
