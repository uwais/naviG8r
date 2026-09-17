# Local RBAC walkthrough

Use the `naviG8r-rbac` worktree on `feat/rbac-authorization`. This walkthrough covers the server and `/ops` portal. For the Flutter application, use the mobile steps below; Finance and Admin work stays in the operations portal.

## 1. Start the disposable local demo

In Terminal:

```sh
cd /Users/sundeepperchani/workspace/NaviG8r/naviG8r-rbac
git branch --show-current
node --version
npm ci --ignore-scripts
node --experimental-strip-types scripts/rbac-manual.mjs
```

Use Node with native TypeScript stripping (Node 22.18+ or newer). The current installed Node 26 was used for the earlier API verification. The branch command should print `feat/rbac-authorization`.

The launcher creates fresh synthetic data in a new temporary directory, selects FILE storage and mock payments, and listens only on localhost. It starts no payout or outbound webhook workers. No Postgres setup, database migration, SMS, bank details or `.env` file is needed. Leave this Terminal open. If port 3139 is occupied, stop the other local process before starting this one.

Open:

- [Health check](http://127.0.0.1:3139/health): expect `ok: true`, `persistence: "file"`, `paymentProvider: "mock"`.
- [RBAC test portal](http://127.0.0.1:3139/ops).
- [Admin alias](http://127.0.0.1:3139/admin): the same portal, not a separate application.
- [Shipment workflow](http://127.0.0.1:3139/workflow): shipper/carrier shipment and POD workflow without admin role/compliance sections.

## 2. Sign in with synthetic accounts

Enter the phone, click **Send code**, enter **123456**, then click **Sign in**. No SMS is sent. Use **Sign out** before changing accounts. Separate browser profiles let you keep different users signed in at the same time.

| Account | Phone | User ID | Organization | Effective role |
|---|---|---|---|---|
| Shipper A admin | 8000000001 | user-shipper-a | shipper-a | SHIPPER |
| Shipper B admin | 8000000002 | user-shipper-b | shipper-b | SHIPPER |
| Carrier A owner | 8000000003 | user-carrier-a | carrier-a | CARRIER |
| Carrier B owner | 8000000004 | user-carrier-b | carrier-b | CARRIER |
| Operations | 8000000005 | user-ops | platform | OPS |
| Finance | 8000000006 | user-finance | platform | FINANCE |
| Administrator | 8000000007 | user-admin | platform | ADMIN |
| Dual membership | 8000000008 | user-dual | shipper-a / platform | SHIPPER / FINANCE |
| Carrier A driver | 8000000009 | user-driver | carrier-a | CARRIER, DRIVER subrole |
| Shipper A member | 8000000010 | user-member | shipper-a | SHIPPER, CUSTOMER_MEMBER subrole |

Seeded shipments:

| Shipment | Owner / assigned carrier | Initial state |
|---|---|---|
| load-a-hold | Shipper A / Carrier A | POD uploaded 1 hour ago; payment held |
| load-a-expired | Shipper A / Carrier A | POD uploaded 49 hours ago; payment ready |
| load-a-booked | Shipper A / Carrier A | BOOKED; ready for POD upload |
| load-b-pending | Shipper B / Carrier B | Awaiting carrier acceptance; Carrier B compliance is SUBMITTED |

## 3. Check the browser permissions

Sign in with each role before making changes:

1. Shipper A sees only the three `load-a-*` shipments and **Accept POD** for pending PODs. It has no Finance release or role-management controls.
   Repeat the same check at `/workflow`; this is the dedicated shipment/POD page. `/admin` remains available during the transition.
2. Shipper B sees only `load-b-pending`.
3. Carrier A sees its three assigned shipments; Carrier B sees its one assigned shipment. Neither has POD acceptance or Finance release controls.
4. Ops sees pending-release shipments, the compliance-review form, and read-only payment messaging. It cannot release payments.
5. Finance sees **Release payment** buttons: disabled for `load-a-hold`, enabled for `load-a-expired`. It has no role-management/compliance-review form.
6. Admin sees the **Membership roles** form and support shipment status. It has no release button or raw bank/KYC data.

## 4. Exercise server permissions from the browser

Hidden buttons alone do not prove authorization. While on `/ops`, open Developer Tools → Console (macOS Chrome: Option+Command+J). Paste this helper once in each page session:

```js
window.rbacCall = async (path, method = 'GET', body, extraHeaders = {}) => {
  const token = sessionStorage.getItem('navig8r_access');
  const orgId = document.getElementById('organization').value;
  const response = await fetch(path, {
    method,
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...(orgId ? { 'x-organization-id': orgId } : {}),
      ...extraHeaders,
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const result = { status: response.status, body: await response.json() };
  console.log(result);
  return result;
};
```

The helper attaches only your local test session. Opening a protected API URL in the address bar does not attach that token and will return 401.

### Tenant isolation

As **Shipper A**:

```js
await rbacCall('/shipments/load-a-hold'); // 200
await rbacCall('/shipments/load-b-pending'); // 404
await rbacCall('/shipments/load-b-pending/accept-pod', 'POST', {}); // 404
```

As **Carrier B**:

```js
await rbacCall('/shipments/load-a-booked/driver-pod', 'POST', {}); // 404
```

Verify direct unauthenticated access in Terminal:

```sh
curl -i http://127.0.0.1:3139/shipments
```

Expected: 401. A foreign object returns 404 so another tenant cannot determine whether it exists.

### Operations and Finance separation

As **Ops**, try even the shipment whose hold has already expired:

```js
await rbacCall('/ops/shipments/load-a-expired/release', 'POST', {}); // 403
```

As **Finance**:

```js
await rbacCall('/v1/pilot/anchor-trips/trip-carrier-a/start', 'POST', {}); // 403
await rbacCall('/ops/shipments/load-a-hold/release', 'POST', {}); // 403 payment_hold_active
```

### Existing subrole distinctions

As the **Shipper A member** (`8000000010`):

```js
await rbacCall('/shipments'); // 200
await rbacCall('/v1/pilot/customer/members?orgId=shipper-a'); // 403
```

The same member-list request succeeds as Shipper A admin. As the **Carrier A driver** (`8000000009`), this is denied before any payout data is processed:

```js
await rbacCall('/v1/pilot/carrier/payout-setup', 'POST', { orgId: 'carrier-a' }); // 403
```

## 5. Complete the POD/payment flow

1. As **Finance**, confirm the hold blocks `load-a-hold` (step 4).
2. Sign in as **Shipper A** and click **Accept POD** on `load-a-hold`.
3. Sign in as **Finance** again. Its release button should now be enabled.
4. Click **Release payment**. The shipment leaves the pending-release list.
5. As Finance, verify:

```js
await rbacCall('/ops/shipments/load-a-hold'); // 200, shipment.status = DELIVERED
await rbacCall('/ops/shipments/load-a-hold/release', 'POST', {}); // rejected; no second ledger entry
```

`load-a-expired` lets Finance exercise the expired 48-hour hold without waiting or obtaining acceptance. Release it only after completing the negative Ops check above.

To exercise a new upload, sign in as **Carrier A**:

```js
await rbacCall('/shipments/load-a-booked/driver-pod', 'POST', { notes: 'Synthetic POD test' });
// 200, PENDING_RELEASE; a new 48-hour hold begins.
```

POD here records a delivery transition; raw document upload/storage and dispute management are outside this approved scope. Payment release uses MOCK and moves no money. Settlement remains subject to the existing payout schedule; the manual launcher does not run background payouts.

## 6. Verify independent compliance approval

As **Carrier B**:

```js
await rbacCall('/v1/pilot/carrier/shipments/load-b-pending/accept', 'POST', {});
// 409 carrier_compliance_required
await rbacCall('/v1/organizations/carrier-b/kyc', 'POST', { status: 'APPROVED' });
// 403: carrier cannot verify itself
```

Sign in as **Ops**. In **Carrier compliance review**, enter:

- Carrier organization ID: `carrier-b`
- Reason code: `DOCUMENTS_REVIEWED`
- Status: `APPROVED`

Click **Record review**. Sign back in as Carrier B and repeat the acceptance request: expect 200 and BOOKED. Use only the synthetic record; this test does not inspect real compliance documents.

## 7. Verify role revocation

Sign in as **Admin**. In **Membership roles**, enter:

- User ID: `user-finance`
- Organization ID: `platform`
- Roles: leave blank to remove all canonical roles

Click **Save roles**. Sign in as Finance and issue:

```js
await rbacCall('/payout-batches'); // 403
```

For an immediate-revocation check, keep the Finance session open in another browser profile before removing the role; the next request must fail without logging out. Restore it as Admin by entering `FINANCE` in the same form. Try `ROOT` instead: expect `invalid_role` and no grant.

## 8. Verify one user can act in two organizations

Sign in as **Dual membership** (`8000000008`). Choose an organization explicitly:

- **Synthetic Shipper A:** SHIPPER; sees only Shipper A loads; no Finance release action.
- **Synthetic NaviG8r Internal:** FINANCE; sees the financial pending-release view; no shipper POD acceptance action.

Use the helper to call `/payout-batches` under each selection: expect 403 for Shipper A and 200 for Internal. The server must not combine permissions across these memberships.

## 9. Inspect response filtering and audit records

As Admin, inspect `/ops/shipments/load-a-hold` in DevTools → Network → Response, or use the helper. The shipment should omit gross/commission/net amounts, pickup address, free-text POD notes and payment-provider references. Admin does not inherit raw financial/KYC access.

```js
await rbacCall('/v1/audit');
```

Expected audit views differ by role: Admin sees role/security actions, Finance sees financial actions, Ops sees operational/compliance actions, and external users see their own recorded actions. After the walkthrough, look for `ROLE_REMOVED`, `ROLE_ASSIGNED`, `COMPLIANCE_STATUS_CHANGED`, `POD_UPLOADED`, `POD_ACCEPTED` and `PAYMENT_CAPTURED` in the appropriate views. Records must not include bank values, tokens, or POD-note contents.

## 10. Stop or reset

Press Ctrl+C in the launcher Terminal. To reset, run the launcher command again: every run creates a fresh temporary store. Sign out/in again because browser tokens from the previous run are no longer valid. Existing project data is never overwritten.

Known validation limits: the earlier API suite passed 151 tests; the earlier Playwright run did not launch because its browser installation was incomplete. These manual checks do not mean Playwright, Flutter compatibility, or production migration approval has passed. Gate 2 approval is still required before applying a migration outside a disposable test database.


## 10. Flutter mobile RBAC

Start the synthetic backend using the command at the top of this guide (port 3139). In another terminal:

```sh
cd /Users/sundeepperchani/workspace/NaviG8r/naviG8r-rbac/apps/driver_pilot
flutter run -d chrome --web-port=8080 --dart-define=API_BASE_URL=http://127.0.0.1:3139
```

Open <http://localhost:8080/#/customer/login>. Enable Chrome's device toolbar and choose a 390-pixel-wide phone viewport. OTP is `123456` for every synthetic account.

1. Sign in as Shipper A (`8000000001`). The top selector displays Synthetic Shipper A. Open Shipments and a pending-release shipment. The screen shows the hold deadline; Accept delivery requires confirmation. Accepting changes the status to Delivery accepted and makes the shipment ready for Finance review, without releasing funds automatically. Booking and delivery acceptance never grant Finance permissions.
2. Open <http://localhost:8080/#/customer/shipments/load-b-pending> while still Shipper A. The app must show an unavailable-record message and no other customer's shipment data.
3. Sign out using the top toolbar. Sign in as dual membership (`8000000008`). Select an organization explicitly. Synthetic Shipper A opens the shipper workspace. Switch to Synthetic NaviG8r Internal: the shipper screens disappear and the app directs Finance work to the operations portal. Switch back to restore only shipper permissions. A page reload requires choosing the organization again; the selection is intentionally kept in memory, not shared between browser tabs.
4. Sign in as carrier owner (`8000000003`). Open Profile > Earnings & payouts. Manage payout method is available. Sign out and repeat with driver (`8000000009`): that button is absent. Opening <http://localhost:8080/#/driver/payout-setup> as the driver redirects away without rendering bank fields.
5. Sign in as Carrier B (`8000000004`). The compliance banner explains that Operations approval is pending. Accept and Start controls are unavailable. Approve Carrier B with the Operations account in `/ops`, then tap Refresh access in the mobile toolbar; the compliance block clears. Bank setup is separate from compliance approval.
6. In another browser context, sign in as Admin in `/ops` and remove a mobile user's roles. Tap Refresh access in the mobile app. Existing data and actions disappear. Restore the roles and refresh again. API denials also trigger a session refresh; returning the app from the background refreshes access.

For an Android emulator, replace the launch command with:

```sh
flutter run -d <emulator-id> --dart-define=API_BASE_URL=http://10.0.2.2:3139
```

The synthetic data does not include complete vehicle/driver profiles. Vehicle editing and full GPS trips require additional synthetic registration fixtures. The operations portal uses its own login; mobile tokens are not copied into portal URLs.

## 11. Automated mobile checks

From `apps/driver_pilot`:

```sh
flutter test --no-pub
flutter analyze --no-pub
flutter build web --no-pub --no-web-resources-cdn --dart-define=API_BASE_URL=http://127.0.0.1:3140
```

From the repository root:

```sh
npx playwright test --config=playwright.mobile.config.ts
```

The browser harness creates a fresh synthetic API on port 3140 and serves the compiled Flutter app on port 8087, leaving a manual server on port 3139 alone. It blocks external provider requests. The harness uses installed Chrome on macOS when available, otherwise Playwright Chromium; `RBAC_BROWSER_CHANNEL` can override this selection. Install the selected browser if it is unavailable. Results are written under `/private/tmp/navig8r-mobile-rbac-results`.
