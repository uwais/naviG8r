# Decisions, guardrails and open items

## Guardrails (from the brief, not negotiable)

1. **No new features.** Layout, order and words only. Every action exists today. If a screen needs data or an endpoint that does not exist, stop and report it; do not add it.
2. **No permission changes.** Owners, dispatchers, drivers and shippers keep exactly what they can do today.
3. **Drivers never see money.** No price, amount, payout, commission or "net" on any driver route, in any state.
4. **Light mode only.** `themeMode: ThemeMode.light`, no `darkTheme`.
5. **No emoji.** Not in copy, labels, notifications or icons.
6. **No dark patterns.** Full price on the same screen as Pay; nothing preselected; neutral decline words; the way out (the named contact) as visible as Book; ranking only by closeness to the route.
7. **No raw codes.** No `HTTP 400`, `SHP_…`, `PENDING_RELEASE`, field names or IDs a user did not ask for.
8. **48 dp targets, 360 dp width, 200% text.** Primary action visible without scrolling at 360 x 800.

## Design decisions the build follows

| Decision | Why |
|---|---|
| Shipper tabs: Home, Find a lane, Shipments; Book reached from a lane card | A Book screen with no lane is how stale prices and guessed weights happened |
| Driver tabs: Today, Trips, Profile | Drivers do not publish or manage bookings |
| Carrier "Shipments" → "Bookings", "Loads" → "Trips" | The product's words |
| One header button replaces org drop-down, refresh, sign-out, avatar | Brief: "one menu for switching company and signing out" |
| Pull to refresh replaces the refresh icon | Frees the header |
| Start trip only on the trip screen, behind a confirm sheet | A slip on the list started trips |
| Start sheet warns when a booking's bill has no truck | Uses existing bill fields only |
| The shipper adds the truck to the e-way bill; every carrier login only reads it (Rishabh, 18 Oct 2026, replacing Uwais's 15 Oct answer) | The shipper makes the bill, so it holds Part B too; the carrier pays check-post fines, so it still sees the bill's state |
| No confirm sheet before the payment provider: Pay ₹X opens it in one tap (Rishabh, 19 Oct 2026, replacing the confirm sheet) | The full price, the no-cancel rule and what happens after Pay now sit on the Book screen beside Pay, so the sheet only repeated them |
| The price is fetched by itself, and any change to weight or a pin fetches a new one (Rishabh, 19 Oct 2026, replacing "Get price") | Brief A.2: the price shown is the price charged; the old price goes the moment an input changes |
| E-way bill step 0 can be answered before acceptance | Brief B: the carrier sees the answer before accepting |
| Portal field names on copy rows | Testers could not tell GSTIN from transporter ID |
| Fonts bundled as assets | Drivers have weak signal |

## Open items: use the placeholder, do not invent

| Item | Placeholder in copy | Owner |
|---|---|---|
| Contact shown for change or cancel | `[NaviG8r contact]` | Team (brief question 6) |
| One line on when an e-way bill is needed | `[One line from the team on when an e-way bill is needed.]` | Team (question 7) |
| Truck size guide | `[Size guide from the team]` | Team |
| Tax on top of price | None shown (accepted risk) | Accountant (question 5). If tax applies, it must appear before Pay |
| Known payment issue behind "collected after delivery" | Copy as written | Rishabh (dark-pattern item 8) |
| Languages and small phones for drivers | English, 360 dp | Team (question 1) |
| One app or two for shippers | One app with the start-screen choice | Team (question 2) |

Put placeholders in one constants file (`lib/ui/pending_copy.dart`) so they are easy to find and replace.

## Facts to verify before shipping

- **E-way bill portal field names.** As far as the designer knows, Transporter ID sits in Part A (transporter details) and Vehicle No. in Part B. The brief said both go in at Part B. Confirm on the live portal and correct the "Portal field:" strings if needed.
- **Validity rule** "one day per 200 km, ending at midnight India time": confirm wording with whoever owns compliance copy.
- **Status words** in `copy.md` map to the API statuses in brief section 9. Confirm the mapping table in `screens.md` against `pilot_api.dart`.
