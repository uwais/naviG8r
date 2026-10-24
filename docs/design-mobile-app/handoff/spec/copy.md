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
| App name | NaviG8r, on the web and on Android (23 Oct 2026) | NaviG8r Customer, NaviG8r Driver |

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
| Home | Home · NEEDS YOU · [the next task, e.g. "Make the e-way bill"] · [route, date, who did what] · Fix the e-way bill with "The trip cannot start until the truck and valid-until time on the bill are right." (a bill whose truck is not the trip's, or whose valid-until time has passed; Next: You check the truck and valid-until time on the e-way bill; status E-way bill needs a fix). Shown only when the shipment's trip status is known and the login may both write the bill and add the truck; before the carrier accepts, the e-way bill step waits (later), not a problem · Open shipment · Your shipments · Updates · [n] new since yesterday · Find a lane for new goods | Nothing needs you: card hidden; Find a lane becomes primary |
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
| Title | Book this trip | No subtitle (Uwais, 22 Oct 2026: too verbose; owner approved the shorter screen) |
| Lane | [From] to [To] · [Carrier] · Leaves [dates] · Room left: [n] kg |  |
| Fields | Weight · Up to [room] kg on this lane. · Pickup · Drop (place boxes: City or area · search · map pin) | Start at the searched values and pins, else empty. Same place box as Publish |
| Price | Price · ₹[amount] · [Carrier] accepts after you pay. NaviG8r holds your payment and releases it after delivery. | "The carrier" when the lane names none. Fetched by itself once weight, pickup and drop are in (Rishabh, 19 Oct 2026). Tax line only if question 5 says so. Typing new words in a place box after its search drops that place's pin and the price, and the line under the button asks to search for it; after a pin drag, the typed name stays with the pin |
| Above the button | To cancel, contact hello@navig8r.org. · Full price. Nothing is added at payment. | The cancel line comes first, so it is the part that shows at very large text; at very large text both lines scroll inside the bar. A screen reader hears a new price as "Price for [weight]: [amount] rupees. Full price. Nothing is added at payment." Open item 6 (contact): the owner chose the address |
| Button | Book and pay ₹[amount] · while fetching: Getting the price · after a price error: Try again · before a price, disabled: Book and pay, with "To see the price, enter the weight and search for the pickup and drop." (only the missing parts) or "Enter a lower weight to see the price." · after a pin drag, disabled until the pin is named: "Updating address from pin…" | One tap books and opens the payment provider; the confirm sheet is gone (Rishabh, 19 Oct 2026). While the booking is sent, weight, pickup and drop cannot be changed |
| Too heavy | This lane does not have room for that weight. Enter a lower weight, or choose another lane. · Choose another lane | Replaces "HTTP 400" |
| Paid after the trip left | This trip has already left. If your bank shows a payment, it comes back within 3 days. | The server's own sentence (409 trip_already_started) when the payment comes back after the trip started (owner, 23 Oct 2026). Shown and read out, then the shipment opens on "This trip left without your shipment". Never "Booked" |

```
DARK PATTERN SCREEN — Book: price by itself, Book and pay in one tap, no confirm sheet — 2026-10-19
Screened: the Book and pay rows above, after Rishabh's 19 Oct calls (maps on Match and Book,
  no Get price, no confirm sheet; then the "Book and pay" label and the cancel line)
Verdict: PASS, with finding 1 accepted by Rishabh
Passes: 1 actionability (Book and pay only for an open lane with room for the weight);
  2 no comparison; 3 full cost: the quote has one part, the total, and the server adds
  nothing (booking recomputes the same price), so the total on the button plus "This is the
  full price. Nothing is added at payment." beside it is the whole cost; tax stays the open
  question 5 below; 4 no urgency; 5 no defaults, fields start empty or at the shipper's own
  search; 7 no decline button, "Choose another lane" and "Try again" are neutral; 8 the price
  goes the moment weight or a pin changes, or a place box gets new words after its search,
  and a late answer for older inputs is dropped, so the button always names the price of
  what is on screen, and the place booked is the place priced; 9 nothing new asked for;
  10 no payout; 11 "we show you the full price as soon as weight and both places are in;
  one tap on Book and pay books the space, which holds the room, and opens the payment
  provider; you cannot cancel in the app, so the line above the button says to contact
  NaviG8r" can be said to the shipper's face.
Findings:
  1. 6 Exit — FAIL, accepted — one tap creates the booking and holds the room, while
     cancelling still needs NaviG8r (no shipper cancel). The label "Book and pay ₹[amount]"
     and the line "Booking holds the room on this lane. To cancel, contact NaviG8r." directly
     above it say both before the tap.
Accepted risks: finding 1 — Rishabh, 19 Oct 2026: one tap books and opens payment, and the
  label and the line say so; shipper cancel is not built (his 17 Oct call).
Re-screened 22 Oct 2026: the subtitle, payment-partner, price-change and capacity lines were
  cut; the basis is now the Book and pay label, the carrier-accepts line and the cancel line.
Open checks: "contact NaviG8r" names no phone number or email; the app has none to show yet
  (open item 6). The line "Your payment is held when you book and collected after delivery."
  is no longer on Book; the shipment screen says it while the booking waits for the carrier.
```

### Shipment screen and e-way bill

| Element | Copy | Notes |
|---|---|---|
| Summary | [From] to [To] · [Status] · [pickup locality] to [drop locality] · [weight] · Leaves [dates] · [carrier] · Messages · Change or cancel | Title is the route, not the carrier |
| Steps | Booked and paid · Carrier accepts and names the truck · E-way bill · Bill check · On the way · Delivered | Each with who: You, [Carrier], NaviG8r staff |
| Waiting | Waiting for [Carrier] to accept. | The hold is on the Booked step: "₹[amount] held by NaviG8r until after delivery" (copy trim, 22 Oct 2026) |
| Waiting, cancel requested | [Carrier] asked to cancel this trip. NaviG8r will tell you if your shipment is cancelled. Your payment is on hold. | When the booking's trip is `CANCEL_REQUESTED`, read from the trip the tracking call returns. The server refuses Accept on such a trip, so "Waiting for [Carrier] to accept" would be false. "Your payment is on hold." only when it is held |
| Step 0 | Does this load need an e-way bill? · [one line from the team] · Yes, make one · No e-way bill needed · [Carrier] sees your answer before accepting. | Neither preselected |
| Before acceptance | Make the bill after [Carrier] accepts. We will tell you. · Transporter name · [Carrier] · Carrier's transporter ID · After [Carrier] accepts · Truck number · After [Carrier] accepts · Copy all | True after PR #153. The ID is sent only once accepted. When the trip already names its truck (owner, 22 Oct 2026), the same lead line and the truck row shows the number with Copy. No note that the carrier can change it (owner, 23 Oct 2026). |
| Step 1 | Make the bill on loading day, in your billing software or on the portal. Copy in these details: · Transporter name · Portal field: Transporter Name · Carrier's transporter ID · Portal field: Transporter ID. Not your GSTIN. · Truck number · Portal field: Vehicle No. (Part B) · Copy all · Open the e-way bill portal (in the step on a desktop) · The trip cannot start until the bill is here, or you say none is needed. · I have made it. Enter the details | No transporter ID: "[Carrier] has not added one. Leave Transporter ID empty. Only you, the bill's maker, can then change the truck." Copy all copies "Transporter name: · Transporter ID: · Mode: Road · Vehicle number:", one per line, only the known ones; announced "Transport details copied." Screen readers hear the button as "Copy all transport details". Hidden while none is known |
| Step 2 | E-WAY BILL · PART 2 OF 2 · Enter the bill's details · Copy these four from the bill. · E-way bill number · 12 digits, at the top of the bill. · Bill date · Your GSTIN · The GSTIN that made the bill. Not the carrier's transporter ID. · Invoice number · Save e-way bill · NaviG8r staff then check it on the portal. |  |
| Step 2 errors | [n] details need fixing before you can save. · This has [n] digits. An e-way bill number has 12. · This is the carrier's transporter ID. Enter the GSTIN that made the bill. |  |
| Step 3 | Bill [number] saved. The truck is not on it yet. · Add the truck on the portal, then here. The trip cannot start until you do. (Before acceptance: Add the truck after [Carrier] accepts.) · The step 1 rows and Copy all, with the truck's field as Portal: Update Part B, Vehicle No. · The bill runs one day per 200 km from when the truck is added, to midnight India time. · Add the truck on the portal first. Then copy the truck number and valid-until time here. (the truck form) · Add truck | Shipper only; the carrier only reads the bill (decisions.md, 18 Oct 2026) |
| Step 4 | E-way bill saved. Nothing more for you to do until delivery. · The valid-until time you entered has passed, so the trip cannot start. Check the bill on the portal, then enter the new time here. (shipper, once the time has passed; carrier and driver: The valid-until time has passed. Check the bill on the portal.) |  |
| Step 4 problem | E-way bill needs a fix · NaviG8r staff found a difference · The [field] on the portal's bill is [value]. You entered [value]. · If the bill is wrong, fix it on the portal first. Then fix it here. · Fix the details · Ask NaviG8r staff |  |
| Footnote | NaviG8r does not make or change e-way bills. | Once per screen, small |
| Not needed | E-way bill: not needed · You said so on [date]. [Carrier] saw this before accepting. · Change |  |
| Remove the bill | Remove the e-way bill? · Keep it · Remove | Asked after Remove e-way bill is tapped, before anything is sent (23 Oct 2026). Remove e-way bill is not offered once the trip is on the way, and the server refuses it then: The trip has started, so the e-way bill cannot be removed. Edit the bill and Change stay (owner, 23 Oct 2026) |
| On the way | Left [pickup] on [date] at [time] IST. [Carrier] confirms when it is delivered. · Message [Carrier] |  |
| Delivered | [Carrier] confirmed delivery and added proof of delivery. Your payment of ₹[amount] is collected now. · View proof of delivery · Book another shipment | Open item 8 (payment issue) |
| Proof of delivery, full size | This photo cannot be shown. | When a photo opened full size cannot be shown (23 Oct 2026). The same words as in the list of photos |
| Messages, closed | Messages are closed for this shipment. (carrier: Messages are closed for this booking.; anyone else: Messages are closed.) | When a send is refused because messages closed since the screen loaded (409 conversation_read_only). The conversation loads again, so the closed banner shows at once. Until the first load says a reply may be sent, there is no message box (23 Oct 2026) |
| Cancelled | This shipment was cancelled · NaviG8r operations cancelled it on [date] at your request. · You paid · Refunded · Refunds reach your account in the time your bank or payment app takes. · Questions about this refund? Contact [NaviG8r contact]. | Replaces the system code |
| Cancelled, hold released | This shipment was cancelled · NaviG8r never collected this payment. It comes back within 3 days of when you paid. Your bank may take 5-7 more working days. · Questions about this payment? Contact [NaviG8r contact]. | Payment `HOLD_RELEASED`: no "You paid", no refund lines (Rishabh, 19 Oct 2026). Never "never taken": with UPI or netbanking the shipper's bank is debited when they pay; "held" only means NaviG8r has not collected it |
| Cancelled, collected after cancel | This shipment was cancelled · Your payment came in after the cancel. NaviG8r is refunding it. Your bank may take 5-7 working days. · Questions about this refund? Contact [NaviG8r contact]. | Payment `CAPTURED_AFTER_CANCEL`: Razorpay collected it after the cancel and Finance refunds it in Razorpay. Once Finance marks it refunded it reads as Cancelled (`REFUNDED`) |
| Cancelled, bill made | Made an e-way bill? Cancel it on the portal within 24 hours of making it. · If you made an e-way bill for this load, it is over 24 hours old, so the portal no longer lets you cancel it. | Only when a bill was entered. NaviG8r never cancels the bill. The second sentence when the bill's date is before yesterday in India: only the date is known, not the time, so a bill dated today or yesterday may still be inside its 24 hours and gets the first. The 24 hours: CGST rule 138(9), via the GST Council's e-way bill flyer; the current rule text was not re-read |
| Closed, trip left | This trip left without your shipment · You were not charged. · Questions about this shipment? Contact [NaviG8r contact]. · Book a trip | The trip started before the shipper finished paying, so the server closed the booking (owner, 23 Oct 2026; `leftBehindAtUtcMs` set). Replaces "This shipment was cancelled" and "Nothing was paid for this shipment."; the money lines of the other Cancelled rows still apply if a payment came in. Status word stays Cancelled, never Waiting for carrier |
| Update: trip left | This trip left without your shipment · If your bank shows a payment, it comes back within 3 days. Book another trip when you are ready. | To shipper logins only, when the trip starts without the booking. If Razorpay had already collected it: NaviG8r is refunding your payment. Your bank may take 5-7 working days. The shipper hears no Trip started or Trip completed for it |
| Update: cancelled | Shipment cancelled · The carrier cannot carry your load from [From] to [To], so it was cancelled. + one of: NaviG8r never collected this payment. Razorpay returns it within 3 days of when you paid; your bank may take 5-7 working days after that. · Your refund has started. · Nothing was charged. | Sent when Finance cancels the shipment; the carrier's office and driver read "NaviG8r cancelled this shipment on your trip." "Nothing was charged." only for a payment never made (`CREATED` or `FAILED`) |
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

```
DARK PATTERN SCREEN — Remove the bill question and the full-size photo error — 2026-10-23
Screened: the Remove the bill and Proof of delivery, full size rows above
Verdict: PASS
Findings: none. 1 actionability, 2 comparison, 3 cost, 4 urgency, 9 data, 10 money: N/A, nothing
  ranked, priced, timed, asked for or paid. 5 defaults: no choice is preselected; closing the
  question keeps the bill. 6 exit: Keep it and closing the question are as easy as Remove. 7 decline
  copy: "Keep it", neutral. 8 promise: Remove removes the bill as the button did before; the photo
  line says only that it cannot be shown. 11 reversal: "we ask once before removing your bill, and
  say so when a photo cannot be shown" is fine to say to the shipper.
Accepted risks: none
```

## Copy: carrier office and driver

Tabs for the office: Home, Bookings, Trips, Publish, Profile. Tabs for drivers: Today, Trips, Profile. Rows marked "owner only" never render for dispatchers or drivers.

### Office home, bookings

| Element | Copy | Notes |
|---|---|---|
| Home | Home · NEEDS YOU · Accept a booking · [Shipper], [weight], on your [route] trip, leaves [dates]. · Review booking · Assign a driver · [route] · Leaves [dates] · Start a trip · Waiting for [Shipper]'s e-way bill · Waiting for e-way bills (in place of Start a trip while a bill is not final; listed under NEEDS YOU only when the office can change the trip's truck, otherwise under the heading Waiting on shippers) · Waiting on shippers · Nothing needs you right now. · Today | Signed-in home has no sign-in, register or developer links. No add-truck task: the shipper adds the truck (owner decision, 18 Oct 2026). No Start a trip and no Waiting line for a trip while a booking on it waits to be accepted: its Accept a booking task is the next step (owner, 23 Oct 2026). A waiting booking the server marks not ready to accept (the shipper has not finished paying) does not hold the trip, and has no Accept a booking task (owner, 23 Oct 2026) |
| Bookings list | Bookings · Needs you ([n]) · Active · Done · [Shipper] · [pickup] to [drop] · Leaves [dates] · [weight] · E-way bill: needed \| not needed · Next: [action]. · Truck not on bill · Next: [Shipper] adds the truck to the e-way bill. · Waiting for the shipper | Whole card opens. A bill without the truck is Active, not Needs you. Waiting for the shipper is the status of a waiting booking the server marks not ready to accept; it never says payment, since dispatchers read it (owner, 23 Oct 2026) |
| Booking title | BOOKING · [Shipper] | Was "Proof of delivery" |
| Booking facts | Pickup · Drop · Weight · E-way bill: Needed. [Shipper] makes it. \| Not needed (shipper said so). |  |
| Steps | Accept and choose the truck · Truck on the e-way bill · Driver assigned and trip started · Confirm delivery · Payment released |  |
| Accept panel | Your [route] trip leaves [dates]. After this, [n] kg of room is left. · Accept · Decline | Decline is neutral, no guilt. Worded so Accept still shows without scrolling at 360 x 800 |
| Accept sheet | Which truck carries this trip? · [route], leaves [dates]. [Shipper] puts this truck number on the e-way bill. · Accept with this truck (disabled) · Choose a truck first. · Accept with [truck] · Cancel | No truck preselected |
| Accept result | Accepted with [truck]. [Shipper] can make the e-way bill now. · Could not accept. Check your connection and try again. | Announced |
| Accept, trip started | Accept (disabled) · This trip is already on the way, so it cannot take this booking. | When the trip is In transit or Done (owner, 23 Oct 2026). The server's own sentence for its refusal (409 trip_already_started), so a tap on an out-of-date screen shows the same words. Same on the driver's booking screen, under Accept booking |
| Accept, waiting for the shipper | Accept (disabled) · Waiting for the shipper. | Office booking screen, when the server marks the waiting booking not ready to accept (the shipper has not finished the booking). No payment words: dispatchers read it (owner, 23 Oct 2026) |
| No trucks | You have no trucks yet. Add one to accept bookings. · Add truck |  |
| Truck on bill | [Shipper] has not added the truck to the bill yet. · Truck on the bill: [truck] · Valid until: [date], [time] IST · [ops check line] | Read only for every carrier login: no form, no pickers, no portal button (owner decision, 18 Oct 2026) |
| Confirm delivery | When the goods are handed over at [drop], add a photo of the signed delivery note, then confirm. · Proof of delivery · Add photo · Confirm delivery · Add the proof of delivery first. |  |
| Payment (owner only) | Awaiting payment release · NaviG8r operations check the proof of delivery, then release the payment to your bank account ending [4 digits]. · You receive · Only owners see payment amounts. Dispatchers and drivers do not. | Only the carrier's own amount. Never the shipper's price or NaviG8r's cut (owner hard rule, 21 Oct 2026) |
| Same, dispatcher | Delivery confirmed · Nothing more for you to do on this booking. · NaviG8r operations check the proof of delivery. The owner sees the payment. | No amounts |

### Trips, publish, profile

| Element | Copy | Notes |
|---|---|---|
| Trips list | Trips · Open · In transit · Done · Leaves · Room left · Bookings · [truck] · [driver] \| No driver yet · Truck chosen when you accept the first booking · Cancel requested (under Open) · Cancelled (under Done) | No View or Start on the card |
| Cancel, no bookings | Cancel this trip · Cancel this trip? · Shippers will no longer see or book it. You can publish a new trip any time. This cannot be undone. · Keep trip · Cancel trip · Trip cancelled. Shippers can no longer see or book it. · This trip has bookings, so it cannot be cancelled here. | Office logins that may assign trips, on an Open or Full trip with no booking. The question is in the page, never a dialog; Keep trip comes first and has the focus. Cancel this trip and Cancel trip are the destructive style |
| Ask to cancel, bookings | Ask NaviG8r to cancel · Why do you want to cancel this trip? · Shippers cannot book the trip now. NaviG8r reviews your request. Shippers already booked are told if their shipment is cancelled. · Truck not available · Driver not available · Route changed · Other reason · Note (optional) · Send request (disabled) · Choose a reason first. · Send request · Keep trip · Keep the note to 500 characters or fewer. | A sheet. No reason preselected; the note is never required |
| Cancel requested | You asked NaviG8r to cancel this trip. Shippers cannot book it now. NaviG8r reviews your request. Shippers already booked are told if their shipment is cancelled. · You asked NaviG8r to cancel this trip, so it cannot take this booking. Withdraw the request first. (on a waiting booking's Accept) · Withdraw request · Withdraw your request? · Shippers can book this trip again while it has room. · Keep request · Withdraw request · Request withdrawn. Shippers can book this trip again while it has room. | Withdraw only for logins that may assign trips; its question is in the page, Keep request first and focused. The Accept line is the app's own, for the office; the server's refusal, which drivers also read, is "This trip's carrier asked NaviG8r to cancel it, so it cannot take this booking now." |

```
DARK PATTERN SCREEN — carrier trip cancel: cancel an empty trip, ask NaviG8r, withdraw, held money on cancel — 2026-10-19
Screened: the Cancel no bookings, Ask to cancel, Cancel requested and Trips list rows above;
  the shipper's Cancelled hold released, Cancelled bill made and Update cancelled rows; the
  /ops/beta "Trip cancel requests" card (Cancel shipment… · Cancel shipment [id] for [Shipper]?
  [amount sentence] The shipper is told. This can't be undone from the console. · Keep shipment
  · Cancel shipment · Finance cancels each shipment. You hold [roles].). Written with the build
  on 19 Oct from Rishabh's brief, not before it.
Verdict: PASS
Passes: 1 actionability: each button shows only when the server would allow it (Open or Full,
  trip.assign, bookings or none), and a refusal for a booking that arrived meanwhile says so and
  offers Ask instead; 2 no comparison; 3 no cost to the carrier exists, and the shipper's words
  say what happens to the money in each of the three cases; 4 no urgency; 5 no defaults: no
  reason preselected, Keep is the focused answer; 6 exit: an empty-trip cancel says "This
  cannot be undone." before the tap; a request can be withdrawn from the same screen, behind
  the same kind of question; 7 decline copy is neutral: Keep trip, Keep request, Keep shipment;
  8 "Shippers cannot book it now" and "Shippers will no longer see or book it" match the
  server (off the public list and Match, booking refused); 9 data asked: one required reason
  from a fixed list of four, "Other reason" included so no one is forced into a false one, and
  an optional note labelled optional, capped at 500 characters, seen only by NaviG8r staff;
  10 no payout involved; 11 "if no one booked, you can take the trip back yourself; if
  someone did, you tell us why and we contact them and cancel each booking; you can take the
  request back until then" can be said to the carrier's face.
Findings: none
Accepted risks: none
Open checks: "NaviG8r will contact the shippers already booked" promises a person acting;
  nothing in the app does it except the cancel notification Finance's action sends, so ops
  must own that step. "Razorpay releases it within 3 days of when you paid" rests on Razorpay's
  docs as read on 19 Oct 2026, not on a live test. A booking still waiting on a requested trip
  can be accepted by the carrier.
```

```
DARK PATTERN SCREEN — carrier trip cancel, copy changed after review — 2026-10-19
Screened: the rows changed after review: Cancelled hold released and Update cancelled ("NaviG8r
  never collected this payment..."), Cancelled bill made (the 24-hour line), Ask to cancel and
  Cancel requested ("NaviG8r reviews your request. Shippers already booked are told if their
  shipment is cancelled."), and the Accept refusal on a requested trip.
Verdict: PASS
Passes: 1 actionability: the Accept refusal names the one step that unblocks it (withdraw), and
  the bill line tells the shipper the limit while they can still act; 2 N/A; 3 the money words
  no longer deny a bank debit the shipper may see ("never taken" was false for UPI and
  netbanking); 4 the 24-hour limit is a real, material deadline from CGST rule 138(9), not a
  manufactured one; 5 N/A, no default changed; 6 withdraw is unchanged; 7 decline copy
  unchanged (Keep trip, Keep request, Keep shipment); 8 the contact promise now matches what the
  system does, the cancel notification when Finance acts, and the old open check about it is
  closed; accepting or confirming delivery on a requested trip is refused, closing that check
  too; 9 N/A; 10 N/A; 11 "we tell you if your shipment is cancelled, NaviG8r never collected
  the held money and Razorpay returns it" can be said to the shipper's face.
Findings: none
Accepted risks: none
Open checks: the 24-hour rule was taken from the GST Council flyer citing rule 138(9); the
  current rule text was not re-read. If Razorpay captures a held payment after the cancel
  (account auto-capture), "NaviG8r never collected this payment" becomes false for that
  shipper; the server records it as CAPTURED_AFTER_CANCEL for Finance to refund, but the
  shipper is not told again.
```

```
DARK PATTERN SCREEN — trip cancel second review: role-neutral refusals, money after cancel, bill age — 2026-10-19
Screened: Waiting cancel requested, Cancelled collected after cancel, Cancelled bill made (both
  sentences), the driver's Booking cancel requested row, the server's two refusal sentences in
  the Cancel requested notes, and the /ops/beta card's new words (Mark refunded in Razorpay… ·
  Mark payment [id] of [amount] as refunded? Do this only once you have refunded it in the
  Razorpay dashboard. The shipper's screen then says it is refunded. This can't be undone from
  the console. · Not yet · Mark refunded · Marked refunded by you at [time]. This leaves the
  list on the next reload. · Money collected after cancel. Refund it in the Razorpay dashboard,
  then mark it refunded here. · Money collected after cancel. Finance refunds this in the
  Razorpay dashboard. · Settled outside NaviG8r · This load's payment is settled outside
  NaviG8r through the partner's system, so it cannot be cancelled here. Ask the carrier to
  withdraw the request, or settle it with the partner.). Written with the build on 19 Oct from
  the review brief, not before it.
Verdict: PASS WITH CHANGES
Passes: 1 actionability PASS: a driver is no longer told to withdraw a request they cannot
  withdraw; Accept and Confirm delivery are off with the reason; the ERP row names the two
  steps that can settle it, and a bill too old to cancel is no longer sent to the portal to
  try; 2 comparison N/A; 3 cost PASS: the late-capture line says the money came through and is
  being refunded, with the bank's time after the refund; 4 urgency PASS: the 24-hour limit is
  the real rule, and the over-24-hours sentence shows only once the date proves it; 5 defaults
  PASS: no default, Not yet has the focus; 6 exit PASS after the change below; 7 decline copy
  PASS: Not yet is neutral; 8 promise PASS with an open check: "Waiting for [Carrier] to
  accept" is gone where the server refuses Accept, "Your payment is on hold." shows only when
  it is held, and the shipper whose money arrived after the cancel is now told (closing the
  open check above); 9 data N/A, nothing new is asked; 10 money N/A; 11 reversal PASS: "your
  carrier asked us to cancel the trip, we review it and tell you; money that arrived after a
  cancel is being refunded" can be said to the shipper's face.
Findings:
  1. 6 Exit — FAIL — Mark refunded did not say it cannot be undone from the console, though it
     cannot, and a wrong mark tells the shipper they were refunded — the question now ends
     "This can't be undone from the console.", as Cancel shipment's does.
Accepted risks: none
Open checks: "NaviG8r is refunding it" promises a person acting: Finance refunds in the
  Razorpay dashboard; nothing refunds it automatically, and nothing checks that Razorpay did
  before Mark refunded. A bill dated yesterday may already be past its 24 hours (only its date
  is known), so it still gets the cancel sentence, which states the limit.
```
| Trip | TRIP · [route] · [status] · Leaves [dates] · [size] truck · Room left: [n] kg of [capacity] kg · Truck and driver · Not assigned · Assign driver · Bookings on this trip ([n]) |  |
| Start (disabled) | Start the trip · Start trip · Assign a driver first. Then start on loading day. · Waiting for you to accept a booking. (driver: Waiting for your office to accept a booking.) · Choose a truck first. (driver: Your office has not chosen a truck yet.) · Waiting for e-way bill. · Status on the trip: Booking waiting, then Waiting for e-way bill, then Ready to start · First, one line per booking waiting to be accepted, above Start: [Shipper]'s booking is waiting for you to accept. (driver: [Shipper]'s booking is waiting for your office to accept.) · Then one line per accepted booking whose bill is not final: [Shipper] has not added the e-way bill yet. · [Shipper] has not added the truck to the e-way bill yet. · [Shipper]'s e-way bill has a different truck from this trip. Change the trip's truck, or ask [Shipper] to fix the bill. (driver: [Shipper]'s e-way bill has a different truck from this trip.) · The valid-until time on [Shipper]'s e-way bill has passed. · NaviG8r found a problem with [Shipper]'s e-way bill. · Under each line, office only: Remind [Shipper] (quiet button), then Reminder sent (disabled), or No one at [Shipper] can get reminders. · Under the list, outside its scrolling, office: You can message the shipper from the booking. (only when a bill line shows) · Driver: Call your office. | Start lives only here. A trip cannot start while a booking on it waits to be accepted (owner, 23 Oct 2026); the server lists it first, with reason waiting_for_accept, in the same 409 eway_bill_not_ready. No Remind for it: the office accepts it. A waiting booking whose shipper has not finished paying cannot be accepted, so it holds nothing; the server marks each waiting booking readyToAccept so the app knows which. A trip starts only once every accepted booking has a bill marked not needed, or one with the trip's truck, a valid-until time ahead and no problem from ops; the server refuses otherwise (409 eway_bill_not_ready), the trip and its bookings load again, and the server's lines show (owner, 23 Oct 2026). A bill with a truck but no valid-until time reads as the truck not added. Choose a truck first shows only when the trip has no truck and a bill names one. Same on the driver's trip screen. Refusing Start tells no shipper. Remind sends the shipper one notice, The trip is waiting for your e-way bill, with the words for the reason (pilot-api.md); while that notice is unread and the reason is the same, or one for the same reason was sent in the last 6 hours, read or not, nothing more is sent and the button still reads Reminder sent (owner, 23 Oct 2026). With no shipper login that can get notices it reads No one at [Shipper] can get reminders. instead. A new reason, or loading the trip again, brings Remind back; each booking sends its own. If the server refuses because the bill or trip changed: Nothing was sent. The trip loaded again. No Remind for a driver, for a login that may not assign trips, or for a different truck while the trip has no truck (owner, 23 Oct 2026). When the office changes the trip's truck from one truck to another, a shipper whose bill names another truck is told: The truck on your trip is different from your e-way bill · [Carrier] set the truck on this trip to [truck]. Your e-way bill has [truck on the bill]. Ask [Carrier] which is right. If the bill is wrong, fix it on the portal, then here. With no carrier name: Your carrier. At most one truck notice per shipment in 6 hours: a further change in that time sends nothing, since the shipment screen shows the latest truck. |
| Start sheet | Start [route] now? · Truck · Driver · Bookings · Start trip · Not yet · Starting tells each shipper their goods are on the way. · Bookings still waiting for the shipper close when you start. | Opens only once every e-way bill is final, so it has no bill warning (owner, 23 Oct 2026). The last line shows only when a booking on the trip waits for its shipper to finish it (owner, 23 Oct 2026) |
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

```
DARK PATTERN SCREEN — a trip waits for bookings to accept; no accept after start — 2026-10-23
Screened: the Start (disabled), Home and Accept, trip started rows. Written with the build on
  23 Oct from Rishabh's decision, not before it.
Verdict: PASS WITH ONE OPEN FAIL (owner to decide)
Passes: 1 actionability: Start is off only while the carrier can act (accept), and a booking it
  cannot accept (shipper not paid) holds nothing, so no trip waits on something the carrier
  cannot do; Accept is off on a started trip, which the server refuses anyway; 2 no comparison;
  3 no cost shown or changed; 4 no urgency; 5 no defaults; 6 exit unchanged; 7 no decline
  button added; 9 no new data asked; readyToAccept carries no payment status or amount;
  10 no payout involved; 11 "the trip leaves once every booking you can accept is accepted"
  can be said to the carrier's face.
Findings:
  1. 8 Promise matches delivery — FAIL — a booking left waiting on a trip that started without
     it (its shipper paid after the start, or never paid) still reads "Waiting for carrier" to
     the shipper, though it can no longer be accepted; a paid one keeps the payment held until
     Finance cancels it by hand or the hold lapses, nobody is told, and the trip cannot
     complete while it waits. Fix needs an owner call: end such bookings at start, or refuse
     checkout once the trip has left, plus the shipper's words.
Accepted risks: none
Re-screened 23 Oct 2026 after Rishabh's call on finding 1: see the next block.
```

```
DARK PATTERN SCREEN — bookings the trip left without; reminders once in 6 hours — 2026-10-23
Screened: Paid after the trip left, Closed trip left, Update trip left, and the Remind and truck
  notice lines in Start (disabled). Written with the build on 23 Oct from Rishabh's decision.
Verdict: PASS WITH ONE OPEN FAIL (owner to decide)
Passes: 1 actionability: the closed shipment offers Book a trip, which the shipper can do; a
  started trip takes no payment, so nothing asks for money that cannot buy the trip; 2 no
  comparison; 3 no cost added; a payment Razorpay collected is refunded through Finance's list;
  4 no urgency; 5 no defaults; 6 exit: nothing to cancel, the booking is already closed;
  7 no decline button; 9 no new data asked; 10 no payout involved; the earlier finding 1 (a
  booking left "Waiting for carrier") is fixed: the shipment is closed and says why; reminders
  and truck notices reach a shipper at most once in 6 hours, and the office is told when no one
  can get them, instead of Reminder sent; 11 "your trip left before you paid, so we closed the
  booking and took nothing" can be said to the shipper's face for a checkout never finished.
Findings:
  1. 8 Promise matches delivery — FAIL — "You were not charged." is Rishabh's wording for every
     closed booking. When the shipper finishes checkout just after the start, Razorpay has
     authorized the payment: with UPI or netbanking the bank shows a debit until Razorpay
     releases the hold (within 3 days), the case the Cancelled, hold released row refuses to
     call untaken. Fixed 23 Oct 2026: the 409 and the closed-shipment screen now say "If your bank shows a
     payment, it comes back within 3 days."; the start notice says the same.
Accepted risks: none
```

```
DARK PATTERN SCREEN — bug-hunt batch 2 copy — 2026-10-23
Screened: the rows added on 23 Oct for batch 2: Messages, closed; App name; Remove the bill once the
  trip is on the way; Waiting for the shipper (Home, Bookings list, Accept, Start sheet); Location
  shared; Before the start; Not ready for delivery; Proof of delivery, full size.
Verdict: PASS WITH ONE OPEN FAIL (owner to decide)
Passes: 1 actionability: no screen now offers an action the reader cannot take: Accept is off with the
  reason, Remove is hidden when the server would refuse it, Home gives no task the office cannot do;
  2 no comparison; 3 no cost shown or added; 4 no urgency: the start sheet line states what the
  server does at the start, nothing counts down; 5 no new default; 6 exit: removing a bill ends at the
  start, and the row says so; editing it stays; 7 no decline button added; 9 no data asked for;
  10 no money: no payment words reach a driver or dispatcher; 11 each line is the plain truth: the
  location line says when the position is sent, the start sheet says waiting bookings close.
Findings:
  1. 8 Promise matches delivery — FAIL — on the Bookings list a booking waiting for the shipper still
     reads "Next: accept." and counts under Needs you, while its screen has Accept off with "Waiting
     for the shipper." — open: the batch rule allows only the listed changes, so the Next line and
     the Needs you group wait for Rishabh's call.
Accepted risks: none
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
| Location shared | Shippers see your location while this screen is open. | Owner, 23 Oct 2026. The phone sends its position only while the trip screen is open; nothing about tracking changed |
| Before the start | Start the trip first. | Confirm delivery or a delivery photo before the trip has started: the server refuses both (409 trip_not_started, owner, 23 Oct 2026) |
| Not ready for delivery | This booking is not ready for delivery yet. Ask your office. (owner-driver: This booking is not ready for delivery yet.) | No payment words. An owner-driver is the office, so is not sent to ask it (23 Oct 2026) |
| Booking, cancel requested | Accept booking (disabled) · Confirm delivery (disabled) · Your office asked NaviG8r to cancel this trip. | On the driver's booking screen when the trip is `CANCEL_REQUESTED`: the server refuses both. The driver did not ask and cannot withdraw, so nothing asks them to |
| Profile | Profile · Name · Phone · Company · Role · Call your office · Help from NaviG8r · Sign out · Your office changes your trips and the truck. Ask them if something is wrong. | No bank, earnings or payouts |
| Offline | No signal. Showing what was saved at [time] IST. · Could not confirm: no signal. Try again when you have one. | Saved copy only if the app already keeps one; no offline queue is promised |
