# Scope: a truck and a driver on each trip

Status: scope only, 15 Oct 2026. Nothing here is built. It needs Rishabh's approval first because it changes data
(two optional fields on a trip) and who may see what. It answers question 1 of the e-way bill brief.

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

1. **Data (needs approval, additive):** `assignedVehicleId` and `assignedDriverUserId` on a trip, both optional.
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

## Demo changes if approved

Seed a second driver and a second trip so the filtering shows; the guide gets a driver-sees-only-mine step.

## Open questions for the team

- May a dispatcher assign, or only the owner? (This scope says both.)
- Should starting a trip require a named truck and driver for fleets? (This scope says no for now.)
- Is "a driver with nothing assigned sees nothing" acceptable in the pilot, or does the carrier want a fallback to
  all trips for small fleets?
