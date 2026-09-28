# Admin/Ops dashboard restoration with RBAC

## Status and comparison baseline

- Date: 2026-09-27.
- Status: implementation complete on `feat/admin-ops-dashboard-v1`; final validation and feature-branch review recorded in the testing guide. No main merge or deployment.
- Historical UI reference: `3a284098cbb256af587f16a838ee6ff112e40f6e` (PR #112).
- Latest main fetched for this review: `6c7a0878c2abe63c8ef126bbbd31575c96dfb8e5` (PR #132, carrier compliance review queue).
- Planning branch: `docs/admin-ops-rbac-restoration-plan`, created from that latest `origin/main` in a separate worktree.
- Original dashboard replacement: `215de567ee564ef8f6b9a2cc7d102b3343c4fc30` (RBAC implementation).
- Scope: V1 restoration alongside preserved V2, additive protected APIs, tests, CI and documentation. Shared-environment data and deployments are excluded. The user approved implementation and intermediate steps, excluding merge to main.
- Delegation: when assigning small tasks to the local Qwen model, follow the [Qwen/Codex connection and background-task guide](qwen-codex-delegation.md). Run it asynchronously and check status about every three minutes while continuing independent work.
- Approved UI follow-up (2026-09-28): bring the full-width blue V1 header and responsive navigation to V2, retaining its compact content and RBAC actions. See the [testing guide](admin-ops-dashboard-testing.md#v2-header-follow-up-2026-09-28) for verification and new screenshots.
- Heading follow-up (2026-09-28): match admin/ops page headings and responsive heading sizes across versions; preserve the workspace when switching versions. See [manual verification](admin-ops-dashboard-testing.md#workspace-heading-consistency).

Requirements: add the previous full admin/ops layout as V1 alongside the current compact V2 flow, retaining server-enforced RBAC, organization isolation, workflow checks, and audit attribution in both. The user explicitly requested coexistence rather than replacement. Sources reviewed: the user-selected historical commit; current code; [RBAC design decisions](rbac-design-review.md); [RBAC release metadata](rbac-release-metadata.md); and `/Users/sundeepperchani/Downloads/NaviG8r_RBAC_Codex_Implementation_Plan.md`. The approved reduced Phase 1 scope still applies; this is not a reopening of deferred credit, mandates, disputes, or document-storage products.

Use the historical commit as a functional and layout reference, not as a wholesale revert. In particular, its admin data sections were server-rendered JSON dumps inside a visually hidden HTML container, not protected data-fetching tables. Restoring those dumps would expose data before authentication.

## Two dashboard versions: coexistence contract

| Route                  | Planned behavior                                                                                  |
| ---------------------- | ------------------------------------------------------------------------------------------------- |
| `/admin`, `/ops`       | Keep the current compact V2 flow and existing bookmarks working; do not redirect these to V1      |
| `/admin/v2`, `/ops/v2` | Add explicit aliases to the existing V2 renderer                                                  |
| `/admin/v1`            | Add the traditional full admin layout with RBAC-controlled sections and actions                   |
| `/ops/v1`              | Add the traditional Ops payment/operations view, with links to authorized full-dashboard sections |
| `/workflow`            | Keep the current external shipment/POD workspace                                                  |

These are UI version labels, not API versions or permission levels. V1 and V2 share the existing database, authentication, selected-organization semantics, permission catalog, service functions, and audits. New V1-only capabilities use additive protected APIs where possible. Existing API response contracts and V2 workflows must remain compatible; do not fork security or business rules per UI version.

Keep `opsPortalHtml()` as the V2 renderer. Build V1 in a separate renderer/module rather than replacing the V2 template. A small version-switch link may be added to each dashboard, using the same session and selected organization; switching must revalidate the principal and must never grant access or copy stale protected content. Preserve all current V2 controls, including the compliance queue, role editor, and payment/POD actions available to the selected membership.

The comparisons below describe capabilities to add to V1; they are not instructions to remove or redesign V2. V1 is a second live UI over current RBAC, not a deployment of the historical application. Disabling the V1 routes later must leave V2 usable without reverting shared data or RBAC state.

## Comparison: what must be restored

| Historical capability at `3a284098`                                                | Current behavior at `6c7a087`                                                                                     | Restoration task          |
| ---------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- | ------------------------- |
| Full-width `/admin`: action cards, session header, login/logout, ten data sections | `/admin` and `/ops` share a compact portal capped at 960px                                                        | DASH-03, DASH-04          |
| Carriers, organizations, users, memberships                                        | Removed from dashboard; `/v1/orgs` and `/v1/users` still exist under `user.role_manage`; no complete directory UI | DASH-02, DASH-04          |
| Vehicles and driver profiles                                                       | Removed from dashboard; pilot APIs are not a global internal directory                                            | DASH-02, DASH-04          |
| Anchor trips and shipments                                                         | Removed full listings; internal portal fetches only pending-release shipments                                     | DASH-02, DASH-04          |
| Ledger lines and payout batches                                                    | Removed dashboard sections; Finance-protected APIs still exist                                                    | DASH-02, DASH-08          |
| Grant/revoke Ops Admin by phone                                                    | Legacy APIs remain; replacement UI edits roles of an existing membership by IDs                                   | DASH-05                   |
| Deactivate user by phone, optional force                                           | API and soft-delete logic remain; form removed                                                                    | DASH-05                   |
| Create carrier by name                                                             | Legacy `/carriers` route returns `410 legacy_route_retired` through RBAC guard                                    | DASH-06                   |
| Publish anchor trip                                                                | Legacy POST `/anchor-trips` retired; authenticated `/v1/pilot/anchor-trips` supports an Ops assistance path       | DASH-07                   |
| Book shipment                                                                      | `/shipments/book` permits a selected SHIPPER; OPS fails with `assisted_booking_requires_target`                   | DASH-07                   |
| Mark POD / Mark delivered                                                          | Legacy `/shipments/:id/pod` retired; submission and shipper acceptance are now separate                           | DASH-08                   |
| Fail + refund                                                                      | Protected service/API remains, requires FINANCE                                                                   | DASH-08                   |
| Run payout batch, payout-mode explanation                                          | Protected API remains, requires FINANCE; old optional `nowUtcMs` input is no longer honored by the route          | DASH-08                   |
| Separate `/ops` payment-release table and recently-delivered table                 | Pending rows remain in compact form; delivered API exists but portal does not load it                             | DASH-08                   |
| New RBAC role selection and `/workflow` shipper POD acceptance                     | Present; must remain                                                                                              | DASH-03, DASH-05, DASH-08 |
| New carrier approval queue, reason validation, review confirmation                 | Added by `0518f8a`; absent from old dashboard                                                                     | DASH-09                   |

## Permission and UX decisions

Existing rules to preserve:

- Roles combine only within the selected active organization membership. `X-Organization-Id` identifies the acting user's organization, not a target customer/carrier.
- ADMIN manages access and sees a support view; OPS performs operational work and KYC review; FINANCE handles money operations. SHIPPER/CARRIER retain their own workspaces and resource scopes.
- A person who needs all three internal functions can be explicitly assigned `ADMIN,OPS,FINANCE` on one PLATFORM membership. Do not give every ADMIN automatic Finance access or rewrite legacy role mappings.
- POD submission does not accept the POD for the shipper or capture payment. Only the owning SHIPPER accepts it; Finance release respects acceptance or the 48-hour hold rule.
- KYC approval remains independent of registration and payout-bank setup. Unapproved carriers remain blocked from accepting shipments and starting trips; publishing a trip remains possible under current policy.
- Preserve tombstones, payment/provider validation, customer checkout, carrier-owner-only payout setup, audit retention, and current mobile/API contracts.
- Keep `/workflow` usable by shippers. The user previously deferred automatic redirects for non-internal visitors; do not silently introduce a redirect in this restoration. A public login shell is acceptable, but internal data and actions must require internal permissions.

The following are proposed design choices to settle in DASH-01 before implementing the affected behavior:

1. **Carrier onboarding:** recommend OPS creates a real carrier Organization linked to a selected existing, active owner user, with compatible legacy owner metadata and canonical CARRIER assignment. Initial KYC is `NOT_STARTED`. A name-only legacy Carrier record is insufficient. New-user signup can remain in the existing registration flow. Decide whether creating a new user directly in Ops is also required.
2. **Directory access:** recommend explicit internal directory permissions for organization summaries and operational fleet data; ADMIN keeps user/membership management. OPS receives only the member/owner lookup fields needed for assisted operations, not broad user-role management. FINANCE receives organization summaries and financial records, not user/vehicle administration. Approve concrete field lists, including any phone/contact fields.
3. **Page layout (user direction established):** maintain both versions using the coexistence contract above. V1 restores responsive action cards and full data coverage; V2 retains the current compact implementation. The proposed explicit route names and version-switch links implement that direction; neither route nor version grants a role.
4. **Historical controls:** retain safe functionality, not arbitrary storage dumps, raw filesystem paths, client-supplied payout time overrides, or a one-click POD-to-payment shortcut. Show business-relevant payout mode/status through a protected response if needed.

## Proposed API approach

Keep the existing native HTTP server and central permission catalog. Names below marked NEW are proposed contracts, not existing endpoints. Prefer a small dashboard route/service module over another large inline handler. All mutations must also enforce policy at their service boundary.

Versioned HTML routes must be deliberately registered in the public-shell allowlist, without allowing a wildcard over their data/action APIs. Serve the same V2 renderer at both existing and explicit V2 URLs. For APIs used by V2 or mobile, preserve existing request/response shapes; add optional pagination or a separate dashboard endpoint rather than breaking an existing collection contract.

| API or API group                                                                                     | Plan                                      | Authorization and response requirements                                                                              |
| ---------------------------------------------------------------------------------------------------- | ----------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| `GET /v1/auth/me` and OTP routes                                                                     | Reuse                                     | Server principal, roles and permissions drive display; clear stale content on session/organization changes           |
| NEW `GET /v1/ops/organizations` (carrier-kind filter supported)                                      | Add paginated directory                   | Internal organization-directory read grant; role-specific summary fields; carrier view uses Organization IDs         |
| `GET /v1/users`; NEW `GET /v1/ops/memberships`                                                       | Adapt/add paginated admin listings        | ADMIN via `user.role_manage`; explicit fields; effective canonical roles plus legacy subrole                         |
| NEW `GET /v1/ops/organizations/:id/assistance-members`                                               | Add narrow target selector                | OPS directory grant; eligible member ID/name/subrole only, target organization validation                            |
| NEW `GET /v1/ops/vehicles`, `/v1/ops/driver-profiles`                                                | Add operational directories               | Internal fleet-read grant; scope, field filtering, pagination                                                        |
| NEW `GET /v1/ops/anchor-trips`                                                                       | Add internal listing                      | Internal `load.read`; filters and no exposure of protected tracking/provider fields                                  |
| `GET /shipments`, `/ops/shipments/:id`, `/ops/shipments/pending-release`, `/ops/shipments/delivered` | Reuse/extend                              | All-status listing and permitted details; operational, financial and support projections                             |
| `/v1/ops-admins`, `POST /v1/roles`, `DELETE /v1/ops/users/:id`                                       | Reuse/harden where needed                 | ADMIN; preserve role replacement, compatible organizations, tombstones, safeguards and audit attribution             |
| NEW `POST /v1/ops/carrier-organizations`                                                             | Implement onboarding                      | Proposed dedicated OPS `carrier.onboard` permission; owner validation; atomic creation; no automatic KYC approval    |
| `POST /v1/pilot/anchor-trips`                                                                        | Reuse assisted publish path               | OPS `trip.publish`, validated effective actor and reason; selected internal org stays the acting org                 |
| `POST /shipments/book`                                                                               | Extend with explicit assisted context     | SHIPPER own org or OPS for a validated customer/member; service-level checks; audited ownership and no forged booker |
| `POST /shipments/:id/driver-pod`, `/shipments/:id/accept-pod`                                        | Reuse                                     | Carrier/assisted OPS submission; owning SHIPPER acceptance; no implicit Finance grant                                |
| `POST /ops/shipments/:id/release`, `/shipments/:id/fail-refund`, `/payout-batches/run`               | Reuse                                     | FINANCE and valid workflow; confirmations and safe failures; server-controlled time                                  |
| `GET /carriers/:id/ledger`, `/payout-batches`; NEW paginated internal ledger listing if needed       | Reuse/add all-carrier ledger view         | FINANCE; complete protected field allowlists, including nested transfers                                             |
| `GET /ops/compliance/pending`, `POST /v1/organizations/:id/kyc`                                      | Preserve                                  | OPS `kyc.verify`; independent reviewer; show review reason and confirmation                                          |
| `GET /v1/audit`                                                                                      | Correct combined-role filtering if needed | Union permitted audit categories within one membership; never union across organizations                             |

New route patterns must be added deliberately to the default-deny guard. The current broad `/v1/ops/users` pattern is tied to role management; do not overload it to give OPS unrelated administration privileges. Filtering and counts must operate on authorized records before pagination. Inactive records may be shown only through an explicitly authorized support/admin filter; do not remove tombstones or make them externally visible.

## Implementation tasks and acceptance criteria

DASH-01 through DASH-12 are implemented. The descriptions below preserve the agreed acceptance contract; actual grouped API routes, local results and verification instructions are recorded in [the implementation/test guide](admin-ops-dashboard-testing.md). New directory routes were consolidated under `/v1/ops/dashboard/:section` to preserve existing collection contracts. Dependencies identify sequencing, not separate service deployments.

### DASH-01 — Finalize the restoration contract and access matrix

- Dependencies: none.
- Preserve the user's two-version direction; finalize the remaining decisions above and a section/action/field matrix for each single role and supported combined role.
- Confirm complete coverage of all ten historical data sections and every historical action, with deliberate RBAC replacements documented.
- Record proposed directory/onboarding permissions in the design; identify any catalog persistence update.
- Acceptance: no ADMIN superuser assumption, no unresolved authority for carrier onboarding or assisted booking, and a V1 layout/reference checklist plus a V2 preservation checklist.

### DASH-02 — Add protected directory and dashboard read APIs

- Dependencies: DASH-01.
- Files: `rbac.ts`, `rbacRoutes.ts`, `rbacResponses.ts`, `httpServer.ts`, proposed dashboard route/service modules, relevant persistence/catalog code.
- Implement the missing read contracts above with bounded page size, stable ordering, supported filters and explicit field projections. Use carrier Organizations as the canonical directory; preserve existing CARRIER_LEGACY identities and show unresolved legacy records only as reconciliation items.
- Reuse shipment detail and financial services where appropriate; add missing all-carrier ledger aggregation without granting OPS financial detail.
- Acceptance: every restored data section has a documented API and permission; external callers cannot enumerate internal directories; list/detail/count responses expose only permitted records and fields; no storage snapshot is embedded in HTML.

### DASH-03 — Add the V1 shell alongside the existing V2 flow

- Dependencies: DASH-01; real data integration depends on DASH-02.
- Files: a new V1 renderer (for example `adminDashboardV1.ts`), route rendering in `httpServer.ts`, shell allowlist in `rbacRoutes.ts`, and minimal version-navigation additions to `opsPortal.ts`.
- Keep V2's renderer, default routes and controls. Register `/admin/v1`, `/ops/v1`, `/admin/v2`, and `/ops/v2` according to the coexistence contract; leave `/workflow` in place.
- Restore full-width responsive cards, navigation, session header, OTP/login/logout, selected organization, loading/empty/error states and accessible forms/tables in V1. Use separate V1 styling to avoid changing V2 layout.
- Reuse server-provided permissions rather than `isOpsAdmin` or a cached role flag. On organization change, logout, 401/403, or role refresh, clear protected content and discard stale in-flight responses.
- Acceptance: existing `/admin` and `/ops` remain V2; explicit V2 aliases match them; V1 renders separately; `/workflow` remains usable; switching versions preserves the selected membership but revalidates access; no sensitive HTML before login, stale data after context switch, or unapproved external-user redirect.

### DASH-04 — Restore all ten data sections

- Dependencies: DASH-02, DASH-03.
- Restore carriers, organizations, users, memberships, vehicles, driver profiles, anchor trips, shipments, ledger lines, and payout batches in V1 using protected APIs. Do not replace V2's compact shipment view with these tables.
- Provide names/IDs, meaningful status, search/filter controls, pagination and permitted details rather than raw JSON dumps. Use safe text rendering for user-entered values. Financial sections are completed with DASH-08.
- Acceptance: each historical section is accessible to its authorized role; tables work on desktop and narrow viewports; full combined-role access does not reveal raw bank/KYC/provider fields.

### DASH-05 — Restore role management and user deactivation

- Dependencies: DASH-02, DASH-03.
- Restore grant/revoke by registered user lookup, with explicit canonical role choices. `/v1/roles` replaces roles on an existing membership; retain a supported path to create the internal membership when absent, instead of assuming the role endpoint creates it.
- Correct the historical button/API naming mismatch: current `grantOpsAdmin()` creates an `OPS_AGENT` membership with canonical `OPS`, not ADMIN. Show the actual grant, preserve existing role assignments when creating/updating access, and use the canonical role assignment flow for explicitly selected ADMIN/FINANCE grants. Do not blindly relabel this endpoint as a full administrator grant.
- Show the target user/org, existing roles and proposed replacement before save. Inspect and preserve applicable self-revocation/last-admin safeguards in legacy grant/revoke flows; test the canonical role endpoint consistently against the agreed policy.
- Restore deactivation, active-work rejection, force confirmation, affected-entity summary and audit entries. Preserve shared-org membership handling and tombstones.
- Acceptance: ADMIN-only API enforcement; OPS/FINANCE cannot grant roles or deactivate accounts; roles persist across restart; authorized ADMIN+FINANCE users can operate payments without globally changing ADMIN grants.

### DASH-06 — Replace legacy carrier creation with RBAC onboarding

- Dependencies: DASH-01, DASH-02, DASH-03.
- Implement the approved organization/owner creation contract, compatible canonical and legacy role metadata, duplicate/retry handling, actor/reason audit, and atomic persistence.
- Keep `POST /carriers` retired; do not revive an unauthenticated name-only creation path.
- Acceptance: the new carrier appears in directories, its selected owner can access its workspace, KYC starts pending, failed creation leaves no partial membership, and audit/identity survive JSON and PostgreSQL round trips.

### DASH-07 — Restore assisted publishing and booking

- Dependencies: DASH-02, DASH-03; DASH-06 for testing a newly onboarded carrier.
- Publish using the existing pilot route and validated carrier/member selectors. Capture reason and effective actor; add any missing publish audit event.
- Complete assisted booking in both handler and service: require an active CUSTOMER organization and eligible member, persist that customer ownership/booker, retain the actual Ops actor in audit, and reject conflicting or forged target IDs. Keep normal shipper and integration bookings compatible.
- Retain geographic eligibility, capacity, pricing, payment-order creation and booking rollback on provider failure. Ops creates the booking; the shipper still completes checkout.
- Acceptance: OPS can publish/book for validated targets; FINANCE-only and ADMIN-only cannot; inactive/wrong-org targets fail; owning shipper sees the booking and another shipper does not; direct service calls cannot bypass assistance checks.

### DASH-08 — Restore POD, payment, ledger and payout workflows

- Dependencies: DASH-02, DASH-03, DASH-04; DASH-07 for end-to-end fixture flow.
- Replace the historical Mark delivered shortcut with explicit Submit POD and shipper Accept POD actions. Preserve `/workflow` and mobile acceptance.
- Restore the historical Pending release and Recently delivered tables at `/ops/v1`, plus V1 refund and payout forms/history. Keep `/ops` and `/ops/v2` on the existing compact flow. Display permitted amounts, hold state, eligibility and payout mode where meaningful.
- Require confirmation, prevent accidental repeated submissions, and handle retries without duplicate financial effects. Keep time controlled by the server; do not restore the old arbitrary `nowUtcMs` field.
- Acceptance: approved/paid-ready carrier acceptance and trip start remain enforced; pending POD acceptance/hold blocks premature capture; OPS alone cannot capture/refund/pay out; FINANCE alone cannot submit/accept POD; repeated release/payout requests cannot pay twice; existing financial tests remain passing.

### DASH-09 — Preserve the latest compliance queue and review UX

- Dependencies: DASH-03.
- Carry forward `0518f8a`: pending-carrier listing, approve/reject controls, reason validation, disabled controls while saving, visible last-review confirmation and queue refresh.
- Keep the existing V2 queue intact and integrate an equivalent queue into V1 with organization links, using the same approval service and APIs. New onboarding must not auto-approve carriers or confuse bank setup with independent review.
- Acceptance: OPS sees and acts on the queue; ADMIN/FINANCE-only cannot verify; carrier self-verification is denied; approved carrier is removed from the pending queue and can pass the compliance gate after session refresh.

### DASH-10 — Complete audit, catalog and persistence coverage

- Dependencies: DASH-02 and mutation tasks DASH-05 through DASH-09.
- Record actor, acting organization, target/effective actor, reason where required, resource, previous/new state, timestamp and request ID for restored privileged operations.
- Fix the current `/v1/audit` role-precedence behavior: ADMIN+FINANCE currently selects the ADMIN audit branch, hiding its financial categories. Return the authorized category union for the selected membership, with field filtering.
- Verify new permission catalog rows persist consistently with runtime grants. No destructive schema migration or role/KYC backfill is expected for the proposed design; inspect the actual diff and document any necessary additive catalog/schema work before applying it outside disposable storage.
- Acceptance: business mutation and audit persist together, history survives restarts/deactivation, no cross-org audit union, no duplicate onboarding audit on a successful retry, and both FILE/DB paths pass.

### DASH-11 — Add automated API, browser and visual coverage

- Dependencies: implement relevant tests alongside DASH-02 through DASH-10; final suite after integration.
- Extend `rbac.test.ts`, `rbacHttp.test.ts`, `httpServer.test.ts`, `opsDeleteUser.test.ts`, and affected carrier/POD/payment tests with actual allowed and denied actions. Add dashboard-specific tests as appropriate.
- Expand `apps/api/playwright/ops.spec.ts` beyond its current shell-only checks. Seed synthetic ADMIN, OPS, FINANCE, ADMIN+FINANCE, ADMIN+OPS+FINANCE, SHIPPER and CARRIER users plus separate external organizations.
- Cover all historical actions, every restored data section, unauthorized direct API calls, hostile text rendering, context switching, inactive membership, role revocation, stale requests, financial duplicate submissions, and compliance/hold gates.
- Add explicit V2 regression journeys for login, organization selection, role assignment, payment release, compliance review and `/workflow` POD acceptance. Verify existing routes and V2 aliases render equivalent controls. For actions exposed in both versions, assert identical allow/deny decisions and persisted outcomes. Test same-session version switching, cross-version state refresh after a mutation, and no privilege gain from changing a UI URL.
- Capture desktop and mobile screenshots of V1 login, directories, actions, validation failures, KYC review, POD/payment states and combined-role views, plus V2 before/after preservation evidence. No visual baseline replacement without explicit approval.
- Acceptance: relevant formatting/static checks, unit and HTTP integration tests, Playwright journeys, and FILE/DB persistence checks pass; report failures/tool gaps explicitly. Do not claim UI restoration based only on shell-string tests.

### DASH-12 — CI, manual test guide and release evidence

- Dependencies: DASH-11.
- Inspect all CI workflows; add the dashboard browser job where needed. Current `release.yml` Repository Tests runs `npm test`, which does not invoke Playwright. Keep release image promotion/digest behavior unchanged.
- Update RBAC release/manual-testing docs and fix the existing role-assignment example: `X-Organization-Id` is the ADMIN's selected PLATFORM org, while the request body identifies the target membership's org.
- Document synthetic fixture identities, links for both versions, expected UI per role, existing-user access assignments and known intentional differences from the old dashboard. Document how to disable V1 routes while retaining V2 and shared state, plus safe rollback to the pre-restoration RBAC build if shared backend changes require it.
- Acceptance: reviewers can execute the manual sequence below; evidence identifies exact tested SHA, screenshots and suite results; feature-branch review precedes any authorized commit/push/merge/deployment. Do not push directly to main.

## Delivery order

1. DASH-01 access and functional contract.
2. DASH-02 additive read APIs and DASH-03 separate V1 shell, then DASH-04 V1 listings and DASH-09 queue integration, with V2 regression checks throughout.
3. DASH-05 administration and DASH-06 onboarding.
4. DASH-07 assisted operations and DASH-08 POD/financial functions.
5. DASH-10 completes audit/persistence across those slices; DASH-11 tests accompany each slice and then run together.
6. DASH-12 documents and wires the validated functionality into CI/release review.

Do not label restoration complete while any historical capability lacks a working authorized V1 replacement or an explicitly accepted scope decision, or while the existing V2 flow regresses.

## Local validation and manual acceptance plan

Use only disposable synthetic storage, mock payments, and bookkeeping payouts. No production backup fixtures. Existing harness: `node --experimental-strip-types scripts/rbac-manual.mjs` at port 3139, with OTP `123456`; extend it with the additional combined-role and dashboard fixtures. Document the final fixture list in DASH-12.

Manual sequence:

1. Open `http://127.0.0.1:3139/admin/v1` and `/ops/v1` for the full dashboard; open `/admin`, `/ops`, `/admin/v2`, and `/ops/v2` for V2; also check `/workflow`. Signed out, verify no protected records in HTML or requests. Run the restored full-functionality steps below in V1 and repeat overlapping actions in V2.
2. ADMIN: inspect users/memberships, grant/revoke approved roles, deactivate a disposable account and exercise active-work/force cases; verify financial actions are unavailable without FINANCE.
3. OPS: inspect operational directories and all shipment states, onboard a synthetic carrier, publish a trip, and create an assisted booking for a synthetic shipper; verify attribution and ownership.
4. Owning SHIPPER: see only its booking and complete mock checkout. A second shipper cannot access it.
5. CARRIER: acceptance fails while unapproved. OPS approves through the queue; carrier refreshes and can accept/start when all other conditions pass.
6. Carrier or assisted OPS submits POD; owning SHIPPER accepts through `/workflow`. Verify Finance cannot impersonate that acceptance.
7. FINANCE: exercise pending and delivered views, capture after valid acceptance/hold eligibility, refund an eligible separate fixture, inspect ledger, run a bookkeeping payout, and verify no duplicate payment on retry.
8. ADMIN+FINANCE and ADMIN+OPS+FINANCE: show the expected combined sections and audit categories. Switch to a separate external membership and verify internal records/actions disappear.
9. Revoke a role while another browser session is open; subsequent requests fail and stale UI content clears. Restart the local API; confirm assignments, audit and transitions persisted.
10. Switch V1/V2 within the same browser session and verify the same selected organization and permissions. Mutate a shared record through one version, then refresh the other and confirm consistent state. Verify default `/admin` and `/ops` bookmarks still open V2 and all previous V2 controls work.
11. Repeat key journeys at desktop and mobile widths; attach screenshots for each relevant state in both versions. Run equivalent persistence cases against a disposable PostgreSQL database.

Verification commands at implementation time:

```sh
# Use the project's installed Node 22 tooling and a fresh disposable data path.
NODE_ENV=test PERSISTENCE=FILE DATA_FILE=/private/tmp/navig8r-dashboard-tests.json PAYMENT_PROVIDER=MOCK PAYOUTS_MODE=BOOKKEEPING npm test
npx tsc --noEmit -p tsconfig.json
npx playwright test --config=playwright.config.ts
git diff --check
```

Run the repository's applicable formatter/lint checks on changed files; record pre-existing diagnostics separately. Root `package.json` currently has no named lint/format scripts, so DASH-11 must document the exact scoped commands rather than invent a passing lint job. Give the browser harness its own synthetic FILE storage and deterministic reset; do not point it at an already-running shared API. Stop the manual port-3139 server before launching the current Playwright webServer on that port. Flutter tests are needed if shared API/session changes affect mobile; retain the project's pinned SDK compatibility rather than changing theme/navigation APIs incidentally.

## Completion record for this planning task

- [x] Fetched `origin/main` and recorded its exact revision.
- [x] Inspected both historical `/admin` and `/ops` implementations at the requested commit.
- [x] Compared current routes, permission catalog, serializers, services, browser tests, release workflow and approved RBAC decisions.
- [x] Documented the restoration gaps, proposed contracts, task dependencies, acceptance criteria and manual verification.
- [x] Incorporated the user's direction to retain the current V2 flow and add the traditional layout as a separate V1, including route, API compatibility and regression-test requirements.
- [x] Implementation/design decisions approved by the user; OPS onboarding links an existing owner, both UI versions coexist, and role grants remain explicit.
- [x] DASH-01 through DASH-12 implemented; TypeScript, API/core, browser, mobile and disposable PostgreSQL validation performed.
- [x] Intermediate implementation, testing and feature-branch publication authorized by user.
- [ ] Merge to main or deployment (excluded from this authorization).

Implementation verification: 179 API/core tests, 10 browser journeys, 20 Flutter tests, TypeScript, scoped formatting and disposable PostgreSQL round trip passed locally. Flutter analysis had 37 existing informational diagnostics and no warnings/errors. Local browser tests used installed Chrome; CI installs pinned Chromium. See the test guide for reproducible commands and screenshot evidence.
