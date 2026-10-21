# Claude Code prompts: NaviG8r mobile app redesign

Run one Claude Code session per PR, in order. In each session, paste **Prompt A (context)** first, then the PR's prompt. Merge a PR before starting the next one: each builds on the last.

| # | PR | Depends on | Size goal |
|---|---|---|---|
| 0 | Recon: map today's code to the mockups (no code) | — | report only |
| 1 | Theme, tokens, bundled fonts | 0 | ≤ 6 files |
| 2 | Shared components and format helpers | 1 | ≤ 12 files, mostly new |
| 3 | App shell: start, sign in, header, account menu, tabs by role | 2 | |
| 4 | Shipper: find a lane, book, pay | 3 | |
| 5a | Shipment step list (shipper) | 4 | |
| 5b | E-way bill steps and forms (shipper) | 5a | |
| 6 | Carrier bookings: accept with truck, truck on bill, delivery, payment | 5b | |
| 7 | Carrier trips: trip, assign, start sheet, publish, profile, truck | 6 | |
| 8 | Driver screens and the no-money test | 7 | |
| 9 | Shipper web layout (≥ 1024 px) | 8 | |
| 10 | Copy, accessibility and 200% text sweep | 9 | |

Prompt R (review) at the bottom runs on any PR before you merge it.

---

## Prompt A: context (paste at the start of every session)

```text
You are working in the naviG8r repo on the Flutter app at apps/driver_pilot. We are implementing a
redesign that already exists as mockups and specs in docs/design-mobile-app/handoff/.

Read these first, in this order, before writing anything:
1. docs/design-mobile-app/handoff/README.md
2. docs/design-mobile-app/handoff/spec/decisions.md   (guardrails: obey every one)
3. docs/design-mobile-app/handoff/spec/screens.md     (screens, states, step mapping)
4. docs/design-mobile-app/handoff/spec/components.md
5. docs/design-mobile-app/handoff/spec/copy.md        (use strings verbatim)
6. docs/design-mobile-app/handoff/spec/accessibility.md
7. docs/PR-STANDARD.md                                (how PRs and tests must look here)
The PNGs in docs/design-mobile-app/handoff/screens/ are the visual target. Open the ones for the
screens you touch and look at them. The HTML in mockups/ is reference only: never copy it into the app.

Rules for this work:
- No new features, endpoints, permissions or data fields. Layout, order and words only. If a screen
  needs something the API does not give (check apps/driver_pilot/lib/pilot_api.dart), STOP and tell
  me what is missing instead of building around it.
- Drivers never see money. Light mode only. No emoji. Nothing preselected. No raw codes or IDs in UI.
- Tap targets >= 48 dp. Must work at 360 dp wide and at 200% text scale.
- Use the theme and components from lib/ui/ (once PRs 1 and 2 exist). No hard-coded colours, sizes
  or fonts in screens.
- Placeholders such as [NaviG8r contact] come from lib/ui/pending_copy.dart. Never invent their text.
- Before you start: git fetch, branch from the latest origin/main, and confirm the PR named in my
  next message has not already been opened (gh pr list --search).
- One problem per PR. Keep the diff small. Follow docs/PR-STANDARD.md for the description
  (<= 400 words; Verified items labelled ran/read/claimed; a "Not verified" section; steps to check
  on the emulator without reading code).
- Tests: every user-visible element you add or change gets a named widget-test assertion with a
  `reason:`. No golden tests. Run `flutter analyze` and `flutter test` in apps/driver_pilot and paste
  the summary lines into the PR.
- Do not push to main. Open a PR and stop.

Scope gate before any code: in 5 lines or fewer, tell me (1) which requirement in the spec each change
answers, (2) what existing code you will delete or reuse rather than add, (3) the smallest version of
this PR. Wait for my "go".
```

---

## PR 0: recon (no code)

```text
Task: produce a recon report, no code changes, no PR.

1. List every screen and route in apps/driver_pilot/lib (main.dart router, driver_flow.dart,
   customer_flow.dart, customer_layout.dart, etc.). For each, give file:line of its build method and
   which mockup(s) in spec/screens.md it becomes. Mark screens with no mockup.
2. For every row of the "Shipment step mapping" table in spec/screens.md, say which API fields in
   pilot_api.dart decide it, or "MISSING" if none does.
3. List every field the mockups display that pilot_api.dart does not return (brief section 9 is the
   promise). Include: truck list for the accept sheet, carrier transporter ID for shippers, e-way bill
   valid-until, ops check status and note, proof-of-delivery photo, commission amount.
4. List every place the app formats dates, money, weights or IDs, with file:line.
5. List every place a driver route can reach a price, amount or payout today.
6. Check the Flutter version in use and whether `CardTheme` or `CardThemeData`, and
   `MaterialStateProperty` or `WidgetStateProperty`, are the right names for it.

Write the report to docs/design-mobile-app/handoff/RECON.md and show me a 10-line summary.
Stop there.
```

---

## PR 1: theme, tokens, fonts

```text
PR 1 of the redesign: "Move the app to the NaviG8r design system theme".

Inputs: spec/design-tokens.json and spec/navig8r_theme.dart (a reference implementation).
Do:
- Replace the palette in lib/driver_theme.dart with the tokens (navy #16233D, page #F8F7F2, etc.) by
  adapting spec/navig8r_theme.dart. Keep existing public names that other files import working, or
  update their imports in the same PR. Fix any API names flagged in RECON.md item 6.
- Bundle Poppins (600, 700) and Manrope (400, 500, 600, 700) TTFs under apps/driver_pilot/assets/fonts/
  from the official Google Fonts repository (OFL). Add the OFL licence file next to them. Declare
  them in pubspec.yaml.
- MaterialApp: themeMode: ThemeMode.light and no darkTheme.
- Tabular figures on body text.
Do not change any screen layout or copy in this PR.
Tests: a test that pumps the app root and asserts the scaffold background equals NvColors.page and
that themeMode is light (reason: "brief 7: light mode only, page is warm off-white").
```

---

## PR 2: components and format helpers

```text
PR 2: "Add the shared UI components". New files under lib/ui/, no screen changes yet.

Build every component in spec/components.md (NvHeader, NvAccountSheet, NvButton, NvStatusLabel,
NvStepList/NvStep, NvCopyRow, NvField, NvChoiceChips/NvChoiceRows, NvListCard, NvSheet, NvMap
wrapper, NvMessage, NvActionBar), plus lib/ui/format.dart with the helpers listed there and
lib/ui/pending_copy.dart with the open placeholders from spec/decisions.md.
Match the component mockups: screens/cp-header.png, cp-buttons.png, cp-status.png, cp-steps.png,
cp-copy.png, cp-field.png, cp-card.png, cp-sheet.png, cp-map.png, cp-tokens.png.

Tests (test/ui/): for each component, one test per state in the components.md table, asserting the
visible words and semantics (e.g. NvStep done exposes "Done: Booked and paid"; NvButton disabled
shows its reason; NvCopyRow copies "KA01AB1234" with no spaces and announces "Truck number copied";
NvListCard has exactly one tappable target; NvChoiceRows starts with nothing selected).
format.dart: unit tests for every format in the "Formats" table of copy.md, including Indian
grouping (₹1,25,000) and IST 24-hour time.
If this exceeds ~12 files, split into 2a (buttons, status, field, chips, message, format) and
2b (header, account sheet, step list, copy row, list card, sheet, map, action bar) and tell me.
```

---

## PR 3: app shell

```text
PR 3: "One header, start screen and role-based tabs".

Mockups: Main, c-signin, c-code, c-code-error, c-menu, and the header on every screen.
Do:
- Start screen (Main.png) replaces the default Flutter logo screen when signed out. Signed out shows
  no tabs.
- Sign-in and code screens per copy.md. Remove the visible "Challenge id" field (keep it in state).
- NvHeader on every signed-in screen; remove org drop-down, refresh icon, sign-out icon and avatar.
  Add pull-to-refresh where the refresh icon was.
- Tabs by role per the Navigation table in spec/screens.md (labels only for carrier; shipper and
  driver lose tabs as listed). Existing screens keep working under the new tabs; their insides change
  in later PRs.
- Hide /pilot-lab and the signed-in carrier home's sign-in/register links unless !kReleaseMode.
Tests: start screen shows "How do you use NaviG8r?" and both choices; signed out shows no
NavigationBar; header shows company and "Person · Role" for each role; shipper tabs are exactly
[Home, Find a lane, Shipments]; driver tabs exactly [Today, Trips, Profile]; office tabs exactly
[Home, Bookings, Trips, Publish, Profile]; no "Challenge id" text; account sheet lists companies and
"Sign out".
Not in this PR: changing the insides of Home, lists or details.
```

---

## PR 4: shipper find a lane and book

```text
PR 4: "Shipper: find a lane and book with the full price before paying".

Mockups: sh-home, sh-lanes-browse, sh-lanes-match, sh-lanes-empty, sh-book-start, sh-book-price,
sh-book-confirm, sh-book-error. Web is PR 9; keep these phone-first.
Do:
- Lane cards via NvListCard: route, carrier, size, dates, "Room left: N kg". Browse is not sorted
  and says so; Match keeps the server's order and says "closest to your route first".
- Book: one small map, text fields first. Weight/pickup/drop start at the searched values, else
  empty. "Get price", then price card, then "Pay ₹X and book" in NvActionBar. Any change to weight,
  pickup or drop clears the price and hides Pay.
- Confirm sheet (sh-book-confirm) before the existing Razorpay call.
- insufficient_capacity shows the existing plain-language message (do not reintroduce HTTP text).
- The no-cancel line with [NaviG8r contact] sits directly above Pay.
Tests: price disappears after editing weight (reason: "brief A.2: shown price is the charged
price"); Pay is absent before a price; weight field starts with the searched weight; the cancel /
contact line is present on the price state; the confirm sheet shows "You pay" and the amount;
"Room left: 105 kg" renders from capacity 1000 and booked 895; HTTP text never renders.
```

---

## PR 5a: shipment step list

```text
PR 5a: "Shipment screen as numbered steps".

Mockups: sh-ship-waiting, sh-ewb-ask, sh-ship-transit, sh-ship-delivered, sh-ship-noewb,
sh-ship-cancelled, sh-shipments, sh-notifications.
Do:
- Implement the "Shipment step mapping" in spec/screens.md as one pure function (lib/shipment_steps.dart)
  returning the steps, the current step, who acts, and the "Next:" line. Use it for the shipment
  screen, the shipments list and the home "Needs you" card.
- Shipment title is the route, never the carrier name. Summary card with Messages and Change or
  cancel (opens a sheet with [NaviG8r contact]).
- Notifications name shipments by route and date.
- The e-way bill step's insides can be a stub that links to the current e-way bill UI; PR 5b replaces it.
Tests: unit-test every row of the mapping table; widget tests that the title is the route; that
"Waiting for Ravi Roadways to accept. Your payment is on hold; it is collected after delivery."
renders in that state; that no "SHP_" string renders in notifications; that cancelled shows words,
not a code.
```

---

## PR 5b: e-way bill steps

```text
PR 5b: "E-way bill as clear steps with copy rows".

Mockups: sh-ship-waiting (step 0), sh-ewb-ask, sh-ewb-portal, sh-ewb-details,
sh-ewb-details-error, sh-ewb-truck, sh-ewb-checking, sh-ewb-problem.
Do:
- Step 0 question with "Yes, make one" / "No e-way bill needed", neither preselected, answerable
  before acceptance.
- Part 1: NvCopyRow for truck number and carrier transporter ID with the portal field names from
  copy.md; "Open the e-way bill portal" (existing link); "I have made it. Enter the details".
  No transporter ID: show the empty-state guidance from cp-copy.png.
- Part 2 form: four fields with the help and error copy in copy.md; GSTIN equal to the carrier's
  transporter ID is an error.
- Truck-missing, checking and problem states as in the mockups. The NaviG8r-never-makes-a-bill
  line appears once per screen in small type.
- The primary button must be visible without scrolling at 360 x 800 in sh-ewb-portal.
Tests: copy rows copy values without spaces and announce; neither step-0 option is selected
initially; 11-digit bill number shows "This has 11 digits. An e-way bill number has 12.";
transporter ID entered as GSTIN shows its error; footnote appears exactly once; a test at
Size(360, 800) asserting "Open the e-way bill portal" is fully on screen (tester.getRect within the
view) (reason: "success criterion: primary action visible without scrolling").
```

---

## PR 6: carrier bookings

```text
PR 6: "Carrier bookings: accept with a truck, truck on the bill, delivery, payment".

Mockups: ca-home, ca-bookings, ca-booking-new, ca-accept-empty, ca-accept-chosen,
ca-booking-truck, ca-booking-deliver, ca-booking-owner, ca-booking-dispatcher.
Do:
- Booking screen title "Booking" + shipper name (never "Proof of delivery" before delivery).
- Accept opens NvSheet "Which truck carries this trip?": fleet list, nothing chosen, primary
  disabled with "Choose a truck first.", label becomes "Accept with [truck]".
- Truck-on-bill step with copy rows (bill number, truck number).
- Confirm delivery disabled until the proof-of-delivery photo is added.
- Owner payment block shows only "You receive" and the carrier's amount, never the shipper's price or
  NaviG8r's cut (owner hard rule, 21 Oct 2026). Dispatchers
  see "Delivery confirmed" and no amounts. Use the existing role checks; do not add new ones.
Tests: no truck preselected; disabled reason present; dispatcher widget tree contains no "₹";
owner tree contains all three labels; booking title is not "Proof of delivery" in any pre-delivery state.
```

---

## PR 7: carrier trips, publish, profile

```text
PR 7: "Carrier trips, start confirmation, publish and profile".

Mockups: ca-trips, ca-trip, ca-assign, ca-start, ca-publish, ca-profile, ca-vehicle-sheet.
Do:
- Trip cards open the trip; remove View and Start buttons from the list.
- Trip screen: "Room left: N kg of C kg", truck and driver card, Assign driver sheet (nothing
  preselected), Start trip only here, behind the ca-start confirm sheet. The missing-truck warning
  shows only when a booking's bill lacks the truck.
- Publish: fields empty by default; truck size as chips.
- Profile: transporter ID help text; trucks list; vehicle size as a choice (replaces the typed
  "Vehicle class (SMALL|MEDIUM|LARGE)"); Remove truck only on the truck screen; bank details owner-only.
- If the owner's vehicle registration is empty while the fleet has trucks (brief section 4), show
  the fleet's trucks list instead of an empty field.
Tests: trip list cards contain no "Start" text; Start on the trip screen opens a sheet before any
API call; publish fields start empty; no "SMALL|MEDIUM|LARGE" text anywhere; dispatcher profile
has no bank section.
```

---

## PR 8: driver

```text
PR 8: "Driver screens: today, next stop, e-way bills, confirm delivery".

Mockups: dr-today, dr-trip, dr-ewb, dr-confirm, dr-done, dr-profile.
Do: 56 dp primaries; "Show e-way bills" one tap from the trip; bill numbers in NvText.idDisplay;
missing truck on a bill shows the problem copy and "Call [carrier]"; confirm needs the photo.
Add test/driver_no_money_test.dart: pump every driver route with a fixture that includes prices and
payouts, and assert no Text widget contains "₹", "paid", "commission", "receive", "payout" or the
word "net" (regex \bnet\b, case-insensitive) (reason: "brief 2: a driver never sees money").
Also: driver tabs are exactly Today, Trips, Profile (already in PR 3; keep the test green).
```

---

## PR 9: shipper web layout

```text
PR 9: "Shipper screens at desktop width".

Mockups: wb-lanes, wb-book, wb-shipment, wb-shipments (1280 px).
Do: at width >= 1024, a top bar with logo, nav (Home, Find a lane, Shipments) and the account
button; content max-width 1200; two columns (main + side) that stack below 1024. Lanes become a
card grid; Book puts the price card in the side column; the shipment puts details, messages and
"Change or cancel" in the side column; the shipments list is a table inside a horizontal-scroll box.
Same widgets and copy as the phone; no web-only behaviour.
Tests: at Size(1280, 900) the price card and the Pay button are on screen together; at Size(360, 800)
the layout is the phone layout.
```

---

## PR 10: copy, accessibility and text-scale sweep

```text
PR 10: "Copy and accessibility sweep".

1. Grep the app for any user-visible string not in copy.md and either match it to copy.md or list
   it in the PR for me to decide.
2. Grep for raw formats: ISO dates, "AM"/"PM", "net", ".toStringAsFixed(2)" on money, "SHP_",
   "HTTP". Replace with lib/ui/format.dart.
3. Implement every announcement in accessibility.md ("What a screen reader announces") with
   SemanticsService.announce or a live region, plus focus moves listed there.
4. Add a test that pumps each main screen at textScaler 2.0 and Size(360, 800) and expects no
   overflow errors (FlutterError for RenderFlex overflow) (reason: "brief 7: 200% text").
5. Add a semantics test that every IconButton (if any remain) has a tooltip/label.
Report anything you could not fix as "Not verified".
```

---

## Prompt R: review (run on each PR before merging)

```text
Review PR #<n> against docs/PR-STANDARD.md and docs/design-mobile-app/handoff/spec/.
In order:
1. Scope: does it do one thing? Name unrelated changes.
2. Spec: for each screen touched, compare to the PNG in handoff/screens/ and the strings in
   spec/copy.md. List every mismatch in words, layout order or primary action.
3. Guardrails in spec/decisions.md: new feature, new endpoint, permission change, money on a
   driver route, preselected choice, raw code in UI, dark mode, emoji. Any one is blocking.
4. Tests: for every user-visible element the PR adds or changes, name the assertion that protects
   it. List elements with none.
5. Did `flutter analyze` and `flutter test` run (look for pasted output)? If not, run them.
6. Money, auth, payouts or roles touched? Say "needs a human review" explicitly.
Output a short list: blocking, should fix, fine. Do not approve; I merge.
```
