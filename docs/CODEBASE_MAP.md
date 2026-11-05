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

## Entry points

- API server: `apps/api/src/index.ts`, which calls `createApp` in `httpServer.ts`.
- API tests, from the repo root: `node --experimental-strip-types --test $(find apps/api/src packages -name '*.test.ts')`.

## Gotchas learned the hard way

- **The data file is version 8.** `persistence.ts` reads versions 1 to 8 and always writes 8. A server built before the
  Load Board refuses a version 8 file (`unsupported_store_version`), so rolling back past this change needs the file
  from before it, or a hand edit of `version` back to 7 (the extra lists are then ignored).
