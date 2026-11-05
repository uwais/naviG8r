# Codebase map

This branch had no map. The full map lives on the `docs/codebase-documentation` branch, not yet merged; when the two
meet, fold these sections into it. Until then this file covers only what the Load Board added or changed.

**What gets written down here:** any new folder, any new file a change recipe needs, and any trap that cost time.

## Layout

| Directory | What lives there and why |
|---|---|
| `apps/api/src/features/loadBoard/` | The Load Board: a shipper posts a load that fit no route, approved carrier offices answer with an ordinary route. Its own folder because it is a feature with its own record, rules and audiences, not a change to booking |

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
| `tests/` | `loadBoardVisibility.test.ts` (who sees what), `loadBoardRules.test.ts` (every rule), `loadBoardPersistence.test.ts`; `loadBoardSetup.ts` is their shared set-up, not a test |

## Entry points

- API server: `apps/api/src/index.ts`, which calls `createApp` in `httpServer.ts`.
- API tests, from the repo root: `node --experimental-strip-types --test $(find apps/api/src packages -name '*.test.ts')`.
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
- **The Load Board sweep runs before every request**, right after the unpaid-booking expiry in `httpServer.ts`, so a
  load whose booking just expired is back on the board in the same request. There is no timer.
- **A route for a load is checked against the booking radius.** Booking refuses a route whose ends are more than
  15 km (`PHASE_A_MAX_PICKUP_KM`) from the shipper's points, so making the route refuses that first, with no distances
  in the answer: they would tell the carrier where the shipper's points are.
