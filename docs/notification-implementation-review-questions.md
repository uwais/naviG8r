# Notification implementation questions for product review

This file tracks decisions that need Sundeep's review before production release. They do not block local implementation where a safe, documented default exists.

- [ ] Confirm the proposed 14-day configurable reply window after a shipment first becomes `DELIVERED` or `FAILED_CARRIER_REFUNDED`. This controls conversation replies only; it does not pause payment or settlement work.
- [ ] Approve the shipment-aligned retention/deletion schedule for messages, notification references, local drafts/caches, and escalation audit records. The design intentionally does not invent an independent communications retention period.
- [ ] Review the event catalog and recipient-specific copy/fields before production: booking/carrier acceptance, trip start/completion, POD submission/acceptance, payment-state changes, and new messages. All eligible active SHIPPER/CARRIER members on both organizations are recipients, including the actor; each recipient sees only fields allowed by current permissions.
- [ ] Name the designated role or users allowed to approve OPS escalation requests. Requester, approver, and named OPS grantee must remain three different users; OPS gets no default conversation access.
- [ ] Confirm whether legacy terminal shipments should remain read-only at launch when reliable terminal-transition timestamps cannot be backfilled. Current safe default is read-only immediately.
- [ ] Confirm English-only system copy for the first release and the Hindi localization milestone. User-authored messages remain untranslated.
- [ ] Confirm whether the initial server-side message throttle of 20 sends per user per conversation per minute is appropriate.
- [ ] Confirm the supported Flutter version for release validation. The installed current SDK cannot compile untouched `origin/main` files (`CardTheme` versus `CardThemeData`, plus removed legacy web interop APIs), while the previously used Flutter 3.22.3 binary is not installed in this worktree. Feature-specific Flutter widget tests can run without importing those baseline files.

Channel opt-outs are a required policy/implementation gate before WhatsApp business notifications. This is tracked in the phase plan and does not need to block the in-app release.
