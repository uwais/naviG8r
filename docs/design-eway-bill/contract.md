# E-way bill link-out demo: contract

Status: demo build, 14 Oct 2026. Built from `docs/CLAUDE-DESIGN-BRIEF-ewaybill.md` (the 3 Oct brief, on the
unpushed branch `docs/standup-2026-10-05`). The claude.ai/design step in section 9 of that brief was not done;
this is built straight from the brief's rules.

The app never makes, changes or imitates an e-way bill. The shipper makes it on the government portal and types
its details here. Ops looks it up on the portal by hand. The carrier reads it.

## In this demo

| Who | Does what |
|---|---|
| Shipper | Adds the bill's four details, or says none is needed with a reason. Edits, removes. Opens the government portal from the shipment. Sees the ops check. |
| Carrier and driver | Read the bill number and the ops check, also before accepting. Cannot change anything. |
| Ops (`/ops/beta`) | Two lists: bills to check, and shipments with no bill. Opens the portal, copies each detail, marks "found" or "problem". |

## Not in this demo, and why

| Left out | Why |
|---|---|
| Blocking trip start | Depends on the team's questions 1 to 3 and 5. |
| Truck number, valid-until, time left | Brought back in Part B below; trips name a truck since 15 Oct 2026 (`trip-assignment-scope.md`). |
| PDF upload | Own route, size cap, and a retention answer (question 8). |
| Naming a truck, "Start without this shipment" | Questions 1 and 2. |
| Reading offline | The app keeps nothing on the phone, and a failed refresh replaces every screen. Not cheap. |
| Pickup time on the ops "Missing" list | Needs a trip lookup; rows show the booking time instead. |
| Carrier trip screen | Detail screen only, to keep the driver file edit to two lines. |

## Data

One optional record on the shipment, `ewayBill`. A shipment without it is exactly as before.

| Field | Meaning |
|---|---|
| `kind` | `BILL` (details entered) or `NOT_NEEDED` (shipper's statement) |
| `billNumber` | 12 digits |
| `billDate` | `YYYY-MM-DD`, not later than today in India |
| `makerGstin` | 15 characters, GSTIN of whoever made the bill |
| `invoiceNumber` | 1 to 32 characters |
| `notNeededReason` | `BELOW_THRESHOLD`, `GOODS_EXEMPT` or `OTHER` |
| `notNeededNote` | the shipper's words, 3 to 140 characters, only with `OTHER` |
| `enteredAtUtcMs`, `enteredByUserId` | who and when; the user id is never sent to the app |
| `check` | `{ result: FOUND or PROBLEM, problemReason?, checkedAtUtcMs, checkedByUserId }`; cleared by any edit |

Format checks catch typos only. A passing number is not proof the bill exists.
Problem reasons: `NOT_FOUND`, `CANCELLED`, `DETAILS_DO_NOT_MATCH`, `OTHER`.

## What each role gets back

The record is cut by role before it leaves the server (nested objects are not filtered by the general
serializer, so `ewayBill` is built per role in `ewayBillVisibility.ts`).

| Role | Gets |
|---|---|
| Shipper (own shipment), Ops | everything above except the two user ids |
| Carrier owner, dispatcher, driver | `kind`, `billNumber`, `notNeededReason`, `notNeededNote`, `check` result, reason and time. Never the bill date, the maker's GSTIN or the invoice number |
| Finance, Admin | nothing |
| ERP integration responses | nothing (stripped) |
| Open trips, marketplace | nothing |

## Routes

| Route | Who | Does |
|---|---|---|
| `POST /shipments/:id/eway-bill` | Shipper, permission `eway_bill.write` | Body `{ kind: "BILL", billNumber, billDate, makerGstin, invoiceNumber }` or `{ kind: "NOT_NEEDED", reason, note? }`. Replaces the record and clears the check. 200 `{ shipment }` |
| `POST /shipments/:id/eway-bill/remove` | Shipper | Back to "nothing added". 200 `{ shipment }` |
| `GET /ops/eway-bills` | Ops, permission `eway_bill.check` | `{ toCheck, missing, notNeeded }`, each a list of shipments, oldest first |
| `POST /ops/eway-bills/:shipmentId/check` | Ops | Body `{ result: "FOUND" }` or `{ result: "PROBLEM", problemReason }`. Only on a `BILL` |

Errors: `{ error, detail, field? }` with a plain sentence in `detail`. Another shipper's shipment answers 404.
A shipment already delivered, accepted or refunded answers 409 `eway_bill_locked`. Editing or removing is open
until delivery is accepted.

Audit rows (`shipment`): `EWAY_BILL_ENTERED`, `EWAY_BILL_NOT_NEEDED_STATED`, `EWAY_BILL_REMOVED`,
`EWAY_BILL_CHECKED`. States are words only (`ABSENT`, `BILL`, `NOT_NEEDED`, `UNCHECKED`, `FOUND`,
`PROBLEM_NOT_FOUND` and so on). No typed text ever goes in an audit row.

## Copy (screened before building)

Shipper card, title "E-way bill":

- Nothing added: "No e-way bill added yet." Two equal buttons: "Add e-way bill" and "No e-way bill needed".
  Nothing preselected.
- Add form note: "Copy these four details from the government portal. All four are needed to save. naviG8r
  does not make or change e-way bills." (On a practice build every "government portal" in the app's copy reads
  "practice portal".) Fields: "E-way bill number (12 digits)", "Bill date", "GSTIN of
  whoever made the bill", "Invoice number"; under the last two: "Used only by naviG8r ops to find the bill on
  the portal." Above Save, when the bill had been checked: "Changing these details clears the check." Buttons:
  "Save e-way bill", "Cancel". Link: "Open the government e-way bill portal" ("Open the practice e-way bill
  portal" on a practice build; see Part B).
- Saved: number in groups of four, then date, GSTIN, invoice number. Check line, one of: "Entered by you. Not
  checked yet." / "Ops saw this bill on the government portal on 14 Oct 2026. It may have changed since." /
  a problem line by reason: "Ops could not find this bill on the portal on 14 Oct 2026." / "Ops saw on the
  portal that this bill was cancelled, on 14 Oct 2026." / "The details here did not match the portal when ops
  looked, on 14 Oct 2026." / "Ops found a problem with this bill on 14 Oct 2026." Each problem line adds
  "Check the details here and on the portal." Buttons: "Edit", "Remove e-way bill".
- Not needed: "You said no e-way bill is needed: Below the value that needs one." Buttons: "Change",
  "Remove e-way bill". Form: "Why is no e-way bill needed?" with three reasons, none preselected, and "Other"
  asks for the reason in words.
- Errors show the server's own sentence, never "HTTP 400".

Carrier card, same title, read only:

- Nothing added: "[Shipper] has not added an e-way bill or said none is needed."
- Not needed: "[Shipper] says no e-way bill is needed: [reason]. This is the shipper's statement. naviG8r has
  not checked it." The "Other" words are shown exactly as typed. Plain styling, not a warning.
- Bill: number in groups of four, the same check line as the shipper's (with the same date and "may have
  changed since"), and "Shown as the shipper entered it. naviG8r has not made or changed this bill, and has not
  checked the truck or the expiry." A problem adds "The shipper can see this on their shipment."
- Who sees it (changed 15 Oct 2026, `trip-assignment-scope.md`): the carrier's owner, owner-driver and dispatcher
  see every shipment of that carrier, so any of them sees any bill number and note on it. A driver sees only the
  shipments on trips naming them.

Ops page: "E-way bills to check" and "Missing". Each row shows the four details, a Copy button on each, a link
"Open the government portal" ("Open the practice portal" when the server points at its practice site), "Mark as found on the portal" and "Report a problem" (reason chosen from the four
above, none preselected). Results appear inside the row and say whether anything changed.

## Part B (the truck) and the demo portal, added 15 Oct 2026

Rishabh asked for a demo where shipper, carrier and driver each do their part, with a fake government site to
link out to and come back from. This brings back, from the cut list, the truck number and valid-until.

| Who | Part |
|---|---|
| Shipper | Makes the bill on the portal (Part A), copies its four details into the app. May also add the truck. |
| Carrier owner or dispatcher | The carrier named on the bill: adds its truck to the bill on the portal (Part B), then types the truck number and valid-until into the app. |
| Driver | Read only: the number in large type, truck, valid-until, the ops line, and "Expires in N hours" only under 12 hours. Quotes the number at a check-post. |
| Ops | Looks the bill up on the portal's search page with the four details, then records found or problem. |

New data on the record: `truckNumber` (6 to 12 letters and digits, spaces and hyphens removed, upper case),
`validUntilUtcMs`. Both are shown to shipper, ops and carrier logins. Adding or changing them clears the ops check
(same rule as every other detail). New permission `eway_bill.add_truck`: SHIPPER, and CARRIER for owner, owner-driver
and dispatcher only (not DRIVER). It is an allow-list of subroles, so a new subrole gets nothing until named. New routes: `POST /shipments/:id/eway-bill/truck` (shipper) and
`POST /v1/pilot/carrier/shipments/:id/eway-bill/truck` (carrier), body `{ truckNumber, validUntilUtcMs }`, only on a
`BILL`. Audit `EWAY_BILL_TRUCK_ADDED` (state words only). Since 15 Oct 2026 a trip can name its truck
(`trip-assignment-scope.md`): when the bill's truck and the trip's differ, ignoring spaces, hyphens and case, both
cards add one plain sentence under the truck lines, worded for who is reading:

- Carrier office (owner, owner-driver, dispatcher): "The e-way bill shows KA01AB1234. The truck on this trip is
  KA02XY9999. Check which one is right; if the e-way bill is wrong, update it on the portal, then here." ("practice
  portal" or "government portal", as everywhere else.)
- Shipper: "The e-way bill shows KA01AB1234. Your carrier has assigned KA02XY9999 to this trip. Ask your carrier which
  truck is right." The shipper is not sent to the portal: the carrier chose the truck, and once the transporter has
  updated the vehicle the practice portal refuses the supplier (an assumed rule, listed in the guide's box).
- Driver: "The e-way bill shows KA01AB1234. The truck on this trip is KA02XY9999. Tell your carrier."

No sentence shows once the shipment is delivered, accepted or refunded, since the bill can no longer change. The
carrier's truck form starts with the trip's truck, with "Filled in from the truck on this trip. Change it if the
e-way bill shows a different truck." under the field. A wrong truck is replaced with Change truck; removing a truck is left out
of the demo.

Truck copy: "Valid until: 16 Oct 2026, 23:59 (India time)". The date button reads "Valid until, date in India: choose
the date", then the chosen date; the picker ends 29 days after today in India, so even 23:59 on the last day stays
inside the server's 30 days. Once the typed time has passed the line reads "The valid-until time entered has passed.
Check the portal." (naviG8r cannot see the portal, so it never says "Expired"). The portal button reads "Open the
government e-way bill portal" only when the build's address is https://ewaybillgst.gov.in, and "Open the practice
e-way bill portal" otherwise; the could-not-open sentence names the build's own address.

**Return path (Rishabh's choice): browser tab, copy back.** The app opens the portal in the browser (a new tab on
web, Chrome on a phone). The user makes or looks up the bill there, copies the details, switches back to the app and
pastes. There is no automatic return: the real portal cannot send data to naviG8r, so the demo does not pretend it
can. The fake portal says on every page that it is a naviG8r demo and not the government site.

**The fake portal** is served by the demo server only when `EWAY_DEMO_PORTAL=1` (the demo script sets it), under
`/demo/eway-portal` with a step-by-step guide at `/demo/eway-guide`. It copies the real portal's BEHAVIOUR, never its
look: a demo sign-in as the supplier, the carrier (transporter) or a stranger; generate a bill with the real Part A
field names; validity computed from the distance (one day per 200 km, ending at 23:59 India time of the last day);
update the vehicle with the real reasons, by the generator or the named transporter only; extend validity (the
transporter, within the window the notification states); cancel within 24 hours; a public Verify page that takes the
four details. Which rules come from the notifications and which are assumptions is listed in the guide's "Rules I
modelled" box (the three notifications were read as page images; the assumed rules and practice-site limits are listed under their own heading). It keeps its bills in
memory and resets on restart, holds at most 500 and drops the oldest (never the two seeded bills) to make room. It is answered before the server's one-at-a-time request queue, since it never
touches the store, and drops a form whose body is not complete within 5 seconds, so a slow sender cannot stall other
requests. Its generated bill and look-up result are headed "Practice bill, not a real e-way bill" and "Found (practice
site)". The guide builds its addresses from the Host the visitor used. The app's portal address comes from the
build (`--dart-define=EWAY_PORTAL=...`, default the real portal); the ops page gets its link from the server.

## Open and unchecked

- Permission keys `eway_bill.write` and `eway_bill.check` are new (code only; the database seeds them on save).
- Database mode needs one nullable JSON column, `ShipmentRow."ewayBill"`, applied by hand BEFORE this merges,
  because merging deploys to alpha and beta. Not applied by me.
- The portal address is `https://ewaybillgst.gov.in`, named in the brief from CBIC's FAQ. I have not opened it.
  Whether it has a page that takes a bill number directly, or needs a captcha, is unknown.
- Whether the team wants ops to check at all, or the GSTIN and invoice number collected, is the brief's open
  question 4 and the chartered accountant's question 7.

Team answers, 15 Oct 2026 (Uwais, #navig8r-pilot Slack thread, 12:19 EDT). The team's position, not legal or
accounting advice:

- E-commerce operator (CGST section 52): the team says naviG8r is not one but a carrier matching platform. Still
  open: the accountant has not confirmed it.
- Check-post fine: answered. The carrier pays it and may collect it from the shipper in the invoice. So the carrier
  bears the risk and must see the bill before accepting a booking, which the carrier card already shows; the terms
  of service must say so.
- Keeping the bill number, GSTIN and invoice number: answered, not built. Six months for now, and an OpsAdmin may
  delete them, with an audit row, on a data protection (DPDP) request. Nothing purges them after six months and
  there is no OpsAdmin delete yet. Still open: when the six months start (booking, delivery or bill date) and
  exactly what is deleted.
- Who adds the truck (Part B): answered, the dispatcher or the owner, which is what is built (owner, owner-driver
  and dispatcher; a driver only reads). Still open: validity extension, which the answer did not cover.
