# RBAC discovery and design review

Status: Gate 1 approved; implementation complete on the feature branch. Gate 2 evidence is included below. No production database was accessed or changed.

Requirement: `/Users/sundeepperchani/Downloads/NaviG8r_RBAC_Codex_Implementation_Plan.md`, version 1.0, referencing PRD v2.0. No separate PRD v2.0 was found in the checkout; the supplied plan is the available acceptance-criteria source.

## Branch and baseline

- Repository: `https://github.com/uwais/naviG8r.git`.
- Branch: `feat/rbac-authorization`.
- Base: `f96ccf983ceffdb547afa405541c4fa0fc24a156`, fetched from remote main.
- Isolated worktree: `/Users/sundeepperchani/workspace/NaviG8r/naviG8r-rbac`.
- Existing checkouts and their uncommitted work were preserved.
- Applicable guidance: parent `AGENTS.md`; no tracked nested AGENTS.md found in this checkout.
- Runtime available: Node 26.7.0, npm 11.19.0. README and Dockerfile target Node 22+; Node 22 validation remains outstanding.
- No commits, pushes, migrations, or deployments performed.

## Discovery

| Component | Files | Findings |
|---|---|---|
| API | `apps/api/src/index.ts`, `httpServer.ts` | Native Node HTTP server; inline admin/Ops HTML; background payout and integration-webhook jobs |
| Authentication | `auth.ts` | OTP challenges, HMAC-signed bearer tokens, persisted/revocable sessions, inactive-user checks |
| Existing authorization | `services.ts`, `httpServer.ts` | Scattered membership/role checks; optional `ALLOW_X_USER_ID` bypass; Ops environment bootstrap; Ops and administrator privileges conflated |
| Tenancy | `types.ts`, `store.ts` | Organizations and composite user/org memberships already exist; one legacy role per membership; shipments have optional customerOrgId and carrierId |
| Persistence | `persistence.ts`, `persistenceDb.ts`, `prisma/schema.prisma` | Versioned JSON snapshots by default; optional Postgres/Prisma; database save deletes/reinserts domain tables transactionally; documented schema setup is db push, no versioned migration history |
| Domain | `services.ts`, `types.ts` | Carrier-published anchor trips, customer bookings, driver milestones, POD, payments, ledger and payout batches |
| Payments | `razorpayPayments.ts`, `razorpayPayouts.ts`, `razorpayWebhook.ts` | Mock/Razorpay collection, optional RazorpayX payouts; capture/release currently performed by Ops; automatic payout worker |
| Integrations | `integrationAuth.ts`, `integrationHttp.ts`, `integrationServices.ts`, `integrationWebhooks.ts` | Organization-scoped ERP keys, scopes, idempotency and webhook events; must preserve a distinct service principal boundary |
| Customer/carrier UI | `apps/driver_pilot/lib/*` | Flutter customer/carrier app; role/session behavior also needs updates |
| Marketing | `apps/www` | Vite static site, separate from operational UI |
| Tests | `apps/api/src/*.test.ts`, `packages/core/src/*.test.ts` | Node built-in test runner; service tests and actual localhost HTTP tests; synthetic JSON persistence; some tests use x-user-id |

Not found: NACH mandates/debits, Rupifi credit/underwriting, dispute model/window, invoice model, document storage/downloads, document expiry/verification, or a privileged-action audit store. KYC is currently only an organization status. Do not invent provider integrations or document endpoints to fill these gaps.

### Confirmed gaps to address

1. Customer visibility falls back to organization display-name, phone and booking-user matches. These are not reliable tenant ownership keys.
2. Several customer/carrier membership helpers do not check inactive membership/organization status. Active organization selection is not consistently represented.
3. Ops agents can perform payment actions and manage Ops grants. Finance has no distinct role. Environment bootstrap can independently grant Ops access.
4. Some legacy administrative routes are unauthenticated outside production, or when the demo flag is enabled. Protected operations must not depend on environment flags for authorization.
5. `pilotListCarrierPayoutBatches` returns whole matching batches, which can contain other carriers' transfers and totals.
6. Standard handlers frequently return domain objects directly, including provider references. Provider error messages can flow into API responses.
7. RazorpayX payout setup sets KYC APPROVED on successful bank provisioning; this is not independent compliance verification.
8. Database schema/persistence lack several fields present in the runtime model, including integration records and some trip/shipment transition fields. RBAC-critical persistence cannot rely on those fields surviving a restart without changes.
9. The current delete/reinsert database snapshot strategy cannot be used for an append-oriented audit table.

## Proposed architecture

Retain native HTTP, the existing OTP/session boundary, and both storage modes. Add a central typed permission catalog and `authorize(principal, permission, resource, context)` policy that defaults to deny. No new framework is needed.

- Principal resolution validates user, session, active organization, and active membership on every request. Use a validated `X-Organization-Id` selector; infer it only when exactly one eligible membership exists. Never union rights across organizations. Responses expose allowed actions for UI use.
- Internal OPS/FINANCE/ADMIN require PLATFORM membership. External roles require a compatible external organization. Unknown roles, permissions, missing relationship fields and malformed workflow context deny access.
- Keep legacy role names as compatibility/subrole metadata, preserving narrower driver/staff permissions. Use canonical membership role assignments for SHIPPER/CARRIER/OPS/FINANCE/ADMIN; permit multiple roles without giving rights from an inactive membership.
- Authenticate protected routes in all environments; remove the production-capable x-user-id bypass. Integration keys use their own validated organization-bound service principal and existing scopes; user management remains unavailable to those keys.
- Filter collections by authorized organization/relationship before serialization; inaccessible objects return 404, visible-but-forbidden actions 403, invalid authentication 401.
- Apply policy and workflow checks in the service mutation boundary too, so alternate routes and scheduled jobs cannot bypass them. Scheduled payouts use an explicit system action with the same payment-hold checks, plus system attribution.
- Use allowlisted response serializers, including per-carrier payout batch projections. No raw KYC/bank permission is granted by any baseline role. Sanitize provider failures and audit metadata.
- Record role changes, POD and financial transitions with actor/org/resource/time, safe state summaries, reason and correlation ID. Financial/state overrides and assisted actions require explicit permissions, reasons and effective-actor attribution.

## Proposed permission matrix for this repository

All external access below is within the active organization and resource relationship. Unlisted actions deny by default. Emergency, raw-sensitive-data and break-glass grants are absent by default.

| Capability | SHIPPER | CARRIER | OPS | FINANCE | ADMIN |
|---|---|---|---|---|---|
| Booking/create shipment | Own organization | No | Assisted with reason | No | No |
| Shipment read | Own | Assigned/offered | Operational view | Payment view | Support view |
| Carrier trip publish/manage | No | Own, existing staff restrictions | Assisted with reason | No | No |
| Accept carrier offer/milestones | No | Assigned | Assisted with attribution | No | No |
| POD upload | No | Assigned | Assisted | No | No |
| POD acceptance | Own | No | No | Financial review only | No |
| Payment/ledger status | Own approved fields | Own settlement | Status only | Financial view | Support status |
| Capture/refund/payout execution | No | No | No | Eligible workflow only | No |
| Payout setup | No existing route | Verified owner-level submission | No | No default account change | No |
| KYC status | Own | Own | Status | Status | Status |
| KYC verification | No | No | Dedicated permission; independent actor | No | No |
| Raw KYC/full bank values | No | No | No | No | No |
| Organization invitations | Existing org-admin subset | Existing owner/dispatcher subset | No | No | Catalog-constrained role management |
| Role administration | No system roles | No system roles | No | No | Yes, audited |
| Audit read | Own permitted actions | Own permitted actions | Operational | Financial | Security/admin |

No raw-document, NACH, Rupifi, invoice, analytics-export, or carrier-reassignment endpoints are proposed when the underlying functionality does not exist.

## Proposed schema and compatibility strategy

Preserve Organization, UserRow and Membership identities and composite membership uniqueness. Add deterministic Role, Permission, RolePermission and MembershipRoleAssignment tables/maps, and AuditEvent. Add explicit organization indexes to shipment/carrier/vehicle lookup paths; use compound keys on catalog and role joins. Add membership foreign keys where compatible with the existing snapshot write order; do not add unrelated schema refactors.

Persist any new POD acceptance/hold fields and all authorization-critical transition fields in both JSON and Prisma. A JSON version upgrade must be deterministic and idempotent. Existing audit rows are inserted append-only, never swept by the snapshot delete/reinsert routine; retain them on user/org deactivation. Database audit append and the associated domain change must share the transaction. JSON state and audit changes must share the atomic snapshot write; neither store is claimed to be tamper-proof against storage administrators.

Legacy role mapping proposed for review:

- CUSTOMER_ADMIN/CUSTOMER_MEMBER -> SHIPPER, retaining the admin-only invitation distinction.
- OWNER_DRIVER/OWNER/DISPATCHER/DRIVER -> CARRIER, retaining narrower staff actions; drivers do not gain bank setup or owner administration.
- OPS_AGENT -> OPS.
- OPS_ADMIN -> ADMIN + OPS, with no automatic FINANCE or sensitive-data grant.
- Unknown/incompatible/inactive memberships -> no effective grants.
- Existing environment-bootstrap users require explicit reviewed PLATFORM membership; environment values will not bypass persisted revocation.

Backfill customerOrgId only from a validated, unique organization relationship to bookedByUserId. Do not resolve ambiguous rows using names or phone alone. Unresolved historical shipments remain inaccessible externally pending a reviewed reconciliation; preserve their data and internal support visibility. No production records are inspected for this proposal.

Before any migration outside a disposable local test database, gate 2 requires actual migration files, schema diff, backfill evidence, rollback instructions and query/index impact. Do not run db push on a configured or production database. Proposed migration work should provide versioned up/down scripts suitable for the current non-Prisma-Migrate baseline rather than silently baselining an existing database.

Rollback must preserve audit history, original legacy roles and ownership reconciliation output. An old application cannot interpret new roles/holds safely: rollback requires quiescing writers and a reviewed compatible snapshot/database restoration or downgrade transform. Do not claim that dropping new tables alone is a safe rollback.

## Decisions needed at gate 1

1. **Scope:** recommend securing existing workflows now; defer new NACH/Rupifi/invoice/document-storage/dispute products. The plan's unconditional definition of done includes absent workflows, although its implementation sections say "where underlying workflows exist." This deferral needs explicit approval and must be reported as reduced scope, not full completion of every original criterion.
2. **Marketplace compatibility:** recommend retaining a public sanitized trip catalog and quote preview, requiring authenticated SHIPPER membership to book, and treating trip selection as marketplace offer selection rather than administrative carrier assignment. This changes anonymous booking behavior and requires approval against the matrix's no-direct-assignment rule.
3. **POD/payment safety:** recommend adding POD acceptance and a 48-hour payment hold to the existing flow; Finance capture/release and automatic payouts require owning-shipper acceptance or expiry. A dispute management product remains deferred under decision 1; if dispute submission is required in this feature, its states, ordinary resolution and financial-materiality threshold must be agreed before implementation. Do not advertise dispute protection until it exists.
4. **Dispatch/compliance scope:** recommend using existing payment authorization/capture and independently approved organization KYC as readiness gates. Do not treat provider bank provisioning as KYC approval. Document-level expiry and credit/mandate readiness cannot be claimed without new models. Existing unverified carriers will be blocked until reviewed.
5. **Validation tooling:** approve adding scoped TypeScript/static-analysis/format checks and a Playwright harness for the operational UI. None is currently configured. Flutter checks/build and disposable Postgres persistence tests are also needed; no local Postgres test lifecycle is documented. Docker is installed, but daemon/database/browser availability has not been verified. These gaps cannot be reported as passed.

## Baseline verification

Dependency install used the committed root package-lock. Test commands were executed with a clean environment, temporary synthetic storage, mock payment provider and bookkeeping payouts. No local secret files or production snapshots were read.

| Command | Result | Count / duration | Notes |
|---|---|---|---|
| `npm ci --ignore-scripts --cache /private/tmp/navig8r-rbac-npm-cache-approved --no-audit --no-fund --fetch-retries=0 --fetch-timeout=15000` | Passed | 54 packages | Network approval required; initial sandbox install failed DNS |
| `npm test` (sandbox) | Environment failure | 51 passed, 9 failed | All nine failures were loopback `listen EPERM` |
| `npm test` (approved local listener access) | Passed | 60 passed, 0 failed, 447.96 ms | Includes API/core unit and HTTP integration tests |
| `npm run build --workspace=navig8r-www` | Passed | 73 ms | Existing warning: runtime-config.js lacks module type |
| `./node_modules/.bin/tsc --noEmit --allowImportingTsExtensions` | Passed | N/A | TypeScript validation added for the API and tests |
| `git diff --check` | Passed | N/A | Whitespace validation |
| `./node_modules/.bin/prisma validate --schema apps/api/prisma/schema.prisma` | Passed | N/A | Validated against the disposable Postgres URL |
| Baseline schema + `apps/api/prisma/rbac-migration/up.sql` | Passed | N/A | Applied to disposable Postgres on localhost; no production database |
| JSON persistence round trip | Passed | N/A | Roles, memberships and audit events survived save/load |
| `npx playwright test --config=playwright.config.ts` | Blocked | 1 test not run | Chromium download was started but did not finish in the available run window; API UI shell is covered by HTTP tests |
| Flutter analyze/build | Not run | N/A | No Flutter source changed in this implementation |

Exact safe baseline invocation:

```sh
env -i PATH=/opt/homebrew/bin:/usr/bin:/bin \
  HOME=/private/tmp/navig8r-rbac-test-home NODE_ENV=test PERSISTENCE=FILE \
  DATA_FILE=/private/tmp/navig8r-rbac-baseline.json \
  PAYMENT_PROVIDER=MOCK PAYOUTS_MODE=BOOKKEEPING npm test
```

`npm test` expands to:

```sh
node --experimental-strip-types --test "packages/**/src/**/*.test.ts" "apps/**/src/**/*.test.ts"
```

Implemented validation includes table-driven policy tests, real OTP HTTP tests for all roles, cross-tenant IDs, inactive organizations/memberships, revocation, serializers, workflow boundaries, audit sanitization, payout idempotency and scheduled-job holds using deterministic provider fakes. The Playwright test and config are present; only the local browser executable remains unavailable.

Gate 2 migration review evidence:

- Up migration: `apps/api/prisma/rbac-migration/up.sql` adds authorization-critical columns, indexes, catalog tables, deterministic role/permission seeds, legacy membership backfill and unambiguous shipment ownership backfill.
- Down migration: `apps/api/prisma/rbac-migration/down.sql` is wrapped in an explicit review/quiescence warning and retains audit/recovery state. Dropping authorization state is not presented as a safe application rollback.
- Existing-user backfill preserves `Membership.role`; `MembershipRoleAssignment` provides canonical roles. Ambiguous historical shipments are left unchanged and therefore remain unavailable to external tenant queries.
- The migration was applied only to a disposable local Postgres container, then validated through a JSON and Prisma persistence round trip.

Gate 1 approved. Gate 2 remains required before applying migrations outside a disposable local test database.
