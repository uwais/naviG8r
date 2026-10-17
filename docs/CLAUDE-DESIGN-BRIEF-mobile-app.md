# Design brief: NaviG8r mobile app (shipper, carrier office, driver)

> **Status:** Draft for team review · **Written:** 2026-10-17 · **For:** Claude Design
> **Screens as of:** main f82628f plus open PR #153 (truck and transporter ID at acceptance), synthetic data

Paste this whole file into Claude Design, attach the screenshots in `docs/design-mobile-app/screenshots/`, and
pick the NaviG8r design system. How to do that: `docs/CLAUDE-DESIGN-HOW-TO.md`. The output wanted is in section 10.

## 1. Surface

The NaviG8r Android app. One app holds three kinds of user, each with their own tabs:

| Who | Tabs today | Reaches it by |
|---|---|---|
| Shipper (a business sending goods) | Home, Trips, Book, Shipments | The web app; in the Android app, the only way I found is the Developer lab |
| Carrier office (owner, owner-driver, dispatcher) | Home, Shipments, Loads, Publish, Profile | Sign in with phone |
| Driver (works for a carrier) | The same five tabs as the office, with less on each | Sign in with phone |

The shipper screens also run as a web page in a phone or laptop browser. Design at phone width first; the web
layout can widen the same screens.

Out of scope: the ops console (its own brief), the marketing site, the government e-way bill portal (we link to
it; we cannot change it).

## 2. Who uses it, and for what

**Shipper.** A small or mid-size business in India booking part-load space on a carrier's trip. Uses a phone or
a desk computer, a few times a week. Knows freight and GST; does not know our app.
1. Find a lane that goes their way and book space on it, knowing the full price before paying.
2. Make the e-way bill for the goods, with the truck and the carrier's transporter ID, in one visit to the
   government portal, and tell NaviG8r the bill's four details.
3. Follow the shipment to delivery; talk to the carrier in the shipment conversation.

**Carrier office (owner or dispatcher).** Runs one to a few trucks. Uses a phone, often between other work.
1. Publish a trip (a lane with dates and room) that shippers can book.
2. Accept each booking, choosing which truck carries the trip; assign a driver.
3. Add the truck to the e-way bill on the portal if the shipper did not, then enter it here.
4. Confirm delivery and proof of delivery; see what they will be paid (owner only).
5. Keep company details current: vehicle, transporter ID, bank details, drivers.

**Driver.** On the road, often one-handed, in sun, on an older phone with weak signal.
1. See today's trip, start it, go to the next pickup.
2. Show the e-way bill number at a check-post.
3. Confirm delivery.
- **Rule:** a driver never sees money: no earnings, payouts, prices or "net" amounts, anywhere.

**Not checked:** which languages drivers read, and how many use very small or very old phones. Assume English
second-language readers and 360 dp wide screens until the team says otherwise (question 1 in section 11).

## 3. Success criteria

- A first-time shipper books a lane and makes the e-way bill without help or a phone call.
- Every step of a sequence says, in one sentence, what to do now and who does the next step.
- Each screen has one primary action, and it is visible without scrolling on a 360 x 800 dp phone.
- No raw codes, IDs, "HTTP 400" text or system field names reach a user.
- A driver can do every driver task with one thumb; every tap target is at least 48 dp.

## 4. Current state

Screenshots, all from the Android emulator on synthetic data (`docs/design-mobile-app/screenshots/`):

| File | What it shows |
|---|---|
| common-00-start-screen | The start screen: the default Flutter logo, not ours |
| carrier-00-landing-signed-out, -00-sign-in, -00b-verify-code | Carrier landing, phone sign-in, code screen |
| carrier-01-home | Office home while signed in |
| carrier-02-shipments, -10-shipment-detail | Bookings list and one booking, with its e-way bill card |
| carrier-03-loads, -04-trip-top, -05-trip-middle | Trips list with filters; one trip with truck and driver |
| carrier-06-publish | Publish a trip |
| carrier-07-profile, -08-profile-more | Profile: vehicle, transporter ID (saved, with Change), menu |
| dev-01-lab | Developer lab, reachable from the carrier home |
| shipper-00-home-signed-out, -01-sign-in, -02-home | Shipper home and sign-in |
| shipper-03-trips, -03b-match-route | Find a lane: browse, and match my route |
| shipper-04-book, -04b-book-bottom, -13-book-error-reported | Book shipment; the error a tester hit |
| shipper-05-shipments | Shipments list |
| shipper-06/07-shipment-no-bill | A shipment before the e-way bill, with the copy box |
| shipper-08/09-add-eway-bill-form | Entering the bill's four details |
| shipper-10/11-shipment-bill-and-truck | A shipment with bill and truck |
| shipper-12-notifications | Notifications |
| driver-01-loads, -02-trip, -04-shipment, -05-profile, -06-shipments, -07-shipment-with-bill | Driver views |

Not captured: the "Which truck carries this trip?" sheet the office sees on Accept (a list of the fleet's trucks,
none chosen, "Accept with this truck" greyed until one is picked, and Cancel). Team, Integrations, bank details
and sign-up screens were not captured either.

**What is wrong, from the team's testing (17 Oct) and a walk through every screen:**

*Where am I, and as whom*
- On a shipper's shipment the big title is the carrier's name (shipper-06), so it reads as a carrier sign-in.
  Proposed instead: the signed-in company as the title, the person's name and role (Shipper, Owner, Dispatcher,
  Driver) underneath.
- The subtitle is a raw user name and a cut-off phone number ("Synthetic user-shipper-a · 8000000...").
- Every screen repeats an organization drop-down, a refresh icon and a sign-out icon under the title.
- A carrier's booking screen is titled "Proof of delivery" before anything is delivered (carrier-10).
- The round avatar at top right does nothing.
- The signed-in carrier home still offers "Sign in with phone", "Register as new carrier" and "Developer lab"
  (carrier-01). Signed out, all five tabs still show (carrier-00-landing).
- On Android, the only way I found from the carrier screens to the shipper screens is the Developer lab.

*Doing the job*
- Loads: the View button is small, and Start sits right beside it, so a slip starts a trip. The whole card should
  open the trip; Start belongs on the trip screen.
- Book: two tall maps, with Get quote and Book & pay squeezed between them (shipper-04b). The difference
  between Get quote and Book & pay is not explained. Not checked: what the payment step shows before money moves.
- Trips: "Capacity 1000 kg (895 kg reserved)" makes the shipper do the subtraction. Say "Room left: 105 kg".
- Book & pay too heavy showed "HTTP 400: {error: insufficient_capacity}" (shipper-13). Fixed in code, waiting for
  review: "This lane does not have room for that weight. Enter a lower weight, or choose another lane." The Book
  screen now shows "Room left" and keeps the weight searched with; the designs should keep both.
- The code screen shows a "Challenge id" field (carrier-00b).
- Profile: "Vehicle class (SMALL|MEDIUM|LARGE)" is a typed field with system words in its label; the owner's
  vehicle registration is empty though the fleet has trucks.
- Lists use long one-line sentences ("Accepted · Bommasandra, Bengaluru → Guindy, Chennai") that wrap badly.

*Words and numbers*
- Dates in three formats: "2026-10-17", "16 Oct – 17 Oct", "10/17 7:41 AM" (US order, in an Indian app).
- Money in two: "Net to carrier: ₹45" and "₹4704.35 net".
- Notifications name shipments by internal ID ("Shipment SHP_4135").
- A cancelled-and-refunded shipment shows a system code to anyone who sees payments.

*The e-way bill, which testers found hardest*
- The card stacks three equal buttons (Add e-way bill, No e-way bill needed, Open the practice portal) with no
  order, so it is unclear what comes first (shipper-07).
- The copy box is one five-line paragraph (shipper-06).
- Testers did not know whether a GSTIN and a transporter ID are the same thing. They are not: the transporter ID
  is the carrier's own GSTIN, or a TRANSIN if the carrier has no GST registration. The shipper's GSTIN is a
  different number.
- The portal itself has many fields. We cannot change it, so the app has to say which ones come from us and
  what to copy back.

## 5. The sequences to lay out as steps

Show each as numbered steps on the shipment screen: done steps ticked, the current step expanded with one
sentence and one button, later steps named but collapsed. Wording below is a starting draft; keep each line
short and true.

**A. Shipper: booking**
1. Find a lane: "Pick a lane going your way." Each card shows the route, carrier, dates and room left. A lane with
   less room than the weight searched shows "Not enough room for 500 kg" and no Book button, after the lanes that
   fit. Lanes are ordered by how well they fit the route and dates, never by what NaviG8r earns on them.
2. Book and pay: "Check the price, then pay." The full price, with any fee or tax, shows before Pay, and is the
   amount charged. The weight starts at the weight searched with; with no search, the field starts empty, not at a
   guessed number. If the lane fills while the shipper is paying, say so in words and charge nothing.
3. Wait for the carrier: "Waiting for Carrier A to accept. You are not charged until they do." Check that
   sentence with the team before using it: it must match what payment actually does.
4. E-way bill (sequence B), then tracking, then delivery.
5. Cancelling: the shipment screen says how to cancel and what is refunded at each status, as plainly as Book
   says how to book. If the app cannot cancel at some status, it says so and names who to contact.

**B. E-way bill (shipper and carrier)**

| Step | Who | What the card says | Button |
|---|---|---|---|
| 0 | Shipper | "Does this load need an e-way bill?" | Yes, make one · No e-way bill needed |
| 1 | Shipper | "Make the bill on the government portal. Copy these two in at Part B:" truck number and transporter ID, each with Copy, each labelled with the portal's field name | Open the e-way bill portal |
| 2 | Shipper | "Copy four details from the portal's bill: bill number, bill date, your GSTIN, invoice number." | Save e-way bill |
| 3 | Shipper or carrier | Only if the truck was not on the bill: "Add the truck on the portal before the goods move, then enter it here." | Add truck |
| 4 | NaviG8r ops | "We are checking the bill on the portal." Then "Checked." | none |
| 5 | Driver | The bill number in large type, the truck, and the valid-until time | none |

- Before the carrier accepts, step 1 says "You can make the bill once the carrier accepts and names the truck."
- Validity starts when the first truck is entered (one day per 200 km, ending at midnight India time), so step 1
  says to enter the truck on loading day, before the goods move.
- If the carrier has no transporter ID, step 1 shows the truck only and says only the bill's maker can then change
  the truck.
- NaviG8r never makes or changes a bill. The card says so once, in small type, not in every state.

**C. Carrier office: a trip**
1. Publish a trip. 2. Accept each booking, choosing the truck. 3. Assign a driver. 4. Truck on the e-way bill, if
the shipper left it to you. 5. Start. 6. Confirm delivery for each booking. 7. Proof of delivery accepted, then
payment released. Only the owner sees amounts, and sees them together: what the shipper paid, NaviG8r's commission,
and what the carrier receives.

**D. Driver: a day**
Today's trip, then Start, then the next stop, then the e-way bill number, then Confirm delivery. No money anywhere.

## 6. Brand

- **Design system:** the NaviG8r design system, https://claude.ai/artifact/Y5Y3QwE9ZRBB4XuHLN2YXD. It holds the
  colours, type, spacing, corners, status labels, logos and base components. Where this brief and the system
  disagree on looks, the system wins; this brief decides what each screen must do.
- **In short:** navy `#16233D` for primary actions and selected states; gold `#E8A33D` only on navy; page
  `#F8F7F2`; white only for cards; text `#2B2620`; every status as a word on a tinted label.
- The app today uses a cool grey-blue page `#F4F7FA` and navy `#122C53`; move it to the system's values.
- **Voice:** plain, short, specific. Say what happened and what to do next. Use the product's words: shipper,
  carrier, trip, lane, booking, shipment, e-way bill, proof of delivery.
- **Type:** Poppins for headings, Manrope for everything else, a monospace face for bill numbers, truck numbers
  and IDs that people copy; tabular figures for money, weights and dates.
- **Density:** simpler and roomier than the ops console. These are occasional users on phones: one task per
  screen, larger type, fewer words.

## 7. Hard constraints (not negotiable)

- **Light mode is the default.** Warm off-white page, never pure white; white only for raised cards. Warm
  near-black text, never pure black. Dark mode only as an explicit setting, never switched on from the phone's
  setting.
- **No emoji anywhere.**
- **WCAG AA:** 4.5:1 for text, 3:1 for large text, control borders and focus rings. Colour is never the only
  signal: every status has words.
- **Touch:** targets at least 48 x 48 dp; text still fits at 200% system font size; works at 360 dp wide.
- **Screen readers:** every icon button has a label; messages that appear after an action are announced.
- **Drivers see no money**, in any state, on any screen.
- **No dark patterns:** no manufactured urgency or scarcity; the full price, with fees and tax, on the same screen
  as Pay; no pre-checked options; cancelling as easy to find as booking; neutral decline wording; a button does
  what it says; nothing ranked for reasons other than the user's benefit; no asking for data the task does not
  need.
- **Honest copy:** loading says what is loading; errors say what went wrong and what to do; empty states say what
  will appear and when.

## 8. What this design is not

- Not new features. Every action in section 5 exists today; this is layout, order and words.
- Not a change to who can do what: owners, dispatchers, drivers and shippers keep their current permissions.
- Not a redesign of the government portal, which we only link to.
- Not a marketing page: no tours, no upsell, no rating prompts.

## 9. What the screens get from the server

Field lists, not code. Everything exists today.

- **Signed-in person:** name, phone, organizations (name, kind: shipper or carrier), role in the chosen one.
- **Trip (lane):** origin and destination city, carrier name, dates (window), truck size, capacity and booked
  weight (room left = the difference), status: Open, Full, In transit, Done.
- **Booking (shipment):** shipper, carrier, pickup and drop, weight, price (not for drivers), status: Awaiting
  carrier acceptance, Accepted, Delivery confirmed (Awaiting payment release for those who see payments),
  Delivered, Cancelled.
- **E-way bill on a booking:** none yet, or "not needed", or bill number, bill date, maker's GSTIN, invoice
  number; truck and valid-until once added; who entered it; checked by ops or not.
- **For the e-way bill box (shipper, once accepted):** the trip's truck number in the portal's format and the
  carrier's transporter ID, if it has one.
- **Trip's truck and driver:** truck number, driver name, or not assigned.

## 10. Output wanted from Claude Design

- **Layouts:** phone, 360 x 800 dp. Then the shipper screens at 1280 px for the web.
- **Screens:** sign-in and code; each role's home; Trips and Book (with price before Pay); Shipments list; the
  shipment screen with the steps of section 5 in every state; the accept sheet; trip screen; Publish; Profile.
- **Header:** company as title, person and role underneath, one menu for switching company and signing out.
- **Cards:** the whole card opens its item; risky actions (Start, Remove) live on the detail screen, not the list.
- **Components, each with every state** (default, pressed, focus, disabled, loading, success, error, empty):
  step list, status label, copy-to-clipboard row, primary and secondary buttons, form field with help and error,
  list card, bottom sheet, map with fallback when location is off.
- **Tokens:** use the design system's by name; list any missing one with its value and contrast ratio.
- **Copy:** every label, button, status, error and empty-state line, as a table per screen.
- **Accessibility notes:** heading order, focus order, what a screen reader announces after each action.

## 11. Questions for the team before the build

1. Which languages and phone sizes do drivers use? (Changes type size and whether to plan for Hindi or others.)
2. Should shippers get a separate app, or keep one app with a clear "I ship goods / I carry goods" choice?
3. Does a shipper pay at booking, or only once the carrier accepts? Step A.3's sentence depends on it.
4. Should the e-way bill step offer "No e-way bill needed" before or after the shipper opens the portal?

## 12. Dark pattern screen

```
DARK PATTERN SCREEN — mobile app redesign brief — 2026-10-17
Screened: this brief, sections 1 to 11
Verdict: PASS WITH CHANGES (changes made in section 5; two items open)
Findings:
  1. Actionability — FAIL — a lane with less room than the searched weight still offered Book this lane —
     such lanes say "Not enough room for N kg", have no Book button and sort after lanes that fit (A.1).
  3. Full cost on the same screen — FAIL — the owner saw only a net amount — the owner sees what the shipper
     paid, the commission and what the carrier receives together (C.7). Shipper: full price before Pay (A.2).
  5. Defaults — FAIL — the Book weight started at 200 kg whatever was searched — it starts at the searched
     weight, or empty (A.2). The accept sheet preselects no truck; the e-way bill step preselects neither choice.
  6. Exit — FAIL — the brief described booking but not cancelling — the shipment screen says how to cancel and
     what is refunded at each status, or who to contact (A.5).
  8. Promise matches delivery — FAIL — room left can change between the list and payment — the amount at Pay is
     the amount charged, and a lane that fills meanwhile is refused in words with no charge (A.2).
  Passed: 2 honest comparison (nothing compared; room left is capacity minus booked), 4 urgency (the only
  countdown is the e-way bill's legal validity, which is real and material), 7 decline copy (Cancel, No e-way
  bill needed, Not enough room: neutral), 9 data (nothing new asked; transporter ID stays optional and labelled
  so; the bill's four details are what ops needs to find it on the portal), 10 money (NaviG8r earns a commission
  per booking; lane order never uses it), 11 reversal test (we show lanes with room going your way, you pay the
  shown price, the carrier pays our commission out of it).
Open, not accepted: (a) A.3 says the shipper is not charged until the carrier accepts; true only if payment
  works that way (question 3). (b) A.2 "charge nothing if the lane fills" must match the payment flow; check
  before build.
Accepted risks: none
```
