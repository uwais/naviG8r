# Conversation timeline and grouped notification inbox plan

**Status:** Reviewed and revised after Astra-High feedback on 2026-10-07; implementation and DB-side grouping are on `feat/inapp-notifications-communication`. Release review remains open. No changes to `main`.

## Goal

Present each shipment as one notification-inbox row while showing that shipment's workflow notifications and text messages together in a paginated conversation timeline. Preserve the existing canonical message and per-recipient notification records; do not copy notification events into the text-message table.

## Agreed product behavior

- The notification inbox displays at most one row per shipment for the selected active organization and signed-in user.
- Each row uses a generic **Shipment update** heading, shipment reference, latest activity time, and unread update count. A single unread event may use “New update”; multiple unread events show a count such as “3 new updates.” Do not expose message text or payment amounts in the inbox summary.
- Any new message or workflow notification increments that shipment's unread count and moves its row to the top. The global bell count is the total unread event count; a row count is the unread event count for that shipment.
- Inbox pagination is a fixed per-recipient snapshot: the first page returns a notification sequence watermark; later pages use that same watermark so new events cannot move shipment groups across the current page boundary. Refresh starts a new snapshot. Unread/read count changes do not change activity ordering.
- Tapping a row opens the shipment conversation timeline. The timeline interleaves canonical messages with the current user's authorized workflow notification events. Render messages as left/right chat bubbles and workflow events as centered system cards.
- Do not render `conversation.message` notification rows as timeline cards; the canonical message is already displayed once in the timeline. Keep those notification rows for unread accounting and inbox deep-link/read behavior.
- If two items have the same stored UTC millisecond timestamp, render the human-authored message first, followed by the system event. Use stable item identity as the final tie-breaker. This is a display tie-break preference, not a change to event timestamps.
- Workflow event cards come from that user's per-recipient notification rows. A member added later does not receive historical notification rows, although current shipment authorization may allow them to read canonical conversation messages. OPS escalation provides access to its grant-scoped canonical conversation only; it does not expose another recipient's event rows.
- Sender-owned message notifications remain unread until acknowledged, consistent with the current fanout contract. Opening the conversation acknowledges the sender's event row and message through the returned read watermark.
- Do not backfill this rollout's historic notification recipients or event cards. Current membership cannot prove historical recipient eligibility. Keep this iteration limited to event rows captured after enablement.

## Current baseline

- PostgreSQL Prisma models: `ConversationRow`, `ConversationMessageRow`, `NotificationRow`, `ConversationReadStateRow`, and `ConversationEscalationGrantRow`.
- FILE persistence stores the same communication maps in Store format version 6.
- `GET /v1/notifications` currently returns individual notification rows with a timestamp/ID cursor and scans the in-memory notification map.
- `GET /v1/shipments/:shipmentId/conversation/messages` currently returns only messages, paginated by per-conversation sequence, and updates message read state while handling the GET.
- Before the grouped/timeline work, DB mode hydrated communication rows into the in-memory Store and list functions did not use PostgreSQL pagination even though several lookup indexes existed.
- Message reads currently calculate `canSend` from the reply deadline alone; the new timeline must include active membership/role permissions and OPS grant capability.
- Notification fanout creates one `NotificationRow` per recipient per event. Message notification rows reference the canonical message and do not store its body.

## Implementation progress

- Added Store format version 7 and a stable notification sequence watermark, with version-6 file migration.
- Added grouped inbox and unified timeline endpoints while preserving the existing flat notification and message routes.
- Timeline cursors use an exclusive `(timestamp, priority, item ID)` boundary; message priority is `0`, workflow-event priority is `1`, and the cursor points at the oldest returned item.
- DB-mode timeline source reads use bounded Prisma queries; Store remains the serialized mutation owner. FILE mode continues to aggregate in memory; DB mode uses the new PostgreSQL grouping query described below.
- DB-mode grouped inbox now aggregates groups/unread totals in PostgreSQL and fetches only `limit + 1` groups for the page. It retains the known Store hydration/serialized-write architecture; aggregation work is proportional to matching recipient history and is not claimed to be bounded.
- Added timeline read acknowledgement bounded by the returned notification/message snapshot.
- Flutter inbox and conversation screens now use the grouped inbox and mixed timeline, render generic shipment rows and centered workflow cards, and acknowledge the snapshot on open.
- Validation on 2026-10-07: full API/package suite with disposable PostgreSQL integration enabled: 207 passed, 1 skipped; Prisma schema validation and TypeScript check passed; full Flutter suite on Flutter 3.22.3: 46 passed; Flutter web build passed; changed-file Flutter analysis passed; grouped inbox/timeline Playwright flow passed. On 2026-10-08, the PostgreSQL timeline integration passed with page-size-one equal-timestamp ties, both cursor priorities, legacy null-conversation events, late-arrival snapshot/read boundaries, and database reload assertions. Repository-wide Flutter analysis exits nonzero on 36 informational lints elsewhere in the app. The browser flow uses mocked notification/timeline payloads, and captured screenshots do not reliably paint Flutter text, so this is not visual sign-off.
- PostgreSQL integration applied the schema to a disposable PostgreSQL 16 database and verifies grouped paging, stable inbox/timeline snapshots after late activity, timeline event/message ordering and cursor traversal, read persistence after reload, unread totals, and cross-organization isolation. An `EXPLAIN (ANALYZE, BUFFERS)` run over 100,000 synthetic notification rows (10,000 matching one recipient) returned two groups in 4.6 ms and used the recipient/org/shipment/sequence index plus shipment indexes. This is a local synthetic measurement, not production-scale performance evidence.
- Fixed sign-out draft cleanup to tolerate an unavailable secure-storage channel; identity-scoped draft keys prevent cross-account visibility if best-effort deletion cannot run. The complete Flutter suite now passes.

## Implementation tasks

### NTF-TL.1 — Define stable timeline item and cursor contract

Files: `apps/api/src/notifications.ts`, `apps/api/src/httpServer.ts`, `docs/pilot-api.md`, API tests.

- Keep `GET /v1/shipments/:shipmentId/conversation/messages` unchanged for compatibility. Add an authenticated timeline endpoint for an authorized shipment, for example `GET /v1/shipments/:shipmentId/conversation/timeline?limit=50&before=<opaque-cursor>`.
- Return a discriminated union: `message` items contain the canonical message projection; `event` items contain the recipient-safe notification projection. Return `nextBefore` and authoritative `canSend`/conversation metadata.
- Sort chronologically by `(createdAtUtcMs, itemPriority, itemId)`, where message priority is `0` and sorts before workflow-event priority `1` on an exact timestamp tie. Compare IDs bytewise consistently in PostgreSQL and FILE mode; do not depend on host/database locale ordering.
- Fetch each source newest-first, merge and select the newest page, then reverse it for oldest-to-newest rendering. `nextBefore` must encode the **first/oldest item returned in the rendered page**. Older-page queries use an exclusive tuple predicate before that cursor, fetch newest-first, merge, select, then reverse. This is deliberately different from using the last/newest displayed item.
- Use a versioned opaque cursor containing and validating the timestamp, item priority, stable ID, user/org/shipment scope, inbox snapshot watermark, and page-size bounds. Recheck current authorization on every request; the cursor is not an access token.
- Return a server-issued read watermark with the initial newest-page response: the current recipient notification sequence and the highest conversation message sequence as of that snapshot. Older-page fetches retain the initial watermark.
- Migrate Flutter explicitly to `/timeline`; keep the current `/messages` route and its response unchanged in this iteration.
- Exclude `conversation.message` notifications from `event` items to avoid showing one message twice.

**Acceptance:** same-millisecond ordering is deterministic and message-first, including page-size-one tie tests; cursor boundaries neither skip nor repeat items; malformed, cross-user/org/shipment, and old-version cursors are rejected; empty and single-type timelines work; retries produce the same canonical message row only once.

### NTF-TL.2 — Add indexed, bounded database reads

Files: `apps/api/prisma/schema.prisma`, `apps/api/src/persistenceDb.ts`, focused API persistence/query module, disposable PostgreSQL tests.

- Add `recipientSequence` to notification rows, unique within `(recipientUserId, recipientOrgId)`, and allocate it monotonically in the serialized single-writer mutation path. Backfill existing rows deterministically on schema upgrade; migrate FILE persistence to a new version with a compatible old-version reader. The sequence is the inbox snapshot and read-ack boundary; timestamps remain the display order.
- Add timeline lookup indexes matching predicates and order, including conversation + timestamp + ID for messages and conversation + recipient user + recipient org + timestamp + ID for events. Add a recipient/org/shipment/sequence lookup for grouped inbox aggregation and assess a partial unread index from query plans.
- Query only the authorized conversation and current recipient's event rows. Apply composite keyset predicates and fetch at most `limit + 1` rows from each source before merging; do not load all historic rows to build a timeline page.
- Keep PostgreSQL ordering and FILE-adapter ordering identical, including exact timestamp ties and null-safe cursor handling.
- Preserve message-idempotency uniqueness and notification event/recipient deduplication. Do not add foreign-key cascades to snapshot-rewritten parent tables as part of this timeline change.
- Keep mutations owned by the serialized Store path for this iteration. Do not issue direct DB read-state or sequence writes that the next Store flush can overwrite. Synchronize successful persistent state before returning; restore in-memory state on DB write failure. Indexed endpoint reads must not imply that startup hydration or full-history persistence costs have been removed.
- Verify indexed SQL query plans with representative recipient histories and `EXPLAIN (ANALYZE, BUFFERS)`, bounded endpoint row counts, and schema-upgrade coverage. Current deployment remains single API writer until wider Store concurrency is resolved. Direct endpoint pagination does not eliminate full-store startup hydration/flush; a focused repository migration is a separate follow-up.

**Acceptance:** endpoint result sets are bounded by page size, use the intended indexes, preserve page order under equal timestamps, and return only data authorized to the selected active user/org. Grouped inbox aggregation/unread totals are measured separately from result size; do not claim bounded aggregation work without evidence.

### NTF-TL.3 — Group inbox notifications by shipment

Files: notification query/service, `apps/api/src/httpServer.ts`, Prisma schema/query module, API tests.

- Keep `GET /v1/notifications` unchanged. Add a separate grouped inbox route, for example `GET /v1/notifications/shipments?limit=30&before=<opaque-cursor>`, and migrate Flutter explicitly.
- Each group contains the shipment ID, latest activity timestamp, unread event count, safe generic display text, and no embedded message content or payment amount.
- Keep the global unread count as the sum of unread event rows. A shipment row's count is the sum for that user/org/shipment.
- Sort shipment groups by latest event time descending, then shipment ID using the same deterministic bytewise comparison as the cursor. Paginate grouped rows, not raw events followed by client grouping. Each page is evaluated at the first page's fixed recipient-sequence watermark; later notifications appear after refresh, never by silently moving a group through an active cursor set.
- Read counts can change without changing row order. Acknowledged rows stay in the inbox as read activity; they are not removed by read acknowledgement.
- On a new notification, update that shipment's latest time and count. Preserve the event-level records as the durable inbox/read history.
- Enforce current access filtering before group counts and summaries are returned; do not leak foreign shipment IDs through totals, cursors, or group counts.

**Status: implementation complete; release/performance review remains open.** DB integration covers fixed-watermark inbox and timeline pagination, unread counts, tied-item ordering, legacy events, late-arrival/read-watermark isolation, read-state reload, and cross-organization isolation. Keep result pages bounded to `limit + 1`; recipient-history aggregation and Store startup hydration still grow with stored history.

**Acceptance:** one row per shipment per selected recipient scope; multiple unread events increment one row's count; read/revoked membership affects visible counts immediately; new events do not mutate an active pagination snapshot; groups do not duplicate or disappear across pages. Include legacy notifications with null `conversationId` by filtering on `shipmentId` and current authorization.

### NTF-TL.4 — Synchronize thread and notification read state

Files: conversation read service/repository, `apps/api/src/httpServer.ts`, Flutter notification/timeline screens, tests.

- Add an explicit idempotent operation to mark the authorized user's timeline notifications for one shipment as read and advance the message read cursor. Avoid using a GET request to mutate notification read state.
- Acknowledge only notification rows for the shipment with `recipientSequence <= readWatermark.notificationSequence` and messages through `readWatermark.messageSequence`. Notifications/messages arriving after the timeline snapshot remain unread. Preserve an existing `readAtUtcMs` value and advance `lastReadSequence` monotonically.
- Include `conversation.message` alert rows in the notification acknowledgement boundary even though those rows are omitted from timeline event cards.
- Keep the existing single-notification read endpoint for inbox compatibility, but refresh the grouped row and global badge after individual or conversation-level reads.
- Prevent unauthorized callers from changing read state; read operations cannot grant shipment access.

**Acceptance:** in a GET → new message/event → read POST race, the new item stays unread; opening a thread clears only activity through its returned snapshot; other shipment rows remain unread; read state survives an unrelated Store save and restart; repeated read requests are harmless; another org's thread cannot be marked read.

### NTF-TL.5 — Build the unified Flutter timeline and grouped inbox

Files: `apps/driver_pilot/lib/notification_center.dart`, focused widget tests, mobile Playwright coverage.

- Render the grouped inbox rows with **Shipment update**, shipment reference, latest activity time, and per-shipment unread count. The global badge shows total unread event count.
- On tap, open the authorized shipment thread. Render system event cards between participant message bubbles using the API timeline order; preserve role-safe event copy and current read-only/send rules.
- Compute `canSend` from full active membership, role permission, shipment access, OPS grant scope/capability, and reply deadline—not deadline alone. OPS timeline access must not expose shipper/carrier recipient notification rows.
- Support loading earlier timeline items without moving the visible scroll position or duplicating rows. If a live inbox refresh detects newer activity, Flutter starts a new inbox cursor snapshot and merges cards by shipment ID; it does not continue paging a now-stale snapshot. Refresh unread indicators after a thread is marked read.
- Keep message retry/draft identity behavior unchanged. Message alerts navigate to the corresponding thread but do not create duplicate timeline content.
- Ensure narrow phone widths, accessible labels, loading/empty/error states, and no notification preview after sign-out or membership change.

**Acceptance:** UI tests cover a grouped shipment with several events and messages, equal-timestamp message-first ordering, unread counts, opening/read behavior, history pagination and scroll anchoring, empty conversation, sign-out/org-switch stale responses, and authorization/read-only states. Mobile-browser review confirms the inbox and timeline layout at phone and desktop widths.

## Validation and rollout

- Run API unit/HTTP tests for timestamp ties across pages, page-size-one cursors, scope misuse, membership revocation/inactive shipment between requests, OPS read-only grants, late arrivals during acknowledgements, sender unread semantics, and persistence/restart; run type checking, Prisma validation/generation, PostgreSQL integration/schema-upgrade tests, and FILE adapter parity tests. (Targeted DB paging, timeline tie/cursor, read-boundary/reload, and isolation coverage passes; schema-upgrade, revocation, and broader restart cases remain.)
- Run Flutter format, focused widget tests, full supported-SDK analysis/tests, and mobile Playwright checks. (Full tests pass; role/state visual review and screenshot text-rendering issue remain.)
- Run `EXPLAIN (ANALYZE, BUFFERS)` on representative histories; verify page-sized timeline reads and separately measure grouped aggregation/global unread count. Verify no item is missing or duplicated across cursors. (A 100k-row synthetic grouping plan was measured; production-representative profiles and timeline EXPLAIN remain.)
- No production schema change, deploy, or main-branch update is included in this plan. Implement and validate on `feat/inapp-notifications-communication` only, then request review before any merge or release.

## Astra-High review record

Reviewed on 2026-10-07 by an Astra-High subagent in read-only mode. The review requested precise cursor boundary semantics, stable grouped-inbox behavior under new activity, a read acknowledgement watermark, explicit Store/DB mutation ownership, complete send authorization, bounded aggregation claims, compatible route migration, and additional security/race tests. The plan above incorporates those findings. Highest-priority constraints are:

1. The older-page cursor is the oldest item in the rendered page and uses an exclusive composite keyset predicate.
2. Per-recipient notification sequence anchors both inbox snapshot pagination and read acknowledgements; event timestamps alone are not safe watermarks.
3. The current single-writer Store remains mutation owner. Direct indexed endpoint reads do not remove history hydration or full-store write costs.
4. Preserve `/notifications` and `/conversation/messages`; add grouped/timeline routes and migrate Flutter explicitly.
5. Measure grouped aggregation and unread-total work separately from the bounded page result.

No implementation or changes to `main` were made as part of this planning/review step.
