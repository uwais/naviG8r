# Driver app backlog

Everything here is the Flutter app in `apps/driver_pilot/`. One line per **fix**, not per finding —
several findings usually collapse into one change. Tick items here; the evidence, the file and line,
and the reasoning stay in [`UX-REVIEW.md`](UX-REVIEW.md) and are not deleted when an item is ticked.

Ordered by what it costs the person using the app. Severity is the worst finding folded into that fix.

**Scope note.** App only. Findings in the API, the marketing site and the deployment pipeline are not
tracked here. One of them outranks everything on this page and is recorded at the bottom.

---

## Money and irreversible actions

- [ ] **Show the price on the accept card, and let the row be tapped.** A carrier accepts a binding
  load without seeing what it pays, and the tap to the screen that shows it is disabled for exactly
  those rows. `high` — [2.1](UX-REVIEW.md#21-a-carrier-accepts-a-binding-load-without-ever-seeing-what-it-pays)
- [ ] **Confirm the four irreversible actions.** Accept, start trip, POD and publish have no
  confirmation anywhere; there is not one `showDialog` in the 2,490-line driver flow. Both buttons
  stay neutral. `high` — [2.2](UX-REVIEW.md#22-there-is-not-one-confirmation-dialog-in-the-entire-driver-app)
- [ ] **Name the delivery on the POD screen.** It shows no customer, no address, no amount before the
  one irreversible action in the app. `high` — [J-4.1, J-4.2](UX-REVIEW.md#journeys)
- [ ] **Name the subject on the active-trip POD button.** On a multi-drop load it submits for
  whichever shipment came back first, releasing the wrong customer's payment. `high` — [J-3.3](UX-REVIEW.md#journeys)
- [ ] **Empty the publish form.** It ships pre-filled with a real bookable lane behind one unguarded
  button on a nav tab, and nothing can withdraw a published lane. `high` — [2.3](UX-REVIEW.md#23-the-publish-form-ships-pre-filled-with-a-real-bookable-lane), [J-9.3](UX-REVIEW.md#journeys)
- [ ] **Validate the payout account number, and confirm it twice.** It is optional in the request
  while the label says required, there is no re-entry check, and the form opens blank on update. A
  mistyped account is the one error nobody can reverse. `high` — [J-6.1, J-6.2](UX-REVIEW.md#journeys)
- [ ] **Say when the money actually arrives.** POD, earnings, payout setup and payout history all say
  "after review" and none gives a timeframe. One sentence, used verbatim on all four. `high` — [J-4.3, J-5.2](UX-REVIEW.md#journeys)
- [ ] **Group rupee amounts the Indian way.** A payout renders `₹1250000`. `medium` — [J-C4](UX-REVIEW.md#journeys)

## Failure states

- [ ] **Stop rendering ₹0 when the request failed.** Earnings and payout history both use
  `try`/`finally` with no `catch` and `?? 0`, so a failure reads as "you have earned nothing" and
  "you have never been paid". `high` — [2.4](UX-REVIEW.md#24-a-failed-request-tells-the-driver-they-have-earned-nothing), [J-6.3](UX-REVIEW.md#journeys)
- [ ] **Translate API errors into sentences a driver can act on.** Every error is currently a raw
  code; two of them tell the user to redeploy the API with CORS enabled. `high` — [2.10](UX-REVIEW.md#210-every-error-a-driver-sees-is-a-raw-api-code)
- [ ] **Give every fetch an error state and a retry.** The shipment detail spins forever on failure;
  the shipments list shows an error and "No shipments to deliver" together. `high` — [J-2.2, J-2.4](UX-REVIEW.md#journeys)
- [ ] **Reload after POD from the shipment detail.** The screen still says pending and still offers
  Confirm delivery; tapping again returns a raw error. `high` — [J-2.1](UX-REVIEW.md#journeys)
- [ ] **Make money results survive longer than four seconds.** Accept, start, POD and complete report
  only via snackbar, with no history screen to check against. `high` — [J-C2](UX-REVIEW.md#journeys)
- [ ] **Queue a POD submitted with no signal.** Nothing in the app survives a dropped connection.
  POD only — accepting stale work is worse than failing. `medium` — [J-C5](UX-REVIEW.md#journeys)

## Location and permissions

- [ ] **Make the tracking copy match the implementation.** Location is shared only while one screen is
  on top, yet the driver is told it is shared for the whole load and the customer is promised updates
  every 30 seconds. `high` — [2.9](UX-REVIEW.md#29-location-is-shared-only-while-one-screen-is-on-top)
- [ ] **Handle a denied location permission.** It is a bare `return`: no message, no state, and the
  screen goes on claiming GPS is being shared. `high` — [J-3.2](UX-REVIEW.md#journeys)
- [ ] **Decide on background location.** A foreground service is the real fix for the above and is an
  architecture decision, not a code change. Needs a call before anyone writes it. `high` — [2.9](UX-REVIEW.md#29-location-is-shared-only-while-one-screen-is-on-top)

## Forms

- [ ] **Replace the four free-text vehicle-class fields with the dropdown that already exists**
  elsewhere in the same file. Deletes three validation branches that only catch typed-enum typos.
  `medium` — [J-8.2](UX-REVIEW.md#journeys)
- [ ] **Replace the ISO timestamp fields with date pickers.** Publish asks a driver to type
  `2026-05-12T00:00:00+05:30` on a phone. `high` — [2.6](UX-REVIEW.md#26-publish-field-labels-are-raw-api-parameter-names)
- [ ] **Fix keyboard types, autofill and submit-disabling across every form.** There are zero
  `autofillHints`, zero `inputFormatters` and zero `TextFormField` validators in the repo. `medium` —
  [Forms and input](UX-REVIEW.md#forms-and-input)
- [ ] **Hide the OTP screen's Challenge id field and gate the debug code on `kDebugMode`.**
  `medium` — [J-O.1](UX-REVIEW.md#journeys)

## Accessibility and the visual system

- [x] **Add a secondary-text token that passes AA on the scaffold.** `muted #64748B` is 4.43:1 and
  fails; `mutedOnBackground #52607A` is 5.90:1, with a test computing the ratio. `high` —
  [2.8](UX-REVIEW.md#28-two-palette-tokens-fail-wcag-aa-where-they-are-used)
- [ ] **Add a `danger` token and replace the seven bare `Colors.red` uses.** Error text is currently
  3.42:1 — the text a driver most needs to read, at the lowest contrast in the app. `high` —
  [2.8](UX-REVIEW.md#28-two-palette-tokens-fail-wcag-aa-where-they-are-used)
- [ ] **Promote the de facto type and spacing scale into the theme.** The theme carries four colours
  and no type scale, so screens invent their own. `medium` — [The visual system](UX-REVIEW.md#the-visual-system)
- [ ] **Add semantics labels to icon-only buttons.** There is not one `Semantics` widget in the app.
  `medium` — [Accessibility](UX-REVIEW.md#accessibility)

## Navigation and landing

- [x] **Rebuild the landing around who the visitor is.** Four resolved states instead of five
  undifferentiated buttons; a fleet driver is no longer told to register a business they should not
  own. `high` — [2.5](UX-REVIEW.md#25-a-driver-joining-a-fleet-is-told-to-register-a-business-they-should-not-own)
- [ ] **Decide what `/driver` shows a signed-in driver.** It currently redirects to Loads, so the Home
  tab can never stay selected and hardware back lands on Loads. Needs a real signed-in home. `medium`
  — [Entry point and navigation](UX-REVIEW.md#entry-point-and-navigation)
- [ ] **Delete `DriverTrackScreen`.** Unreachable: nav index 3 goes to `/driver/publish` and nothing
  pushes `/driver/track`. `medium` — [2.7](UX-REVIEW.md#27-a-whole-screen-is-unreachable)
- [ ] **Move earnings out from behind Profile.** It is two taps deep while Publish gets a nav tab;
  for an owner-operator that ranking is backwards. `medium` — [J-5.4](UX-REVIEW.md#journeys)
- [ ] **Gate Start on an accepted shipment, not on reserved kilos.** The list offers an action the
  trip screen refuses, and the driver gets a raw error. `medium` — [J-1.4](UX-REVIEW.md#journeys)

## Copy

- [ ] **Settle on one word for the central object.** The app calls it anchor trip, trip, load and lane.
  `medium` — [Copy and microcopy](UX-REVIEW.md#copy-and-microcopy)
- [ ] **Remove developer strings from the UI.** One screen tells drivers to "merge driver-onboarding
  PR". `medium` — [J-3.4](UX-REVIEW.md#journeys)
- [ ] **Label raw enums.** KYC status and trip status render as `SUBMITTED` and `IN_PROGRESS`, while
  four label helpers already exist for other enums. `medium` — [J-5.3](UX-REVIEW.md#journeys)
- [ ] **Use "Confirm delivery" everywhere.** The same action is labelled two different ways, one of
  them an acronym. `medium` — [J-3.5](UX-REVIEW.md#journeys)

## Build and tooling

- [ ] **Pin the JDK, or raise Gradle.** A fresh clone does not build on a current Android Studio:
  it bundles JDK 25 and the repo pins Gradle 8.7, which reads up to Java 22, so `assembleDebug`
  dies with `Unsupported class file major version 69` before any Dart is compiled. Workaround is
  `JAVA_HOME` pointing at JDK 17 — `flutter config --jdk-dir` does not take. `medium` —
  [5.1](UX-REVIEW.md#tooling)
- [ ] **Run the Flutter app in CI.** None of the four workflows runs `flutter analyze`, `flutter
  test` or an Android build, so a green PR says nothing about this app. `medium` —
  [5.1](UX-REVIEW.md#tooling)

## Structure

- [ ] **Split `driver_flow.dart`.** 2,490 lines, 17 screens plus the shell plus the route table. Its
  own change, not bundled with feature work. `medium` — specified as R4 in `IMPROVEMENTS.md` on the
  docs branch
- [ ] **Make `DriverWelcomeScreen` testable.** `DriverSession.refresh()` in `initState` needs the
  network and a secure-storage channel, so the three resolved states cannot be covered. The customer
  session already has the seams to copy. `medium` — [Entry point and navigation](UX-REVIEW.md#entry-point-and-navigation)

---

## Done

- [x] Landing rebuilt around visitor intent, with an offline state and a rejected-token state
- [x] `mutedOnBackground` token added, with a contrast test that computes the ratio
- [x] Stale post-OTP advice removed — it named a deleted button and pushed a driver toward the wrong flow
- [x] Landing no longer claims an upload the app cannot do
- [x] Sign-out clears `lastRegisteredOrgId` and invalidates an in-flight session refresh
- [x] Shell rebuilds on sign-out, so the five tabs no longer outlive the session
- [x] `widget_test.dart` replaced — it had asserted the legacy pilot-lab tabs and failed silently

---

## Not in this doc

One API finding outranks everything above and is deliberately not tracked here, because this page is
app-only: **an invited fleet driver can redirect the whole carrier's weekly payouts to their own bank
account.** `pilotSubmitPayoutSetup` guards with `assertPilotDriverCanManageOrg`, whose allowlist
includes `DRIVER`; the stricter `assertCarrierCanInviteStaff` three lines below excludes it.
Production runs `PAYOUTS_MODE=RAZORPAYX`. Wherever API work is tracked, it belongs at the top.
