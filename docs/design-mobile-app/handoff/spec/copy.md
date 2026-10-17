# Copy deck

Every visible string by screen. `[brackets]` = data from the server or text the team must still supply. Use these strings verbatim; do not paraphrase. Example names and numbers in the mockups are synthetic.

## Copy: start, sign in, shipper

Every visible string, by screen. Brackets mark text the team still has to supply. Placeholders in examples (names, numbers) are synthetic.

### Formats (every screen)

| Thing | Format | Never |
|---|---|---|
| Date | 18 Oct · 18 – 19 Oct · 18 Oct 2026 when the year is not this year, or in a form | 2026-10-17, 10/17 |
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
| Match result line | [n] lanes with room for [weight] kg, closest to your route first. | Announced |
| Lane card | [From] to [To] · [Carrier] · [Size] truck · Dates · Room left · [Open \| Full] | Full lane: "Room left: None" |
| Empty, match | No lanes pass near this route with room for [weight] kg. · Try a lower weight, or browse all lanes. · Change weight · Browse all lanes |  |
| Empty, browse | No lanes are open right now. · New lanes appear here when carriers publish them. |  |
| Loading, error | Loading lanes. · Could not load lanes. Check your connection, then try again. · Try again |  |

### Book and pay

| Element | Copy | Notes |
|---|---|---|
| Title, sub | Book space · Check the price, then pay. |  |
| Fields | Weight · Up to [room] kg on this lane. · Pickup · Drop · Change | Start at the searched values, else empty |
| Button 1 | Get price · loading: Getting price | Was "Get quote" |
| Price | Price · ₹[amount] · This is the full price. Nothing is added at payment. · Changing weight, pickup or drop clears this price, and you get a new one. | Tax line only if question 5 says so |
| Above Pay | Your payment is held when you book and collected after delivery. Booked shipments cannot be cancelled in the app; to change one, contact [NaviG8r contact]. | Open item 6 (contact) |
| Button 2 | Pay ₹[amount] and book | Was "Book & pay"; only after a price |
| Confirm sheet | Pay ₹[amount] to book? · Lane · Carrier · Dates · Weight · You pay · The payment is held now and collected after delivery. · [Carrier] then accepts and names the truck. · You cannot cancel in the app. To change the booking, contact [NaviG8r contact]. · Continue to payment · Go back · Next, you choose how to pay on the payment provider's screen. | Not checked: provider's screen |
| Too heavy | This lane does not have room for that weight. Enter a lower weight, or choose another lane. · Choose another lane | Replaces "HTTP 400" |

### Shipment screen and e-way bill

| Element | Copy | Notes |
|---|---|---|
| Summary | [From] to [To] · [Status] · [pickup locality] to [drop locality] · [weight] · [dates] · [carrier] · Messages · Change or cancel | Title is the route, not the carrier |
| Steps | Booked and paid · Carrier accepts and names the truck · E-way bill · Bill check · On the way · Delivered | Each with who: You, [Carrier], NaviG8r staff |
| Waiting | Waiting for [Carrier] to accept. Your payment is on hold; it is collected after delivery. | Brief A.3 |
| Step 0 | Does this load need an e-way bill? · [one line from the team] · Yes, make one · No e-way bill needed · [Carrier] sees your answer before accepting. | Neither preselected |
| Before acceptance | You can make the bill once the carrier accepts and names the truck. We will send you an update. | True after PR #153 |
| Step 1 | Make the bill on the government portal. Copy these two in: · Truck number · Portal field: Vehicle No. (Part B) · Carrier's transporter ID · Portal field: Transporter ID. Not your GSTIN. · Make it on loading day, before the goods move: the bill is valid from when the truck is entered. · Open the e-way bill portal · I have made it. Enter the details | No transporter ID: "[Carrier] has not added one. Leave Transporter ID empty. Only you, the bill's maker, can then change the truck." |
| Step 2 | E-WAY BILL · PART 2 OF 2 · Enter the bill's details · Copy these four from the bill on the portal. · E-way bill number · 12 digits, at the top of the bill. · Bill date · Your GSTIN · The GSTIN that made the bill. Not the carrier's transporter ID. · Invoice number · Save e-way bill · NaviG8r staff then check it on the portal. |  |
| Step 2 errors | [n] details need fixing before you can save. · This has [n] digits. An e-way bill number has 12. · This is the carrier's transporter ID. Enter the GSTIN that made the bill. |  |
| Step 3 | Bill [number] saved. The truck is not on it yet. · Add the truck on the portal before the goods move, then enter it here. · Portal: Update Part B, Vehicle No. · The bill's validity starts when the truck is added: one day per 200 km, ending at midnight India time. · Add truck | Shipper or carrier |
| Step 4 | E-way bill saved. Nothing more for you to do until delivery. · NaviG8r staff check the bill on the portal by hand. We will tell you if anything needs fixing. |  |
| Step 4 problem | E-way bill needs a fix · NaviG8r staff found a difference · The [field] on the portal's bill is [value]. You entered [value]. · If the portal is right, fix it here. If the bill itself is wrong, change it on the portal first. · Fix the details · Ask NaviG8r staff |  |
| Footnote | NaviG8r never makes or changes an e-way bill. You make it on the portal. | Once per screen, small |
| Not needed | E-way bill: not needed · You said so on [date]. [Carrier] saw this before accepting. · Change |  |
| On the way | Left [pickup] on [date] at [time] IST. [Carrier] confirms when it is delivered. · Message [Carrier] |  |
| Delivered | [Carrier] confirmed delivery and added proof of delivery. Your payment of ₹[amount] is collected now. · View proof of delivery · Book another shipment | Open item 8 (payment issue) |
| Cancelled | This shipment was cancelled · NaviG8r operations cancelled it on [date] at your request. · You paid · Refunded · Refunds reach your account in the time your bank or payment app takes. · Questions about this refund? Contact [NaviG8r contact]. | Replaces the system code |
| Updates | [Carrier] accepted your shipment · [Route, date]. You can make the e-way bill now. · Your shipment is on the way · E-way bill checked · Delivered · Proof of delivery is ready. | Named by route and date |

## Copy: carrier office and driver

Tabs for the office: Home, Bookings, Trips, Publish, Profile. Tabs for drivers: Today, Trips, Profile. Rows marked "owner only" never render for dispatchers or drivers.

### Office home, bookings

| Element | Copy | Notes |
|---|---|---|
| Home | Home · NEEDS YOU · Accept a booking · [Shipper], [weight], on your [route] trip, [date]. · Review booking · Add the truck to an e-way bill · Assign a driver · Today | Signed-in home has no sign-in, register or developer links |
| Bookings list | Bookings · Needs you ([n]) · Active · Done · [Shipper] · [pickup] to [drop] · [date] · [weight] · E-way bill: needed \| not needed · Next: [action]. | Whole card opens |
| Booking title | BOOKING · [Shipper] | Was "Proof of delivery" |
| Booking facts | Pickup · Drop · Weight · E-way bill: Needed. [Shipper] makes it. \| Not needed (shipper said so). |  |
| Steps | Accept and choose the truck · Truck on the e-way bill · Driver assigned and trip started · Confirm delivery · Payment released |  |
| Accept panel | On your trip [route], [dates]. After this, [n] kg of room is left. · Accept · Decline | Decline is neutral, no guilt |
| Accept sheet | Which truck carries this trip? · [route], [dates]. [Shipper] puts this truck number on the e-way bill. · Accept with this truck (disabled) · Choose a truck first. · Accept with [truck] · Cancel | No truck preselected |
| Accept result | Accepted with [truck]. [Shipper] can make the e-way bill now. · Could not accept. Check your connection and try again. | Announced |
| No trucks | You have no trucks yet. Add one to accept bookings. · Add truck |  |
| Truck on bill | [Shipper] made the bill without it · Add the truck on the portal before the goods move, then enter it here. · E-way bill number · Portal: Update Part B, find the bill by this number · Truck number · Portal field: Vehicle No. · Add truck · Open the e-way bill portal |  |
| Confirm delivery | When the goods are handed over at [drop], add a photo of the signed delivery note, then confirm. · Proof of delivery · Add photo · Confirm delivery · Add the proof of delivery first. |  |
| Payment (owner only) | Awaiting payment release · NaviG8r operations check the proof of delivery, then release the payment to your bank account ending [4 digits]. · Shipper paid · NaviG8r commission · You receive · Only owners see payment amounts. Dispatchers and drivers do not. | All three amounts together |
| Same, dispatcher | Delivery confirmed · Nothing more for you to do on this booking. · NaviG8r operations check the proof of delivery. The owner sees the payment. | No amounts |

### Trips, publish, profile

| Element | Copy | Notes |
|---|---|---|
| Trips list | Trips · Open · In transit · Done · Dates · Room left · Bookings · [truck] · [driver] \| No driver yet · Truck chosen when you accept the first booking | No View or Start on the card |
| Trip | TRIP · [route] · [status] · [dates] · [size] truck · Room left: [n] kg of [capacity] kg · Truck and driver · Not assigned · Assign driver · Bookings on this trip ([n]) |  |
| Start (disabled) | Start the trip · Start trip · Assign a driver first. Then start on loading day. | Start lives only here |
| Start sheet | Start [route] now? · Truck · Driver · Bookings · [Shipper]'s e-way bill does not have the truck yet. Add it on the portal before these goods move. · Start trip · Add the truck first · Not yet · Starting tells each shipper their goods are on the way. | Warning only when true |
| Assign sheet | Who drives this trip? · [route], [dates], truck [truck]. The driver sees the trip and the e-way bill, never the payment. · Assign [name] · Cancel · Add a driver to your company | No driver preselected |
| Publish | Publish a trip · Shippers can book space on it once it is published. · From · To · Leaves · Arrives by · Truck size: Small, Medium, Large · Room for shippers · The weight you can carry for shippers on this trip. · You choose the truck when you accept the first booking. · Publish trip | Fields start empty |
| Profile | Company · Approved by NaviG8r · Transporter ID · Your GSTIN, or a TRANSIN if you have no GST registration. Shippers copy it into their e-way bills. It is not the shipper's GSTIN. · Trucks ([n]) · Add truck · Drivers ([n]) · Add driver · Manage drivers · Bank details (owner only) · Account ending [4 digits] · Team · Invite · Dispatchers accept bookings and assign drivers. They do not see payments. | No developer lab |
| Truck | Truck · Registration number · As on the registration certificate. Spaces are removed for the e-way bill. · Truck size · [Size guide from the team] · Save truck · Remove this truck · You are asked to confirm before anything is removed. · Remove truck | Replaces "Vehicle class (SMALL\|MEDIUM\|LARGE)" |

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
