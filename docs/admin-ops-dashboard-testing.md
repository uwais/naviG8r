# Admin/Ops V1 and V2: implementation and testing

Implemented on `feat/admin-ops-dashboard-v1`, based on main `6c7a0878c2abe63c8ef126bbbd31575c96dfb8e5`. The historical layout reference is `3a284098cbb256af587f16a838ee6ff112e40f6e`. Main is not merged or deployed by this work.

## What is available

| URL                                      | View                                                 |
| ---------------------------------------- | ---------------------------------------------------- |
| `/admin/v1`                              | Full administrative dashboard                        |
| `/ops/v1`                                | Full operations dashboard, opening Shipments         |
| `/admin`, `/ops`, `/admin/v2`, `/ops/v2` | Existing compact V2 portal                           |
| `/workflow`                              | Existing external shipment and shipper POD workspace |

V1 and V2 use the same session, selected organization, data and business services. Version links do not grant permissions. V2 retains its compact content layout and now shares V1's full-width blue header, branding, and responsive navigation, labeled V2. No redirects or automatic migration of existing users were introduced.

V1 provides the ten historical data sections as protected searchable tables, plus a narrow Assistance members lookup. It restores carrier creation, trip publishing, assisted booking, POD submission, refunds, payouts, role management and user deactivation. Payment queues include Pending release and Recently delivered filters. The current carrier compliance queue is available in both versions.

The old Mark delivered shortcut is deliberately replaced by carrier/assisted-Ops submission, owning-shipper acceptance in `/workflow`, and eligible Finance release. KYC and payment readiness remain enforced. Payout timing uses server time. No unfiltered database snapshots or local storage paths are embedded in HTML.

## Permissions and API contracts

Existing roles retain their separation. ADMIN gains internal directory/fleet support reads, OPS gains directory/fleet reads and carrier onboarding, and FINANCE gains organization directory reads. These additive catalog permissions are `directory.read`, `fleet.read`, and `carrier.onboard`. External roles gain none of these permissions.

Internal users needing all dashboard actions require explicit `ADMIN,OPS,FINANCE` assignments on one active PLATFORM membership. No existing users are automatically granted these roles. New carriers are CARRIER_FLEET organizations linked to an existing active owner user, with OWNER legacy metadata, a CARRIER assignment, and NOT_STARTED KYC.

| Endpoint                                                        | Access / behavior                                                                                                                                             |
| --------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `GET /v1/ops/dashboard/:section`                                | Internal, with a section-specific check; sections: carriers, organizations, users, memberships, vehicles, drivers, trips, shipments, ledger, payouts, members |
| `POST /v1/ops/carrier-organizations`                            | OPS onboarding; body: displayName, ownerUserId, requestId; valid `X-Reason-Code` required; repeating the same requestId and input reuses the organization     |
| `POST /v1/ops/dashboard-access`                                 | ADMIN creates/updates a registered user's roles in the acting PLATFORM org; body: userId, roles; valid reason required                                        |
| `POST /v1/roles`                                                | Existing membership role replacement; adds last-active-admin protection                                                                                       |
| `POST /shipments/book`                                          | Existing shipper booking, plus OPS assistance using body customerOrgId and headers `X-Effective-Actor-Id`, `X-Reason-Code`                                    |
| Existing trip, POD, compliance, financial and deactivation APIs | Reused; no legacy retired route was reopened                                                                                                                  |

Collection query parameters: `q`, `status`, `offset` (default 0), `limit` (default 25; maximum 100), and ADMIN-only `inactive=true`. The `members` section requires `targetOrgId` for a customer/carrier organization. Response: `{items,total,offset,limit}`; payouts also includes `mode`. Counts and filters operate on projected authorized records. User phone lookup is ADMIN-only through Users search; Ops can look up member IDs through Assistance members for a known organization.

The new routes are grouped under `/v1/ops/dashboard` rather than adding a separate handler for each proposed directory endpoint. Existing collection response shapes remain unchanged for V2 and mobile clients. HTML version labels and the API's `/v1` namespace are independent.

## Start locally with synthetic records

```sh
npm ci
node --experimental-strip-types scripts/rbac-manual.mjs
```

The script creates a fresh temporary FILE store, mock payments and bookkeeping payouts; it never loads a production store or an env file. It serves `http://127.0.0.1:3139`. Every account below uses OTP **123456**.

| Phone      | Role / organization                                                                 |
| ---------- | ----------------------------------------------------------------------------------- |
| 8000000001 | SHIPPER, shipper-a                                                                  |
| 8000000002 | SHIPPER, shipper-b                                                                  |
| 8000000003 | Carrier owner, carrier-a                                                            |
| 8000000004 | Carrier owner awaiting approval, carrier-b                                          |
| 8000000005 | OPS, platform                                                                       |
| 8000000006 | FINANCE, platform                                                                   |
| 8000000007 | ADMIN, platform                                                                     |
| 8000000008 | SHIPPER in shipper-a; FINANCE in platform; explicit organization selection required |
| 8000000009 | Carrier DRIVER in carrier-a                                                         |
| 8000000010 | Disposable customer member, user-member                                             |
| 8000000011 | ADMIN + OPS + FINANCE, platform                                                     |
| 8000000012 | ADMIN + FINANCE, platform                                                           |

Use a fresh seed run when repeating destructive synthetic scenarios. Changes made through either UI are visible in the other after refresh.

## Manual acceptance steps

1. Open [V1 admin](http://127.0.0.1:3139/admin/v1). Sign in as 8000000011. Inspect all ten data tabs, search, record details and pagination. Try desktop and 390px width; wide tables scroll within their container.
2. Use **Compact dashboard (V2)**. Verify the same selected internal organization, current role editor, carrier review queue and payment controls. Return using **Open full dashboard (V1)**. Existing `/admin` and `/ops` must still show V2.
3. In a separate browser context, test ADMIN-only, OPS-only and FINANCE-only accounts. ADMIN has account tools but no payment execution; OPS has operational forms/KYC but no Finance actions; FINANCE has payment tools but no role management or trip publishing. Changing the URL does not change access.
4. **Create carrier:** use a synthetic carrier name, owner `user-carrier-a`, and reason `PILOT_ONBOARDING`. Confirm it appears with NOT_STARTED compliance. Record its organization ID from the success message. Reusing a request after a network retry does not duplicate the carrier.
5. In **Carrier compliance review**, supply `DOCUMENTS_REVIEWED` and approve the new carrier. Verify the confirmation and that it disappears from the pending queue in V1 and V2. A carrier account cannot approve itself.
6. **Assistance members:** enter `carrier-a` or `shipper-a` as the target organization and Search. Copy the represented member ID. Ops cannot use this as a global user/role directory.
7. **Publish trip:** carrier `carrier-a`, member `user-carrier-a`, synthetic cities, valid ISO window timestamps including timezone, capacity 500, and reason `CARRIER_REQUEST`. Coordinates are optional for synthetic trips without geographic endpoints. Copy the returned trip ID.
8. **Book shipment:** customer `shipper-a`, member `user-shipper-a`, the new trip ID, weight 10, synthetic addresses and reason `CUSTOMER_REQUEST`. For geographically constrained trips, include matching pickup/drop coordinates. Sign in as shipper-a to verify ownership; shipper-b must not see this booking. Real-provider checkout remains the shipper's responsibility.
9. **Submit POD:** use seeded BOOKED shipment `load-a-booked`, represented member `user-carrier-a` and reason `DELIVERY_CONFIRMED`. This leaves payment pending; it does not accept the POD or capture funds.
10. Sign in as 8000000001 at [Shipment/POD workspace](http://127.0.0.1:3139/workflow), and accept POD for `load-a-booked`. Sign in as Finance at V2 or V1 and release that payment. Verify its Delivered status and ledger entry.
11. Finance releasing `load-a-hold` must receive `payment_hold_active`. `load-a-expired` may be released after its seeded hold expiry. Inspect Pending release and Recently delivered views. Repeat attempts must not duplicate the capture/ledger effect.
12. **Fail and refund:** on a fresh seed, use `load-b-pending` and reason `CARRIER_FAILED`. Inspect the resulting shipment state. **Run payout batch** with `SETTLEMENT_REVIEWED` and inspect Payout batches. The fixture uses BOOKKEEPING and respects the normal payout schedule; a batch with no eligible lines is valid and moves no real money.
13. **Set internal roles:** grant registered `user-member` OPS access with `ACCESS_REVIEW`. Inspect Memberships. Use **Set membership roles** with that user, target `platform`, and an empty role field to revoke. Verify its subsequent requests are denied. Do not revoke the only remaining ADMIN; the API rejects that action.
14. **Deactivate user:** deactivate `user-member` using reason `ACCOUNT_CLOSED`. Inspect inactive Users as ADMIN. Existing active-work/force and shared-organization protections remain. Use disposable fixtures for force-deactivation testing.
15. Open OPS in one browser and ADMIN in another. Revoke the OPS membership through ADMIN, then refresh access in OPS: protected content clears and direct protected requests fail. Test the dual account switching between platform and shipper-a; internal permissions must not follow it into the shipper workspace.

## Automated checks and visual evidence

```sh
npx tsc --noEmit -p tsconfig.json
npm test
npx playwright install chromium
npx playwright test --config=playwright.config.ts
```

Stop the manual server before Playwright because both use port 3139. The browser harness starts its own fresh synthetic server. `PLAYWRIGHT_CHANNEL=chrome npx playwright test` supports an installed Chrome browser for local verification; CI installs pinned Chromium. Browser output and screenshots live in `test-results/` and are uploaded as CI artifacts. The tests exercise actual mutations, role denials, session revocation and V1/V2 transitions, not just HTML presence. Screenshots are review evidence, not approved visual baselines.

PostgreSQL round trip, only against a disposable local database named `navig8r_dashboard_test`:

```sh
DATABASE_URL=postgresql://postgres@127.0.0.1:55461/navig8r_dashboard_test npx prisma db push --schema apps/api/prisma/schema.prisma --skip-generate
DASHBOARD_TEST_DATABASE_URL=postgresql://postgres@127.0.0.1:55461/navig8r_dashboard_test node --experimental-strip-types scripts/test-dashboard-db.mjs
```

No schema change or role/KYC backfill is required. Runtime permission additions are mirrored by the existing catalog upserts on persistence. The database test verifies owner membership, canonical roles, initial KYC, audit retention and retry behavior after reload. It replaces the disposable database contents and refuses nonlocal or differently named databases.

CI: `dashboard.yml` runs TypeScript, unit/HTTP tests, PostgreSQL round trips and Playwright on relevant pull requests. `release.yml` also gates image builds on TypeScript and browser checks. Flutter retains its separate pinned-SDK workflow.

## Rollback

Keep `/admin` and `/ops` pointing to V2. If V1 must be disabled, remove its two page routes and version links while retaining V2 and the existing shared data. Do not revert the RBAC migration, KYC statuses or audit records. If a backend rollback is needed, revert the feature code through review; no destructive database downgrade is needed for this implementation.

## Local verification results (2026-09-27)

| Check                                      | Result                                                             |
| ------------------------------------------ | ------------------------------------------------------------------ |
| TypeScript (`tsc --noEmit`)                | Passed                                                             |
| Full API/core suite                        | 179 passed                                                         |
| Playwright in installed Chrome             | 10 journeys passed, including every restored action and V2 handoff |
| PostgreSQL round trip                      | Passed, including retries after reload and retained audit history  |
| Flutter 3.22.3 tests                       | 20 passed                                                          |
| Flutter 3.22.3 analysis                    | Passed with 37 existing infos, no warnings/errors                  |
| Scoped Prettier and diff whitespace checks | Passed                                                             |

Representative screenshots were visually inspected: [V1 desktop](screenshots/dashboard-v1/desktop.png), [V1 mobile](screenshots/dashboard-v1/mobile.png), and [preserved V2](screenshots/dashboard-v1/v2-preserved.png). The full browser run captures each data section and action state in `test-results/` and attaches them to test artifacts. No golden baseline was updated.

Local Node version was 26.7.0; CI is configured for Node 22. Local Chrome was used because the pinned Chromium download stalled. Passing local checks do not claim that remote CI or deployment has run.

## V2 header follow-up (2026-09-28)

The user requested the blue V1 header on V2 after comparing desktop/mobile screenshots. The header now appears on `/admin`, `/ops`, `/admin/v2`, and `/ops/v2`, before and after sign-in. It includes the NaviG8r brand, V2 label, full-dashboard link, and shipment/POD workspace link. The compact content layout and RBAC actions remain in place; `/workflow` retains its existing presentation.

For manual verification, restart the local server to load the updated renderer, then open each V2 URL at desktop and 390px/320px mobile widths. Check that the blue header spans the viewport, both links remain visible, and the page does not scroll horizontally. Sign in as `8000000011`, check the same header, and follow the V1 link to confirm the selected membership is retained.

Validation: TypeScript and scoped Prettier checks passed, all 19 affected dashboard/RBAC/HTTP tests passed, and all 13 Playwright journeys passed in installed Chrome. The three new browser cases cover 1440px, 390px, and 320px widths, all four V2 routes, and sign-in/version navigation. Browser checks used an isolated synthetic server on port 3141 because an existing local server occupied 3139.

New evidence: [V2 desktop header](screenshots/dashboard-v1/v2-header-desktop.png) and [V2 mobile header](screenshots/dashboard-v1/v2-header-mobile.png). These screenshots were visually compared with V1. The previous `v2-preserved.png` is historical evidence from before this follow-up and was not replaced; no visual baseline was updated.

### Workspace heading consistency

The subsequent heading correction uses the same page heading and responsive heading sizes in both versions: **Full dashboard** on admin routes and **Operations workspace** on ops routes. The blue header continues to show the app name and version. V2 browser titles identify the selected workspace, and its V1 link preserves the admin/ops route instead of always opening admin. `/workflow` keeps its existing shipment heading and controls.

After restarting the local server, compare `/admin/v1` with `/admin/v2` and `/ops/v1` with `/ops/v2`. Check the headings on desktop and mobile, then follow the version links in both directions. The workspace, selected organization, and roles must remain consistent. `/admin` must match `/admin/v2`, and `/ops` must match `/ops/v2`.

The browser tests cover this behavior at 1440px, 390px, and 320px before/after login. HTTP tests check both route aliases and the actual H1 text. A small background Qwen review supplied the regression checklist; its suggestions were independently checked against these tests, including the unchanged shipment workspace.

Current heading screenshots: [Admin desktop](screenshots/dashboard-v1/v2-admin-heading-desktop.png), [Admin mobile](screenshots/dashboard-v1/v2-admin-heading-mobile.png), [Ops desktop](screenshots/dashboard-v1/v2-ops-heading-desktop.png), and [Ops mobile](screenshots/dashboard-v1/v2-ops-heading-mobile.png). Earlier header screenshots above retain the previous heading as historical evidence.
