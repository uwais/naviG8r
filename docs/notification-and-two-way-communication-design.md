# Notifications and two-way communication design

**Status:** Architecture reviewed and finalized for implementation planning, 2026-10-04. This document records the product and architecture decisions; it does not authorize implementation, provider setup, real message delivery, or deployment.

## Goal

Give shipper and carrier users a reliable way to see shipment-related updates and exchange messages in the NaviG8r Flutter app. Keep the design ready for later push and WhatsApp delivery without making WhatsApp or a separate notification service a prerequisite for the first release.

## Current project facts

- The running product is a TypeScript API with a Flutter app in `apps/driver_pilot`; it does not currently have notification, conversation, or message models, nor a WhatsApp provider/webhook.
- `docs/phase0_arch_diagram.md` describes a future notifications service, event bus, and WhatsApp Cloud API. That is aspirational architecture, not infrastructure present in this codebase.
- The accepted OTP plan keeps code generation/verification independent from delivery. OTP currently returns a generated code only under the debug policy; WhatsApp authentication-template delivery is a later, separate auth-purpose integration. The existing plan already calls out provider selection, templates, retries, status callbacks, and production removal of `debugCode` in `docs/generated-otp-implementation-plan.md`.
- Current FILE persistence serializes a whole store snapshot. PostgreSQL mode hydrates a whole in-memory snapshot and rewrites tables in a transaction. HTTP work is serialized within one process, but that does not protect concurrent API instances from stale snapshots overwriting newer data.

## Decisions

1. **Start as a modular feature in the existing API and Flutter app.** Do not create a separately deployed notification microservice, Kafka/SQS dependency, or general-purpose provider framework for the first release. Keep notification, conversation, and delivery code behind clear module interfaces so an external worker/channel can be added later.
2. **Build the first user-visible phase in Flutter, in-app.** Provide an authenticated notification inbox and shipment-scoped, two-way text threads. The first release refreshes while the app is foregrounded and on screen entry; OS push when the app is backgrounded or closed is a later phase.
3. **Treat notifications and conversations as different records.** A notification is a per-recipient alert about a workflow event or a new message. A conversation message is the canonical authored text/history. An in-app notification can point to a conversation/message or shipment; it is not a substitute for the conversation history. Each enabled workflow event and message event fans out to every eligible active member of both the shipper and carrier organizations, including the initiating actor; content may be projected differently for each recipient's permissions. The sender sees the committed message in the thread, and the UI need not produce a duplicate interruptive alert.
4. **Limit conversations to a shipment context.** Start with one thread per shipment, shared by its shipper and carrier sides. Do not add arbitrary direct messages, public rooms, or group chat. Attachments, media, typing indicators, per-message read receipts, and automated chat commands are deferred.
5. **Keep OTP separate from business conversations.** OTP codes, challenge IDs, and authentication delivery attempts must never appear in chat history, notification previews, or ordinary delivery logs. WhatsApp OTP delivery remains its own auth-purpose adapter and template, not a use of the shipment-chat feature.
6. **Resolve the database writer before adding communications.** The current PostgreSQL snapshot writer deletes and recreates parent rows such as shipments, users, memberships, and organizations. A focused communications repository cannot safely coexist with that destructive writer, even with one API process. Before Phase 1, establish one authoritative persistence path for communications and their shipment/identity dependencies, and remove migrated rows from destructive snapshot replacement. Keep FILE mode behind a local/test adapter with its single-process limit explicit. Multiple API instances additionally require fresh database-backed authorization and concurrency control for all shared mutable state; a worker lock alone is insufficient.
7. **Do not add a generic outbox for in-app-only delivery.** Persist a message and its recipient notification in one focused transaction. Persist each workflow-event notification atomically with its complete source transition and related audit/payment/trip writes. Add a durable outbox and worker when push/WhatsApp introduces asynchronous external side effects.
8. **Notify all active shipment actors with recipient-specific content.** At event commit, resolve all active users with an active organization and membership, effective SHIPPER or CARRIER role, notification permission, and matching `customerOrgId` or `carrierId`. This is organization-wide because current access is organization-wide; do not infer driver assignment from action history or phone numbers. Include the initiating actor for both workflow and message events; the sender receives the canonical notification row and sees the committed message in the thread, while the UI may suppress a duplicate interruptive alert. Snapshot recipients at event time; new members receive no historical notifications. Re-check current resource access when listing or opening a notification.
9. **Make terminal conversations read-only after a configurable support window.** Shipment terminal states for this policy are `DELIVERED` and `FAILED_CARRIER_REFUNDED`; trip `COMPLETED` and shipment `PENDING_RELEASE` are not terminal shipment states. Use an initial proposed default of 14 days from immutable `terminalAtUtcMs`, persist `replyUntilUtcMs` and a policy version at the first terminal transition, and never reset the deadline on retry or unrelated updates. Later configuration changes apply only to future terminal transitions. Existing terminal shipments at launch are read-only immediately unless an explicit migration provides a trustworthy terminal timestamp; do not infer it from a potentially later `updatedAtUtcMs`. After the deadline, current authorized users retain read access but all new sends fail server-side. OPS grants cannot bypass this deadline.
10. **Gate OPS access on an approved escalation.** OPS has no default access to conversations. An escalation grant is conversation-specific, time-bounded, and scopes read and send separately. Require an approved case/reason, a requester distinct from both the approver and named OPS grantee, expiry/revocation, and audit of approval, denial, access, send, and revocation without logging bodies. Grant approval does not itself grant the approver conversation access; access must also be explicitly granted. The approving authority is a designated user with a dedicated approval permission.
11. **Use English first, make system copy localizable, and defer channel preferences.** Phase 1 uses English notification/system copy and preserves user-authored text as written. Keep stable event/template identifiers so Hindi system copy can be added later; do not automatically translate user messages. Channel opt-outs/preferences are deferred in-app and are a required follow-up before any WhatsApp notification launch.

## Domain and access model

Use relational records with stable IDs and timestamps:

- `Conversation`: shipment reference, status, created/updated timestamps. Enforce one conversation per shipment in this first scope.
- `ConversationMemberState`: user and organization membership context plus a last-read message cursor. This state tracks the inbox cursor; it does not grant access by itself.
- `ConversationMessage`: conversation ID, authenticated sender user/org, plain-text body, creation time, and an idempotency key scoped to the sender. A future channel field can identify `IN_APP` or `WHATSAPP`; provider-specific IDs belong in channel-delivery records, not in authorization logic.
- `Notification`: recipient user/org, event type, minimal resource reference, created/read timestamps, and a unique `(eventId, recipientUserId, recipientOrgId)` dedupe key. New-message alerts reference the canonical message.
- **Later, with external delivery:** `OutboxEvent` and per-channel `DeliveryAttempt` records with retry state, attempt count, provider identifiers, and bounded payload references.

Authorization is evaluated on every list, read, and send request using the current bearer session, selected active organization, RBAC permission, and shipment visibility. The initial recipient set is every active user whose active membership has an effective SHIPPER or CARRIER role in the shipment's customer or carrier organization and the relevant notification/conversation permission. This matches current organization-wide shipment access; it does not claim driver-specific assignment. FINANCE and ADMIN do not gain conversation access just because they have other platform or payment permissions. OPS access requires an approved, unexpired conversation grant and is audited; the general `visible()` shortcut for internal roles cannot bypass it. Membership revocation removes access immediately, including historical messages. Notification lists, unread counts, previews, mark-read, thread reads, and sends all re-evaluate current authorization. A notification deep link is only navigation; the destination must repeat authorization checks.

Use a per-conversation monotonic message sequence for read cursors, allocated under a conversation row lock; use keyset pagination for inbox and message history. Make message submission idempotent with a client request ID scoped to conversation, sender, and organization; reusing a key with a different body returns a conflict. Persist an unsent Flutter draft until the API acknowledges it, reusing the same key on retries and clearing local drafts/caches on logout or account switch. Keep message bodies plain text in the first phase, limit length, apply send rate limits, and exclude OTPs and unnecessary shipment/financial details from stored notification projections and logs. Conversation/message/notification history follows the related shipment's retention and deletion policy; the reply window is not a deletion timer. Establish a written shipment-aligned retention policy before production launch, including local drafts, notification references, and audit exceptions.

## Phased delivery

### Phase 0 — Product, access, and persistence boundaries

- Confirm the initial event catalog and recipient-specific projections for booking/carrier acceptance, trip start/completion, POD submission/acceptance, payment status, and new messages. Fan out to all active eligible members on both organizations, including the actor for every event; content and sensitive fields follow each recipient's current permissions.
- Add explicit permissions such as `notification.read`, `conversation.read`, `conversation.send`, `conversation.escalation_request`, `conversation.escalation_approve`, `conversation.support_read`, and `conversation.support_send`; define eligible grant approvers and resource checks in the RBAC matrix. A grant request grants no access; the requester, approver, and named OPS grantee must be three different users.
- Establish a single authoritative persistence writer before communications tables are added. Remove shipments/users/memberships/organizations migrated into focused repositories from destructive delete-and-recreate snapshots; make each enabled shipment transition, audit/payment/trip effects, and notification rows commit atomically. Document the single-process FILE adapter and prohibit mixed writers that can erase communication parents or overwrite targeted changes.
- Define the relational schema, migration and FILE/test adapter, per-conversation sequence/read cursor, pagination/idempotency/conflict behavior, message length/rate limits, 14-day reply policy/versioning, and shipment-aligned retention/deletion policy. Create schema/repository scaffolding only after the destructive parent writer is removed; keep user-facing routes and event fanout disabled until Phase 1.
- Define terminal time and workflow event identities so notification fanout is deduplicated and its recipient set is snapshotted at event commit. New memberships must not receive retrospective notifications. For already-terminal shipments, backfill only from trustworthy status-transition evidence; otherwise keep conversations read-only immediately rather than infer from `updatedAtUtcMs` or start a new window at deployment.

**Acceptance:** event/recipient/content and permission matrices are approved; schema/repository scaffolding and rollback tests exist while feature routes remain disabled; notification inserts cannot survive a rolled-back source transition or be lost after it commits; migrated source rows have one authoritative writer; no full-store snapshot flush can delete communication parents; revocation is checked against the current authoritative data; FILE mode is explicitly single-process; reply closure is immutable and derived from `terminalAtUtcMs` or is immediately read-only when a safe terminal timestamp cannot be backfilled.

### Phase 1 — In-app inbox and shipment conversations in Flutter

- Add authenticated API operations to list/paginate notifications, mark notifications read, list/paginate messages for an authorized shipment, and post a text reply. Require a stable client request ID for each new message; retries reuse it, and reuse of the same ID with a different body returns a conflict.
- Add a Flutter inbox/unread badge, notification list with authorized shipment deep links, shipment conversation view, and reply composer. Refresh on screen entry and periodically while foregrounded. Persist an unsent draft locally until the server acknowledges it, and reuse its stable client request ID on retry; show a message as sent only after acknowledgement.
- Create per-recipient message notifications in the same database transaction as the message. Create workflow alerts with their source state transition. Use dedupe keys and the client message idempotency key to avoid duplicate rows on retries.
- Keep phase-one event coverage narrow and explicit: shipment booking/carrier acceptance, trip start/completion, POD submission/acceptance, payment state changes, and new conversation messages. Fan out at commit to all eligible active SHIPPER and CARRIER members, including the actor for workflow and message events; create role-specific minimal content. Do not target OPS, FINANCE, or ADMIN by default.
- Implement an approved escalation grant path. The request is tied to a shipment conversation/case, is approved by a distinct designated approver, grants explicitly selected support-read/support-send rights to a named OPS user for a bounded period, and is audited. It cannot extend the shipper/carrier reply deadline.
- Capture `terminalAtUtcMs`, `replyUntilUtcMs`, and the policy version only on the first transition to `DELIVERED` or `FAILED_CARRIER_REFUNDED`. After the 14-day default window, deny new messages while preserving authorized history.
- Persist notification text as a stable event identifier plus structured, permission-safe data. English is the only phase-one system language; message bodies remain unmodified and are not translated.

**Acceptance:** eligible shipper and carrier members can exchange text on their shipment; a different organization cannot list/read/reply; removed memberships lose historical access; duplicate client requests create one message/notification and a conflicting body for an existing request ID is rejected; unread/read and pagination are stable under concurrent sends; unsent drafts survive app restart until acknowledged; terminal sends are rejected after the persisted deadline; authorized OPS escalation works only during its grant; each workflow and message event reaches all eligible members on both sides, including the actor, with safe content. No OS notification is promised while the app is closed.

### Phase 2 — Mobile push as a wake-up channel

- Add device-token registration and revocation, then FCM/APNs delivery from a durable outbox worker. The in-app inbox remains the source of truth; push prompts the user to refresh it.
- Deliver minimal, privacy-safe payloads with an opaque notification ID/deep link. The app fetches the authorized details after opening.
- Add deduplicated delivery, bounded retries/backoff, provider status handling, dead-letter/manual recovery, and metrics that never contain message bodies or OTPs.

**Acceptance:** app foreground/background/open transitions recover the same notification from the inbox, revoked device tokens stop receiving pushes, repeated provider callbacks do not duplicate inbox entries, and worker/provider failure does not lose the persisted notification.

### Phase 3 — WhatsApp outbound notifications and OTP delivery

- Select the Meta Cloud API or an approved provider at implementation time; validate current account, template, consent, and operational requirements then.
- Add a WhatsApp notification adapter for eligible transactional alerts and a separate WhatsApp OTP delivery adapter using the accepted OTP plan's authentication-template flow. Both use durable delivery state, but distinct purpose policies and templates.
- Do not fall back from a WhatsApp provider failure to exposing an OTP in an API response. Keep debug code exposure restricted to explicit development/test policy.

**Acceptance:** delivery is idempotent, provider failures are observable/retryable without generating extra challenges, callbacks are authenticated/deduplicated, and production OTP responses never include `debugCode`.

### Phase 4 — Inbound WhatsApp replies

- Ingest authenticated provider webhooks into the same canonical shipment conversation, with a unique provider event/message ID and durable deduplication.
- Correlate using provider message context or an opaque NaviG8r conversation reference, then bind the sender to a previously verified/consented phone and re-check current user, membership, organization, and shipment permissions. Phone-number lookup alone never grants access.
- Quarantine unknown/ambiguous senders for manual handling. Treat replies as text only; messages do not execute shipment, payment, or account actions. For an action, link the user back into an authenticated NaviG8r workflow.

**Acceptance:** invalid signatures, replays, wrong/ambiguous numbers, revoked memberships, and out-of-scope shipments are rejected without leaking shipment details; one accepted inbound provider message creates one canonical conversation message and an in-app notification.

## Approaches considered

| Approach | Decision | Reason |
| --- | --- | --- |
| In-app inbox and shipment-scoped two-way threads first | **Selected** | Reuses NaviG8r identity/RBAC and supports true replies without immediately depending on provider approval, templates, or webhook operations. |
| One-way alerts only | Defer | Smaller first slice, but does not meet the requested two-way communication goal. It remains a valid staged rollout if the conversation UI needs to ship later. |
| WhatsApp-first messaging | Defer | Adds external provider setup, recipient consent/identity binding, template and webhook policy, retries, and operational support before the in-app product contract is proven. WhatsApp OTP delivery is already separately planned. |
| Separate notification microservice/event bus now | Reject for initial phases | Current deployment is a single API app and does not run the aspirational SQS/Kafka architecture. Focused relational transactions provide the first reliable boundary with less operational overhead. Revisit extraction when scale or independent release needs justify it. |

## Product decisions recorded

- All eligible active shipper and carrier organization members receive notifications for workflow and message events, including the initiating actor; the event meaning may be identical while the rendered content differs by current permissions. The sender's notification is canonical, while the UI may avoid a duplicate interruptive alert. Memberships added later do not receive old notifications.
- A terminal shipment's conversation becomes read-only after a configurable support window, initially proposed as 14 days. History remains readable under current authorization for the shipment retention period. Read-only does not mean deletion.
- OPS has no default conversation access. Access requires a separately approved, time-bounded escalation grant with audited read/send scope.
- English is the current system-notification language; Hindi is a later localization. User-authored messages are not translated. Channel opt-outs are a follow-up gate before WhatsApp launch.
- Retention follows shipment-record retention and deletion; the written retention schedule must be established before production launch because no independent communications retention period is defined here.

## Review record

A separate `gpt-6-luna` agent at high reasoning effort acted as Staff Software Engineer and independently reviewed current project assumptions, persistence behavior, security, and delivery phases. A second independent review by `gpt-6-astra` at high reasoning effort acted as Senior Staff Software Engineer. It identified that focused communication writes cannot safely coexist with the current destructive snapshot writer, that internal-role visibility cannot substitute for approved OPS escalation, and that active recipients must be defined by organization membership rather than historical action authors. The Astra review also challenged offline draft behavior and clarified support-window persistence and event recipient snapshots. The design incorporates those findings and the user's decisions above. Implementation began on `feat/inapp-notifications-communication` from `origin/main` on 2026-10-05; see the implementation plan and review-questions file for validation and release gates.
