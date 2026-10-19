# Copy deck

Every visible string by screen. `[brackets]` = data from the server or text the team must still supply. Use these strings verbatim; do not paraphrase. Example names and numbers in the mockups are synthetic.

## Copy: start, sign in, shipper

Every visible string, by screen. Brackets mark text the team still has to supply. Placeholders in examples (names, numbers) are synthetic.

### Formats (every screen)

| Thing | Format | Never |
|---|---|---|
| Date | 18 Oct · 18 – 19 Oct · 18 Oct 2026 when the year is not this year, or in a form | 2026-10-17, 10/17 |
| A trip's dates | Leaves 18 – 19 Oct · Leaves 18 Oct when both are one day. The first and last day the truck can leave (windowStart, windowEnd), India time. Mid-sentence: "leaves 18 – 19 Oct" (Rishabh, 19 Oct 2026) | Arrives by, any arrival or delivery date |
| Time | 16:40 IST (24-hour) | 7:41 AM |
| Money | ₹2,640 (Indian grouping, no paise unless paise matter, tabular figures) | ₹4704.35 net, "Net to carrier: ₹45" |
| Weight, room | 80 kg · Room left: 105 kg | Capacity 1000 kg (895 kg reserved) |
| Shipment name | Route plus date: "Bengaluru to Chennai, 18 Oct" | SHP_4135, any internal ID |
| Copyable IDs | Mono face. Bill numbers shown as 3412 0098 7654, copied without spaces | Body face for IDs |

### Start, sign in, code, account menu

| Element | Copy | Notes |
|---|---|---|
| Start title | How do you use NaviG8r? | Replaces the Flutter logo screen |
| Start sub | Choose one. You can add the other later from the account menu. |  |
| Choice 1 | I ship goods · Book space on a carrier's trip and follow it to delivery. | Question 2: one app or two |
| Choice 2 | I carry goods · For truck owners, dispatchers and drivers. |  |
| Start footer | Already have an account? Either choice signs you in with your phone number. · New carrier? Sign in first, then register your company. | "Developer lab" removed from release builds |
| Sign-in title, sub | Sign in with your phone · We send a 6-digit code to this number by SMS. |  |
| Field, help, button | Mobile number · 10 digits. Standard SMS rates may apply. · Send code | +91 shown as a fixed prefix |
| Role reminder | Signing in to ship goods. · I carry goods instead |  |
| Code screen | Enter the code · We sent a 6-digit code to +91 98450 12345. · 6-digit code · The code fills in by itself if your phone reads the SMS. · Sign in | No "Challenge id" field |
| Resend | No SMS yet? You can ask for a new code in 0:24. · Send a new code · Change number | A real timer, not urgency |
| Code errors | That code is not right. Check the SMS and type it again, or send a new code. · This code has expired. Send a new code. | role="alert" |
| Code loading | Signing you in | On the button |
| Account menu | [Name] · [full phone] · YOUR COMPANIES · [Company] [Role] · Add a company · Register as a carrier, or join one · Sign out · Close | The only place for switching and sign-out |

### Shipper home, Find a lane

| Element | Copy | Notes |
|---|---|---|
| Header | [Company] · [Person] · [Role: Shipper, Owner, Dispatcher, Driver] |  |
| Home | Home · NEEDS YOU · [the next task, e.g. "Make the e-way bill"] · [route, date, who did what] · Open shipment · Your shipments · Updates · [n] new since yesterday · Find a lane for new goods | Nothing needs you: card hidden; Find a lane becomes primary |
| Lanes title, sub | Find a lane · Pick a lane going your way. |  |
| Switch | Browse all · Match my route |  |
| Browse note | Every open lane, not sorted by distance. To see the closest to your route first, use Match my route. | Browse is not ranked |
| Match form | Pickup · Drop (place boxes: City or area · search · map pin) · Weight · Find matching lanes · Enter the [pickup \| drop] place. · Search for the [pickup \| drop] place. | Same place box as Publish (Rishabh, 19 Oct 2026) |
| Match result line | [n] lanes with room for [weight] kg, closest to your route first. | Announced |
| Lane card | [From] to [To] · [Carrier] · [Size] truck · Leaves · Room left · [Open \| Full] | Full lane: "Room left: None" |
| Empty, match | No lanes pass near this route with room for [weight] kg. · Try a lower weight, or browse all lanes. · Change weight · Browse all lanes |  |
| Empty, browse | No lanes are open right now. · New lanes appear here when carriers publish them. |  |
| Loading, error | Loading lanes. · Could not load lanes. Check your connection, then try again. · Try again |  |

### Book and pay

| Element | Copy | Notes |
|---|---|---|
| Title, sub | Book space · Check the price, then pay. |  |
| Lane | [From] to [To] · [Carrier] · Leaves [dates] · Room left: [n] kg |  |
| Fields | Weight · Up to [room] kg on this lane. · Pickup · Drop (place boxes: City or area · search · map pin) | Start at the searched values and pins, else empty. Same place box as Publish |
| Price | Price · ₹[amount] · After you pay, [Carrier] accepts and names the truck. · Pay opens the payment provider's screen, where you choose how to pay. · Changing weight, pickup or drop gets a new price. | Fetched by itself once weight, pickup and drop are in (Rishabh, 19 Oct 2026). Tax line only if question 5 says so |
| Above Pay | This is the full price. Nothing is added at payment. · Your payment is held when you book and collected after delivery. Booked shipments cannot be cancelled in the app; to change one, contact [NaviG8r contact]. | Open item 6 (contact) |
| Button | Pay ₹[amount] · while fetching: Getting the price · after a price error: Try again · before a price, disabled: Pay, with "To see the price, enter the weight and search for the pickup and drop." (only the missing parts) or "Enter a lower weight to see the price." | One tap opens the payment provider; the confirm sheet is gone (Rishabh, 19 Oct 2026) |
| Too heavy | This lane does not have room for that weight. Enter a lower weight, or choose another lane. · Choose another lane | Replaces "HTTP 400" |

```
DARK PATTERN SCREEN — Book: price by itself, Pay in one tap, no confirm sheet — 2026-10-19
Screened: the Book and pay rows above, after Rishabh's 19 Oct call (maps on Match and Book,
  no Get price, no confirm sheet)
Verdict: BLOCKED until Rishabh decides finding 1
Passes: 1 actionability (Pay only for an open lane with room for the weight); 2 no comparison;
  3 full cost: the quote has one part, the total, and the server adds nothing (booking
  recomputes the same price), so the total on Pay plus "This is the full price. Nothing is
  added at payment." beside it is the whole cost; tax stays the open question 5 below;
  4 no urgency; 5 no defaults, fields start empty or at the shipper's own search;
  7 no decline button, "Choose another lane" and "Try again" are neutral; 8 the price goes
  the moment weight or a pin changes and a late answer for older inputs is dropped, so Pay
  always names the price of what is on screen; 9 nothing new asked for; 10 no payout;
  11 "we show you the full price as soon as weight and both places are in; one tap on
  Pay books the space and opens the payment provider; you cannot cancel in the app, so
  the contact is beside Pay" can be said to the shipper's face.
Findings:
  1. 6 Exit — FAIL — one tap on Pay now creates the booking and reserves the room, while
     cancelling still needs NaviG8r contact (no shipper cancel, decided 17 Oct). The removed
     sheet was the only step between a slip of the finger and an uncancellable booking; a
     closed payment screen leaves an unpaid booking. Fix options: Rishabh accepts it with
     the reason written here, or the booking is made only after the payment provider
     succeeds, or a shipper can cancel an unpaid booking in the app.
Accepted risks: none yet
Open check: the label booked is the words in the place box; if the shipper types new words
  without searching, the pin (and the price) stay at the old place under the new name. The
  map shows the pin, but nothing stops it.
```

### Shipment screen and e-way bill

| Element | Copy | Notes |
|---|---|---|
| Summary | [From] to [To] · [Status] · [pickup locality] to [drop locality] · [weight] · Leaves [dates] · [carrier] · Messages · Change or cancel | Title is the route, not the carrier |
| Steps | Booked and paid · Carrier accepts and names the truck · E-way bill · Bill check · On the way · Delivered | Each with who: You, [Carrier], NaviG8r staff |
| Waiting | Waiting for [Carrier] to accept. Your payment is on hold; it is collected after delivery. | Brief A.3 |
| Step 0 | Does this load need an e-way bill? · [one line from the team] · Yes, make one · No e-way bill needed · [Carrier] sees your answer before accepting. | Neither preselected |
| Before acceptance | You can make the bill once the carrier accepts and names the truck. We will send you an update. · Transporter name · [Carrier] · Carrier's transporter ID · After [Carrier] accepts · Truck number · After [Carrier] accepts · Copy all | True after PR #153. The ID and truck are sent only once accepted |
| Step 1 | Make the bill in your billing software or on the e-way bill site. Copy these in: · Transporter name · Portal field: Transporter Name · Carrier's transporter ID · Portal field: Transporter ID. Not your GSTIN. · Truck number · Portal field: Vehicle No. (Part B) · Copy all · Open the e-way bill portal · Make it on loading day, before the goods move: the bill is valid from when the truck is entered. · I have made it. Enter the details | No transporter ID: "[Carrier] has not added one. Leave Transporter ID empty. Only you, the bill's maker, can then change the truck." Copy all copies "Transporter name: · Transporter ID: · Mode: Road · Vehicle number:", one per line, only the known ones; announced "Transport details copied." Screen readers hear the button as "Copy all transport details". Hidden while none is known |
| Step 2 | E-WAY BILL · PART 2 OF 2 · Enter the bill's details · Copy these four from the bill. · E-way bill number · 12 digits, at the top of the bill. · Bill date · Your GSTIN · The GSTIN that made the bill. Not the carrier's transporter ID. · Invoice number · Save e-way bill · NaviG8r staff then check it on the portal. |  |
| Step 2 errors | [n] details need fixing before you can save. · This has [n] digits. An e-way bill number has 12. · This is the carrier's transporter ID. Enter the GSTIN that made the bill. |  |
| Step 3 | Bill [number] saved. The truck is not on it yet. · Add the truck in your billing software or on the e-way bill site before the goods move, then enter it here. · The step 1 rows and Copy all, with the truck's field as Portal: Update Part B, Vehicle No. · The bill's validity starts when the truck is added: one day per 200 km, ending at midnight India time. · Add truck | Shipper only; the carrier only reads the bill (decisions.md, 18 Oct 2026) |
| Step 4 | E-way bill saved. Nothing more for you to do until delivery. · NaviG8r staff check the bill on the portal by hand. We will tell you if anything needs fixing. |  |
| Step 4 problem | E-way bill needs a fix · NaviG8r staff found a difference · The [field] on the portal's bill is [value]. You entered [value]. · If the portal is right, fix it here. If the bill itself is wrong, change it in your billing software or on the e-way bill site first. · Fix the details · Ask NaviG8r staff |  |
| Footnote | NaviG8r never makes or changes an e-way bill. You make it in your billing software or on the e-way bill site. | Once per screen, small |
| Not needed | E-way bill: not needed · You said so on [date]. [Carrier] saw this before accepting. · Change |  |
| On the way | Left [pickup] on [date] at [time] IST. [Carrier] confirms when it is delivered. · Message [Carrier] |  |
| Delivered | [Carrier] confirmed delivery and added proof of delivery. Your payment of ₹[amount] is collected now. · View proof of delivery · Book another shipment | Open item 8 (payment issue) |
| Cancelled | This shipment was cancelled · NaviG8r operations cancelled it on [date] at your request. · You paid · Refunded · Refunds reach your account in the time your bank or payment app takes. · Questions about this refund? Contact [NaviG8r contact]. | Replaces the system code |
| Updates | [Carrier] accepted your shipment · [Route, date]. You can make the e-way bill now. · Your shipment is on the way · E-way bill checked · Delivered · Proof of delivery is ready. | Named by route and date |

```
DARK PATTERN SCREEN — shipper e-way bill transport details and Copy all — 2026-10-18
Screened: the Before acceptance, Step 1, Step 3, Step 4 problem and Footnote rows above
Verdict: PASS
Findings: none. No ranking, cost, urgency, default, exit, decline button, money or new data
  asked for; the rows show only what the server already sends, unknown values say when they
  arrive, Copy all copies only known values, and the wording now names billing software
  as well as the site instead of implying the site is the only place.
Accepted risks: none
Open check: Transporter name is the carrier's display name in NaviG8r; if a carrier's
  display name differs from its registered name, the bill could carry the display name.
```

## Copy: carrier office and driver

Tabs for the office: Home, Bookings, Trips, Publish, Profile. Tabs for drivers: Today, Trips, Profile. Rows marked "owner only" never render for dispatchers or drivers.

### Office home, bookings

| Element | Copy | Notes |
|---|---|---|
| Home | Home · NEEDS YOU · Accept a booking · [Shipper], [weight], on your [route] trip, leaves [dates]. · Review booking · Assign a driver · [route] · Leaves [dates] · Start a trip · Today | Signed-in home has no sign-in, register or developer links. No add-truck task: the shipper adds the truck (owner decision, 18 Oct 2026) |
| Bookings list | Bookings · Needs you ([n]) · Active · Done · [Shipper] · [pickup] to [drop] · Leaves [dates] · [weight] · E-way bill: needed \| not needed · Next: [action]. · Truck not on bill · Next: [Shipper] adds the truck to the e-way bill. | Whole card opens. A bill without the truck is Active, not Needs you |
| Booking title | BOOKING · [Shipper] | Was "Proof of delivery" |
| Booking facts | Pickup · Drop · Weight · E-way bill: Needed. [Shipper] makes it. \| Not needed (shipper said so). |  |
| Steps | Accept and choose the truck · Truck on the e-way bill · Driver assigned and trip started · Confirm delivery · Payment released |  |
| Accept panel | Your [route] trip leaves [dates]. After this, [n] kg of room is left. · Accept · Decline | Decline is neutral, no guilt. Worded so Accept still shows without scrolling at 360 x 800 |
| Accept sheet | Which truck carries this trip? · [route], leaves [dates]. [Shipper] puts this truck number on the e-way bill. · Accept with this truck (disabled) · Choose a truck first. · Accept with [truck] · Cancel | No truck preselected |
| Accept result | Accepted with [truck]. [Shipper] can make the e-way bill now. · Could not accept. Check your connection and try again. | Announced |
| No trucks | You have no trucks yet. Add one to accept bookings. · Add truck |  |
| Truck on bill | [Shipper] has not added the truck to the bill yet. · Truck on the bill: [truck] · Valid until: [date], [time] IST · [ops check line] | Read only for every carrier login: no form, no pickers, no portal button (owner decision, 18 Oct 2026) |
| Confirm delivery | When the goods are handed over at [drop], add a photo of the signed delivery note, then confirm. · Proof of delivery · Add photo · Confirm delivery · Add the proof of delivery first. |  |
| Payment (owner only) | Awaiting payment release · NaviG8r operations check the proof of delivery, then release the payment to your bank account ending [4 digits]. · Shipper paid · NaviG8r commission · You receive · Only owners see payment amounts. Dispatchers and drivers do not. | All three amounts together |
| Same, dispatcher | Delivery confirmed · Nothing more for you to do on this booking. · NaviG8r operations check the proof of delivery. The owner sees the payment. | No amounts |

### Trips, publish, profile

| Element | Copy | Notes |
|---|---|---|
| Trips list | Trips · Open · In transit · Done · Leaves · Room left · Bookings · [truck] · [driver] \| No driver yet · Truck chosen when you accept the first booking | No View or Start on the card |
| Trip | TRIP · [route] · [status] · Leaves [dates] · [size] truck · Room left: [n] kg of [capacity] kg · Truck and driver · Not assigned · Assign driver · Bookings on this trip ([n]) |  |
| Start (disabled) | Start the trip · Start trip · Assign a driver first. Then start on loading day. | Start lives only here |
| Start sheet | Start [route] now? · Truck · Driver · Bookings · [Shipper]'s e-way bill does not have the truck yet. [Shipper] adds it. Without the truck, the bill is not valid for moving the goods. · Start trip · Not yet · Starting tells each shipper their goods are on the way. | Warning only when true; it informs, it does not ask the carrier to act |
| Assign sheet | Who drives this trip? · [route], leaves [dates], truck [truck]. The driver sees the trip and the e-way bill, never the payment. · Assign [name] · Cancel · Add a driver to your company | No driver preselected |
| Publish | Publish a trip · Shippers can book space on it once it is published. · From · To · [route map, pins named "From and To"] · Leaves between · and · Choose a date · Truck size: Small, Medium, Large · Room for shippers · The weight you can carry for shippers on this trip. · You choose the truck when you accept the first booking. · Publish trip · Choose the first day the truck can leave. · Choose the last day the truck can leave. | Fields start empty. The two days are the first and last day the truck can leave; there is no arrival date (Rishabh, 19 Oct 2026). The last day may be the first, never before it, and no day before today in India. The route map shows only once From and To both have a point. A screen reader hears "First day the truck can leave" and "Last day the truck can leave" |
| Profile | Company · Approved by NaviG8r · Transporter ID · Your GSTIN, or a TRANSIN if you have no GST registration. Shippers copy it into their e-way bills. It is not the shipper's GSTIN. · Trucks ([n]) · Add truck · Drivers ([n]) · Add driver · Manage drivers · Bank details (owner only) · Account ending [4 digits] · Team · Invite · Dispatchers accept bookings and assign drivers. They do not see payments. | No developer lab |
| Truck | Truck · Registration number · As on the registration certificate. Spaces are removed for the e-way bill. · Truck size · [Size guide from the team] · Save truck · Remove this truck · You are asked to confirm before anything is removed. · Remove truck | Replaces "Vehicle class (SMALL\|MEDIUM\|LARGE)" |

```
DARK PATTERN SCREEN — a trip's dates as a departure window, and the Publish route map — 2026-10-19
Screened: the "A trip's dates" format row, and the Lane card, Lane, Confirm sheet, Summary,
  Home, Bookings list, Accept panel, Accept sheet, Trips list, Trip, Assign sheet and Publish rows
Verdict: PASS
Findings: none. No ranking, cost, urgency, exit, decline button, money or new data changes.
  No day is chosen for the carrier; the route map only shows the two places already entered.
  The words now promise less, not more: they say when the truck can leave and never imply an
  arrival, where a single date before read as the day it goes.
Accepted risks: none
Open check: the server does not close or hide a trip once its last leaving day has passed,
  so a lane can still show "Leaves 18 – 19 Oct" and take bookings after 19 Oct.
```

### Driver

| Element | Copy | Notes |
|---|---|---|
| Today | Today · [weekday] [date] · [route] · Ready to start · Truck · Pickups · Drops · Open today's trip · Next | No money anywhere |
| No trip | No trip today. · Your office assigns trips. They appear here. | Empty state |
| Trip | In transit · Show e-way bills · NEXT STOP · DROP [n] OF [n] · [place] · [Shipper] · [weight] · Directions · I am here: confirm delivery · All stops | Start trip appears here before the trip starts |
| E-way bills | E-way bills · Truck [truck] · [Shipper] · Drop [n] · [bill number] · Valid until [date], [time] IST · This truck is not on this bill. Call your office now so they can add it. · Call [Carrier] | Large mono numbers |
| Confirm | Confirm delivery · 1. Photo of the signed delivery note · Photo added · Take again · 2. Confirm the goods are handed over · [Shipper] gets the photo as proof of delivery. · Confirm delivery |  |
| Done | Delivery confirmed · [place] · [Shipper] · [time] IST | Announced; next stop follows |
| Profile | Profile · Name · Phone · Company · Role · Call your office · Help from NaviG8r · Sign out · Your office changes your trips and the truck. Ask them if something is wrong. | No bank, earnings or payouts |
| Offline | No signal. Showing what was saved at [time] IST. · Could not confirm: no signal. Try again when you have one. | Saved copy only if the app already keeps one; no offline queue is promised |
