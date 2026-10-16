# Scope: a truck and a driver on each trip

Status: built, 15 Oct 2026, on branch feat/trip-assignment after Rishabh approved it that day. It changes data
(two optional fields on a trip) and who may see what. It answers question 1 of the e-way bill brief. Routes, the
permission and the database column note are in `docs/pilot-api.md` under "Truck and driver per trip".

## The problem

Today every login at a carrier sees every shipment of that carrier, including each bill number. A driver should
see only the trips and shipments assigned to them. Nothing records which truck or which driver carries a trip, so
the app cannot tell, and the e-way bill's truck number has nothing to be compared with.

## Who puts the truck number on the government site

| Question | Answer | How I know |
|---|---|---|
| Who may enter or change Part B (the vehicle)? | The person who made the bill, or the transporter it is assigned to. The rules never name the driver. | Primary: CGST Rules 138(2), 138(3), 138(5) as in Notification 12/2018 (read by the researcher on gstcouncil.gov.in) |
| Does the portal enforce that? | Only the bill's generator and its assigned transporter can enter Part B. | Secondary: snippets of a state FAQ, pages not read |
| In practice, the owner, the dispatcher or the driver? | I do not know. I think the carrier's office, because the driver has no Transporter ID, but that is my reasoning, not a finding. | Not verified |
| Can an owner-operator with no GST registration do it? | Rule 58 lets an unregistered person enrol (FORM GST ENR-01) and third-party guides say this gives a 15-character Transporter ID. | Rule: secondary copy. Portal steps: secondary. Whether Aadhaar is required: sources conflict |
| Breakdown, goods move to another truck | The Part A filer or the transporter updates Part B before the goods move. | Primary: Rule 138(5) |
| What the driver carries | The invoice or challan, and the e-way bill on paper or as its number. So the number alone covers the bill, not the invoice. | Primary: Rule 138A(1). I did not see the CBIC FAQ line |

Consequence for the app: the carrier owner or dispatcher does Part B (the demo already works this way: "Add truck"
is for the owner and dispatcher, not the driver). The driver reads and quotes the number. A solo owner-operator is
owner and driver at once and does both.

Correction to the brief: normal cargo gets one day of validity per 200 km, not 100 km (primary: Notification
94/2020, in force from 1 Jan 2021). The app shows no distance rule, so no copy changes, but the brief's figure is
wrong.

## What each person would reasonably do in the app (my reasoning, not verified with carriers)

| Person | Does | Does not |
|---|---|---|
| Fleet owner or dispatcher | Publishes the trip, accepts bookings, names the truck and the driver for the trip, adds the truck and valid-until to each bill after doing Part B on the portal, reassigns on a breakdown | |
| Owner-operator (one truck, drives it) | Same, but the truck and driver fill in by themselves | |
| Driver | Signs in by phone code on a mid-range Android with weak signal, sees only their trips, starts the trip, shares location, reads the bill number and truck at a check-post, confirms delivery | Cannot edit a bill, cannot see other drivers' trips or other trucks' bills |
| Shipper | Makes the bill on the portal, types the four details, may add the truck if the carrier has not | |
| Ops | Looks the bill up and records the check | |

## Proposed change

1. **Data (approved 15 Oct 2026, additive):** `assignedVehicleId` and `assignedDriverUserId` on a trip, both optional.
   Database mode needs two nullable columns on the trip table, applied by hand before merge.
2. **Who assigns:** carrier owner, owner-driver and dispatcher, any time before the trip completes. A change is
   recorded (audit, state words only). A solo owner-operator's trip assigns itself to the owner and the primary
   vehicle, with no extra tap.
3. **Who sees what:** owner, owner-driver and dispatcher see all of the carrier's trips and shipments, as now. A
   DRIVER sees only trips assigned to them, and only the shipments on those trips. Changes in the carrier shipment
   list, the shipment detail guard, and the trip list. A driver with nothing assigned sees "Your carrier has not
   assigned you a trip yet."
4. **The truck on the bill:** the bill's truck number is compared with the assigned truck ignoring spaces and case.
   Same: nothing shown. Different: a plain sentence to the carrier and the shipper, not a block. The carrier's "Add
   truck" form is pre-filled with the assigned truck's number.
5. **Two trucks, one driver:** assignment is per trip, so a driver can drive different trucks on different trips.
   Assigning a driver who is already on a trip in progress shows a warning, not a refusal.
6. **Breakdown:** the carrier changes the assigned truck; the bill now differs from it, so the app asks for the
   truck on the bill to be updated (the portal reason is Break Down; reason codes are from secondary sources).

## Not in this scope

Blocking trip start, extending validity, consolidated bills, SMS, PDF upload, drivers working for two carriers at
once (a login with two memberships already picks one organization per request), letting a driver do Part B.

## Demo changes

Carrier A has two drivers, Synthetic Driver A (8000000009) and Synthetic Driver B (8000000013), and its owner is
Synthetic Owner A (8000000003), so the owner's driver list shows names. The first trip is assigned to Driver A and
truck KA01AB1234; a second trip (Hoskote to Kolar), with one shipment, is assigned to Driver B. The guide's Step 5
shows each driver seeing only their own trip.

## Decided 15 Oct 2026: a driver never sees carrier earnings

Rishabh's call after the build. It covers every place a driver could see what the carrier earns or when it is paid:

- A `DRIVER` membership has no `payment.read`, so the earnings, ledger and payout-batch routes answer 403 for a driver.
- No response to a driver carries an amount the carrier earns, a payout date or the payment hold, whatever the route
  (the field names are in `docs/pilot-api.md`).
- A driver is never notified of a payment status change.
- The app shows a driver no "Net to carrier" line, no amount or "Payment pending" on the trip screen, and no payment
  hold or release line after delivery: a shipment awaiting payment release reads "Delivery confirmed"; once payment is
  released it reads "Delivered" (see the not-decided item below). Confirming delivery mentions no payment. Profile has
  no "Earnings & payouts" for them.

Owners, owner-drivers and dispatchers keep all of it, unchanged, as do shippers, finance and ops where they had it.

## As built: differences and limits

- Assigning needs both a truck and a driver; there is no way to clear an assignment once made.
- A driver on a trip sees the truck and driver line on the trip screen, read only.
- When the e-way bill's truck and the trip's differ, each reader gets their own sentence: the carrier office is asked
  to check which is right and, if the e-way bill is wrong, to update it on the portal and then in the app; the
  shipper is told what the carrier assigned and asked to check with the carrier; a driver is told the two numbers and
  to tell the carrier. Once the shipment is delivered, accepted or refunded, no sentence shows.
- A driver with no trip sees "Your carrier has not assigned you a trip yet. Ask your carrier to assign one.", and the
  bar above the list shows only the carrier's name.
- Trips from before this change (approved 15 Oct 2026): a trip that names no driver stays with the driver who started
  it, in any status, so nobody mid-route loses it and it stays in their list once complete. It leaves only if the
  office assigns it to someone else before it is complete; a completed trip cannot be assigned, so it stays with its
  driver. A trip never started has no starter, so open and full trips that name no driver
  are visible to no driver. Before go-live the carrier office should assign every open trip; in-progress trips
  started by a driver keep working until assigned.
- A driver cannot change a truck that a trip which is not finished names, since the shipper reads that truck. A
  truck number has at most 20 characters when a carrier registers, invites a driver or edits a truck, with no
  letters-and-digits rule.
- Only a solo owner-operator's trip assigns itself. Once the owner invites a driver or dispatcher, the organization
  is a fleet and the office assigns each trip.
- A push queued for a driver is dropped at send time if the trip names someone else by then. The replaced driver and
  the new one are sent no message; the new trip shows on their Loads screen when they pull down to refresh. A
  replaced driver who still has the trip or one of its shipments open is told it is no longer assigned to them and
  to pull down to refresh.
- A trip a driver publishes is assigned to no one, so the app tells them, for ten seconds, that their carrier must
  assign it and that it shows under their Loads only if it is assigned to them. Whether drivers should publish at
  all is the owner's open decision.
- Database mode: two nullable columns, `ALTER TABLE "AnchorTripRow" ADD COLUMN "assignedVehicleId" TEXT, ADD
  COLUMN "assignedDriverUserId" TEXT;`. Without them the API does not start in database mode at all, so applying them
  by hand is a merge gate for every database-mode service. Not applied.
- Not decided: payment-status notices a driver already received stay in their list (there is no amount in them).
  The owner may want them hidden.
- Not decided: a driver can still tell when payment is released, because the shipment's status moves from "Delivery
  confirmed" to "Delivered" then. The owner has not decided whether that counts as payment state.
- Not decided: an unapproved carrier's banner tells every driver "Ask the carrier owner to add bank details.", which
  the owner may count as payment text.
- In database mode the unread number and the paging marker of the grouped notification list can still count
  notifications on trips a driver no longer sees (counts and ids only, no content or money). Fixing it needs a SQL
  join and cannot be tested without Postgres.
- The truck shown on a finished shipment follows the truck record, so it changes if that truck's registration is
  edited later.
- An older app build shows "Net to carrier: ₹0" once the API stops sending the amount to a driver, so ship the new
  app build before or with the API.
- The public price quote and the rate estimate return the shipper's price to anyone, drivers included, so taking
  publish away from drivers would not hide the price. The commission rate is in no driver response.
- Refusals of accept, confirm delivery and start on an unpaid booking can carry the shipper's checkout state or a raw
  status, and the app prints the raw reply. This existed before this branch and affects every carrier role.

## Open questions for the team

The team answered four e-way bill questions (Uwais, #navig8r-pilot Slack thread, 15 Oct 2026, 12:19 EDT). This is
the team's position, not legal or accounting advice.

| Question | Team's answer | Status |
|---|---|---|
| Is naviG8r an e-commerce operator (CGST section 52)? | No, a carrier matching platform. | Open: the accountant has not confirmed it |
| Who pays a fine at a check-post? | The carrier, who may collect it from the shipper in the invoice. The carrier bears the risk, so it must see the bill before accepting a booking (the carrier's shipment screen already shows it), and the terms of service must say so. | Answered |
| How long are the bill number, GSTIN and invoice number kept? | Six months for now; an OpsAdmin may delete them, with an audit row, on a data protection (DPDP) request. | Answered, not built: no purge after six months and no OpsAdmin delete. Open: when the six months start (booking, delivery or bill date) and exactly what is deleted |
| Who adds the truck (Part B)? | The dispatcher or the owner. | Answered; matches what is built (owner, owner-driver and dispatcher add it, a driver only reads). Validity extension was not answered and stays open |

Still open, on this scope:

- May a dispatcher assign, or only the owner? (This scope says both.)
- Should starting a trip require a named truck and driver for fleets? (This scope says no for now.)
- Is "a driver with nothing assigned sees nothing" acceptable in the pilot, or does the carrier want a fallback to
  all trips for small fleets?
