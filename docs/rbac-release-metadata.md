# RBAC release metadata

Status: ready for review on `feat/rbac-authorization`; this document is part of the
RBAC release and must be reviewed before promoting a beta build toward production.

The authorization model is server-owned. The Flutter app uses the principal and
permission lists returned by `/v1/auth/me` for navigation and display, but API
handlers enforce every permission again. An absent, inactive, incompatible, or
unknown role denies access.

## Canonical roles and permissions

Permissions are organization-scoped and are never combined across organizations.
The role assignments below are the catalog defaults in `apps/api/src/rbac.ts`.
Resource ownership, workflow state, and legacy subrole restrictions can narrow a
permission further.

| Role | Permissions |
|---|---|
| `SHIPPER` | `organization.profile.read`, `organization.member.invite`, `load.create`, `load.read`, `pod.accept`, `payment.read`, `payment.checkout`, `kyc.status_read`, `audit.read`, `integration.manage` |
| `CARRIER` | `organization.profile.read`, `organization.member.invite`, `load.read`, `trip.publish`, `load.status_update`, `carrier.offer_accept`, `pod.upload`, `payment.read`, `bank_account.create_token`, `kyc.status_read`, `audit.read` |
| `OPS` | `organization.profile.read`, `load.create`, `load.read`, `trip.publish`, `load.status_update`, `pod.upload`, `payment.read`, `kyc.status_read`, `kyc.verify`, `audit.read` |
| `FINANCE` | `organization.profile.read`, `load.read`, `payment.read`, `payment.capture`, `payment.refund`, `settlement.release`, `kyc.status_read`, `audit.read` |
| `ADMIN` | `organization.profile.read`, `load.read`, `payment.read`, `user.role_manage`, `kyc.status_read`, `audit.read` |

Additional policy restrictions are intentional:

- `SHIPPER` can accept POD and check out payment for its own shipments, but cannot
  capture/release funds or refund a payment.
- `FINANCE` can capture/refund/release only when payment workflow and hold checks
  pass. Finance cannot assign carriers or update trip status.
- `OPS` can verify another organization's KYC and perform explicitly attributed
  assisted actions; it cannot perform Finance-only payment operations.
- `ADMIN` can manage roles and view support-safe status, but receives no raw KYC
  documents, bank account values, or automatic Finance grant.
- `CARRIER` payout setup is restricted to legacy `OWNER_DRIVER` and `OWNER`
  subroles. `DISPATCHER` and `DRIVER` retain carrier operational permissions but
  cannot create a bank-account token.
- `integration.manage` is restricted to legacy `CUSTOMER_ADMIN` membership
  metadata even when the canonical role is `SHIPPER`.

## Legacy role compatibility

The migration preserves `Membership.role` as subrole metadata and creates
canonical assignments in `MembershipRoleAssignment`:

| Existing membership role | Canonical role(s) | Narrowing that remains |
|---|---|---|
| `CUSTOMER_ADMIN` | `SHIPPER` | Invitations and integrations |
| `CUSTOMER_MEMBER` | `SHIPPER` | No admin-only invitation/integration actions |
| `OWNER_DRIVER`, `OWNER`, `DISPATCHER`, `DRIVER` | `CARRIER` | Only `OWNER_DRIVER`/`OWNER` can set up payout; invitations remain owner/dispatcher scoped |
| `OPS_AGENT` | `OPS` | Assisted actions require reason and effective actor |
| `OPS_ADMIN` | `ADMIN`, `OPS` | No automatic Finance or raw-sensitive-data grant |
| `FINANCE` | `FINANCE` | Finance permissions only |
| `ADMIN` | `ADMIN` | Admin permissions only |

An organization must be compatible with its role (`CUSTOMER` for `SHIPPER`,
carrier organization kinds for `CARRIER`, and `PLATFORM` for internal roles).
Ambiguous historical ownership is not guessed from names or phone numbers.

## Assigning and reviewing roles

Role changes must be performed by an authenticated `ADMIN` principal with
`user.role_manage`. The selected organization is sent in `X-Organization-Id`.
The API validates compatibility, replaces the canonical assignment set, and
writes `ROLE_ASSIGNED`/`ROLE_REMOVED` audit events.

Example request against a synthetic or beta API:

```sh
curl -X POST "$API_BASE/v1/roles" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -H "X-Organization-Id: $TARGET_ORG_ID" \
  -d '{"userId":"'$TARGET_USER_ID'","orgId":"'$TARGET_ORG_ID'","roles":["SHIPPER"]}'
```

Use an empty `roles` array only when intentionally revoking all canonical roles.
Do not edit catalog tables or bypass the API in a shared environment. After a
role change, the client must refresh `/v1/auth/me`; revoked users must lose
protected data and actions without relying on a browser restart.

## Local and beta manual test procedure

All local tests use synthetic data, OTP `123456`, mock payments, and bookkeeping
payouts. Never use production credentials or production data.

1. Start the synthetic API from the repository root:

   ```sh
   node --experimental-strip-types scripts/rbac-manual.mjs
   ```

2. Start the Flutter web client in a second terminal:

   ```sh
   cd apps/driver_pilot
   flutter run -d chrome --web-port=8080 \
     --dart-define=API_BASE_URL=http://127.0.0.1:3139
   ```

3. Open `http://localhost:8080/#/customer/login` using a 390px phone viewport.
   Sign in with OTP `123456`.

4. Test Shipper A (`8000000001`): confirm the organization selector, own
   shipment visibility, payment-hold banner, POD confirmation dialog, and POD
   acceptance. Confirm that acceptance does not capture payment or grant Finance
   permissions.

5. While signed in as Shipper A, open
   `/#/customer/shipments/load-b-pending`. It must show an unavailable-record
   response and no Shipper B data.

6. Test the dual account (`8000000008`): explicitly select `Synthetic Shipper A`,
   verify shipper actions, switch to `Synthetic NaviG8r Internal`, verify that
   shipper screens disappear and internal Finance work points to `/ops`, then
   switch back. Confirm that permissions from the two organizations are never
   combined.

7. Test Carrier Owner (`8000000003`) and Driver (`8000000009`). Payout setup
   must be visible only to the owner. A driver opening
   `/#/driver/payout-setup` must be redirected without bank fields.

8. Test Carrier B (`8000000004`) while KYC is pending. Carrier offer/start
   controls must be blocked. Approve the organization with an Operations account
   in `/ops`, tap mobile **Refresh access**, and confirm the controls become
   available. Carrier self-verification must remain rejected.

9. As Admin, revoke a user's role in `/ops`, refresh access in the mobile app,
   and confirm that protected records/actions disappear. Restore the role and
   confirm recovery after another refresh.

10. Review `/v1/audit` as the appropriate internal role. Confirm role changes,
    KYC transitions, POD acceptance, payment transitions, and assisted actions
    include actor, organization, resource, request ID, timestamp, and safe state
    summaries. Confirm raw bank/KYC values and provider secrets are absent.

For an Android emulator use `http://10.0.2.2:3139`; for a physical device use a
LAN address. The operations portal has its own login and does not receive mobile
tokens in URLs.

## Automated release checks

Run these before moving a beta build toward production:

```sh
env -i PATH=/opt/homebrew/bin:/usr/bin:/bin NODE_ENV=test \
  PERSISTENCE=FILE DATA_FILE=/private/tmp/navig8r-rbac-release.json \
  PAYMENT_PROVIDER=MOCK PAYOUTS_MODE=BOOKKEEPING npm test

cd apps/driver_pilot
flutter test --no-pub

cd ../..
npx playwright test --config=playwright.mobile.config.ts --timeout=25000
git diff --check
```

The API suite must have zero failures. The focused RBAC/session Flutter tests and
the three mobile browser scenarios must pass. If a full Flutter analyze/build or
browser test is unavailable in the release environment, record the exact command
and failure rather than marking it passed.

## Beta-to-production gate

Before production promotion, reviewers must confirm:

- The branch contains the approved RBAC commit and this metadata file.
- `apps/api/prisma/rbac-migration/up.sql` was applied and verified only in a
  disposable database first; production execution has an approved backup,
  writer-quiescence window, schema review, and rollback plan.
- Existing memberships have deterministic canonical assignments; ambiguous
  historical shipment ownership remains quarantined for internal review.
- Synthetic manual tests and automated tests pass in the beta environment with
  production-like auth/session configuration and no demo bypass.
- Admin, Finance, Ops, Shipper, Carrier Owner, Dispatcher, and Driver scenarios
  have been tested with separate accounts and cross-tenant IDs.
- Audit events are present for role and financial transitions, and sensitive
  response fields are absent.
- A rollback decision preserves audit history and legacy membership metadata;
  dropping new RBAC tables alone is not a safe rollback.
- A separate, explicit approval authorizes production migration and deployment.

This document does not authorize a production migration, deployment, merge, or
use of production data by itself.
