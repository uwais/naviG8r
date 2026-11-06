# Design brief: choosing pickup and drop on one map

> **Built 5 Nov 2026 to the October design, not to a new one.** The app follows the October design system's Map
> component (`design-place-picker/cp-map.html` and `cp-map.png`): one small map per screen, text fields first, pickup a
> navy dot and drop a gold dot with a navy ring, a "Pickup and drop" chip, a line between them, and the "map could not
> load" state. One addition the owner approved: the map moves one pin at a time, the place whose box was touched last
> (pickup first), said in words ("Tap the map to move the Pickup pin.") with Pickup and Drop chips to switch. Code:
> `apps/driver_pilot/lib/two_place_map.dart`.

Written 5 Nov 2026 for Claude Design. Attach the NaviG8r design system
(https://claude.ai/artifact/Y5Y3QwE9ZRBB4XuHLN2YXD) when you paste this. Where this brief and the system disagree on
looks, the system wins; this brief decides what the screen must do.

## 1. Surface

The part of a screen where a person sets two places, a start and an end. Today it is two separate blocks, each with
its own text box and its own small map (about 220 dp tall). It appears in three places in the phone app:

| Where | Who | What the two places mean |
|---|---|---|
| Book a trip > Search by route | Shipper | Pickup and Drop: full street addresses, for the driver |
| Book this trip (before paying) | Shipper | Pickup and Drop: full addresses; moving either pin changes the price |
| Add a trip | Carrier office | From and To: town names only, for the trip's listing |

Design one place picker that works in all three, with one map.

## 2. Who uses it, and for what

- **Shippers:** small Delhi-area businesses booking space on a truck, mostly on low-cost Android phones (one
  tester's phone is 720 px wide), often in a hurry, sometimes on weak data. Job: "tell the driver exactly where to
  collect and deliver", and get a price.
- **Carrier office staff:** owners and dispatchers publishing a trip. Job: "say which towns this truck runs between".
- Today they type an address, tap search, check the pin on its own map, then scroll to a second map for the other
  place. People expect one map, as in ride and truck-booking apps.

## 3. Success

- Both places set in under 30 seconds, without scrolling between two maps.
- It is always clear which of the two places the map is editing.
- Works at 360 dp wide and at 200% system text size, with no text cut off.
- A person who cannot use the map (screen reader, no data for map tiles) can still set both places by typing.

## 4. How it works today (keep these behaviours)

- A text box, then a search button. The search finds one best match and drops the pin there.
- The pin can be dragged, and as of 5 Nov a tap on the map also moves it. After a move, the address under the
  pin is looked up and shown.
- Shipper screens keep the full address the person typed (up to 500 characters) and show the looked-up address
  under it. Carrier screens keep only the town name.
- When search fails or is unavailable, the screen says so and asks the person to place the pin by hand.
- On Book this trip, any change to either place clears the shown price until it is worked out again.
- A shipper's pickup and drop must each be within 15 km of the trip's ends to book it; the screen says so when not.

## 5. What to design

- Two text boxes, pickup above drop (or From above To), each clearly labelled, with search.
- One map below them showing both pins in two clearly different colours and shapes (not colour alone), and a line
  between them when both are set.
- One place is "being edited" at a time: the box the person last touched. Map taps and drags move only that pin.
  Show which one is being edited in words, not only by colour.
- A way to switch which pin is being edited without typing, from the map itself.
- The map fits both pins in view after each change.
- States to draw: nothing set; one set; both set; searching; search found nothing; search unavailable; looking up
  the address under the pin; the read-only version (shown after booking).
- Phone (360 dp) and the web layout at 1280 px, where the map can sit beside the boxes.

## 6. Hard constraints (not negotiable)

- Light mode by default: warm off-white page (#F8F7F2), white only for raised cards, warm near-black text
  (#2B2620). Dark mode only as an explicit setting, never from the phone's setting.
- No emoji anywhere.
- WCAG AA: 4.5:1 text, 3:1 large text, borders and focus rings. Colour is never the only signal.
- Touch targets at least 48 x 48 dp. Every icon button has a spoken label. Search results and errors are
  announced to screen readers.
- No dark patterns: no pre-filled places the person did not choose (except from their own earlier search), no
  urgency, a clear way to change either place, plain neutral wording.
- Copy: plain, short, the product's words (pickup, drop, trip, town). Errors say what went wrong and what to do.

## 7. What this is not

- Not live tracking, not a route planner, not turn-by-turn directions.
- No suggestions as you type: today's search finds one best match after the person taps search. Type-ahead
  suggestions would need a paid Google service the team has not approved (see section 9). Design for search-then-
  pin; show where suggestions would go only as a clearly marked option.
- No current-location button for now (it needs location permission on every screen; not in scope).

## 8. Data the screen has

- For each place: the typed words, a map point (latitude, longitude), and the address looked up for that point.
- For carrier screens: the town name instead of a full address.
- Search answers: one result, or nothing found, or search unavailable.

## 9. Questions for the team

- Type-ahead suggestions: worth a paid Google service? (Owner's decision; cost not yet checked.)
- Does the shipper's Post a load form (towns only, from a failed search) also need the map? Today it has none.

## 10. Output wanted

- The handoff folder and standalone HTML pages for each state in section 5, at 360 dp and 1280 px.
- Component specs: the place box, the "being edited" marker, the two pins, the map frame, error and loading lines.
- Exact copy for every label, hint, error and announcement.

## 12. Round 2 (5 Nov): short phones and the keyboard

Found by the owner on a real phone (LG, 720 x 1280 at 320 dpi, so 360 x 640 dp, normal text size). The build
follows sections 1-11 and the October Map component; this round is about fit.

- **Tighter spacing on short screens (approved).** On a 360 x 640 dp phone the boxes, cards and buttons feel too
  large and the map falls below the fold. Design a compact spacing step for screens shorter than about 700 dp:
  smaller gaps, card padding and type steps, while touch targets stay at least 48 x 48 dp and text still fits at
  200%. Apply it to the design system, not just this screen, and show Search by route, Book this trip and Add trip
  at 360 x 640.
- **The keyboard hides the map.** With the keyboard up (about half the screen), the person typing cannot see the
  map or the result of their search. Solve this. One option: tapping a place box opens a search page with the box at
  the top and results below; after a place is picked, the form returns with the map showing both pins. Show the
  option you choose, with and without the keyboard.
- **Suggestions while typing (not yet approved).** Leave room for a list of suggestions under the box in the
  search page, marked as optional; the team is checking cost (Google's India price list shows a free monthly
  allowance) before deciding.

## 11. Dark pattern screen

```
DARK PATTERN SCREEN — one-map place picker — 2026-11-05
Screened: this brief, sections 1-10
Verdict: PASS
 1. Actionability — N/A — nothing is ranked or recommended; search shows one match the person sees on the map.
 2. Honest comparison — N/A — no comparison shown.
 3. Full cost — PASS — on Book this trip any place change clears the price until it is worked out again.
 4. Urgency — PASS — none.
 5. Defaults — PASS — places come only from the person's own earlier search; the pin being edited starts on pickup.
 6. Exit — PASS — either place can be changed at any time before booking.
 7. Decline copy — N/A — no decline buttons.
 8. Promise matches delivery — PASS — the address looked up under the pin is shown under the typed address, so a
    mismatch is visible before booking.
 9. Data asked — PASS — only two places; no location permission.
10. Money — PASS — nothing earned from this screen.
11. Said to face — PASS — "Type each place, check its pin on one map, then book."
Accepted risks: none.
```
