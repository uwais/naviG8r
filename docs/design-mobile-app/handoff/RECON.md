# Redesign recon

What the app and API do today, measured against the handoff spec. This is PR 0 of `PROMPTS.md`:
recon only, no code changed.

**How this was put together.** Three read-only recon passes (shipper side, carrier and driver side,
app shell) on branch `feat/mobile-redesign` at `4a77afa`. Each pass read the Dart files and the API
serializers directly. Two line numbers where the passes disagreed were re-checked by hand
(`notification_center.dart:16` for `_activityDate`, `eway_bill_words.dart:153` for the checked date).
Everything else is as the passes reported it and was not re-checked line by line.

**Paths.** `lib/...` means `apps/driver_pilot/lib/...`. `api/...` means `apps/api/src/...`.
`test/...` means `apps/driver_pilot/test/...`.

**Not checked.**
- The shipper pass did not open the sh-* PNGs. Its mockup fields come from the visible text of
  `mockups/sh-*.html` and `wb-*.html`.
- The carrier pass opened 8 of the ca-/dr- PNGs (`ca-booking-owner`, `dr-confirm`, `ca-home`,
  `dr-today`, `dr-trip`, `ca-trip`, `ca-profile`, `dr-ewb`). The mapping for the rest rests on
  `spec/screens.md`.
- `copy.md`, `components.md` and `accessibility.md` were not read in recon.
- `test/booking_refusal_test.dart` was not opened.

---

## 1. Screens and routes, and the mockups they become

### Router and app root (`lib/main.dart`)

- `main()` at 72-81 creates `api = Api(resolveApiBaseUrl())`, starts push notifications, runs
  `DriverPilotApp`.
- GoRouter built in `initState` at 102-134.
  - `initialLocation` is `/customer` on web, `/driver` on phones (104).
  - `refreshListenable` is `AuthorizationSession.revision` (105).
  - Global redirect is `mobileAccessRedirect(state.uri.path)` (106).
- Routes:
  - `/workspace` shows an empty widget (108-109).
  - `driverFlowRoutes()` (110) and `customerFlowRoutes()` (111).
  - `/pilot-lab` opens the developer `HomeScreen` (112).
  - `/` redirects to `/customer` or `/driver` (113-114).
  - `/register` opens the developer `RegisterScreen` (115).
  - `/login` opens the developer `LoginScreen`; with `mode=customer` it redirects to
    `/customer/login` (116-124).
  - `/trips`, `/trips/:tripId`, `/publish` are developer screens (125-132).
  - None of the developer routes is guarded in `mobileAccessRedirect`. Someone signed out can reach
    them by URL.
- `_sessionChanged` (140-159): on sign-out or while switching it clears the carrier cache and
  `lastBookedShipmentId`; after a switch it calls `router.go(AuthorizationSession.home)` (155-158).
  On resume it calls `AuthorizationSession.refresh()` (161-169).
- Push notifications open `ShipmentConversationScreen` (198-232).
- `MaterialApp.router` (181-193):
  - `builder` wraps every page in its own `Navigator` holding `OrganizationAccess(child: ...)`
    (182-189).
  - Title "NaviG8r Customer" on web, "NaviG8r Driver" on phones (190).
  - `theme: DriverTheme.theme()` (191).
  - **No `themeMode` and no `darkTheme`.** With no dark theme the app already renders light; the
    guardrail still wants `themeMode: ThemeMode.light` set explicitly.

**Developer screens in `main.dart`** (no mockup):
- `PilotScaffold` (235-318) with its own five tabs: Home, Register, Login, Trips, Publish (293-314).
- `HomeScreen` at `/pilot-lab` (320-495): Logout icon (387-391), raw API health and
  `/v1/pilot/me` dumps, quick-action links. Developer links into `/customer` at 487.
- `LoginScreen` (602-803): a visible "challengeId" field (757-759) and raw HTTP button labels such
  as "POST /v1/auth/otp/start" (752, 771). Link into `/customer` at 778.
- Private copies `_formatIst` and `_defaultAnchorTripWindow` at 49-70, used by the `/publish` lab
  screen at 1092 and 1254.

### Access gate (`lib/organization_access.dart`, 207 lines)

**`OrganizationAccess`** (7-76) wraps the whole app.
- Spinner while not initialized or while switching (16-19).
- `blocked` means signed in with no principal, or with neither SHIPPER nor CARRIER role (24-27).
- When blocked or on error it puts `OrganizationToolbar` on top (31-32) and shows one of: "Internal
  workspace", "Organization access", "Choose an organization above to continue.", the
  no-membership text or the no-permission text (41-54).
- For PLATFORM orgs it shows the raw ops URL (55-59) and Retry (60-63).
- Otherwise renders the child under `KeyedSubtree(key: scopeKey)` (66-68).

**`mobileAccessRedirect`** (79-152).
- No principal, or no shipper or carrier role, goes to `/workspace` (83-90).
- `/workspace` sends you to `home` or `/customer/login` (91-95).
- Blocks crossing between shipper and carrier sides (96-108).
- Public paths: the customer list (109-116), and `/driver` plus `/driver/onboarding/*` (117-118).
- Customer path permissions (119-132): team needs `organization.member.invite`, integrations needs
  `integration.manage`, book needs `load.create`, everything else `load.read`.
- Driver path permissions (133-150). `payment.read` gates earnings at 146-149; `path.contains('payout')`
  needs `payment.read`; payout setup needs `bank_account.create_token`.

**`OrganizationToolbar`** (155-207). Renders nothing signed out. Company `DropdownButton<String>`
(173-192), hint "Choose organization", items are `displayName` or the raw org id (182-183). Refresh
icon "Refresh access" (194-197). Sign-out icon "Sign out of all organizations" (198-202), hidden by
`showSignOut` (156-160). Spec replaces it with the header account button and `c-menu` sheet.

### Who is signed in, and switching company

**`lib/authorization_session.dart`**
- State (12-21): `user`, `principal`, `organizations`, `initialized`, `switching`, `error`.
- `signedIn` (23). `organizationId` from `principal['organizationId']` (25); `organization` looks it
  up (26-31). `hasRole` (33-34). `can` checks `principal['permissions']` and returns false while
  switching (35-37).
- `home` (38-42): `/customer` for SHIPPER, `/driver/loads` for CARRIER, else `/workspace`.
- `scopeKey` is `userId:orgId` (43).
- `_load` calls `GET /v1/auth/me` (98). On 400/403 with an org selected it clears and retries
  (99-108). Keeps only `user`, `organizations`, `principal` (111-115). **The response's
  `memberships` array, which holds each org's role, is dropped.** A principal whose org is not
  listed is set to null (116-119). 401 handling at 128-150.
- `selectOrganization(id)` (166-177): `switching = true`, null `principal`, `api.selectOrganization`,
  bump `revision`, await `refresh()`, `switching = false`, bump again. `signOut()` (76-82).

**`lib/pilot_api.dart`**: `selectOrganization` only sets in-memory `activeOrganizationId` (130-134),
sent as `x-organization-id` (83-84). **Not persisted.** Server side (`api/rbac.ts:68-69`,
`api/httpServer.ts:691-703`), with no header and more than one membership `/v1/auth/me` returns no
principal, so a cold start with several companies lands on `/workspace`. `setToken`/`clearToken` at
136-160.

**`lib/driver_session.dart`**: `carrierOrgId` (7-8), `carrierOrgName` (9-11), `carrierRole` =
`principal.subrole` (12-14), `userFullName` (15-16), `userPhone` (17-18), `kycStatus` (19-21),
`hasCarrierOrg` (44), `canInviteDrivers` (45-46), `canSetUpPayouts` (47-48). `refresh()` calls
`/v1/pilot/me` (51-101); `clearCarrierCache` (105-114).

**`lib/customer_session.dart`**: `userFullName`, `userPhone`, `customerOrgName`, `customerRole`
(CUSTOMER_ADMIN or CUSTOMER_MEMBER) at 7-18. `applyForTest` (34-64) used by tests.

### How owner, dispatcher and driver are told apart today

- Subrole string from the server principal, `DriverSession.carrierRole` (`driver_session.dart:12-14`).
  Values OWNER, OWNER_DRIVER, DISPATCHER, DRIVER (labels at `pilot_api.dart:414-427`;
  `carrierMemberRoleLabel` is not called anywhere in `lib`).
  - Direct `== "DRIVER"` checks: `driver_flow.dart:1095, 1115, 1122, 1326, 1827, 2753` and
    `unassigned_driver_notice.dart:13`.
  - No code checks OWNER or DISPATCHER by name.
- Role `hasRole('CARRIER')` (`authorization_session.dart:33-34`) is CARRIER for all four subroles.
- Permissions (`authorization_session.dart:35-37`; server matrix `api/rbac.ts:12` and `:43-60`):
  - `payment.read`: everyone except DRIVER. Used at `driver_flow.dart:211-212, 997, 1149, 1195, 1784,
    2286-2289, 2304, 2377, 2401` and `organization_access.dart:146-147`.
  - `trip.assign` marks the carrier office: `transporter_id_section.dart:84-85`,
    `accept_booking.dart:20`, `trip_assignment_card.dart:39-40`.
  - `eway_bill.add_truck`: `eway_bill_carrier_card.dart:31-34, 65-69`.
  - `bank_account.create_token` (owner, owner-driver) is `canSetUpPayouts`; the approval banner uses
    it as the owner test (`carrier_approval_banner.dart:82`).
  - `transporter_id.write` (owner, owner-driver): `transporter_id_section.dart:102, 115`.
  - `organization.member.invite` (owner, owner-driver, dispatcher) is `canInviteDrivers`, used at
    `driver_flow.dart:782, 847, 1798`.
- No single owner flag. Only `bank_account.create_token`, `transporter_id.write` or the raw subrole
  separate owner from dispatcher. A dispatcher holds `payment.read`, so sees "Net to carrier"
  (`driver_flow.dart:1155-1157`) and can open `/driver/earnings`.

### Shipper shell

**`CustomerScaffold`** (`customer_flow.dart:71-203`, build at 106).
- Tabs Home, Trips, Book, Shipments (`customer_layout.dart:86-91`); index/path mapping
  `customer_flow.dart:83-103`.
- At 900 dp and wider a `NavigationRail` replaces the bar (`customer_layout.dart:13`,
  `customer_flow.dart:164-186`); this is the wb-* layout. Otherwise `NavigationBar` with
  `kCustomerNavDestinations` (188-197).
- App bar (113-162): `bottom:` holds `OrganizationToolbar(showSignOut: false)` (125-130); title
  Column with title 20/w700 and subtitle "fullName · phone" at 11 (113-115, 131-144);
  `NotificationBell` (146-148); "Sign out" logout IconButton (149-154); on phones a "Switch to
  driver" truck icon to `/driver` (155-160). Spec replaces all of these with one account button.
- A signed-in shipper's `home` is `/customer` (`authorization_session.dart:38`), but sign-in sends a
  SHIPPER to `/customer/shipments` (`customer_flow.dart:498-500`).

`NotificationBell` (`notification_center.dart:40-86`, build 78): tooltip "Notifications" or
"Notifications, N unread", polls `/v1/notifications/shipments` every 45 s. Spec removes it; the Home
"Updates" row replaces it.

### Shipper screens (`customer_flow.dart` unless named)

| Route | Screen and build line | Becomes mockup |
|---|---|---|
| `/customer` | `CustomerHomeScreen` :222 (class 205-372, title "Book freight", own Sign out row 321-328) | sh-home |
| `/customer/login` | `CustomerLoginScreen` :509 (class 374-597) | c-signin, c-code, c-code-error (shared screens) |
| `/customer/register` | `CustomerRegisterScreen` :1342 | **no mockup** |
| `/customer/register-user` | `CustomerRegisterUserScreen` :656 | **no mockup** |
| `/customer/team` | `CustomerTeamScreen` :786 | **no mockup** |
| `/customer/integrations` | `CustomerIntegrationsScreen` :1097 | **no mockup** |
| `/customer/trips` (`?tab=match`) | `CustomerTripsScreen` :1420, tabs :1426-1432 | sh-lanes-*, wb-lanes |
| (tab) | `_CustomerBrowseTripsTab` :1491 | sh-lanes-browse |
| (tab) | `_CustomerMatchTripsTab` :1577 | sh-lanes-match, sh-lanes-empty |
| (card) | `_tripCard` :1640 | lane card in sh-lanes-*, wb-lanes |
| `/customer/eligible` | redirects to `trips?tab=match` (:54-57) | no screen |
| `/customer/book?anchorTripId=&weightKg=` | `CustomerBookShipmentScreen` :1934 | sh-book-start, sh-book-price, sh-book-error, wb-book. sh-book-confirm is a new sheet before `_checkout!.open` (:1905) |
| `/customer/shipments` | `CustomerShipmentsScreen` :2153 | sh-shipments, wb-shipments |
| `/customer/shipments/:id` | `CustomerShipmentDetailScreen` :2443 | sh-ship-waiting, sh-ewb-ask, sh-ewb-portal, sh-ewb-truck, sh-ewb-checking, sh-ewb-problem, sh-ship-transit, sh-ship-delivered, sh-ship-noewb, sh-ship-cancelled, wb-shipment |
| (part of detail) | `_ShipmentTimeline` :2623, fed by `shipmentTimelineSteps` (`pilot_api.dart:507-566`) | step list (cp-steps) |
| (part of detail) | `EwayBillCard` (`eway_bill_card.dart:379`) | see the e-way bill parts below |
| (part of detail) | `ShipmentPaymentStatus` (`shipment_payment_status.dart:75`) | part of sh-ship-delivered. Its "Accept delivery" button and dialog (:105-108, :37-51) have **no mockup** |
| pushed route | `NotificationInboxScreen` (`notification_center.dart:206`) | sh-notifications |
| pushed route | `ShipmentConversationScreen` (`notification_center.dart:470`) | **no mockup**; wb-shipment shows messages inline |

**E-way bill parts inside `EwayBillCard`**

| Part | Code | Becomes mockup |
|---|---|---|
| Viewing state | `_viewing` :214 | no bill: sh-ewb-portal, sh-ship-waiting. NOT_NEEDED: sh-ship-noewb. BILL: sh-ewb-truck, sh-ewb-checking, sh-ewb-problem |
| Bill form | `_billForm` :321 | sh-ewb-details, sh-ewb-details-error |
| Not-needed reasons form | `_statementForm` :357, radio list `_ReasonChoices` :422 | **no mockup** for the reasons list |
| Truck form | `EwayBillTruckForm.build` (`eway_bill_truck_form.dart:142`) | sh-ewb-truck shows only the prompt. **No mockup** for the fields (truck, date, time) |
| Copy box | `EwayBillCopyBox.build` (`eway_bill_copy_box.dart:28`) | copy rows in sh-ewb-portal and sh-ewb-truck |
| Portal button | `EwayBillPortalButton.build` (`eway_bill_portal_link.dart:59`) | "Open the e-way bill portal" |
| Error line | `EwayBillErrorText` (`eway_bill_error_text.dart:9`) | field errors |

**Shared with carrier screens** (changing wording changes both sides): `ewayBillRowSummary`
(`driver_flow.dart:1003`), `shipmentStatusLabel`, `EwayBillTruckForm`, `ShipmentPaymentStatus`
(`driver_flow.dart:1193`). `eway_bill_carrier_card.dart` is carrier-only (used at
`driver_flow.dart:1158`).

### Carrier and driver shell (`driver_flow.dart`)

- Screen titles from `driverShellTitle` (33-47): "NaviG8r", "Shipments", "Loads", "Publish trip",
  "Profile", "Fleet", "Active trip", "Proof of delivery", "Earnings" and so on.
- **`DriverShell`** (50-189, build 101):
  - Tab index per path (66-82), path per index (84-98).
  - `PopScope` sends back to `/driver` from tab roots (106-114).
  - App bar `bottom:` holds `OrganizationToolbar` when signed in (117-121). Back arrow on non-root
    pages except `/active` (125-131). Title 26/w700 (132-134).
  - Actions: page actions, `NotificationBell` if `can("notification.read")` (137-139), then a
    `CircleAvatar(backgroundColor: navy, radius: 18)` with no child and no tap: 36 dp, decoration
    only (140-144).
  - Body holds `CarrierApprovalBanner` (149).
  - Bottom nav (152-185): a `const` list of five tabs, Home, Shipments, Loads, Publish, Profile
    (159-183). **Every carrier subrole gets the same five tabs.** `showBottomNav` defaults true; no
    caller sets it false.
- Spec: header plus `c-menu` sheet; office tabs as in `ca-home` (five tabs); driver tabs as in
  `dr-today` (Today, Trips, Profile).
- `driverFlowRoutes()` (2944-3020) is a `ShellRoute` with `driverShellNavigatorKey` (2946-3006);
  onboarding routes sit outside the shell (3007-3018).

### Carrier and driver screens

| Route | Widget and build line | Mockup(s) |
|---|---|---|
| `/driver` | `DriverWelcomeScreen` :195 (class 191-257) | Signed-out start. **No ca-/dr- mockup** |
| `/driver/onboarding/phone` | `DriverPhoneScreen` :304 (class 259-336) | `c-signin` |
| `/driver/onboarding/otp` | `DriverOtpScreen` :473 (class 338-518) | `c-code`, `c-code-error` |
| `/driver/onboarding/register` | `DriverRegisterScreen` :601 (class 520-662) | **no mockup** |
| `/driver/onboarding/join` | `DriverJoinScreen` :708 (class 664-744) | **no mockup** |
| `/driver/fleet` | `DriverFleetInviteScreen` :828 | part of `ca-profile` ("Add driver" / "Invite"), no dedicated mockup |
| `/driver/shipments` | `DriverShipmentsScreen` :978, inline Accept at :1005-1012 | `ca-bookings`. Drivers lose this tab |
| `/driver/shipment/:id` | `DriverShipmentDetailScreen` :1110, app bar title "Proof of delivery" (:42) | `ca-booking-new`, `ca-booking-truck`, `ca-booking-deliver`, `ca-booking-owner`, `ca-booking-dispatcher`. Drivers get `dr-ewb` and `dr-trip` instead |
| `/driver/loads` (carrier home after sign-in, `authorization_session.dart:41`) | `DriverLoadsScreen` :1338; `_LoadCard` :1466, Start at :1535-1539, View/Track/Summary at :1540-1551 | `ca-trips`. For drivers `dr-today` and the Trips tab; no `dr-trips` mockup found |
| `/driver/track` | `DriverTrackScreen` :1627. No in-app link reaches it; route and title (:38) remain | **no mockup** |
| `/driver/profile` | `DriverProfileScreen` :1741 (class 1656-1819) | `ca-profile` (office), `ca-vehicle-sheet` (truck row), `dr-profile` (driver) |
| `/driver/trip/:tripId/active` | `DriverActiveTripScreen` :2125; embeds `TripAssignmentCard` (:2197-2199); Start load (:2218-2234); Complete load (:2244-2256) | Office: `ca-trip`, `ca-assign`, `ca-start`. Driver: `dr-trip` |
| `/driver/shipment/:id/pod` | `DriverPodScreen` :2394 (notes field and "Confirm POD" only) | `dr-confirm`, then `dr-done`. Office: `ca-booking-deliver` |
| `/driver/earnings` | `DriverEarningsScreen` :2468 | **no mockup** |
| `/driver/payout-setup` | `DriverPayoutSetupScreen` :2642 | **no mockup** (the `ca-profile` "Bank details · Change" row would lead here) |
| `/driver/payout-history` | `DriverPayoutHistoryScreen` :2727 | **no mockup** |
| `/driver/publish` | `DriverPublishTripScreen` :2858 | `ca-publish`. Drivers lose this tab |
| Accept sheet (modal) | `acceptBooking` `accept_booking.dart:15`, `_TruckChoiceSheet` build :149 | `ca-accept-empty`, `ca-accept-chosen` |
| Truck and driver card | `TripAssignmentCard` build `trip_assignment_card.dart:278` | card in `ca-trip`, plus `ca-assign` |
| E-way bill card | `EwayBillCarrierCard` build `eway_bill_carrier_card.dart:116` | `ca-booking-truck`, `dr-ewb` |
| Part B truck form | `EwayBillTruckForm` build `eway_bill_truck_form.dart:142` | `ca-booking-truck` (Add truck) |
| Transporter ID section | `TransporterIdSection` build `transporter_id_section.dart:83` | Transporter ID card in `ca-profile` |
| Approval banner | `CarrierApprovalBanner` build `carrier_approval_banner.dart:73`, `_banner` :78 | **no mockup** (related: "Approved by NaviG8r" chip in `ca-profile`) |
| Map and pin editor | `LocationEndpointEditor` build `location_editor.dart:428`; `activeTripMap` :173 | `ca-publish` (map), `dr-trip` |
| Org gate and toolbar | `OrganizationAccess` `organization_access.dart:12`; `OrganizationToolbar` :163 | replaced by header button and `c-menu` |

`ca-home` and `dr-today` have no equivalent screen today; each is a new arrangement of shipments and
trips data. `screens.md` says the design "replaces the Flutter logo screen"; no such screen exists in
`lib/` (it may mean the native launch screen; not checked).

**Welcome screen details** (`DriverWelcomeScreen`, the `/driver` route at 2958-2959, which is also
the Home tab, so signed-in carriers see it): "Driver & carrier" (201-207); body text differs for
drivers (210-217); "Sign in with phone" to `/driver/onboarding/phone` (219-222); "Register as new
carrier" (224-227); "Continue as signed-in driver" (229-244); "Join a carrier fleet" (246-248);
"Developer lab" to `/pilot-lab` (250-252). None is gated by sign-in or `kReleaseMode`, and `/driver`
is public, so signed-in carriers are not redirected away.

**Sign-in details**
- `DriverPhoneScreen`: app bar "Sign in" (306), "Mobile number" with hint "+91 ..." (312-317), "Send
  code" (319-327), "Back" (328-330). `extra` carries challengeId, expiresAtUtcMs, debugCode (289-293).
- `DriverOtpScreen`: "Verify code" (475), "Code sent to $_phone" (479), "Expires at ..." with raw
  local DateTime (481-484), "Debug OTP: ..." (487-491), **a visible "Challenge id" `TextField`**
  (493-495, controller 346), "6-digit code" (496-498), "Verify" (500-508), "Resend code (Ns)" as a
  TextButton (509-513). After verify goes to `AuthorizationSession.home` (444-445), falls back with a
  snackbar to `/driver` (447-453).
- `CustomerLoginScreen`: no visible challenge field (kept in state, 385-386); "Mobile number"
  (551-556); "Send code" / "Resend code (Ns)" as OutlinedButton (558-570); "6-digit code" maxLength 6
  (572-577); "Verify and continue" (583-591); OTP cooldown text at 566; "Debug OTP: [code]" at 546.

**Profile details** (`DriverProfileScreen`): top card org name and "name · phone" (1748-1754);
`TransporterIdSection` (1781); "Earnings & payouts" only with `can("payment.read")` (1784-1792);
"Publish anchor trip" row (1793-1797); "Fleet — invite drivers" row (1798-1806); "Sign out" tile
with logout icon (1807-1815).

---

## 2. Shipment step mapping: which fields decide each row

Data sources:
- `GET /shipments` and `GET /shipments/:id`, read at `customer_flow.dart:2124` and `:2301`.
- SHIPPER serializer `api/rbacResponses.ts:15-23`. E-way bill shape `api/ewayBillVisibility.ts:15-32`.
- The trip comes only from `GET /shipments/:id/tracking` (`customer_flow.dart:2334`), so **only the
  detail screen has it.**
- Status values `PENDING_CARRIER_ACCEPT`, `BOOKED`, `PENDING_RELEASE`, `DELIVERED`,
  `FAILED_CARRIER_REFUNDED` (`api/types.ts:20-25`). There is no "in transit" status.

| `screens.md` row | Fields that decide it |
|---|---|
| Awaiting acceptance, no answer | `status == PENDING_CARRIER_ACCEPT` and no `ewayBill`. Decidable, but looks the same as "needed" below |
| Awaiting acceptance, needed / not needed | Not needed: `ewayBill.kind == NOT_NEEDED`. Needed: **MISSING**. No stored "yes, needed" answer; the only records are `BILL` (all four details required, `eway_bill_card.dart:134-150`) or `NOT_NEEDED`. A `BILL` saved before acceptance can stand in for "needed" |
| Accepted, needed, no bill | `status == BOOKED` and no `ewayBill`. **Cannot be told apart from "never answered"** (same gap) |
| Accepted, bill, no truck | `ewayBill.kind == BILL` and `ewayBill.truckNumber` empty |
| Accepted, bill and truck, not checked | `BILL` with `truckNumber` and no `ewayBill.check` |
| Accepted, ops problem | `ewayBill.check.result == PROBLEM`; `check.problemReason` is NOT_FOUND, CANCELLED, DETAILS_DO_NOT_MATCH or OTHER. The table does not say which wins when a bill is flagged and also has no truck |
| Accepted, checked or not needed, waiting | `check.result == FOUND` or `kind == NOT_NEEDED`, and trip `status != IN_PROGRESS`. **MISSING on list and Home**: trip status is detail-only |
| In transit | **MISSING on the shipment.** It is `status == BOOKED` plus `trip.status == IN_PROGRESS`, and the trip comes only from `/tracking` per shipment. The list "Next:" line and Home counts cannot separate this from the previous row without one `/tracking` call per shipment |
| Delivery confirmed / Delivered | `status == PENDING_RELEASE` or `DELIVERED`; `podAtUtcMs` and `podAcceptedAtUtcMs` present |
| Cancelled | `status == FAILED_CARRIER_REFUNDED` |

The "[Carrier]" name in Next lines comes from `carrierDisplayName` (present). The existing step
function is `shipmentTimelineSteps` (`pilot_api.dart:507`): five steps, none for the e-way bill. The
new function would replace it.

---

## 3. Fields the mockups show that the app does not get

### The six items PROMPTS.md asks about

| Item | Status |
|---|---|
| Truck list for the accept sheet | **Available.** `GET /v1/pilot/carrier/fleet` returns `vehicles[{id, registrationNumber, vehicleClass}]` (`api/tripAssignment.ts:49-63`, needs `trip.assign`). No capacity. Read at `accept_booking.dart:92-101`, shown via `portalTruckNumber` (:140-141). The sheet opens only with `trip.assign` and no `assignedTruckNumber` (:18-20) |
| Carrier transporter ID for shippers | **Available, after acceptance only.** `carrierTransporterId` is sent to SHIPPER (`api/rbacResponses.ts:19`) only while `status == BOOKED` (`api/services.ts:243`). The server does not check GSTIN against it (`api/ewayBillValidation.ts:60-77`), so the sh-ewb-details-error check would be a new client-side validation rule: an owner call |
| E-way bill valid-until | **Available**: `ewayBill.validUntilUtcMs` (`api/ewayBillVisibility.ts:22`) |
| Ops check status and note | **Status available** (`check.result`, `checkedAtUtcMs`). **Note missing**: `check` holds only `result`, `problemReason`, `checkedAtUtcMs` (`api/types.ts:243-248`, `api/ewayBill.ts:123-129`). No note text, so the spec's fallback "show the ops note text" is not possible either. Nearest is today's sentence per reason (`eway_bill_words.dart:157-166`) |
| Proof-of-delivery photo | **Missing.** No camera or picker package in `pubspec.yaml`. `POST /shipments/:id/driver-pod` takes only `notes` (`api/httpServer.ts:1302-1312`); `podNotes` is stripped (`api/rbacResponses.ts:38`). `DriverPodScreen` has a notes field only (`driver_flow.dart:2407-2410`). Shipper has only `podAtUtcMs` |
| Commission amount | **Missing for carriers.** `commissionPaise` goes to FINANCE only (`api/rbacResponses.ts:21`) |

### Shipper side, not sent to shippers

- **Driver name** (sh-ship-transit): `assignedDriverName` goes only to CARRIER and OPS
  (`api/rbacResponses.ts:31-33`).
- **"Needed: yes" answer** and a "Yes, make one" action (sh-ship-waiting, sh-ewb-ask): no field, no
  endpoint.
- **Ops check structured difference** (sh-ewb-problem "The invoice number on the portal's bill is X.
  You entered Y."): not stored.
- **Accepted-at time** (wb-shipment "Accepted by ... 17 Oct, 09:12 IST"): `acceptedAtUtcMs` exists
  in storage (set at `api/services.ts:1829`) but is not in the shipper allowlist
  (`api/rbacResponses.ts:15`).
- **Cancellation details** ("NaviG8r operations cancelled it on [date] at your request"): no who,
  why or cancel time. Only `status` and the shipment's `updatedAtUtcMs`.
- **Refund date**: payment has `status: REFUNDED`, `amountPaise`, `updatedAtUtcMs`
  (`api/rbacResponses.ts:25`, set at `api/services.ts:2202`). `updatedAtUtcMs` could stand in; not
  checked whether anything updates it later.
- **Notification row content** (sh-notifications): a row carries only `shipmentId`,
  `latestAtUtcMs`, `unreadCount`, `shipmentReference` (`api/notifications.ts:254, 380`). No event
  title, body, route or date. `shipmentReference` is `externalLoadId` or the first 8 characters of
  the ID.
- **"[n] new since yesterday"** (sh-home): only `unreadCount` exists.

### Shipper side, reachable through endpoints the app already calls

- **Lane date and city route** on lists, Home and notifications: the shipment has free-text
  `pickupAddress`/`dropAddress` only; `windowStart`, `windowEnd`, `originCity`, `destCity` are on the
  trip. Detail gets them from `/tracking`; lists would need one `/anchor-trips/:id` call per shipment
  (endpoint used at `customer_flow.dart:1769`). Unclear whether "[From] to [To]" means lane cities or
  shipment addresses.
- **"Booked and paid · ₹X held until delivery"** on lists: `payment` comes only from
  `GET /shipments/:id`. `grossPaise` is on list rows.
- **"Left [pickup] on [date] at [time]"**: `trip.startedAtUtcMs` is in the trip allowlist
  (`api/rbacResponses.ts:31`); detail screen only.
- **Home "needs you" card**: Home never loads shipments, only refreshes the session
  (`customer_flow.dart:212-219`). Needs a `/shipments` read on Home (existing endpoint).

### Shipper side, present

`ewayBill.enteredAtUtcMs` ("You said so on [date]", `api/ewayBillVisibility.ts:27`),
`assignedTruckNumber`, `podAtUtcMs`, and per-field server errors: the server returns `field` in
e-way bill errors (`api/ewayBillValidation.ts:16`) but `ewayBillErrorSentence` reads only `detail`
(`pilot_api.dart:260-271`).

**Lanes need nothing new.** Every field is on `/anchor-trips` and the match endpoint
(`api/rbacResponses.ts:31`). Match keeps only OPEN trips with room, sorted by closeness
(`api/services.ts:1343-1365`); it also returns trips failing the distance test, which the app hides
at `customer_flow.dart:1630-1632`. Browse returns every active trip including IN_PROGRESS and
COMPLETED (`api/httpServer.ts:1191`); the mockup shows only Open and Full.

### Carrier and driver side

- **Shipper paid** (`ca-booking-owner`): missing. `grossPaise` goes to SHIPPER and FINANCE only
  (`api/rbacResponses.ts:17`); payment `amountPaise` the same (:25).
- **You receive**: available. `netToCarrierPaise` goes to CARRIER (`api/rbacResponses.ts:20`),
  removed for subrole DRIVER (:41). Shown at `driver_flow.dart:1155-1157` and `:2285-2286`;
  dispatchers also receive it.
- **Bank account ending 4821** (`ca-booking-owner`, `ca-profile`): missing. `accountNumber` is
  stripped (`api/rbacResponses.ts:38`); no last-4 or bank name field exists.
- **Driver list for assign**: available from the same fleet call, `drivers[{userId, displayName}]`,
  names only (`api/tripAssignment.ts:58-61`). Read at `trip_assignment_card.dart:86`, listed at
  :224-229. Saving needs truck and driver (:98, :265). `driverBusy` comes back from the save (:114).
- **Carrier phone** for "Call [carrier]" (`dr-ewb`): no field.
- **Directions button** (`dr-trip`): no maps launch today. `url_launcher` is installed but used only
  for the e-way bill portal; this would be a new action.
- **Add truck, remove truck, truck sheet** (`ca-profile`, `ca-vehicle-sheet`): no endpoint. Only
  invite-a-driver-with-vehicle (`/v1/pilot/carrier/drivers/invite`) and `PATCH /v1/pilot/me/vehicle`
  for your own primary truck.
- **Team list** (`ca-profile` "Team", "Drivers (3)"): no carrier members endpoint (only
  `/v1/pilot/customer/members`). The fleet drivers list is available to office logins.
- **Stop order** ("Drop 1 of 3", `dr-trip`, `dr-ewb`): no field. Shipments sort newest first
  (`api/services.ts:1036`).

### Shell

- **Header "Company · Person · Role"**: company `organization.displayName`, person `user.fullName`,
  role `principal.subrole`, for the selected company only. The account sheet's per-company role needs
  `memberships[].role`, which `/v1/auth/me` sends but `AuthorizationSession` drops (111-115).
  Unclear whether keeping it counts as "adding a data field".
- **"Add a company" / "Register as a carrier"** for someone signed in: `POST /v1/pilot/driver/register`
  refuses an existing phone (`phone_already_registered`, `api/services.ts:290-291`). The shipper
  register endpoint was not checked.

---

## 4. Where the app formats dates, money, weights and IDs

### Money
- `formatInrFromPaise` (`pilot_api.dart:334-338`): no Indian grouping ("₹2640"), paise with 2
  decimals. Called at `customer_flow.dart:2080` (quote), `:2588` (shipment `grossPaise`), `:2605`
  (payment `amountPaise`), and `driver_flow.dart:1157, 2286, 2486, 2490, 2739`.

### Dates and times
- `pilot_api.dart:340-349` `formatIstIsoFromUtc`.
- `pilot_api.dart:351-366` `defaultAnchorTripWindow`, used at `driver_flow.dart:2785, 2876`.
- `pilot_api.dart:458-491` `formatTripWindowRange`: "12 Jun – 14 Jun" (spec wants "18 – 19 Oct").
  Used at `customer_flow.dart:1645` and `:1978`.
- `eway_bill_dates.dart:26-48` (`ewayBillDateFromUtcMs`, `ewayBillDateTimeFromUtcMs`,
  `ewayBillClockTime`, `ewayBillDateFromCalendarDate`): always includes the year, never adds "IST".
  Callers: `eway_bill_card.dart:129-131, 268, 336`; `eway_bill_words.dart:58` ("Valid until: ...
  (India time)") and `:153` (checked date); `eway_bill_truck_form.dart:129-139, 169-171`.
- `eway_bill_truck_form.dart:10-13, 56-61`: converts between India time and UTC.
- `eway_bill_words.dart:59-72`: "Expires in N hours" and a "has passed" line. Not in any mockup.
- `customer_flow.dart:2276`: "Last updated HH:MM" from phone-local `DateTime.now()`, no IST.
- `customer_flow.dart:566`: OTP cooldown "Resend code (24s)".
- `shipment_payment_status.dart:81-83`: `DateTime...toLocal().toString()` prints raw
  "2026-10-19 14:20:00.000" in phone time. Shippers see this card.
- `notification_center.dart:16` `_activityDate`: "10/17 7:41 AM" in phone time (the spec's "Never"
  format). Used at `:285`.
- `driver_flow.dart:483`: raw `DateTime.toLocal()` for OTP expiry.
- `driver_flow.dart:1573-1579` `_LoadCard._formatWindow`: "Window from 2026-05-12", raw ISO date.
- `driver_flow.dart:2742`: raw `cutoffUtcMs`.
- `main.dart:49-70`: private `_formatIst` and `_defaultAnchorTripWindow`.

### Weights
- `customer_flow.dart:1665`: "Capacity X kg (Y kg reserved)" (the spec's "Never" example).
- `customer_flow.dart:1986`: "Room left: N kg".
- `customer_flow.dart:2213`, `:2588`: raw `weightKg` plus " kg".
- `customer_flow.dart:1546`, `:1610`, `:2012`: field labels and the zero-weight error.
- `driver_flow.dart:1000` ("· N kg"), :1468-1470 and :1487 ("N kg available"), :1509 ("res / cap
  kg"), :1518, :1645 ("Reserved Nkg · RAW_STATUS"), :1683-1685 (capacity text), :2284 ("Nkg", no
  space).

### IDs, codes and numbers
- `groupedBillNumber` (`eway_bill_words.dart:10-16`): monospace at `eway_bill_card.dart:261-266` and
  `eway_bill_carrier_card.dart:73`; row summary at `eway_bill_words.dart:38`.
- `portalTruckNumber` (`eway_bill_words.dart:83-98`): used at `eway_bill_copy_box.dart:30`,
  `eway_bill_card.dart:210`, `accept_booking.dart:45, 56, 140`, `trip_assignment_card.dart:213`. Raw
  truck at `eway_bill_words.dart:41, 54` and `eway_bill_copy_box.dart:50-55`.
- GSTIN and invoice raw at `eway_bill_card.dart:269-270`.
- Transporter ID shown as typed (`transporter_id_section.dart:104, 138`).
- `customer_flow.dart:2493`: "Synced from ERP · [externalLoadId]".
- `notification_center.dart:265-269, 285`: "Shipment [reference or first 8 ID characters,
  upper-cased]". An ID in the UI.
- Integrations screen (no mockup): API key id ~`customer_flow.dart:1243`; webhook event id and
  "HTTP: [status]" ~`:1273-1275`.
- Phones raw: `customer_flow.dart:114`, `:318`, `:850`.
- Debug OTP: `customer_flow.dart:546`, `driver_flow.dart:489`.
- `driver_flow.dart:1484`: `Chip(label: Text(vClass))` shows SMALL, MEDIUM, LARGE.
- `driver_flow.dart:1645`: raw trip status.
- `driver_flow.dart:1708`, `:2816`, `:2822`: errors naming fields (`vehicleClass`, `capacityKg`).
- `driver_flow.dart:2066`: "(Shipment list needs API deploy — merge driver-onboarding PR.)".
- `driver_flow.dart:2901-2914`: publish labels such as "windowStart (ISO)" and "vehicleClass
  (SMALL|MEDIUM|LARGE)".
- `organization_access.dart:57-58`: ops URL. `:182-183`: falls back to the org id.
- `location_editor.dart:384-391`: raw geocoder `status` (for example `NO_API_KEY`) and a
  `--dart-define` hint.

### Raw codes and HTTP text reaching screens
- `shipmentStatusLabel` (`pilot_api.dart:369-384`) returns literal "FAILED_CARRIER_REFUNDED" for
  shippers (`seesPayment` true) and any unknown status raw. Shipper caller `customer_flow.dart:2206`.
- `paymentStatusLabel` (`pilot_api.dart:440-455`) and `tripStatusLabel` (`:386-399`) fall back to
  the raw code.
- `formatApiError` (`pilot_api.dart:232-247`) falls back to "HTTP n: body" (:243) and "Cannot reach
  API at [url]" with `--dart-define` text (:236-243). Shown at `customer_flow.dart:1478, 1570, 1774,
  1843, 1919, 2268, 2351`, and `:2565` ("Tracking error: ...").
- `customer_flow.dart:2139` decides "needs sign-in" by checking whether the error text contains
  "401".

---

## 5. Every place a driver route can reach a price, amount or payout today

1. Shipment detail "Net to carrier: ₹X" at `driver_flow.dart:1155-1157`. Gated only on the field
   being present; the server strips it for DRIVER (`api/rbacResponses.ts:41`). The UI does not check
   the role.
2. Active trip row "status · ₹X net" at `driver_flow.dart:2285-2286`. Same gate.
3. Earnings screen: paise at `driver_flow.dart:2470-2490`, "Approval status ..." at :2501, payout
   buttons at :2507-2514. Router blocks it without `payment.read` (`organization_access.dart:146-149`);
   the Profile link is gated at :1784. Server strips `pendingAccruedPaise` and `paidPaise` for
   drivers.
4. Payout history at `driver_flow.dart:2739-2742` (`totalNetToCarrierPaise`, raw `cutoffUtcMs`).
   Router gate `path.contains('payout')` needs `payment.read`.
5. Payout setup ("Delivery payments go to this account", :2652). Gated by
   `bank_account.create_token` in the router and at :2643.
6. `ShipmentPaymentStatus` hold and release lines (`shipment_payment_status.dart:95-101`). Hidden by
   `showPaymentStatus: can("payment.read")` (`driver_flow.dart:1193-1195`).
7. Payment words gated by `payment.read`: "Payment pending" (`driver_flow.dart:2303-2310`); proof of
   delivery copy (:2377-2378, :2401-2402); welcome text "get paid after proof of delivery"
   (:211-215), shown to anyone signed out or holding `payment.read`. `shipmentStatusLabel(seesPayment:)`
   (`pilot_api.dart:369-384`) returns the raw status for unknown codes even for drivers (comment at
   `shipment_payment_status.dart:15-17`).
8. Ungated error text: `formatApiError` maps `payment_hold_active` to a sentence about payment holds
   (`pilot_api.dart:208-209`); its fallback "HTTP n: <body>" (:243) could echo any response field.
9. Notification and conversation text is server-written (`notification_center.dart:515-520, 553`).
   Not determined whether any event body names an amount; a grep for "₹" in `api/services.ts` found
   only a pricing comment at :1394.

Existing guard tests: `test/driver_sees_no_earnings_test.dart` and `api/driverSeesNoEarnings.test.ts`.

---

## 6. Flutter version and API names

- SDK is **Flutter 3.22.3 with Dart 3.4.4**; pubspec allows Dart `>=3.3.0`. Checked by grepping
  `$HOME/flutter-sdks/3.22.3/packages/flutter/lib`.
- **`CardTheme` is the right name.** `card_theme.dart:30` declares `class CardTheme`;
  `ThemeData.cardTheme` takes `CardTheme?` (`theme_data.dart:332, 1261`). **`CardThemeData` does not
  exist in 3.22.3 and will not compile.** Same for `DialogThemeData` and `TabBarThemeData`.
- **`WidgetStateProperty` and `WidgetState` exist** (`widgets/widget_state.dart:42, 484`).
  `MaterialStateProperty` / `MaterialState` are deprecated typedefs ("deprecated after
  v3.19.0-0.3.pre", `material/material_state.dart:49-54, 425-430`). The analyzer reports them as
  `info` only, so they do not fail `--no-fatal-infos`. New code should use the Widget names.
- `Color.withOpacity` is not deprecated in 3.22.3; `withValues` does not exist yet.
- Every ThemeData field used in `spec/navig8r_theme.dart` exists in 3.22.3 (AppBarTheme
  `scrolledUnderElevation`, `shape`; BottomSheetThemeData `modalBarrierColor`, `showDragHandle`;
  ChipThemeData `backgroundColor`, `selectedColor`, `secondaryLabelStyle`; CardTheme `margin`;
  InputDecorationTheme `helperStyle`, `errorStyle`; NavigationBarThemeData `elevation`,
  `indicatorColor`, `labelTextStyle`, `iconTheme`; `FilledButton.styleFrom`
  `disabledBackgroundColor`, `disabledForegroundColor`, `minimumSize`, `textStyle`;
  `OutlinedButton.styleFrom` `backgroundColor`; ColorScheme `outlineVariant`,
  `surfaceContainerHighest`; ThemeData `materialTapTargetSize`, `fontFamily`, `textButtonTheme`,
  `bottomSheetTheme`, `dividerTheme`; `FontFeature`).
- The reference theme was compiled in a scratch package on 3.22.3: `flutter analyze` found 4 issues,
  all `info` `deprecated_member_use` (MaterialStateProperty/MaterialState at lines 196, 198, 199,
  200). No errors.
- Reference theme clashes with the hard rules (not SDK problems): `fontFamily: "Manrope"` (86) and
  the `"Poppins"`/`"Manrope"` names in `NvText` (47-48) must go, since those fonts are not bundled.
  `NvText.id` and `idDisplay` use `fontFamily: "monospace"` (59-60), which the app already uses at
  `eway_bill_card.dart:263`, `eway_bill_carrier_card.dart:75`, `customer_flow.dart:1074, 1245`.
- **Today's theme** (`lib/driver_theme.dart`, 83 lines): navy `0xFF122C53`, background
  `0xFFF4F7FA`, border `0xFFE2E8F0`, muted `0xFF64748B` (5-8), `mutedOnBackground` (13).
  `theme()` (15-82): `ColorScheme.fromSeed(seedColor: navy, surface: background)` (18), appBar
  (20-25), filled (26-33), outlined (34-41), input (42-50), `const CardTheme(...)` (51-58), chip
  (59-63), `navigationBarTheme` with `MaterialStateProperty`/`MaterialState` (64-80) and
  `navy.withOpacity(0.12)` (66). No `fontFamily`, no `minimumSize` or tap-target settings. Tokens
  want navy `0xFF16233D` and page `0xFFF8F7F2`.
- Baseline: `flutter analyze --no-fatal-infos` reports "41 issues found", all `info`, no warnings or
  errors.

---

## 7. Other facts relevant to the guardrails

### Preselected and prefilled values
- Accept sheet preselects the only truck (`accept_booking.dart:104-105`); the test "the only truck is
  already chosen" asserts it (`test/truck_at_acceptance_test.dart:152`). Spec says nothing
  preselected (PR #153 behaviour), so following the spec changes that test.
- Trip card preselects whatever is already assigned (`trip_assignment_card.dart:22-23`, matches its
  docstring).
- Publish, register and invite forms prefill "MEDIUM"/"1000" (`driver_flow.dart:532-533, 757-758,
  2771-2778`, with Gurugram/Jaipur at 2771-2774); invite role defaults to "DRIVER" (:759).
- Match tab presets "Gurugram, Haryana", "Jaipur, Rajasthan", 200 kg (`customer_flow.dart:1519-1523`).
- Book screen presets 200 kg, "Sector 44, Gurugram", "Sitapura, Jaipur" (`customer_flow.dart:1694-1698`).
  Only `weightKg` carries over from the search (`:1672`, `:1740-1744`).

### Booking and pricing behaviour
- The quote is never cleared when weight, pickup or drop changes, and "Book & pay" works without a
  quote (`customer_flow.dart:1816-1847`, `:2035-2055`). The price shown is `quote.grossPaise`; the
  amount charged is `payment.amountPaise` (`:1892-1895`). Not determined whether they are always
  equal.
- Shipment detail title is the carrier name (`customer_flow.dart:2464`); the spec says the route.

### Role conflicts with the spec
- The API gives DRIVER `trip.publish`, `carrier.offer_accept`, `load.status_update`, `pod.upload`
  (`api/rbac.ts:12`, none filtered for DRIVER at :43-60). The spec's driver tabs (Today, Trips,
  Profile) drop Bookings (Accept) and Publish, which removes things a driver can do today. That
  clashes with "no permission changes" and needs the owner's call. Hiding the tabs is a UI change
  only; the permissions stay.
- Which existing route the driver "Today" tab maps to was not determined.
- Spec says "Start lives only on the trip screen"; today Start is also on the list card
  (`driver_flow.dart:1535-1539`) and in the trips query at :1264-1277.
- Removing `OrganizationToolbar` everywhere: `OrganizationAccess` (31-32) relies on it for the
  `/workspace` "Choose an organization" screen, the only way to pick a company after a cold start
  with several companies. The account sheet must be reachable there too.
- Hiding developer links with `kReleaseMode`: tests run in debug and still find them, and the
  `/pilot-lab`, `/register`, `/login`, `/trips`, `/publish` routes stay reachable by URL either way.

### Tap targets (not measured)
Two places probably fall under 48 dp: `_LoadCard` chips with `VisualDensity.compact`
(`driver_flow.dart:1483-1491`) and dropdowns with `isDense: true` (`trip_assignment_card.dart:165`).
The shell avatar is 36 dp but has no tap today.

### Placeholders
`lib/ui/` does not exist yet, so `lib/ui/pending_copy.dart` does not either (checked by `ls`).

### Existing tests that will likely need updating

**`test/otp_flow_test.dart`**
- Challenge id shown in the "Challenge id" field: 192 `find.text('fallback-1')`, 289
  `find.text('new')`, 325 `find.text('challenge-first')`.
- Field order (challenge at index 0, code at 1): 254, 258 and 291 `find.byType(TextField).at(1)`.
- 222, 226: `find.byType(TextButton).first` is Resend.
- Wording: 'Send code' (72, 118, 158, 321); 'Resend code (2s)' (77, 221); 'Resend code' (84, 124,
  161, 225, 255, 285); 'Debug OTP: ...' (120, 127, 284, 288, 324); `textContaining('Expires at')`
  (290); 'Code sent to 9876543210' (326).
- 318 taps 'Sign in with phone'. 80, 87: `find.byType(OutlinedButton).last` is the customer Send
  button. 71, 117, 157, 320: `TextField.first` is the phone field.

**`test/top_bar_sign_out_test.dart`**: 41 `byIcon(Icons.logout)` finds one; 42 `byTooltip('Sign out')`
finds one; 43 'Sign out of all organizations' finds nothing; 45, 57 'Refresh access' finds one; 52
toolbar sign-out finds one; 56 no logout icon when `showSignOut` is false.

**`test/mobile_rbac_test.dart`**: 124 mounts `OrganizationToolbar()`; 128 taps
`DropdownButton<String>`; 131 taps 'Internal'; 133 expects 'Internal workspace'.

**`test/widget_test.dart`**: 41, 98 'Sign in with phone'; 42 'Driver & carrier'; 73 'Choose an
organization above to continue.'; 77, 81 'Book freight'; 80 'Internal workspace'.

**`test/driver_sees_no_earnings_test.dart`**: 43-48 and 60-66 `DriverWelcomeScreen` texts ('Run your
trips with live tracking...' and the everyone text at 36-38); 194-204 Profile 'Your vehicle' and
'Earnings & payouts'.

**`test/driver_shell_test.dart`**: back-arrow behaviour via `byIcon(Icons.arrow_back)` at 38-78.
Breaks if the back control stops being an `Icons.arrow_back` IconButton.

**`test/notification_center_test.dart:201`**: `find.text('Notifications')` (inbox title).

**`test/truck_at_acceptance_test.dart:152`**: single-truck preselection (see above).

No test asserts the bottom-tab labels or the avatar (grepped single- and double-quoted 'Home',
'Shipments', 'Loads', 'Publish', 'Profile', 'Trips', 'Book', plus `NavigationBar` and
`CircleAvatar`).

Other tests touching these screens, not opened in recon: `eway_bill_card_test`,
`eway_bill_copy_box_test`, `eway_bill_refresh_test`, `eway_bill_row_summary_test`,
`eway_bill_truck_form_test`, `eway_bill_carrier_card_test`, `customer_integrations_screen_test`,
`authorization_session_test`, `trip_assignment_test`, `transporter_id_test`,
`trip_no_longer_assigned_test`, and probably `booking_refusal_test`.

---

## Gaps: spec items the app or API cannot support today

Each keeps today's behaviour in the redesign. None is to be built around.

### Shipper

1. **E-way bill "needed: yes" answer** (sh-ewb-ask, sh-ship-waiting, step mapping rows 1-3). No stored
   "yes, needed" answer and no endpoint to save it; "no answer", "needed" and "accepted, needed, no
   bill" cannot be told apart. Nearest fallback: no `ewayBill` maps to the "no answer" / "make the
   bill" row; a `BILL` stands in for "needed".
2. **"Yes, make one" action** (sh-ewb-ask). No endpoint.
3. **In-transit and "waiting for start" on the list and Home** (step mapping rows 7-8, sh-shipments
   "Next:" line, Home "needs you" counts). No in-transit status on the shipment; `trip.status` comes
   only from `/tracking`, one call per shipment. Detail screen can show it; lists cannot without N
   extra calls.
4. **Which row wins when a bill is flagged and also lacks the truck.** Not specified in
   `screens.md`.
5. **Driver name** (sh-ship-transit). `assignedDriverName` not sent to SHIPPER.
6. **Proof-of-delivery photo and "View proof of delivery"** (sh-ship-delivered). No photo field,
   upload or endpoint; shipper has only `podAtUtcMs`.
7. **Ops check note and structured difference** (sh-ewb-problem). `check` holds only `result`,
   `problemReason`, `checkedAtUtcMs`; no note text, so the spec's own fallback is unavailable. Nearest:
   today's per-reason sentence (`eway_bill_words.dart:157-166`).
8. **Accepted-at time** (wb-shipment). Stored but not in the shipper allowlist.
9. **Cancellation details** (who, why, when) (sh-ship-cancelled). Only `status` and `updatedAtUtcMs`.
10. **Refund date** (sh-ship-cancelled). No dedicated field; `payment.updatedAtUtcMs` is a possible
    stand-in, not confirmed.
11. **"Contact NaviG8r" action** (sh-ship-cancelled) and **"Change or cancel"** (every sh-ship-*).
    No contact action; per the owner's decision only the contact line with the `[NaviG8r contact]`
    placeholder.
12. **"Ask NaviG8r staff"** (sh-ewb-problem). Only channel is the shipment conversation; whether ops
    reads it is not known.
13. **Notification row content** (sh-notifications): event title, body, route and date. A row has
    only `shipmentId`, `latestAtUtcMs`, `unreadCount`, `shipmentReference`.
14. **"[n] new since yesterday"** (sh-home). Only `unreadCount`.
15. **Route and lane date on lists, Home and notifications.** Not on the shipment; would need one
    `/anchor-trips/:id` call per shipment. Also unclear whether "[From] to [To]" means lane cities or
    shipment addresses.
16. **"Booked and paid · ₹X held until delivery" on list cards.** `payment` only on
    `GET /shipments/:id`; list has `grossPaise` only.
17. **GSTIN-equals-transporter-ID error** (sh-ewb-details-error). Server does not check it, and
    `carrierTransporterId` is absent before acceptance. Adding it in the app is a new validation rule:
    owner call.
18. **Per-field server errors.** Server sends `field`, the app reads only `detail`. Reading `field`
    is in reach but is a behaviour change: owner call.
19. **Lane browse shows only Open and Full.** `/anchor-trips` returns IN_PROGRESS and COMPLETED too;
    filtering client-side is a behaviour change: owner call.

### Carrier office

20. **Shipper paid** (`ca-booking-owner`). `grossPaise` and payment `amountPaise` not sent to CARRIER.
21. **Commission** (`ca-booking-owner`). `commissionPaise` FINANCE only.
22. **Bank account ending NNNN** (`ca-booking-owner`, `ca-profile`). No last-4 or bank name field;
    `accountNumber` stripped.
23. **Dispatcher sees no amounts** (`ca-booking-dispatcher`). Dispatchers hold `payment.read` and
    receive `netToCarrierPaise` today. Hiding it in the UI is possible via the raw subrole or the
    owner-only permissions, but there is no single owner flag; and the server still sends it.
24. **"Confirm delivery" disabled until a photo is added** (`ca-booking-deliver`). No photo capture
    package (and no new dependencies allowed) and no upload endpoint.
25. **Add truck, remove truck, truck sheet** (`ca-profile`, `ca-vehicle-sheet`). No endpoint; only
    driver invite with vehicle and `PATCH /v1/pilot/me/vehicle`.
26. **Team list, "Drivers (3)"** (`ca-profile`). No carrier members endpoint; only the fleet drivers
    list (names only).
27. **Truck capacity in the accept sheet.** Fleet `vehicles` carry no capacity.
28. **Accept sheet: nothing preselected.** Supported by data, but contradicts the existing test at
    `test/truck_at_acceptance_test.dart:152`; changing it changes tested behaviour.
29. **Publish fields start empty, truck size a chip choice** (`ca-publish`). Supported by data; today
    prefilled. Noted because tests may rely on the prefills (not checked).

### Driver

30. **Photo-first proof of delivery** (`dr-confirm`). Driver POD takes only `notes`.
31. **"Call [carrier]"** (`dr-ewb`). No carrier phone field.
32. **Directions button** (`dr-trip`). No maps launch today; would be a new action.
33. **Stop order "Drop 1 of 3"** (`dr-trip`, `dr-ewb`). No stop-order field.
34. **Driver tabs Today, Trips, Profile.** The API grants DRIVER `trip.publish` and
    `carrier.offer_accept`; dropping Publish and Bookings removes things drivers can do today
    (guardrail 2 conflict). Owner call. Also no decided route for "Today".

### Shell and account

35. **Per-company role in the account sheet.** `memberships[].role` is sent by `/v1/auth/me` but
    dropped by `AuthorizationSession`; unclear whether keeping it counts as adding a data field.
36. **"Add a company" / "Register as a carrier" while signed in.** Carrier register refuses an
    existing phone (`phone_already_registered`); shipper register not checked.
37. **Company choice survives a cold start.** Not persisted; users with several companies land on
    `/workspace` and the account sheet must work there, replacing `OrganizationToolbar`.
38. **Developer routes stay reachable.** `kReleaseMode` hiding does not remove the `/pilot-lab`,
    `/register`, `/login`, `/trips`, `/publish` routes, and they are unguarded.
39. **"Replaces the Flutter logo screen"** (`screens.md`). No such screen in `lib/`; possibly the
    native launch screen, not checked.
40. **Fonts Poppins and Manrope.** Not bundled and downloads are not allowed; platform default
    family is used with token sizes and weights.
41. **`lib/ui/pending_copy.dart` does not exist.** Placeholders cannot be used until it is created,
    and its text must come from the owner, not be invented.
