# Screen inventory

Every mockup in `mockups/` (PNG in `screens/`), what it is for, the state that shows it, and the one primary action. Build the screens; do not build the mockup HTML. Field names refer to brief section 9 ("What the screens get from the server"). If a field below does not exist in `pilot_api.dart`, stop and report it; do not add an API.

## Navigation

| Role | Tabs (in order) | Today | Change |
|---|---|---|---|
| Shipper | Home · Find a lane · Shipments | Home, Trips, Book, Shipments | "Book" tab removed: booking starts from a lane card. Notifications open from a Home row ("Updates") |
| Carrier office (owner, dispatcher) | Home · Bookings · Trips · Publish · Profile | Home, Shipments, Loads, Publish, Profile | Renamed only |
| Driver | Today · Trips · Profile | Same five as office | Publish and Bookings removed for drivers |
| Signed out | No tabs | All five tabs show | Only the start screen and sign-in |

Header on every signed-in screen: one button = company name (title) + "Person · Role" (subtitle) + chevron. Opens the account menu. Remove the org drop-down, refresh icon, sign-out icon and avatar from every screen. Detail screens add a Back button on the left. Pull to refresh replaces the refresh icon.

"Developer lab" (`/pilot-lab`) and the carrier home's "Sign in with phone" / "Register as new carrier" links: hide in release builds (`kReleaseMode`), keep in debug.

## Start and sign in

| Mockup | Shows when | Primary action | Notes |
|---|---|---|---|
| `Main` | Signed out, app start | (two choice cards) | Replaces the Flutter logo screen. Choice only sets which sign-in copy and post-login landing to use; it grants nothing |
| `c-signin` | After a choice | Send code | +91 fixed prefix, `autofillHints: telephoneNumberNational` |
| `c-code` | After Send code | Sign in | One OTP field, `autofillHints: oneTimeCode`. No "Challenge id" field (keep the id in state) |
| `c-code-error` | Verify fails | Sign in | Error under the field, `role=alert` equivalent |
| `c-menu` | Tap header | (sheet) | Lists organizations from the signed-in person; radio to switch; Add a company; Sign out |

## Shipper

| Mockup | Shows when | Primary action | Data |
|---|---|---|---|
| `sh-home` | Shipper Home | First "needs you" task, else Find a lane | Shipments needing the shipper (e-way bill pending) |
| `sh-lanes-browse` | Find a lane, Browse | (cards open lanes) | Trip: origin, destination, carrier, window, truck size, room left = capacity − booked, status |
| `sh-lanes-match` | Find a lane, Match my route | (cards) | Server already filters by room and orders by closeness. Do not re-sort |
| `sh-lanes-empty` | Match returns none | Change weight | Copy in `copy.md` |
| `sh-book-start` | Lane opened, no price yet | Book and pay, disabled, saying what is missing | Weight/pickup/drop and pins prefilled from the search, else empty. The price is fetched by itself once all three are in |
| `sh-book-price` | Price returned | Book and pay ₹X | Any change to weight or a pin fetches a new price; an answer for older inputs is dropped. One tap books (holding the room on the lane), then opens the existing Razorpay flow (no confirm sheet since 19 Oct 2026) |
| `sh-book-error` | `insufficient_capacity` | Book and pay, disabled | Message already merged/under review in code: reuse it |
| `sh-ship-waiting` | Booking status Awaiting carrier acceptance, e-way bill answer missing | Yes, make one | Step 0 can be answered before acceptance |
| `sh-ewb-ask` | Same status, answer = needed | (none: waiting) | "You can make the bill once the carrier accepts and names the truck." |
| `sh-ewb-portal` | Accepted, truck known, no bill yet | Open the e-way bill portal | Truck number (portal format) and carrier transporter ID, each with Copy |
| `sh-ewb-details` | "I have made it" | Save e-way bill | Bill number, bill date, maker GSTIN, invoice number |
| `sh-ewb-details-error` | Validation fails | Save e-way bill | 12-digit check; GSTIN equal to carrier transporter ID is an error |
| `sh-ewb-truck` | Bill saved, truck not on it | Add truck | The shipper adds it in its billing software or on the e-way bill site, then enters it here; truck filled in from acceptance (owner decision, 18 Oct 2026) |
| `sh-ewb-checking` | Bill + truck saved, ops not checked | (none) | Bill number, truck, valid-until |
| `sh-ewb-problem` | Ops marked a problem | Fix the details | Shows ops' message. If the API has no structured "difference", show the ops note text |
| `sh-ship-transit` | In transit | Message carrier | Truck, driver name, bill number |
| `sh-ship-delivered` | Delivered | View proof of delivery | |
| `sh-shipments` | Shipments tab | (cards) | One "Next:" line per card from the step mapping below |
| `sh-notifications` | Home → Updates | (rows) | Name shipments by route + date, never `SHP_…` |
| `sh-ship-noewb` | Answer = not needed | (none) | |
| `sh-ship-cancelled` | Cancelled | Find a lane | Words, never the system code |

## Carrier office

| Mockup | Shows when | Primary action | Data / rule |
|---|---|---|---|
| `ca-home` | Office Home | First needs-you task | |
| `ca-bookings` | Bookings tab | (cards) | Chips: Needs you, Active, Done |
| `ca-booking-new` | Awaiting carrier acceptance | Accept | Title "Booking", never "Proof of delivery". Shows the shipper's e-way bill answer |
| `ca-accept-empty` | Tap Accept | Accept with this truck (disabled) | Truck list from fleet. Nothing preselected (PR #153 behaviour) |
| `ca-accept-chosen` | A truck picked | Accept with [truck] | |
| `ca-booking-truck` | Bill exists without truck | (none: read only) | "[Shipper] has not added the truck to the bill yet." The carrier only reads the bill (owner decision, 18 Oct 2026) |
| `ca-booking-deliver` | In transit | Confirm delivery | Disabled until proof of delivery photo added |
| `ca-booking-owner` | Delivery confirmed, owner | (none) | Owner only: you receive. Never the shipper's price or NaviG8r's cut |
| `ca-booking-dispatcher` | Same, dispatcher | (none) | No amounts. Status "Delivery confirmed" |
| `ca-trips` | Trips tab | (cards) | No View/Start buttons on cards; whole card opens |
| `ca-trip` | Trip opened | Assign driver (or Start trip once a driver exists) | "Room left: N kg of C kg". Start lives only here |
| `ca-assign` | Tap Assign driver | Assign [name] | Nothing preselected (mockup shows a choice made) |
| `ca-start` | Tap Start trip | Start trip | New confirm sheet. Warning only if a booking's bill lacks the truck |
| `ca-publish` | Publish tab | Publish trip | Fields start empty (mockup shows them filled). Truck size is a chip choice |
| `ca-profile` | Profile tab (owner) | (rows) | Bank details owner only. Transporter ID help text distinguishes it from the shipper GSTIN |
| `ca-vehicle-sheet` | Truck row opened | Save truck | Replaces typed "Vehicle class (SMALL\|MEDIUM\|LARGE)" with a choice. Remove truck is here, not on lists |

## Driver

| Mockup | Shows when | Primary action | Rule |
|---|---|---|---|
| `dr-today` | Today tab | Open today's trip | 56 dp primaries |
| `dr-trip` | Trip in transit | Directions | "Show e-way bills" is always one tap away. Start trip appears here before departure |
| `dr-ewb` | Show e-way bills | (none) | Large mono numbers, valid-until; missing truck shown as a problem with "Call [carrier]" |
| `dr-confirm` | At a drop | Confirm delivery | Photo first |
| `dr-done` | After confirm | Directions (next stop) | Announce "Delivery confirmed" |
| `dr-profile` | Profile tab | (rows) | No bank, earnings or payouts |

**Hard rule:** no widget on any driver route may render price, amount, paid, commission, receive, payout or net. Enforce with a test (see `PROMPTS.md`, PR 8).

## Shipment step mapping (shipper view)

Compute steps from the booking status and e-way bill fields. One function, unit tested, used by the shipment screen, the shipments list "Next:" line and the home "needs you" card.

| Booking status | E-way bill state | Current step | Who | Next: line |
|---|---|---|---|---|
| Awaiting carrier acceptance | no answer | E-way bill question | You | You say if it needs an e-way bill |
| Awaiting carrier acceptance | needed / not needed | Carrier accepts | Carrier | [Carrier] accepts and names the truck |
| Accepted | needed, no bill | E-way bill part 1 | You | You make the e-way bill |
| Accepted | bill, no truck | Truck on bill | You | You add the truck to the e-way bill |
| Accepted | bill + truck, not checked | Bill check | NaviG8r staff | NaviG8r staff check the bill |
| Accepted | ops problem | E-way bill fix | You | You fix the e-way bill |
| Accepted | checked or not needed | On the way (waiting) | Carrier | [Carrier] starts the trip |
| In transit | any | On the way | Carrier | [Carrier] confirms delivery |
| Delivery confirmed / Delivered | any | Delivered | — | (none) |
| Cancelled | any | — | — | (none) |

If the API cannot distinguish a state in this table, list the gap in the PR's "Not verified" section and fall back to the nearest row.
