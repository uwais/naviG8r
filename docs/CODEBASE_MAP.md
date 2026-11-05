# Codebase map

This branch had no map. The full map lives on the `docs/codebase-documentation` branch, not yet merged; when the two
meet, fold these sections into it. Until then this file covers only what the Load Board added or changed.

**What gets written down here:** any new folder, any new file a change recipe needs, and any trap that cost time.

## Layout

| Directory | What lives there and why |
|---|---|
| `apps/api/src/features/loadBoard/` | The Load Board: a shipper posts a load that fit no route, approved carrier offices answer with an ordinary route. Its own folder because it is a feature with its own record, rules and audiences, not a change to booking |
| `apps/driver_pilot/lib/load_board/` | The Load Board's app screens for both sides: the shipper's Post a load and My loads, the carrier office's board and Load alerts switch. One folder for the feature, not split into `shipper/` and the carrier file, because both sides share its words |

### `apps/api/src/features/loadBoard/`

| File | What it does |
|---|---|
| `postedLoad.ts` | The posted-load record, its four states, the limits agreed on 4 Nov 2026, and India-day date helpers |
| `postedLoadInput.ts` | Reads the "Post a load" form, refusing anything outside the rules (pickup days, note length, package sizes) |
| `loadBoardAudience.ts` | Who may post, who may read the board (approved carrier owners and dispatchers only), and whether a stored Load Board notice still belongs to its reader |
| `postedLoadViews.ts` | Who sees what: one response builder per audience (posting shipper, carrier office, staff). Every field is picked by name |
| `postedLoads.ts` | The requests: post, list my company's loads, withdraw, read the board, staff list |
| `routeForPostedLoad.ts` | A carrier answering a load: checks before today's route form publishes the trip, then records it on the load and tells the shipper |
| `postedLoadLifecycle.ts` | Booked when its own shipper books a route made for it; the sweep that reopens a load whose booking fell through and expires loads past their pickup window |
| `loadAlerts.ts` | The two Load Board notices and their words, and each carrier user's load-alerts choice |
| `tests/` | `loadBoardVisibility.test.ts` (who sees what), `loadBoardRules.test.ts` (every rule), `loadBoardPersistence.test.ts`, `opsPostedLoadsCard.test.ts` (the staff card); `loadBoardSetup.ts` is their shared set-up, not a test |

The staff view is the "Load Board" card on `/ops/beta`, in `apps/api/src/opsConsoleBetaPostedLoads.ts` beside the
page's other cards. Read only; it reads `GET /ops/posted-loads`.

### `apps/driver_pilot/lib/load_board/`

| File | What it does |
|---|---|
| `posted_load_words.dart` | The plain words both sides use for a posted load: route, size, pickup days, state label, and India calendar days |
| `post_a_load.dart` | Shipper: the Post a load form, opened from a route search that found nothing (`LoadToPost` carries the search in memory) |
| `my_loads.dart` | Shipper: My loads, each load with the trips carriers added; Book opens today's `/customer/book` for that trip |
| `load_board_screen.dart` | Carrier office: the board, and the Home card that opens it. `seesLoadBoard()` is the office check (`trip.assign`) |
| `trip_for_load.dart` | Carrier office: what today's Add a trip form gets for a load (`LoadForTrip`), the line above the form, and the server's refusals in words |
| `load_alerts_switch.dart` | Carrier office: the Load alerts on or off switch on the Company screen |

Wiring outside the folder: the Post a load button is in `_NoMatchBox` (`shipper/find_a_lane.dart`); the routes
`/customer/post-load` and `/customer/loads` are in `shipper/shipper_routes.dart`, `/driver/load-board` and
`/driver/load-board/trip` in `driverFlowRoutes` (`driver_flow.dart`), which also takes `forLoad` on
`DriverPublishTripScreen`; access is in `organization_access.dart`; notice taps go through `openPostedLoadNotice`
(`notification_center.dart`) from the Updates rows, the bell banner (`notification_bell.dart`) and a push
(`_openPushNotification` in `main.dart`).

## Entry points

- API server: `apps/api/src/index.ts`, which calls `createApp` in `httpServer.ts`.
- API tests, from the repo root: `node --experimental-strip-types --test $(find apps/api/src packages -name '*.test.ts')`.
- App tests, from `apps/driver_pilot`: `flutter test` and `flutter analyze`. The Load Board's are
  `test/load_board_shipper_test.dart`, `test/load_board_carrier_test.dart` and `test/load_board_notices_test.dart`.
- Load Board routes, all in the `httpServer.ts` route table next to `POST /v1/pilot/anchor-trips`, and allowed in
  `rbacRoutes.ts`: `POST|GET /v1/posted-loads`, `POST /v1/posted-loads/:id/withdraw`, `GET /v1/load-board`,
  `GET|PATCH /v1/me/settings`, `GET /ops/posted-loads`. A route for a load is today's `POST /v1/pilot/anchor-trips`
  with a `postedLoadId`. Booking is today's `POST /shipments/book`, unchanged apart from `markPostedLoadBooked`.

## Change recipes

**To show a carrier one more field of a posted load:** add it to `loadForCarrier` in `postedLoadViews.ts`, then add its
name to the exact key list in the first test of `tests/loadBoardVisibility.test.ts`. You should see that test fail until
both are changed, and pass after. Never add an amount, the shipper's name, a map point or the note: the same test checks
for each.

**To add a rule to posting:** put the check in `readPostedLoadInput` (`postedLoadInput.ts`) with its own error code, and
a refused case in the first test of `tests/loadBoardRules.test.ts`. You should see `{ status: 400, error: "<your code>" }`
and nothing stored.

**To add a Load Board notice kind:** add its event key and words in `loadAlerts.ts`, call `notify` with the audience, and
add the key to the `IN (...)` list in `readGroupedInboxPageFromDatabase` (`persistenceDb.ts`). In file mode you should
see it in `GET /v1/notifications` and `GET /v1/notifications/shipments` (a row with `postedLoadId` and `loadRoute`).

**To show one more field of a posted load in the app:** word it in `posted_load_words.dart`, add it to the facts list
in `_loadCard` of `my_loads.dart` (shipper) or `load_board_screen.dart` (carrier, only if the server's `loadForCarrier`
sends it), and check for its words in `test/load_board_shipper_test.dart` or `test/load_board_carrier_test.dart`. You
should see the new line on the card in the test, and `flutter test` pass.

## Gotchas learned the hard way

- **The data file is version 8.** `persistence.ts` reads versions 1 to 8 and always writes 8. A server built before the
  Load Board refuses a version 8 file (`unsupported_store_version`), so rolling back past this change needs the file
  from before it, or a hand edit of `version` back to 7 (the extra lists are then ignored).
- **In database mode the Load Board's lists are JSON, not tables.** `postedLoads` and `loadAlertSettings` are kept in the
  one `IntegrationState` row with the other JSON lists (`integrationMaps` in `persistenceDb.ts`), so no Prisma migration
  was needed. A Load Board notice keeps its load id in the notification's `data`, as a new-trip notice keeps its trip.
  The database inbox query was changed but has not been run against Postgres: those tests skip without a database.
- **`trip.publish` includes drivers.** The board and making a route for a load check the carrier office role
  themselves (`requireBoardViewer`), since the route guard's permission alone would let a driver through.
- **A trip for a load sends the load's towns, not the place box's words.** A place search rewrites the box to Google's
  name ("Pune, Maharashtra"), and the server matches the load's towns, so `DriverPublishTripScreen` sends
  `forLoad.fromCity` and `forLoad.toCity` as `originCity` and `destCity`. Sending the box text gets
  `route_cities_do_not_match_load`.
- **Post a load and a trip for a load take their data as the router's extra.** A reload has none, so
  `/customer/post-load` goes back to the route search and `/driver/load-board/trip` back to the board.
- **The Load Board sweep runs before every request**, right after the unpaid-booking expiry in `httpServer.ts`, so a
  load whose booking just expired is back on the board in the same request. There is no timer.
- **A route for a load is checked against the booking radius.** Booking refuses a route whose ends are more than
  15 km (`PHASE_A_MAX_PICKUP_KM`) from the shipper's points, so making the route refuses that first, with no distances
  in the answer: they would tell the carrier where the shipper's points are.
