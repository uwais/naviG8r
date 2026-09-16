# naviG8r driver app — UX review

A review of the Flutter app in `apps/driver_pilot/`, against the tree at `f96ccf9`.

**On the length of this file.** It is long because it is a findings backlog, not a document to read
end to end. Section 2 is the part that should change what anyone does this week; everything after it
is reference, grouped so you can read one lens and ignore the rest. Splitting it would scatter one
argument and break the cross-references between, say, a contrast finding and the token that causes it.

## 1. How this was produced, and what it does not cover

Ten review lenses read the Dart source in parallel. Every finding was then put to two independent
adversarial verifiers whose default position was that it was wrong — one checking whether the cited
line says what the finding claims, one checking whether the proposed fix would actually leave the app
correct. 102 findings survived both. The fix was rewritten by a verifier in 99 of those 102, which is
worth knowing: the first proposed fix was usually not the right one.

**Nothing here was observed running, and the sequence matters.** The ten lenses read the source
while no Flutter SDK was installed on the machine, which is why findings below say so in their own
words. Flutter 3.22.3 was installed afterwards, and `flutter analyze` and `flutter test` were then
run to produce the baseline in the table below. So: the baseline figures are measured, and every
finding is not. There is still no emulator and no device — no screenshot was taken and no screen was
rendered at any point. Every statement about layout, spacing,
rendered colour, scroll behaviour, keyboard overlap or what a driver actually sees is an inference
from source. Findings that would need a device to confirm are marked.

Two consequences worth stating plainly:

- **Contrast ratios are computed, not measured.** They come from the hex values in `driver_theme.dart`
  and the WCAG relative-luminance formula. Real legibility on a mid-range Android panel in Indian
  midday sun is a different question and needs a device.
- **Touch targets are not reported as failures.** Flutter pads button tap targets to 48dp by default,
  so a visual height below that is not automatically a violation. Confirming real geometry needs a
  device.

Also not covered: localisation (there is no i18n layer; every string is a hard-coded English literal,
which is a product decision rather than a defect), screen-reader behaviour and focus order, large-font
layout, performance, and the legacy `/pilot-lab` developer surface, which the product owner has ruled
out of scope for now.

### What was verified by hand

The findings in section 2 were each re-checked directly against the source rather than taken on an
agent's word. The commands and the lines are cited inline. Everything in sections 3 onward carries the
adversarial verification described above but was not independently re-read.

Baseline measured on this branch before any change, on Flutter 3.22.3 / Dart 3.4.4:

| Check | Result |
|---|---|
| `flutter analyze` | 28 issues, 0 errors — all pre-existing |
| `flutter test` | 3 tests, 2 pass, **1 fail** — pre-existing |

The failing test is `test/widget_test.dart`. It asserts the navigation labels
`Home / Register / Login / Trips / Publish`, which belong to the legacy `/pilot-lab` surface. The app
stopped launching there when `/driver` became the Android entry point, so the only test covering the
landing screen has been testing the wrong screen and failing silently — invisible because no CI
workflow runs Flutter tests.

## 2. The things that matter most

Ranked by what they cost the person using the app. Each was verified by opening the file.

### 2.1 A carrier accepts a binding load without ever seeing what it pays

`driver_flow.dart:764-772`. The shipment card shows customer, weight and route. It does not show
money. The amount exists on the same object — the detail screen reads `netToCarrierPaise` at `:850` —
but the driver cannot reach that screen before accepting, because the tap is disabled for exactly the
rows that carry an Accept button:

```dart
onTap: st == "PENDING_CARRIER_ACCEPT" ? null : () => context.push("/driver/shipment/$id"),
```

So the one commercially binding decision in the app is made on a screen that withholds the price and
blocks the route to it. Accept is one-way: there is no cancel endpoint reachable from the app.

**Fix.** Put `formatInrFromPaise(netToCarrierPaise)` in the row as the most prominent line, and make
the row tappable in every status.

### 2.2 There is not one confirmation dialog in the entire driver app

Verified with `grep -c "showDialog\|AlertDialog" driver_flow.dart` → **0**, across 2,305 lines. The
same grep against `customer_flow.dart` returns 2, so the pattern exists in this codebase and simply
was not applied to the driver side.

Nothing is confirmed: not accepting a load, not starting a trip, not submitting proof of delivery, not
publishing a lane, not signing out. Three of those are irreversible and two move money.

**Fix.** Add confirmation to the four irreversible actions only. Both buttons stay neutral per the
house rules — `Not now` and `Yes, accept`, never a confirmshaming decline.

### 2.3 The publish form ships pre-filled with a real, bookable lane

`driver_flow.dart:2110-2117`:

```dart
final _origin = TextEditingController(text: "Gurugram, Haryana");
final _dest = TextEditingController(text: "Jaipur, Rajasthan");
LatLng _originPos = const LatLng(28.4595, 77.0266);
LatLng _destPos = const LatLng(26.9124, 75.7873);
final _vehClass = TextEditingController(text: "MEDIUM");
final _cap = TextEditingController(text: "1000");
```

The pickup window auto-fills too. Publish is a bottom-nav destination, one tap from anywhere, and the
primary button has no confirmation. A carrier who opens the tab by mistake and taps it publishes a
Gurugram–Jaipur lane with 1000 kg of capacity that customers can immediately book against — and there
is no unpublish anywhere in the app. These are developer test values that shipped as defaults.

**Fix.** Start the fields empty with real hints, disable the button until origin, destination and
capacity are filled, and confirm the lane by name before publishing.

### 2.4 A failed request tells the driver they have earned nothing

`driver_flow.dart:1888-1898` is `try`/`finally` with no `catch`, and `:1902-1904` defaults to zero:

```dart
final pending = s?["pendingAccruedPaise"] as num? ?? 0;
final paid = s?["paidPaise"] as num? ?? 0;
```

On any failure the screen reports `₹0` pending and `₹0` paid, with no error, no retry and no
pull-to-refresh. The same shape is in payout history at `:2062-2077`, where a failed fetch renders
"No payout batches yet." On the connectivity this product assumes, that is not an edge case. Telling a
carrier they have earned nothing when the request merely failed is the worst available failure mode on
a money screen.

**Fix.** Catch into an error state, render `—` rather than `₹0`, and offer a retry.

### 2.5 A driver joining a fleet is told to register a business they should not own

`driver_flow.dart:326-334`. After a successful OTP verify, if the owner has not yet added them:

```
SnackBar: "No carrier org for this phone. Use Register as new carrier on the welcome screen."
context.go("/driver");
```

They are signed in correctly and sent backwards into the wrong flow. Following that advice creates a
carrier organization they should not have. `DriverSession.refresh()` also collapses every error into
`false` with a bare `catch (_)` at `driver_session.dart:85`, so a patchy-signal failure produces the
same misleading message.

**Fix.** This is the state 2 screen in the landing redesign below.

### 2.6 Publish field labels are raw API parameter names

`driver_flow.dart:2226-2229`: `windowStart (ISO)`, `windowEnd (ISO)`,
`vehicleClass (SMALL|MEDIUM|LARGE)`, `capacityKg`. The first two are free-text fields expecting
`2026-05-12T00:00:00+05:30`, typed on a phone. For a driver whose first language is not English this
screen is not usable without a support call.

**Fix.** Date pickers for the window, a dropdown for truck size, and plain labels.

### 2.7 A whole screen is unreachable

`DriverTrackScreen` is registered at `driver_flow.dart:2286`, but nav index 3 goes to
`/driver/publish` (`:72-78`) and nothing anywhere pushes `/driver/track`. Verified with
`grep -rn '"/driver/track' --include="*.dart"`, which returns only two path-matching branches and no
navigation call. It duplicates the loads list with a narrower filter and will drift every time that
list changes.

**Fix.** Delete it; the in-progress filter chip on the loads screen already does the job.

### 2.8 Two palette tokens fail WCAG AA where they are used

Computed from `driver_theme.dart:5-8` with the WCAG relative-luminance formula:

| Pair | Ratio | AA normal text |
|---|---|---|
| `muted #64748B` on scaffold `#F4F7FA` | 4.43 | fails |
| `muted #64748B` on white card | 4.76 | passes |
| `Colors.red #F44336` on scaffold | 3.42 | fails |
| `navy #122C53` on scaffold | 12.93 | passes |

Because the theme carries only four tokens, those two failures propagate to essentially every
secondary line of text and every error message in the app. Error text is the worse case: it is the
text a driver most needs to read, in the worst lighting, at the lowest contrast in the app.

**Fix.** Two tokens, which fixes most of it at once: a darker `mutedOnBackground` for text outside
white cards, and a `danger` token replacing the seven bare `Colors.red` uses.

### 2.9 Location is shared only while one screen is on top

The position stream is owned by `_DriverActiveTripScreenState` and cancelled in `dispose`
(`driver_flow.dart:1638-1640`). `pubspec.yaml` declares `geolocator` with no background-execution
package, and the code does not use `AndroidSettings.foregroundNotificationConfig`. Meanwhile `:1776`
tells the driver "Live GPS is shared with customers while the load is in progress", and the customer
is told "Live tracking — updates every ~30 seconds."

Both statements stop being true the moment the driver locks the phone. Separately, `:936` announces
"Load started — live tracking enabled" from the loads list, where no location code runs at all.

**Fix, in two parts.** Today, change the copy so it matches the implementation: "Your location is
shared while this screen is open." The engineering fix — a foreground service — is an architecture
decision that needs your sign-off before anyone writes it, and is listed in section 9 rather than
assumed here.

### 2.10 Every error a driver sees is a raw API code

`pilot_api.dart:74` returns `"HTTP ${status}: ${body}"`. So confirming a delivery twice produces
roughly `HTTP 400: {error: shipment_not_deliverable, status: PENDING_RELEASE}`. Two of the messages
are worse: `pilot_api.dart:65-67` instructs the user to "redeploy the API with CORS enabled".

**Fix.** A `driverFacingError` mapping the handful of codes these screens can actually hit to plain
sentences, keeping the raw formatter for the developer lab only.

---

The rest of this document is the full finding set, grouped by lens. Within each lens findings are
ordered high severity first.

## 3. Full findings by lens

### Entry point and navigation

12 findings, 6 high.


**HIGH — No session restore: the returning driver, the most frequent actor, must tap a third-ranked button on every launch**  
`apps/driver_pilot/lib/main.dart:77` · navigation  

*What goes wrong:* An owner-driver who signed in last week and has a valid stored token relaunches the app at a loading dock and is shown a sign-in screen. The button that actually works for him, "Continue as signed-in driver", is the third of five, styled as a secondary outline, and worded like an edge case. He is the app's highest-frequency user and gets the app's third-ranked affordance, every single time, one-handed, in sunlight.

*Fix:* The proposed fix has three defects; two would break the app.

1. WRONG DELETION RANGE. The fix says to delete "the 'Continue as signed-in driver' OutlinedButton entirely (driver_flow.dart:177-195)". Lines 177-180 are a different button — `OutlinedButton(onPressed: () => context.go("/driver/onboarding/register"), child: const Text("Register as new carrier"))`. Deleting 177-195 removes carrier registration from the landing screen. The correct range is driver_flow.dart:181-195 (the `const SizedBox(height: 8)` at 181 plus the OutlinedButton at 182-195).

2. THE BLANKET ROUTER REDIRECT MAKES THE HOME TAB UNREACHABLE. A top-level `redirect` returning "/driver/loads" whenever `state.uri.path == "/driver" && DriverSession.hasCarrierOrg` fires on every navigation to "/driver", not only at launch. driver_flow.dart:79-82 shows the bottom nav's Home destination (index 0) navigates to exactly "/driver": `case 0: default: return "/driver";`. With that redirect in place, a signed-in driver tapping Home bounces to Loads and `_indexForPath` (driver_flow.dart:34-66) then returns 2, so the Home tab can never be selected. The back-stack fallback at driver_flow.dart:96-98 (`context.go("/driver")`) breaks the same way.

3. A BLOCKING STARTUP REFRESH CAN STALL FOR 45 SECONDS. `DriverSession.refresh()` goes over the network and `pilot_api.dart:31` sets `connectTimeout: const Duration(seconds: 45)`. On the patchy connectivity this product assumes, "render a splash route until it settles" means up to a 45-second splash before the driver sees anything.

CORRECTED FIX — make the landing screen session-aware instead of adding a router redirect:
- Convert `DriverWelcomeScreen` (driver_flow.dart:151) to a StatefulWidget. In `initState`, call `DriverSession.refresh().timeout(const Duration(seconds: 8), onTimeout: () => false)` and hold the result in `_sessionChecked` / `_signedIn` state.
- While the check is in flight, keep the existing Padding/Column and render a compact inline row (a 16px `CircularProgressIndicator` plus `Text("Checking your sign-in")` in `DriverTheme.muted`) where the button stack sits, rather than a full-screen splash — the bottom nav stays on screen and the screen never goes blank.
- When the check returns `true` and `DriverSession.hasCarrierOrg`, build a signed-in body in the same screen: the heading becomes `DriverSession.carrierOrgName ?? "Driver & carrier"`, and the button stack becomes `FilledButton(onPressed: () => context.go("/driver/loads"), child: const Text("Open my loads"))` plus `OutlinedButton(onPressed: () => context.go("/driver/shipments"), child: const Text("My shipments"))`, keeping the `TextButton` for "Developer lab" last.
- When the check returns `false` or `hasCarrierOrg` is false, build the current signed-out stack unchanged except that lines 181-195 are deleted — in the signed-in state that button is what the screen now is, and in the signed-out state it only ever produced the snackbar at driver_flow.dart:189-191.
- Do NOT add a top-level `redirect` and do NOT add `Listenable.merge([CustomerSession.listenable, DriverSession.listenable])`. The finding is right that `refreshListenable: CustomerSession.listenable` (main.dart:78) currently drives no routing decision; merging a second dead listenable into it duplicates that dead wiring instead of removing it. A `DriverSession` notifier is only worth adding if a session-dependent redirect actually exists, and this fix deliberately avoids one.

UNVERIFIABLE FROM SOURCE: the finding's scenario says the driver "signed in last week and has a valid stored token". Token lifetime is set server-side and is not visible in this Dart source, so whether a week-old token still authenticates cannot be confirmed here. The fix above degrades correctly either way — an expired token makes `refresh()` return false and the signed-out stack renders.


**HIGH — The Home tab and every back gesture land a signed-in driver on the sign-in screen**  
`apps/driver_pilot/lib/driver_flow.dart:2271` · navigation  

*What goes wrong:* A driver mid-shift on the Loads tab presses the Android back button and is shown "Sign in with phone" and "Register as new carrier". Nothing tells him he is still signed in. The reasonable reading is that the app logged him out, so he signs in again and burns an OTP; the less reasonable one is that he taps "Register as new carrier" and tries to create a second carrier org. The app has five bottom-nav destinations and not one of them is a home screen for a signed-in carrier.

*Fix:* The split is right, but the redirect predicate as written will send signed-in drivers to the welcome screen on every cold start, which reproduces the bug it is meant to fix.

Why: go_router redirects are synchronous. `DriverSession.hasCarrierOrg` (driver_session.dart:16 `static bool get hasCarrierOrg => carrierOrgId != null && carrierOrgId!.isNotEmpty;`) reads in-memory statics that are only populated by the awaited `DriverSession.refresh()` (driver_session.dart:25). The auth token is persisted — pilot_api.dart:48 `Future<void> setToken(String token) => _storage.write(key: "access_token", value: token);` — but the session fields are not. So on app launch the token is valid, `carrierOrgId` is null, and the redirect resolves to "/driver/welcome". Worse, `DriverSession` exposes no Listenable and main.dart:78 sets `refreshListenable: CustomerSession.listenable`, so the redirect will never re-evaluate when `refresh()` later completes.

Corrected fix, same shape plus a bootstrap:
1. Keep the route split: DriverHomeScreen at "/driver/home" inside the ShellRoute; move DriverWelcomeScreen out of the shell to "/driver/welcome" beside the onboarding routes at driver_flow.dart:2300-2303; change `_pathForIndex` case 0 (driver_flow.dart:81) and the PopScope fallback (driver_flow.dart:97) to "/driver/home". Also update `_indexForPath` (driver_flow.dart:55-67) so "/driver/home" maps to 0, otherwise the Home tab never shows as selected.
2. Make session state observable and resolved before the redirect can answer: add to DriverSession a `static final ValueNotifier<int> listenable` bumped at the end of `refresh()` and in `clear()`, plus a `static bool sessionResolved` set true once the first `refresh()` returns (success or failure). In main.dart:78 pass a `Listenable.merge([CustomerSession.listenable, DriverSession.listenable])`.
3. Make "/driver" a redirect-only GoRoute returning: "/driver/welcome" if there is no stored token; "/driver/loading" (or keep the splash on "/driver" itself with a CircularProgressIndicator) while `!DriverSession.sessionResolved`, kicking off `DriverSession.refresh()` once; "/driver/home" when `hasCarrierOrg`; "/driver/welcome" otherwise. Without step 2 this cannot be written correctly.
4. On the interim four-tab variant: pointing index 0 and the PopScope fallback at "/driver/loads" is fine, but note that main.dart:77 `initialLocation: kIsWeb ? "/customer" : "/driver"` and the sign-out at driver_flow.dart:1411 both still target "/driver", so the welcome screen must remain reachable at that path — do not repurpose "/driver" to Loads outright, or a signed-out driver lands on a Loads screen that will 401.


**HIGH — "Join a carrier fleet" registers the driver on the customer endpoint and loops him back to a message telling him to register as a carrier**  
`apps/driver_pilot/lib/driver_flow.dart:501` · navigation  

*What goes wrong:* A hired driver taps the one button on the landing screen that describes his situation, fills in his name and phone, is sent straight to sign-in, requests an OTP, verifies it, and is bounced back to the landing screen with a message telling him to register as a new carrier — which would create a fake one-truck org under his own name and detach him from his employer's fleet. He has no way to tell that he did the right thing and simply has to wait. Nothing in the app shows a pending state, and the route he is pushed toward is actively wrong for him.

*Fix:* Parts (1) and (3) are sound as written. Part (2) is unimplementable as specified and needs replacing.

Part (2) as proposed says: "keep the 'Register as new carrier' wording only when the phone is unknown to the server." That branch is unreachable at driver_flow.dart:326-333. The code there runs only after `/v1/auth/otp/verify` returned an accessToken, and auth.ts:126 throws `user_not_found` for an unknown phone, so an unknown phone never gets past the `try` into the else-branch at all. Do not add a condition that can never be true.

Corrected part (2): replace the message at driver_flow.dart:329-333 unconditionally. Replace

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text("No carrier org for this phone. Use Register as new carrier on the welcome screen."),
    ),
  );
  context.go("/driver");

with a route to the awaiting-invite screen from part (1), carrying the phone, and no snackbar — the destination screen states the situation in full rather than a message that disappears in four seconds on a screen the driver has already left:

  context.go("/driver/onboarding/awaiting-invite?phone=$_phone");

The awaiting-invite screen from part (1) then carries the whole explanation: heading "Your carrier has not added you yet", body "Ask your carrier to add {phone} to their fleet. You can sign in again once they have.", a FilledButton "Check again" calling `DriverSession.refresh()` and going to "/driver/loads" only when `DriverSession.hasCarrierOrg`, and a TextButton "Back" to "/driver". Reuse that one screen from both entry points (join success at :508 and OTP rejection at :329) so there is one place stating the pending state.

Also add, in part (1), that the phone must survive the hop: the join screen's `_submit` at :500-508 already has `phone` in hand, so route `context.go("/driver/onboarding/awaiting-invite?phone=$phone")` and read it with `GoRouterState.of(context).uri.queryParameters["phone"]`, matching the pattern already used at driver_flow.dart:460-464. Register the route next to the other onboarding children near driver_flow.dart:2288.

One addition outside the original three: the same misdirection sits at driver_flow.dart:186-190, where "Continue as signed-in driver" falls through to `SnackBar(content: Text("Sign in first, or complete carrier registration."))` — which points a hired driver at carrier registration for the same reason. Point that fallback at the awaiting-invite screen too when `ok` is true but `hasCarrierOrg` is false, and keep the "Sign in first" wording only for `ok == false`. That split IS reachable, because `DriverSession.refresh()` returns false on a failed `/v1/pilot/me` (driver_session.dart catch), unlike the OTP path.

Finally, retitle the finding. "registers the driver on the customer endpoint" is not the defect. Use: "Join a carrier fleet dead-ends the driver at sign-in, and the rejection tells him to register as a new carrier, which always fails."


**HIGH — The OTP screen has no back affordance, so a mistyped phone number is a dead end**  
`apps/driver_pilot/lib/driver_flow.dart:353` · navigation  

*What goes wrong:* A driver typos one digit, the code goes to a stranger's phone, and the screen offers him only "Verify" (which will fail) and "Resend code" (which resends to the same wrong number). The Android system back button has nothing to pop, so it drops him out of the app; he has to relaunch and start over. This is the narrowest point in the whole sign-in path and it is the one screen with no exit.

*Fix:* The fix is right in direction but wrong in two specifics. (1) The hardcoded back target is wrong. The OTP route has TWO entry points — driver_flow.dart:234 from DriverPhoneScreen and driver_flow.dart:437 from DriverRegisterScreen ("Carrier created — verify your phone to continue.", line 435). Sending back to "/driver/onboarding/phone" unconditionally drops a carrier who just created an org onto the sign-in screen, which is the wrong place and hides the org he just made. Use "/driver" instead, matching the three siblings at 264, 470 and 537, so there is one consistent escape target across the whole onboarding set. (2) "Nest the four onboarding routes under a shared parent so push gives them a real stack" conflates two things — nesting does not create a stack, the navigation verb does. The real fix is to change driver_flow.dart:234 and driver_flow.dart:437 from `context.go(...)` to `context.push("/driver/onboarding/otp?phone=$phone")`. `push` on a flat top-level route works in go_router 14.6.2 and is already used in this file at line 669 (`context.push("/driver/onboarding/join")`), so it is an established pattern here. That single change gives the OTP page a real stack entry, so `automaticallyImplyLeading` renders the back arrow with no AppBar edit at all, the system back button pops correctly, and the phone screen stays alive underneath with the typed digits intact — which is better than a `go` back, since the driver re-edits one digit instead of retyping ten. The successful-verify path at 327 still calls `context.go("/driver/loads")`, which replaces the stack, so the pushed onboarding pages do not leak into the authenticated stack. Keep the "Change number" TextButton next to "Resend code" at line 372, but have it call `context.pop()` rather than a hardcoded route, so it is correct from both entry points; copy it "Change number", not "Wrong number?", to stay neutral. Drop the PopScope wrapper entirely — with `push` there is a page to pop, so PopScope(canPop: false) would only intercept a back that now works correctly. Keep PopScope only if the team refuses the `go`-to-`push` change, and note that DriverShell's `onPopInvoked` (line 93) is the deprecated callback in current Flutter; a new call site should use `onPopInvokedWithResult`.

*Needs a device to confirm.*


**HIGH — Sign-in sends two OTP messages per attempt and discards the first challenge**  
`apps/driver_pilot/lib/driver_flow.dart:293` · error-state  

*What goes wrong:* Every driver sign-in costs two SMS instead of one, and the driver receives two different codes seconds apart on a screen that says "Code sent to …" once. If he reads the first message he types a code belonging to a discarded challenge and verification fails with no explanation. On a rate-limited OTP endpoint the doubled traffic is also the fastest route to locking a legitimate driver out of his own app.

*Fix:* The proposed fix is wrong and would break a second sign-in path. Do not delete `_resend()` at driver_flow.dart:293.

Reason: DriverOtpScreen is reached from TWO places. The phone screen (line 234) arrives with a challenge already started. The carrier register screen arrives at line 437 `context.go("/driver/onboarding/otp?phone=$phone");` after `POST /v1/pilot/driver/register`, and that endpoint (httpServer.ts:540-552, calling registerSoloOwnerOperatorDriver) returns no challengeId and starts no OTP challenge. On that path the `_resend()` at 293 is the ONLY thing that ever creates a challenge. Delete it and a newly registered carrier lands on "Verify code" with an empty `_challengeId` and no code, and verify fails with `otp_challenge_not_found` (auth.ts:130). That is a worse bug than the one being fixed, and it lands on the first-run path.

Corrected fix — make the OTP screen start a challenge only when it was not handed one:
1. In `_send()` (driver_flow.dart:223-241) capture the response instead of discarding it: `final r = await api.post<Map<String, dynamic>>("/v1/auth/otp/start", data: {"phone": phone});` then `final challengeId = r.data?["challengeId"] as String? ?? "";` and navigate with it: `context.go("/driver/onboarding/otp?phone=$phone&challengeId=$challengeId");`. Carry `debugCode` the same way if the pilot still relies on the auto-filled code (`_code.text = dc` at line 306), otherwise the debug convenience is lost on this path.
2. In `didChangeDependencies` (288-295) read both parameters and make the start conditional:
   final incomingChallengeId = GoRouterState.of(context).uri.queryParameters["challengeId"] ?? "";
   if (p.isNotEmpty && p != _phone) { _phone = p; if (incomingChallengeId.isEmpty) { _resend(); } else { _challengeId.text = incomingChallengeId; } }
   The register path sends no challengeId, so it still starts one; the phone path reuses the challenge already created. One challenge per sign-in on both routes.
3. Keep `_resend()` bound to the "Resend code" TextButton at line 372 as it already is. The 30-second cooldown suggested in the finding is a reasonable addition but is a separate change, not part of this fix, and it is not load-bearing while the endpoint has no rate limit.
4. While in this file: the "Challenge id" TextField at driver_flow.dart:363 `TextField(controller: _challengeId, decoration: const InputDecoration(labelText: "Challenge id")),` exposes an internal token as an editable field to a truck driver. Once the id is carried in the route it should become non-visible state, not a TextField. File that separately rather than folding it into this fix.

Unchecked: none of this was run. Flutter is not installed, so the claim that the register path currently breaks under the proposed fix is read from the source and the backend handler, not observed.


**HIGH — A signed-out user sees all five authenticated tabs, and tapping one shows a raw HTTP error instead of a sign-in prompt**  
`apps/driver_pilot/lib/driver_flow.dart:2262` · empty-state  

*What goes wrong:* A first-time user opens the app and the bottom bar invites him into four sections he cannot use. Tapping Loads shows red text reading roughly "HTTP 401: {error: unauthorized}" — which tells a truck driver that the app is broken, not that he needs to sign in. Tapping Profile shows a card reading "Carrier" and "— · —", which reads like a bug or like lost data. The sign-in screen he needed is one tab away and he has no reason to believe that.

*Fix:* The first half of the proposed fix is broken as written. `showBottomNav: DriverSession.hasCarrierOrg` in the ShellRoute builder would hide the bottom nav from a returning, correctly signed-in driver, for two reasons I confirmed:

1. The session is empty at cold start. main.dart:67-71 is the whole of `main()` — `WidgetsFlutterBinding.ensureInitialized(); api = Api(resolveApiBaseUrl()); runApp(const DriverPilotApp());`. Nothing calls `DriverSession.refresh()` at startup; `grep -n "DriverSession.refresh"` shows every call is inside a screen's initState or a button handler. DriverSession's fields are plain statics (driver_session.dart:5-14) and `hasCarrierOrg` (:16) reads `carrierOrgId != null`, so on launch it is false regardless of the token sitting in secure storage (pilot_api.dart:36-40 reads "access_token" per request). A driver who signed in last week opens the app and gets no nav at all.

2. The shell would not update when the session later fills in. main.dart:79 is `refreshListenable: CustomerSession.listenable,` — CustomerSession only. DriverSession has no notifier (compare customer_session.dart:8 `static final Listenable listenable = ValueNotifier<int>(0);`). The ShellRoute builder reruns on route change, so the nav's presence would be stale until the next navigation.

Corrected, in the order I would ship it:

a) Do the screen-level part first, unchanged in spirit and safe on its own. In DriverLoadsScreen and DriverShipmentsScreen, replace the raw branch at driver_flow.dart:1069-1071 and :753-755 with a signed-out branch keyed on the status code the load actually returned — store `_unauthorized = true` when the DioException status is 401 rather than reading DriverSession — and render a centred column: `Text("Sign in to see your loads")` plus `FilledButton(onPressed: () => context.go("/driver/onboarding/phone"), child: const Text("Sign in with phone"))`. This needs no session plumbing because the screen already rebuilds after its own load, and it is correct on cold start where `hasCarrierOrg` is not. Do the same in DriverProfileScreen ahead of the card at :1358-1363, so "Carrier / — · —" is never rendered.

b) Fix formatApiError (pilot_api.dart:58-77) as proposed, and widen it: 401 becomes "Please sign in again", connection errors become "No connection. Pull down to retry." The two existing branches at :65-67 and :70-71 must go from the driver build too — a truck driver should never be told to redeploy the API with CORS enabled or to pass a --dart-define flag. Keep the raw string behind a check for the developer lab route only.

c) Gating the nav itself is a separate, larger change and per the house rule on architecture it should be raised before it is written. Doing it correctly means: add `static final Listenable listenable = ValueNotifier<int>(0);` to DriverSession mirroring customer_session.dart:8 and bump it at the end of refresh() and clear(); change main.dart:79 to `refreshListenable: Listenable.merge([CustomerSession.listenable, DriverSession.listenable]),`; and hydrate the session once at startup before the first driver route builds. Only then does `showBottomNav: DriverSession.hasCarrierOrg` at the builder behave. Until that lands, leave the parameter alone — or delete it as dead code — rather than wiring it to a value that is false for everyone at launch.

*Needs a device to confirm.*


**MEDIUM — The developer lab is a peer action on the driver landing screen**  
`apps/driver_pilot/lib/driver_flow.dart:199` · navigation  

*What goes wrong:* A pilot driver exploring a new app taps the last item on the list and lands in a tool built for engineers: raw JSON output, buttons labelled with HTTP verbs, someone else's phone number pre-filled in a registration form, and a logout icon in the app bar that silently clears his session. He can get back (main.dart:255-257 offers "Back to driver app (welcome)"), but he may well have registered a junk org or signed himself out first.

*Fix:* The fix is sound and the insertion point is right — driver_flow.dart:1404 is the closing `),` of the `if (DriverSession.canInviteDrivers)` Fleet ListTile, so inserting after it places the new entry immediately above the "Sign out" ListTile at 1405. Three corrections:

1. Drop the `import "package:flutter/foundation.dart";` step. driver_flow.dart:3 already imports `package:flutter/material.dart`, which re-exports foundation, so `kDebugMode` is in scope. Adding the import is dead weight.

2. Do not use `kDebugMode` as the primary gate. Pilot builds handed to real drivers are release builds, so `kDebugMode` would remove the lab from every build anyone is actually testing on — the lab would be unreachable from the UI entirely and only addressable by typing /pilot-lab, which is not practical on Android. Gate on `const bool.fromEnvironment("PILOT_LAB")` as the single condition (`--dart-define=PILOT_LAB=true` for tester builds), not as a fallback. That makes it a build flag rather than a debug-only accident.

3. Profile is reachable pre-sign-in, so moving the entry there does not lock testers out: `/driver/profile` has no redirect guard (driver_flow.dart:2287) and the Profile destination is index 4 of the `NavigationBar` in `DriverShell` (driver_flow.dart:139-140), which renders on the welcome route too. Worth stating in the fix so nobody rejects it on that ground.

Also fix the copy in the finding's own rationale rather than the code: the lab logout is not silent, it shows `SnackBar(content: Text("Logged out (token cleared)."))` at main.dart:212-213. The sharper problem is that main.dart:211 clears the shared token without calling `DriverSession.clear()` (compare driver_flow.dart:1409-1411, which clears both), leaving the driver app holding session state for a token that no longer exists. If the lab stays, add `DriverSession.clear();` after main.dart:211 so the two sign-out paths leave the same state.


**MEDIUM — Outlined and text buttons on the landing are visually indistinguishable: the border token is 1.15:1 against the background**  
`apps/driver_pilot/lib/driver_theme.dart:31` · contrast  

*What goes wrong:* Items two through five all render as navy text on the same pale ground, with the outline that is supposed to distinguish two of them sitting a hair above invisible. On a mid-range screen at full daylight brightness, the landing reads as one dark button followed by four lines of blue text, so a first-time carrier owner cannot see that "Register as new carrier" is a stronger, more considered action than "Developer lab". The one tier the eye does catch, the filled button, is the wrong one for both new actors.

*Fix:* The token change is sound and correctly scoped: `border` is referenced at driver_theme.dart:31 (outlined buttons), :41 (input enabledBorder), :49 (card side), :53 (chip side) and driver_flow.dart:1009. Editing only line 31 to `side: const BorderSide(color: navy, width: 1.5)` changes outlined buttons alone and leaves cards, chips and inputs on the pale hairline, which is the intended contained blast radius.

The restructure half of the fix needs correcting, because it silently drops two of the five actions.

1. It enumerates three tiers — FilledButton sign-in, one OutlinedButton "Register as new carrier", TextButton fleet-joiner — with no home for `driver_flow.dart:182` "Continue as signed-in driver" (a real action: it calls `DriverSession.refresh()` and routes to /driver/loads or shows a snackbar) or `driver_flow.dart:199` "Developer lab". The task brief states the developer lab stays. As written the fix reads as deleting both. Keep both: leave "Continue as signed-in driver" as the second OutlinedButton (it is a returning-user path, same weight as register), and demote "Developer lab" below a `Divider` with `TextButton` styled `foregroundColor: DriverTheme.muted` so it reads as a maintenance affordance rather than a peer of the four onboarding paths.

2. Also add a `textButtonTheme` while in this file. There is none — grep returns no `textButtonTheme` in driver_theme.dart — so `TextButton` at :197 and :199 falls through to `colorScheme.primary`, which `ColorScheme.fromSeed(seedColor: navy, ...)` (driver_theme.dart:13) derives as a tonal-palette blue, not `navy` #122C53. The finding's "navy text" is therefore slightly off for items four and five; they are a different, lighter blue. This does not weaken the finding — it strengthens it, because the tier separation currently comes from an unspecified generated colour rather than a deliberate token. Pin it: `textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: navy))`, so the three tiers differ by weight (filled / outlined / bare) rather than by an accidental hue.

3. The supporting-line suggestion is good but should be implemented as a `Column` inside the button child with `crossAxisAlignment: CrossAxisAlignment.start`, not as free text under the button, otherwise the second line is outside the tap target — which matters for the one-handed-in-a-cab context. It also forces a taller button; give both a `minimumSize: const Size.fromHeight(64)` rather than relying on intrinsic height.


**MEDIUM — DriverTrackScreen is a dead route: nothing in the app navigates to it, and its tab index belongs to Publish**  
`apps/driver_pilot/lib/driver_flow.dart:60` · navigation  

*What goes wrong:* No direct user harm today, because no user can reach the screen. The cost is to the next person changing navigation: the tab table claims five destinations map to four paths, one screen's worth of code is maintained and never rendered, and anyone who restores a Track entry point will find the Publish tab highlights instead.

*Fix:* The deletion is right, but the fix understates what is lost, and as written it would quietly drop a filter the Loads screen does not offer.

Track's filter is two conditions, not one — driver_flow.dart:1223-1225:
`if (item is Map<String, dynamic> && (item["reservedKg"] as num? ?? 0) > 0 && item["status"]?.toString() == "IN_PROGRESS")`

The Loads screen's `_filtered` (944-951) filters only on `vehicleClass` and `status`; there is no reserved-capacity filter anywhere in it. So the FilterChip list at :1053 covers the `IN_PROGRESS` half and nothing covers `reservedKg > 0`. The Loads header already computes that number — :990 `final active = _trips.where((t) => (t["reservedKg"] as num? ?? 0) > 0).length;` — and shows it as text ("$active with bookings", :991) with no way to filter by it.

Corrected fix, same four deletions plus one addition:
1. Delete driver_flow.dart:2286 (the GoRoute), :24 (the title case), :60 (the index mapping) and the class at 1200-1272.
2. Before deleting, confirm with the product owner whether "trips with reserved capacity" is a view drivers want. If yes, add one FilterChip to the Loads status row rather than losing it: extend the list at :1053 to `["All", "IN_PROGRESS", "OPEN", "FULL", "COMPLETED", "WithBookings"]` — or better, keep that list as pure API status values and add a separate chip alongside it labelled "With bookings", backed by its own `bool _bookedOnly` field and one extra clause in `_filtered` (after line 950): `if (_bookedOnly) { list = list.where((t) => (t["reservedKg"] as num? ?? 0) > 0).toList(); }`. A separate chip is the cleaner shape because the existing list maps one-to-one onto API status strings through `_statusChipLabel` (:979-981) and a pseudo-status would break that mapping.
3. If the product instead wants Track restored as a destination, it needs its own index and its own `_pathForIndex` case, not a shared one — as the finding says. That means a sixth NavigationDestination, which is one past the five now in the bar (125-143) and past Material's comfortable limit, so the likelier answer is the filter chip above.


**MEDIUM — The Fleet screen highlights the Home tab while its app bar says "Fleet"**  
`apps/driver_pilot/lib/driver_flow.dart:61` · consistency  

*What goes wrong:* A carrier owner taps Profile, then "Fleet — invite drivers", and the bottom bar jumps back to Home while the app bar reads "Fleet". The nav is telling him he is somewhere he is not, and the tab that would take him back to where he came from looks unselected. On a screen where he is about to type a driver's phone number and grant them access to his org, a lost sense of place is the wrong thing to introduce.

*Fix:* Add `|| path.startsWith("/driver/fleet")` to the condition at driver_flow.dart:61-63, so it reads `if (path.startsWith("/driver/profile") || path.startsWith("/driver/earnings") || path.startsWith("/driver/payout") || path.startsWith("/driver/fleet")) return 4;`. Everything reachable from Profile should highlight Profile.


**MEDIUM — The Join screen's "Back" button destroys the navigation stack when the screen was pushed from Fleet**  
`apps/driver_pilot/lib/driver_flow.dart:537` · navigation  

*What goes wrong:* A carrier owner inviting a new driver taps "New driver? Register account first", fills the form, and is dropped either on the landing screen (via Back) or on a sign-in screen (via submit) — both of which throw away the invite he was halfway through, and one of which looks like he has been signed out of his own org. He then has to go Home, Profile, Fleet and re-enter everything.

*Fix:* The fix at driver_flow.dart:508 is wrong and must not be applied as written: it navigates to `/driver/onboarding/awaiting-invite`, which does not exist. `grep -rn "awaiting-invite" lib/` returns nothing, and the only onboarding routes declared are `/driver/onboarding/phone`, `/otp`, `/register`, `/join` (driver_flow.dart:2300-2303). With no `errorBuilder` on the GoRouter (main.dart:73-99), an unmatched location renders go_router's default error page — so the fix would replace a mildly wrong destination with a dead end on the landing-entry path, which is the more common path.

Corrected version.

1. Back button, driver_flow.dart:537. Use go_router's own `context.canPop()` rather than `Navigator.of(context).canPop()`; go_router exposes it on BuildContext and it is the call that matches the router's stack rather than the nearest Navigator (they agree here, but only by accident of Join sitting on the root navigator):
   `TextButton(onPressed: () => context.canPop() ? context.pop() : context.go("/driver"), child: const Text("Back")),`

2. Success path, driver_flow.dart:504-508. Branch on the same condition and keep the existing route as the fallback — do not invent one. Also fix the snackbar copy, which is written only for the driver-registering-themselves case ("ask your carrier admin to invite you, then sign in") and is simply untrue when the carrier owner is the one at the keyboard:
   ```
   if (!mounted) return;
   final returningToInvite = context.canPop();
   ScaffoldMessenger.of(context).showSnackBar(SnackBar(
     content: Text(returningToInvite
       ? "Account created for $phone. Enter that number to send the invite."
       : "Account created. Ask your carrier admin to invite you, then sign in."),
   ));
   if (returningToInvite) {
     context.pop();
   } else {
     context.go("/driver/onboarding/phone");
   }
   ```
   `phone` is already in scope at :497 (`final phone = digitsOnly(_phone.text.trim());`). Note this drops the em dash from the existing string, which is fine; it is not a token.

3. driver_flow.dart:264 and :470 — apply the same `context.canPop()` pattern for consistency, but label it as consistency work, not a bug fix. Nothing pushes to `/driver/onboarding/phone` or `/driver/onboarding/register` today, so those two Back buttons are currently correct and the change is a no-op at runtime.

4. Worth adding to the finding rather than the fix: driver_flow.dart:519 is `appBar: AppBar(title: const Text("Join a fleet")),` with no `leading` override, so when the screen is pushed from Fleet the AppBar already renders a back arrow that pops correctly. The screen therefore ships two back affordances with different destinations. Once fix 1 lands they agree, and the bottom "Back" TextButton becomes redundant on the pushed path — acceptable, since it is the only back affordance on the `go` path where the arrow is absent.


**MEDIUM — The OTP screen puts a raw "Challenge id" field in front of the driver, and it is the field that silently blocks him**  
`apps/driver_pilot/lib/driver_flow.dart:363` · form-ux  

*What goes wrong:* A driver, possibly reading English as a second language, is shown two fields where he expected one, the first labelled with an internal term and filled with an opaque identifier he must not touch. If his connection dropped during the start call the field is empty, the snackbar explaining that has already vanished, and pressing Verify fails with another transient message — he has no way to work out that the blocker is a field he was never meant to see.

*Fix:* The finding stands, but the proposed fix has three problems.

(1) "Wrap that TextField in `if (kDebugMode)` alongside the debug-code line at :358-361" is wrong twice over. The debug-code line is NOT gated on kDebugMode - it is gated on `if (_debugCode != null)` (:358), which is driven by a server response field (`r.data?["debugCode"]`, :304-307). So a release build pointed at a server that still returns debugCode will still print "Debug OTP: ..." on the driver's screen. And gating the challenge-id field on kDebugMode leaves the release build with a state that cannot be recovered at all, since the driver then has no way to see or refill the empty value - it converts a confusing block into an invisible one. Remove the challenge-id TextField from the tree outright rather than debug-gating it.

(2) "keep `_challengeId` as a plain String" is a three-site change, not one: `_challengeId` is declared as a TextEditingController at :280, read at :320 (`_challengeId.text.trim()`), written at :302, and disposed at :345. Switching to `String _challengeId = ""` requires editing :280, :302 (`_challengeId = id`), :320 (`"challengeId": _challengeId`) and deleting :345, or the file will not compile.

(3) `autofillHints: const [AutofillHints.oneTimeCode]` on the code field does not take effect on its own - Flutter's autofill requires an `AutofillGroup` ancestor, and there is none anywhere in lib/ (grep for AutofillGroup returns nothing). Wrap the ListView children in an `AutofillGroup` if this is added. Also note it partly conflicts with :306 `_code.text = dc;`, which already prefills the field from the server debug code, so the autofill path is only exercised against a server that does not return debugCode.

Also worth folding in while this screen is open: `_send` at :232 already calls `/v1/auth/otp/start` before navigating at :234, and `didChangeDependencies` (:289-294) calls `_resend()` again on arrival, so the start call fires twice per sign-in and the id used at :320 comes from the second one. That is not part of this finding, but any rework of the challenge-id plumbing touches the same code.

The persistent-inline-error half of the fix is sound as written: replace the :309 snackbar with a stored `String? _startError` rendered as an inline row plus a "Try again" TextButton, so the blocking state does not disappear.


### Loading, empty, error and offline states

12 findings, 8 high.


**HIGH — Earnings screen renders zero rupees when the earnings fetch fails**  
`apps/driver_pilot/lib/driver_flow.dart:1888` · error-state  

*What goes wrong:* There is no catch clause. When the request fails — 45-second timeout in a dead zone, 500, expired token — the finally still sets _loading = false, so the spinner clears and _summary stays null. build() then coalesces both figures to 0 and _StatTile renders "Pending (accrued) ₹0" and "Paid out ₹0". An owner-operator who opens Earnings on a patchy connection is told, in the app's most confident typography (22px bold navy, driver_flow.dart:1954), that he has earned nothing. There is no error text, no retry, and no RefreshIndicator on this screen, so his only recourse is to back out and re-enter. This is the screen he checks to decide whether he has been paid.

*Fix:* The fix is sound in shape but names a function that does not exist. `friendlyApiError` appears nowhere in the codebase — grep returns zero hits. The only error formatter is `formatApiError` at pilot_api.dart:57, and its output is developer-facing: it returns strings such as "Cannot reach API at ... This is usually CORS — redeploy the API with CORS enabled, or run a local API with --dart-define=API_BASE_URL=http://localhost:3000" (lines 64-68) and "run with --dart-define=API_BASE_URL=http://10.0.2.2:3000 for a local API on the emulator" (lines 69-72), plus raw "HTTP 500: {body}" (line 74). Showing that to an owner-operator is worse than showing ₹0. Corrected fix: add `String? _error;` to _DriverEarningsScreenState and a `catch (e) { setState(() => _error = "Could not load your earnings. Your balance has not changed."); debugPrint(formatApiError(e)); }` between the try and the finally at driver_flow.dart:1895 — a fixed driver-facing string, with formatApiError kept for logs only. Also clear `_error = null` at the top of _load alongside `_loading = true`, or a retry that succeeds will still render the error. In build(), when `_error != null || _summary == null`, render the error Card plus a FilledButton labelled "Try again" calling _load() INSTEAD of the two _StatTile widgets — keep that Card as a child of the same ListView, not in place of it, so the RefreshIndicator still has a scrollable to attach to; with `physics: const AlwaysScrollableScrollPhysics()` pull-to-refresh then works on the error state too. One case the original fix misses: driver_flow.dart:1905 falls back to `DriverSession.kycStatus ?? "NOT_STARTED"`, so on a failed load the KYC Card and the "Set up payouts" FilledButton still render confident NOT_STARTED copy ("Customer payments sit on the platform ledger until you add a verified payout method"). Suppress that Card and both buttons in the error branch as well, so no part of the screen makes a claim about money state that was never fetched.


**HIGH — Payout history shows the "no payouts yet" empty state when the fetch fails**  
`apps/driver_pilot/lib/driver_flow.dart:2062` · empty-state  

*What goes wrong:* Same missing catch as the Earnings screen. On any failure _batches stays empty and the screen renders a confident, specific empty state that tells the carrier his payouts have not been settled yet and implies he needs to go do more PODs. A network failure is presented as a factual statement about his money. There is no error text and no retry affordance on this screen either.

*Fix:* The fix is right in substance but has two implementation gaps that would bite whoever applies it literally.

1. `_error` is never cleared, so a successful retry still shows the error card. The catch must be paired with a reset at the top of `_load()`:

```dart
Future<void> _load() async {
  setState(() {
    _loading = true;
    _error = null;
  });
  try {
    ...
    setState(() => _batches = list);
  } catch (e) {
    if (!mounted) return;
    setState(() => _error = formatApiError(e));
  } finally {
    if (mounted) setState(() => _loading = false);
  }
}
```
`formatApiError` already exists at pilot_api.dart:58 and is exported into this file; keep its output for a diagnostic line and put the reassuring sentence in the Card copy, not in place of it.

The `if (!mounted)` guards matter here specifically because connectTimeout and receiveTimeout are both 45 seconds (pilot_api.dart:32-33) and this screen is pushed onto a go_router stack the user can pop back out of, so an un-guarded setState after dispose is reachable.

2. `RefreshIndicator(onRefresh: _load)` collides with the existing `_loading ? Center(...) : ListView(...)` branch at driver_flow.dart:2082-2084. `_load` sets `_loading = true`, which swaps the ListView out for a bare `Center(child: CircularProgressIndicator())` while the pull gesture is still animating — the RefreshIndicator loses its scrollable child mid-refresh. Follow the pattern already used at driver_flow.dart:998-1001, where the ListView stays mounted permanently with `physics: const AlwaysScrollableScrollPhysics()` and there is no `_loading` branch in build at all. Either drop the Center branch and render a first-load spinner as a child of the ListView, or gate it on a separate `bool _firstLoad = true;` that is set false after the first `_load()` completes so `_loading` no longer tears the tree down on pull-to-refresh.

Everything else stands: gate the existing copy as `if (_error == null && _batches.isEmpty)`, and render the error Card with a "Try again" FilledButton calling `_load()`. On the error copy, "Could not load your payout history. This does not mean a payout is missing." is good and stays within the no-dark-patterns rule — it corrects a misleading state rather than manufacturing reassurance. No emoji, no icon needed beyond a muted `Icons.error_outline` if one is wanted, and the Card should use `DriverTheme.border` since driver_theme.dart carries no error token.

Worth flagging to the owner as a follow-up rather than folding in here: _DriverEarningsScreenState._load at driver_flow.dart:1888-1898 has the identical defect and should be fixed in the same commit, since the two screens link to each other (the "Payout history" OutlinedButton at driver_flow.dart:1935) and fixing only one leaves the pair inconsistent.


**HIGH — A signed-in driver who is offline is told to sign in**  
`apps/driver_pilot/lib/driver_flow.dart:183` · offline-state  

*What goes wrong:* DriverSession.refresh() returns false for every failure mode — no network, timeout, 500, 401 — with no way for the caller to tell them apart. So a driver with a perfectly valid stored token who taps "Continue as signed-in driver" in a tunnel or a low-signal stretch gets "Sign in first, or complete carrier registration." The app has told him his account is the problem. The recovery path he will then take, Sign in with phone, needs the same network he does not have, so he lands in a loop where OTP start also fails. This is the first screen on Android, so it is the most likely place a driver gets stuck with no explanation.

*Fix:* The diagnosis is right and the enum shape is right, but the fix as written has two defects and one missing check.

DEFECT 1 — the fix cannot be implemented in the widget it targets. DriverWelcomeScreen is `class DriverWelcomeScreen extends StatelessWidget` (driver_flow.dart:151) with a `build` that returns a const-heavy Column. A persistent Card plus a Try again button is per-instance state, so step one is converting it to a StatefulWidget with `SessionRefreshOutcome? _lastOutcome` and `bool _checking`, setState in the button handler, and the Card rendered conditionally above the FilledButton at line 172. The fix must say this or the implementer will reach for another snackbar.

DEFECT 2 — the proposed copy asserts something the app cannot know, and is false for one real user. "you are still signed in" is unverifiable while offline: the stored token may be expired or revoked, and the whole point of the finding is that `unreachable` means the app learned nothing about the account. Worse, a driver who has NEVER signed in and is offline also gets `unreachable` (the interceptor simply omits the authorization header and the request still fails at the socket), so that person is told they are signed in when they are not. That is a truth-in-UI violation. Either drop the clause — "Cannot reach NaviG8r. Check your mobile data and try again." — or gate it on token presence, which needs a new `Future<bool> hasToken() => _storage.read(key: "access_token").then((t) => t != null && t.isNotEmpty);` on Api, since `_storage` is a private top-level in pilot_api.dart and DriverSession cannot reach it today. Only show "You are still signed in on this device" when hasToken() is true, and word it as a device fact rather than a session guarantee.

MISSING CHECK the fix should have stated (it happens to be safe, so this is reassurance, not a blocker): changing the return type of `DriverSession.refresh()` from `Future<bool>` breaks no other caller. There are 10 call sites (driver_flow.dart:184, 324, 577, 894, 1296, 1339, 1891, 1999, 2125, 2145) and 184 is the only one that binds the result; the other nine are bare `await DriverSession.refresh();` statements that discard it and then read the static fields, so they compile unchanged.

ONE SIMPLIFICATION worth considering over a new enum. The codebase already has `formatApiError(Object e)` in pilot_api.dart, which distinguishes connectionError/unknown with "Failed host lookup" and "Network is unreachable" and is the established pattern at driver_flow.dart:238. A smaller change that matches house style is to leave `refresh()` alone and add a sibling `static Future<void> refreshOrThrow()` that does not swallow, letting the welcome screen catch and branch on `DioException.type` itself. The enum is still defensible because it keeps Dio types out of the widget layer — but if the enum goes in, it should be the ONLY thing that classifies errors, not a second classifier sitting beside formatApiError with different rules for the same DioExceptionType values.

Finally, note that `DioExceptionType.unknown` should NOT map to `unreachable` unconditionally as the fix proposes. On dio 5.x, `unknown` is the catch-all wrapper for any non-Dio error thrown inside the request, including a JSON parse failure — mapping all of it to "check your mobile data" would tell a driver his network is broken when the server returned malformed JSON. Map connectionError, connectionTimeout, receiveTimeout and sendTimeout to `unreachable`; treat `unknown` as unreachable only when `e.error is SocketException`, and otherwise fall through to a generic "Something went wrong. Try again." so a 500 or a parse failure is not disguised as an offline state.


**HIGH — Failed proof-of-delivery gives a four-second raw error and no retry, on the screen that releases payment**  
`apps/driver_pilot/lib/driver_flow.dart:1838` · error-state  

*What goes wrong:* POD is submitted at the delivery point — a warehouse dock or yard, where signal is at its worst. If the POST to /shipments/{id}/driver-pod fails, the only feedback is a SnackBar carrying the raw output of formatApiError (pilot_api.dart:74 returns "HTTP 500: {...}" or a Dio timeout sentence). No `duration:` is passed anywhere in this codebase, so it uses the framework default, and no SnackBarAction exists anywhere in the app, so there is no Retry button on it. A driver glancing up from traffic or a loading bay reads nothing, the transient message disappears, the screen looks unchanged with the Confirm POD button re-enabled, and he has no way to know whether the delivery was recorded. POD is what releases his payment.

*Fix:* The diagnosis and the first half of the fix are sound. The offline half is not, and should not ship as written.

KEEP AS PROPOSED (the error-state fix):
Add `String? _error;` to `_DriverPodScreenState` (alongside `_busy` at driver_flow.dart:1813). Set it in the catch at 1838-1839 instead of calling `showSnackBar`, clear it at the top of `_confirm()`. In `build()` (1846), insert between the Spacer (1858) and the FilledButton (1859) a Container with a 1px border in a new `DriverTheme.error` token, carrying two lines: "Delivery not submitted yet." and a plain-language second line. Change the button label at 1863 from "Confirm POD" to "Try again" while `_error != null`. Keep `formatApiError(e)` out of the user-facing copy entirely — line 74 returns "HTTP 500: {json}" and lines 65-71 name CORS and `--dart-define` flags, none of which mean anything to a driver. Put the raw string behind a collapsed "Technical details" ExpansionTile for support calls.

DO NOT SHIP AS PROPOSED (the write queue):
1. The copy "Saved on your phone. It will be submitted when you have signal." promises automatic resubmission. Nothing in this codebase does background retry — there is no queue, no connectivity listener, no retry scheduler. Showing that sentence while only writing a blob to storage tells the driver something untrue on the screen that releases his money. If the queue is not built, the copy must not be shown.
2. A resubmitted POD needs server-side idempotency. `POST /shipments/{id}/driver-pod` (line 1826) can fail after the server committed — a lost response on a patchy link is exactly the case being designed for. Replaying it without an idempotency key risks a duplicate POD on a payment-releasing endpoint, which is worse than the current failure mode. The key has to be generated client-side per POD attempt and honoured by the API; that is a backend change, not a screen change.
3. flutter_secure_storage is the wrong store for this even though it is already a dependency. It is keychain/keystore-backed for small secrets; a pending POD payload is not a secret, and secure storage reads can fail or return null after an OS restore. Use ordinary app-document storage.
4. An offline write queue plus a server idempotency contract is an architecture decision spanning client and API. Per house rules that is a "pause and ask" item, not something bundled into an error-state fix. Split it into its own decision and ship the inline error state first — it is the part that closes the actual reported gap.

Interim copy that is true without the queue, for the connection-error branch specifically: "Not submitted. No connection to the server. Stay on this screen and press Try again when you have signal."


**HIGH — Driver GPS pings fail silently while the screen states that live GPS is being shared**  
`apps/driver_pilot/lib/driver_flow.dart:1550` · offline-state  

*What goes wrong:* _maybePostLocation swallows every failure, and the map keeps moving because _driverPos is updated from the local Geolocator stream at driver_flow.dart:1467 regardless of whether the POST landed. So the driver sees his own pin advancing and an unconditional sentence saying customers can see him, while every ping has in fact been dropped for the last hour of highway with no coverage. The customer side meanwhile shows "Load started — waiting for driver GPS" (pilot_api.dart:347). The driver is being told the opposite of what the customer is being told, and is given no reason to act.

*Fix:* The fix as proposed is misplaced and its backfill half is unimplementable against this API. Corrected:

(a) Put the sync line where the driver actually is. Editing only driver_flow.dart:1775 touches the post-POD tail state. Add the status line to BOTH tripStarted branches — 1773 and 1780 — or better, hoist one `_locationSyncLine()` widget above the `if (tripStarted && _hasActiveShipments)` split at 1780 so it renders for the whole IN_PROGRESS period.

(b) Keep the state, as proposed: `DateTime? _lastLocationAcceptedAt` set after a successful await at 1549, `bool _locationSyncFailing` set in the catch at 1550. Copy: on success "Live GPS shared with customers · last update HH:MM"; on failure "No signal — customers cannot see your location right now. Positions will send when you are back in coverage." Both need a non-muted colour for the failure case; DriverTheme has only navy/background/border/muted, so the failure line needs a real warning token added to driver_theme.dart, not muted #64748B at 12px, which is the styling the current line uses at 1777 and is the least visible text on the screen in sunlight.

(c) Fix the throttle, which the finding missed. driver_flow.dart:1538 assigns `_lastLocationPostAt = now;` before the request. On failure, reset it in the catch (or only assign it after a successful await) so the next stream event retries instead of waiting out another 30 seconds of the 1535 gate.

(d) Drop the "buffer the dropped pings and flush the most recent few" half. The server keeps only a single point — `const updated: AnchorTrip = { ...trip, lastLiveLocation };` (services.ts:1178) — so replayed pings overwrite each other and only the last survives; flushing several is wasted requests on the connection that just came back. Retry the single most recent position only.

(e) If you do replay a stale position, send its capture time. The client payload at driver_flow.dart:1543-1548 omits `recordedAtUtcMs`, but the route accepts it (httpServer.ts:598) and the service defaults to `params.recordedAtUtcMs ?? nowUtcMs()` (services.ts:1169). Without it, a 40-minute-old position is stamped at receipt and shows the customer a stale location as current — and suppresses the customer's own "last GPS signal is stale" warning at pilot_api.dart:349. Add `"recordedAtUtcMs": p.timestamp.millisecondsSinceEpoch` to the payload as part of this change.

(f) Separately gate the false-reassurance pair on load failure. `_shipments = []` at driver_flow.dart:1585 makes both line 1703 ("All bookings have proof of delivery") and line 1776 render on a network error. Add a `bool _shipmentsLoaded` set only in the success path and require it in the 1702 and 1773 conditions, otherwise the new sync line ships next to a sentence telling an offline driver his deliveries are confirmed.


**HIGH — Raw HTTP status and response body are shown to drivers as the error message**  
`apps/driver_pilot/lib/pilot_api.dart:74` · error-state  

*What goes wrong:* formatApiError is the error string for every screen in both flows. Its fallback interpolates the raw Dio response body, so a driver sees "HTTP 400: {message: capacityKg must be positive, code: VALIDATION_FAILED}". Worse, the branch that fires exactly in the target scenario — an Indian highway with no data — hands a truck driver a Flutter CLI flag, an emulator loopback address, and the raw exception text in parentheses. It also leaks the API hostname. Requests that time out (connectTimeout and receiveTimeout are both 45s, pilot_api.dart:32-33) match neither string branch and fall through to line 74 as "HTTP ?: The request connection took longer than 0:00:45.000000 and it was aborted."

*Fix:* The fix is sound; two amendments before implementing.

1. Guard the 4xx message extraction. The proposed "4xx -> the server's `message` field only" assumes the body is a Map with a String `message`. A NestJS-style API commonly returns `message` as a List of validation strings, and the body can also be a String or null (HTML error page, empty body). Without a guard, `body["message"]` throws or renders a raw List. Write it as: if body is a Map and body["message"] is a String, use it; if it is a List, join the entries with ". "; otherwise fall back to "That request could not be completed. Check the details and try again." Never interpolate `body` itself.

2. formatApiError is not the only developer string reaching drivers. driver_flow.dart:1583-1586 appends a hardcoded build note to the shipment-list error: `_error = _error == null ? "$msg
(Shipment list needs API deploy — merge driver-onboarding PR.)" : _error;`. Repointing the call at friendlyApiError leaves that sentence in place, so a driver still sees an instruction to merge a pull request. Delete that suffix in the same change and let the generic empty/error state stand.

Everything else in the proposed fix holds: keep formatApiError for main.dart's pilot-lab surfaces (10 call sites), add friendlyApiError with the DioExceptionType mapping, drop both dart-define branches and the api.baseUrl interpolation from user-facing text, and repoint all 42 driver_flow.dart and customer_flow.dart call sites.


**HIGH — Shipment detail spins forever with no message and no exit when the load fails**  
`apps/driver_pilot/lib/driver_flow.dart:829` · error-state  

*What goes wrong:* _load swallows the exception completely and never sets any error field — the class has no _error at all. It also only sets _shipment when it finds a matching id inside the /v1/pilot/carrier/shipments list, so a shipment the list no longer returns (status changed, filtered server-side) leaves _shipment null on a fully successful request. Either way the driver gets a bare, unlabelled, indefinite spinner. Nothing ever times it out, nothing explains it, there is no retry, and the screen offers no way forward — only the app bar back arrow, which is not obviously the answer to a spinner that looks like it is still working. The driver reached this screen to accept a booking or start a POD.

*Fix:* The fix is sound in shape but names a helper that does not exist: `grep -n "friendlyApiError" lib/*.dart` returns zero hits. The codebase helper is `formatApiError`, used at 21 sites including line 811 inside this same class. Corrected fix: add `bool _loading = true; String? _error; bool _notFound = false;` to _DriverShipmentDetailScreenState (currently 793-794). In _load, set `_loading = true; _error = null; _notFound = false;` before the request, replace `catch (_) {}` at 829 with `catch (e) { if (mounted) setState(() => _error = formatApiError(e)); }` (NOT friendlyApiError), set `_notFound = true` when the loop completes with no match, and clear _loading in a `finally { if (mounted) setState(() => _loading = false); }`. In build (833-837), replace the bare spinner with three states: loading — spinner plus the label "Loading shipment"; error — a Card reading "Could not load this shipment." with a "Try again" FilledButton calling _load and a "Back to shipments" TextButton doing `context.go("/driver/shipments")`; not-found — "This shipment is no longer in your list." with the same Back button. Drop the ellipsis from the loading label per house no-decoration style, and keep the error text on DriverTheme tokens rather than raw Colors.red if the sibling screens are being brought onto tokens in the same pass (they currently use `TextStyle(color: Colors.red)` at 642, 679, 755, 1071, 1257, 1681, 2232 — matching that existing style is acceptable here, do not unilaterally diverge). Also correct the finding's write-up before it reaches the owner: strike "no way forward — only the app bar back arrow" (DriverShell supplies a persistent five-destination NavigationBar) and re-scope the "accept a booking" motivation to the POD back-navigation and deep-link paths, since line 772 blocks list-to-detail navigation for PENDING_CARRIER_ACCEPT.


**HIGH — A failed payment confirmation is swallowed and the customer is routed to the shipment as if it succeeded**  
`apps/driver_pilot/lib/customer_flow.dart:1531` · error-state  

*What goes wrong:* _onCheckoutSuccess runs after Razorpay has reported a successful payment. If the confirm POST to our own backend then fails, the catch discards it and the navigation to the shipment page happens anyway. The customer has been charged, but our backend was never told, so the shipment detail screen they land on will render whatever stale payment state we hold — paymentStatusLabel("CREATED") is "Awaiting checkout" (pilot_api.dart:222). The customer sees money gone and a screen saying checkout has not happened, with nothing telling them a sync failed or what to do. Money screens are the one place a swallowed exception is never acceptable.

*Fix:* The fix is sound on the error handling but wrong on the navigation, and it needs one addition so the banner cannot itself become a lie.

Keep: retry the confirm POST with backoff, and persist the orderId/paymentId/signature triple so a retry survives a reload. Retry is safe — confirmRazorpayCheckoutAuthorization (services.ts:2051-2053) returns the existing payment unchanged when status is already AUTHORIZED or CAPTURED, so it is idempotent.

Drop: "Do not navigate to the shipment page as though the flow completed cleanly." Blocking the navigation is the wrong call. The shipment detail screen is the correct destination and is also the only screen that polls payment status (customer_flow.dart:1959, every 15s, calling _refreshAll which re-reads `payment` at 1943). Stranding a customer who has already been charged on the booking form removes their view of the shipment and their only self-correcting surface. Navigate, and carry the unconfirmed state with them.

Add: the banner must clear itself. Because razorpayWebhook.ts:43-73 can move the payment to AUTHORIZED or CAPTURED without the client confirm ever succeeding, a persistent Card is very likely to be contradicted within seconds by the poll. Render it only while `_payment?["status"]` is still "CREATED", and drop it the moment the poll returns anything else. A banner saying "we have not finished recording it" sitting above a ListTile reading "Payment authorized" is a second defect, not a fix.

Concretely: in _onCheckoutSuccess, replace `catch (_) {}` with a handler that retries up to three times, and on final failure writes the triple to a module-level `unconfirmedCheckout` record (alongside `lastBookedShipmentId` at customer_flow.dart:15) before the existing `context.go` at 1536. In _CustomerShipmentDetailScreen, above the Card at 2075, render when `unconfirmedCheckout?.shipmentId == widget.shipmentId && _payment?["status"] == "CREATED"`: a Card with the title "Payment received, still being recorded", body "Your payment went through. We have not finished recording it on our side. Do not pay again. Reference {razorpayPaymentId}.", and a TextButton "Retry now" that re-posts the confirm. Clear `unconfirmedCheckout` in the _refreshAll setState at 1941-1945 whenever the returned status is not "CREATED". Use DriverTheme.navy for the border and the existing muted token for the body — the theme has no warning token, and inventing one is a separate change.

Copy note: "contact support with this reference" should name the actual channel or be dropped; an instruction the user cannot act on is its own problem.


**MEDIUM — An internal engineering note is rendered in the driver's active-trip error area**  
`apps/driver_pilot/lib/driver_flow.dart:1586` · copy  

*What goes wrong:* When the shipment sub-fetch on the active trip screen fails, the driver sees the raw formatApiError string followed by an instruction to merge a pull request, in red, on the screen he uses to run a live load. It is meaningless to him, it reads as though the app is broken, and it exposes internal branch names. It also fires for any failure of that endpoint, not just the missing-deploy case it was written for.

*Fix:* The direction is right but two details in the fix will not compile or will not match house rules as written.

1. `friendlyApiError` does not exist. Grepping lib/ returns zero hits; the only helper is `String formatApiError(Object e)` at pilot_api.dart:58, and that helper is itself developer-facing (it emits "--dart-define=API_BASE_URL=..." and "HTTP 500: {raw body}"). So do not route the shipment failure through it at all. In the catch at driver_flow.dart:1581, drop the `msg` variable and the whole ternary, and set a separate field instead of overloading `_error`: add `String? _shipmentsError;` beside `String? _error;` (declared at :1435), and in the catch set `_shipmentsError = "Could not load the bookings on this load.";`. Leave `_error` for the trip fetch at :1565 only — that is the failure that genuinely means the screen is unusable. Keep the raw `formatApiError(e)` text out of the UI and send it to a log/debugPrint if it is wanted for support.

2. There is no error colour token. driver_theme.dart defines only navy (#122C53), background (#F4F7FA), border (#E2E8F0) and muted (#64748B); the existing red at :1681 is the raw `Colors.red` (#F44336), which fails WCAG AA as body text on the #F4F7FA background. So the inline Card must not simply reuse `Colors.red`. Either add a token — `static const Color warning = Color(0xFF9A3412);` — which is a theme change to raise with the owner because eight other call sites (:642, :679, :755, :1071, :1257, :1681, :2232) share the same `Colors.red` pattern, or, to keep the fix local and contained, render the notice with `DriverTheme.muted` text inside a `Card` with a `DriverTheme.border` outline and an `Icons.info_outline` leading icon in `DriverTheme.navy`. Prefer the local version for this finding and file the token as its own item.

3. Placement: put that Card in the shipment list region rather than at :1681, so it does not sit above the "Load in progress" line at :1682-1690 and read as a whole-screen failure. Gate it as `if (_shipmentsError != null)` immediately before whatever renders `_shipments`, with a `TextButton(onPressed: _load, child: const Text("Try again"))` — `_load()` is defined at :1555 and already resets `_loading`/`_error`, so also clear `_shipmentsError` in the `setState` at :1556-1559 or the notice will survive a successful retry. That reset is the part the original fix omits and is what would otherwise leave a stale error on screen after a working refresh.

The em dash in the current string is also worth removing along with the parenthetical; no other user-facing copy in this file uses one.


**MEDIUM — Pull-to-refresh is the only retry on two driver lists and does not fire when they are empty or errored**  
`apps/driver_pilot/lib/driver_flow.dart:746` · error-state  

*What goes wrong:* Shipments (driver_flow.dart:746) and Track (driver_flow.dart:1248) wrap a ListView in a RefreshIndicator but omit AlwaysScrollableScrollPhysics, which Loads sets. When those lists are empty or errored the content is shorter than the viewport, so the ListView is not scrollable and cannot overscroll. Pull-to-refresh is also the only retry on both screens — there is no Retry button anywhere in either. The result is that the recovery gesture is unavailable in precisely the failure state it exists for: a driver who loses signal, sees an error and pulls down gets nothing, and concludes the app is frozen.

*Fix:* The fix is sound. Three refinements, none of which change its substance.

1. Add `physics: const AlwaysScrollableScrollPhysics(),` immediately after `child: ListView(` at driver_flow.dart:746 and 1248, matching line 1001 exactly.

2. Put the retry control inside the existing error block rather than loose beside the text, and disable it while a load is in flight, so a driver cannot fire overlapping requests on a patchy connection. Shipments, replacing 753-756:

  if (_error != null) ...[
    const SizedBox(height: 8),
    Text(_error!, style: const TextStyle(color: Colors.red)),
    Align(
      alignment: Alignment.centerLeft,
      child: TextButton(onPressed: _loading ? null : _load, child: const Text("Try again")),
    ),
  ],

Same shape at 1255-1258 for Track. A TextButton is the right weight here: it is the only action in an otherwise empty error state, so it needs no extra emphasis to be found, and promoting it further would compete with the Accept buttons on the cards below once data loads.

3. Track has no empty state at all — children end after `..._trips.map(...)` at 1267, so a carrier with no in-progress trips sees only the one grey description line at 1252 and nothing else. Shipments does have one ("No shipments to deliver.", the `if (!_loading && _shipments.isEmpty)` block). Add the matching line to Track in the same edit, e.g. `if (!_loading && _error == null && _trips.isEmpty) const Padding(padding: EdgeInsets.only(top: 24), child: Text("No trips in progress.", style: TextStyle(color: DriverTheme.muted)))`, otherwise the physics fix makes the pull gesture work on a screen that still gives the driver no words explaining why it is blank.

*Needs a device to confirm.*


**MEDIUM — The Shipments list shows an error and the "nothing here" empty state at the same time**  
`apps/driver_pilot/lib/driver_flow.dart:776` · empty-state  

*What goes wrong:* The empty-state condition is not gated on _error, so a failed fetch renders both a red raw-HTTP line and, below it, the sentence "No shipments to deliver." The driver gets two contradictory answers on one screen: something broke, and also you have no work. The second is the one he is likely to act on, and it is wrong — he may have a booking waiting to be accepted.

*Fix:* Keep part one exactly as proposed. At driver_flow.dart:776 change the guard to:

  if (!_loading && _error == null && _shipments.isEmpty)

Then make three corrections to part two.

(a) Use `context.go`, not `context.push`, for the CTA, matching driver_flow.dart:1395, so the shell selects the Publish tab (index 3 per driver_flow.dart:59) instead of stacking a route over it. Replace the bare Padding+Text at driver_flow.dart:776-777 with:

  if (!_loading && _error == null && _shipments.isEmpty)
    Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text("No active bookings.", style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text("Customer bookings for your published lanes will appear here.", style: TextStyle(color: DriverTheme.muted)),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => context.go("/driver/publish"), child: const Text("Publish a lane")),
          ],
        ),
      ),
    ),

Headline is "No active bookings." rather than "No bookings right now." because the list at driver_flow.dart:711 admits BOOKED and PENDING_RELEASE, which are work already in progress, not just new requests.

(b) Give the error state a recovery path, which the guard change otherwise removes. Add `physics: const AlwaysScrollableScrollPhysics(),` to the ListView at driver_flow.dart:745, matching customer_flow.dart:1806, so pull-to-refresh still fires when the failed screen is shorter than the viewport. Also add an explicit retry inside the existing error block at driver_flow.dart:753-756, since a one-handed driver in a moving cab should not have to discover a hidden gesture:

  if (_error != null) ...[
    const SizedBox(height: 8),
    Text(_error!, style: const TextStyle(color: Colors.red)),
    const SizedBox(height: 8),
    Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton(onPressed: _loading ? null : _load, child: const Text("Try again")),
    ),
  ],

(c) Out of scope for this finding but worth filing separately: `_error!` here is whatever formatApiError returns, and pilot_api.dart:74 returns `"HTTP ${status ?? "?"}: ${body ?? e.message ?? e.toString()}"`. A carrier sees a raw status line and response body. That is its own finding; do not try to solve it inside this one.

Scope of the change: one file, driver_flow.dart, lines 745, 753-756 and 776-777. It touches no other screen, adds no colour token beyond DriverTheme.muted, and leaves the customer flow untouched.


**MEDIUM — The Loads summary pill states the carrier has no lanes when the fetch failed**  
`apps/driver_pilot/lib/driver_flow.dart:986` · empty-state  

*What goes wrong:* _trips is left empty by a failed _load (driver_flow.dart:904-905 only sets _error), so the summary pill at the top of the Loads tab asserts "No anchor trips · tap Publish to add a lane" whenever the request fails. A carrier with ten published lanes who opens the tab on a weak connection is told he has none and instructed to create one — which risks a duplicate lane. The red error text sits below it, but the pill is the confident, styled element at the top of the screen and reads as the app's summary of his business. There is also no empty state in the list body at all when _trips is empty: the guard at driver_flow.dart:1074 is `if (!_loading && _trips.isNotEmpty && _filtered.isEmpty)`, so the truly-empty case shows filter chips over blank space.

*Fix:* The error branch must also require the list to be empty, because _trips is NOT cleared on failure — a failed refresh after a successful load leaves real trips in _trips, and an unconditional `if (_error != null)` would replace accurate counts with "Could not load your lanes" while the correct cards are still visible below, contradicting the screen. Also gate the empty copy on !_loading, since _load sets _loading = true synchronously before its first await, so the first build otherwise shows "No anchor trips" beside the spinner.

In _loadsSummary (driver_flow.dart:983):
  final org = DriverSession.carrierOrgName ?? "Your carrier";
  if (_trips.isEmpty) {
    if (_error != null) return "$org · Could not load your lanes";
    if (_loading) return "$org · Loading your lanes";
    return "$org · No lanes published yet";
  }
...counts unchanged. Keep the existing red _error Text at 1068-1071 as the detail line; the pill only stops asserting a fact it does not have.

Leading icon on the pill (driver_flow.dart:1013): swap Icons.search for Icons.error_outline when `_error != null && _trips.isEmpty`, keeping DriverTheme.muted rather than a red tint, so a transient network failure does not read as an alarm. Icons.search is wrong in every state here anyway — nothing on this screen searches; Icons.local_shipping_outlined is the honest default.

Empty state in the body, inserted before the 1074 filter-empty guard:
  if (!_loading && _error == null && _trips.isEmpty)
    a Card (white, DriverTheme.border, radius 14, dense padding — 12/10 to match the pill) reading "No lanes published yet." with a DriverTheme.muted line "Publish a lane so customers can book space on trips you are already running." and a FilledButton "Publish a lane" calling context.push("/driver/publish"). No urgency copy, no count inflation.

And the failed-fetch case needs its own body block, which the original fix omits — otherwise a failed first load still shows chips over blank space with only a red line:
  if (!_loading && _error != null && _trips.isEmpty)
    the same Card shape reading "Could not load your lanes." over the muted _error text, with an OutlinedButton "Try again" calling _load(). RefreshIndicator pull-to-refresh is the only recovery today and is invisible to a first-time user.

Once the body carries the empty state, drop "tap Publish to add a lane" from the pill string as proposed — the instruction belongs on the button, not in a muted 13px summary line.


### Forms and input

12 findings, 9 high.


**HIGH — Phone field's "+91 …" hint produces input the validator always rejects**  
`apps/driver_pilot/lib/driver_flow.dart:255` · form-ux  

*What goes wrong:* A driver who types their number the way the hint shows it is told "Enter a 10-digit mobile number" — while looking at a field containing what they consider a 10-digit number with the country code the app asked for. The error never mentions the +91. There is no way past this screen until they guess that the app wants the country code dropped, and this is the first screen in the Android app after the landing screen. The same flow's other phone fields are labelled "Phone (10 digits)" (L458, L529, L645), so the one screen that contradicts the rule is the one every driver hits first.

*Fix:* The fix is sound in substance but does not compile as written, and one detail overstates what Flutter renders.

1. Missing import. `FilteringTextInputFormatter` is declared in `package:flutter/services.dart`. `driver_flow.dart` imports only `dart:async`, `package:flutter/material.dart`, geolocator, go_router, google_maps_flutter and the local files (L1-13); `main.dart:7` is the only file in lib/ that imports services. Add `import "package:flutter/services.dart";` to driver_flow.dart alongside the widget change, or drop the formatter and rely on `maxLength: 10` plus the existing `digitsOnly` normalisation at L225.

2. `prefixText` is not always-visible chrome. Flutter's InputDecorator shows prefix/suffix only once the field is focused or has text, so with `labelText: "Mobile number"` still set, an empty unfocused field shows the label and no "+91". That is acceptable, but do not describe it as a permanently visible country code; if the +91 must be visible at rest, use a `prefixIcon` holding a `Text("+91")` (which does render when unfocused) instead of `prefixText`.

3. Keep `maxLength: 10` paired with `counterText: ""` as proposed, and leave the L226 length check in place as the backstop — the formatter and maxLength are input affordances, not validation.


**HIGH — Every server-side form error reaches the driver as a raw JSON envelope**  
`apps/driver_pilot/lib/pilot_api.dart:74` · error-state  

*What goes wrong:* The most common first-run case — a driver who taps "Sign in with phone" before registering — produces the snackbar `HTTP 400: {error: user_not_found}`. A wrong code produces `HTTP 400: {error: otp_incorrect}`; an expired one `HTTP 400: {error: otp_expired}`. For a driver in a truck who may not read English as a first language, none of these say what happened or what to do, and the recovery for `user_not_found` ("Register as new carrier", already on the landing screen) is never mentioned. Every form in the app inherits this.

*Fix:* The fix is directionally right but has three gaps that would leave it incomplete or would regress behaviour:

1. "Keep formatApiError for the developer lab only" is wrong about scope. customer_flow.dart calls formatApiError 25 times (e.g. 365, 518, 774, 1116, 1329, 1562, 1949) and that is the web customer portal, which is a real shipping surface, not the lab. Restricting the friendly mapper to driver_flow.dart leaves paying customers with raw envelopes. Say instead: route both driver_flow.dart and customer_flow.dart through driverFacingError (name it apiErrorMessage, since it is not driver-specific), and leave formatApiError in place only for the 10 main.dart pilot-lab call sites, where the raw status and body are the point.

2. The body is not guaranteed to be a Map. Dio decodes to a Map only when the response carries content-type application/json, which is true for apps/api's own json() helper (httpServer.ts:112) but not for a proxy, gateway or CDN error page on the web /api path (pilot_api.dart:18). Write the switch to read the error code defensively: take response.data, use the "error" key only when data is a Map<String, dynamic> and the value is a String; otherwise fall through to the unknown-code sentence. Do not index the body directly.

3. The connection-error branch at pilot_api.dart:62-72 is not covered by a switch on the error key, and it is the branch a driver on patchy connectivity hits most. As written it returns developer copy naming CORS, --dart-define=API_BASE_URL and the base URL. If the new function delegates non-HTTP errors to formatApiError, drivers get that text. Add an explicit branch to the new function ahead of the status check: for DioExceptionType.connectionError, connectionTimeout, receiveTimeout and sendTimeout, return "No connection to naviG8r. Check your mobile data and try again." Keep the CORS and dart-define strings inside formatApiError for the lab only.

Two smaller points: "Tap Resend code" for otp_expired should be checked against the OTP screen before shipping the string, since the copy must name a control that exists; and account_inactive (auth.ts:87, returned as 403 at httpServer.ts:1687) is a real reachable code that the proposed switch omits and that needs its own sentence rather than the unknown-code fallback.

Finally, the location citation apps/api/src/auth.ts:91 should read auth.ts:92. Line 91 is const user = findUserByPhone(store, params.phone); the throw is on 92.


**HIGH — Opening the OTP screen sends a second SMS and silently invalidates the first code**  
`apps/driver_pilot/lib/driver_flow.dart:293` · form-ux  

*What goes wrong:* Two SMS arrive seconds apart with different 6-digit codes. The app only holds the second challenge, so a driver who opens the first SMS to arrive and types that code gets rejected — and, per the finding above, the rejection reads `HTTP 400: {error: otp_incorrect}`. They retry the same wrong code, or request another resend, and can be locked out of a working number. It also doubles SMS cost on every single sign-in and makes any server-side rate limit twice as likely to trip.

*Fix:* The proposed fix would break sign-in in the current pilot build. `_resend` is not only the challenge starter — L302-306 also read `debugCode` from the response and autofill the code field (`_debugCode = dc; _code.text = dc;`). With no SMS sender in the codebase, that autofill is the only route by which a code reaches a tester. Suppressing the mount call while forwarding only `challengeId` leaves the "6-digit code" TextField (L363) empty with no way to learn the code. Corrected fix, three edits: (1) In `_DriverPhoneScreenState._send`, bind the existing L232 response and forward both values through go_router's `extra` rather than the query string, so no code ever lands in a URL: `final r = await api.post<Map<String, dynamic>>("/v1/auth/otp/start", data: {"phone": phone}); ... context.go("/driver/onboarding/otp?phone=$phone", extra: {"challengeId": r.data?["challengeId"], "debugCode": r.data?["debugCode"]});`. (2) In `_DriverOtpScreenState.didChangeDependencies`, read `GoRouterState.of(context).extra` as a `Map`; when it carries a non-null `challengeId`, set `_challengeId.text` and (if present) `_debugCode`/`_code.text` from it and do NOT call `_resend()`; call `_resend()` only when that map is absent or has no challengeId, which keeps deep-linking to the route working. (3) Apply the same `extra` payload at L437 in the register flow — but note that path does NOT currently call otp/start at all (it posts /v1/pilot/driver/register), so it must keep relying on the mount-time `_resend()`; the absent-challengeId branch in (2) covers it, so leave L437 as is. Leave the explicit "Resend code" TextButton (L372) as the single deliberate new-challenge path. Also worth pairing with the real gap this exposes: auth.ts has no rate limit on /v1/auth/otp/start (types.ts:91 names it as future work), so a fix here should not be mistaken for one.


**HIGH — Bank account number is optional in the submit payload but its helper text calls it required**  
`apps/driver_pilot/lib/driver_flow.dart:1995` · form-ux  

*What goes wrong:* A carrier owner can leave the account number blank, tap "Save and verify", get a success message, be pushed to payout history, and afterwards see "Payout method on file" on their profile — with no bank account recorded anywhere. They believe they are set up to be paid and find out at the first weekly settlement that they are not. This is the app telling someone their money is arranged when it is not.

*Fix:* The finding stands but its first half is not the cure, and the second half is. apps/api/src/types.ts:46-56 shows `Organization` has only `id, kind, displayName, kycStatus, createdAtUtcMs, payoutContactId?, payoutFundAccountId?` — no bank fields. In the non-RazorpayX path (services.ts:1104) the accountHolderName, ifsc and accountNumber the driver typed are all discarded; only kycStatus flips to SUBMITTED. So even after making the account number mandatory on the client, nothing is stored, and "Payout method on file" at driver_flow.dart:1388 is still false. Do the copy fix first and treat it as the required one: change that line to `subtitle: Text(DriverSession.payoutSetupComplete ? "Payout details submitted - verification pending" : "Set up before first transfer")`, which also matches the server's own message string at services.ts:1107-1108 and the earnings card at :1929-1930 ("Payout profile status: $kyc"). Keep the client validation as the second half, with two adjustments: (1) the field at driver_flow.dart:2025-2031 uses `const InputDecoration`, so errorText needs a `String? _accountNumberError` in `_DriverPayoutSetupScreenState` and the `const` dropped from that decoration, set in `setState` before the early return in `_save()`; (2) a client-only guard leaves the same blank-submit reachable from any other caller, so mirror it in `pilotSubmitPayoutSetup` by moving `if (!accountNumber) throw new ApiError("invalid_payout_profile", ...)` out of the `razorpayPayoutsEnabled()` block to sit alongside the `!accountHolderName || !ifsc` check at services.ts:1066. Minor: the helper text "Required to receive real transfers" is conditionally true rather than a flat "this field is required", so the title overstates that half — the load-bearing defect is the profile row, not the helper text.


**HIGH — IFSC field has no keyboard type, no case handling, no length limit and no format check**  
`apps/driver_pilot/lib/driver_flow.dart:2023` · form-ux  

*What goes wrong:* An IFSC is 11 characters where the fifth is always the digit zero — the single most common data-entry error is typing the letter O there, and the second most common is lowercase. Nothing in this screen catches either, so a malformed IFSC is accepted locally and the failure surfaces later as a provider error the driver cannot interpret, or as a payout that does not arrive. This is the one screen in the app where a typo costs the user a week's earnings, and it is the least defended field in the binary.

*Fix:* The fix is right in direction but will not compile or run as written. Three corrections, then two additions.

CORRECTION 1 — missing import. `FilteringTextInputFormatter`, `LengthLimitingTextInputFormatter` and `TextInputFormatter` live in `package:flutter/services.dart`, which driver_flow.dart does not import (verified, lines 1-13). Add `import "package:flutter/services.dart";` alongside the material import.

CORRECTION 2 — `errorText` cannot be set from `_save()` as proposed. L2023's decoration is `const InputDecoration(...)`, and the screen has no `Form` and no `TextFormField` (build() is Padding > Column, lines 2012-2041). `_save()` has nothing to write an `errorText` onto. Either:
  (a) add `String? _ifscError;` to `_DriverPayoutSetupScreenState`, drop `const` from the decoration, pass `errorText: _ifscError`, and have `_save()` do `setState(() => _ifscError = ...); if (_ifscError != null) return;` before the POST — this matches how customer_flow.dart:454-457 already surfaces `_error`; or
  (b) convert the three fields to `TextFormField` inside a `Form` with a `GlobalKey<FormState>` and validate all three at once. (b) is better because the account-holder-name field at L2022 is equally unvalidated and the same gate should cover it.

CORRECTION 3 — drop the redundant parts. `maxLength: 11` already installs a length-limiting formatter, so `LengthLimitingTextInputFormatter(11)` is duplicated; and `textCapitalization: TextCapitalization.characters` is only a keyboard hint that the uppercase `TextInputFormatter.withFunction` already enforces. Keep `maxLength: 11` + `counterText: ""` + `FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]'))` + the uppercase formatter, and drop the other two. (Optional: the one existing precedent, customer_flow.dart:452, shows the counter rather than hiding it. On an 11-character code an "8/11" counter is a genuine progress cue, so consider dropping `counterText: ""` too.)

ADDITION 1 — the omission that matters most on an Android keyboard, and which the fix does not mention: add `autocorrect: false` and `enableSuggestions: false`. A bank code sitting in a default text field is exactly the input Android's suggestion strip mangles, and no formatter catches a substitution the IME performs. The finding's own title says "no keyboard type" but the fix never adds one; `TextInputType.text` (the default) is correct for an alphanumeric code, so the real gap is autocorrect, not keyboardType.

ADDITION 2 — scope the rename honestly. The current label is "IFSC / bank identifier", which reads as deliberately generic. Renaming to "IFSC code" and enforcing an 11-character regex narrows the field to India. That is consistent with what the backend actually does (razorpayPayouts.ts:113-120 posts `bank_account: { ifsc, account_number }`, which is India-only), but it is a product decision, so confirm it with the owner rather than assuming it from the call site.

Finally, keep the finding's own caveat: verify `^[A-Z]{4}0[A-Z0-9]{6}$` against an RBI primary source before shipping it. I did not verify it either. A wrong regex on this field is worse than no regex, because it rejects valid codes on the one screen where the driver cannot route around it.


**HIGH — Bank account number is entered once with no confirmation field and no digit constraint**  
`apps/driver_pilot/lib/driver_flow.dart:2024` · form-ux  

*What goes wrong:* A single mistyped digit in a 9-to-18-digit account number routes every future weekly payout to a different account, and neither the app nor the driver has any way to notice before the money moves. `TextInputType.number` also still permits pasted spaces or hyphens on many Android IMEs, which are passed through untouched. Every consumer banking flow in India double-enters this number precisely because it cannot be checked any other way.

*Fix:* The fix is directionally right but has four defects that would bite on implementation. Corrected version:

1. Add the missing import. driver_flow.dart L1-13 imports only dart:async, material, geolocator, go_router, google_maps_flutter and the local files. `FilteringTextInputFormatter` and `LengthLimitingTextInputFormatter` live in `package:flutter/services.dart`, which is not imported. Without adding `import "package:flutter/services.dart";` the proposed fix does not compile.

2. Drop the hard 18-digit cap, or verify it first. `LengthLimitingTextInputFormatter(18)` does not warn — it makes the 19th character untypeable, so a driver at a bank issuing a longer number simply cannot enter their account and has no idea why. I have not verified the payment provider's documented maximum (services.ts L1078 passes the string straight through to `createRazorpayBankFundAccount`; razorpayPayouts.ts L120 sends `account_number: params.accountNumber.trim()` with no length check of its own), so the length is an unchecked assumption. Use `LengthLimitingTextInputFormatter(40)` as a typo guard only, and put the real 9-to-18 expectation in a soft, non-blocking `helperText`/`errorText` the driver can override, until the provider's limit is confirmed. Keep `FilteringTextInputFormatter.digitsOnly` — that part is safe and fixes the pasted-space problem outright.

3. Do not block paste with `enableInteractiveSelection: false`. That also removes tap-to-position-cursor and selection, which is exactly what someone needs to fix a typo midway through a 16-digit number one-handed in a truck — it makes the confirm field harder to get right, not easier. Remove only the paste action:
   `contextMenuBuilder: (context, state) => AdaptiveTextSelectionToolbar.buttonItems(anchors: state.contextMenuAnchors, buttonItems: state.contextMenuButtonItems.where((i) => i.type != ContextMenuButtonType.paste).toList())`
   Also set `autofillHints: null` and `enableSuggestions: false` on the confirm field so an IME clipboard suggestion does not reintroduce the same mistyped value.

4. `errorText` cannot go where the fix implies. The decoration at L2027 is `const InputDecoration(...)`; an `errorText` that changes needs a `String? _confirmError` field set in `setState` inside `_save()`, and the `const` must come off that decoration. State the mismatch check as: `if (_accountNumber.text.trim() != _accountNumberConfirm.text.trim()) { setState(() => _confirmError = "The two account numbers don't match. Check both and try again."); return; }` before `setState(() => _busy = true)` at L1985.

One addition the fix misses: the masked echo has to be built from the locally typed value, not read back from the server. services.ts L1084-1088 stores only `kycStatus`, `payoutContactId` and `payoutFundAccountId` — the account number is never persisted or returned, so there is no field to display. Show `"Saved to account ending ${acct.substring(acct.length - 4)}"` in the SnackBar at L2000 alongside the server message, built from `acct` (L1988). Guard the substring for a value shorter than 4 characters.

Note also that the field is optional in practice — `if (acct.isNotEmpty)` at L1995 means an empty account number posts successfully and, on the non-Razorpay branch (services.ts L1103-1108), returns "Payout details received for verification" while the `helperText` at L2029 says it is required. That is a separate finding, but any mismatch check must not accidentally make an empty-empty pair pass silently.


**HIGH — Payout setup and POD screens cannot scroll, so the keyboard can bury the submit button**  
`apps/driver_pilot/lib/driver_flow.dart:2012` · form-ux  

*What goes wrong:* When the soft keyboard opens on a mid-range Android phone, the Scaffold shrinks the body and lifts the bottom navigation bar above the keyboard, leaving roughly a third of the screen for content that needs an intro paragraph, three text fields and a submit button. The `Spacer` collapses to zero and there is no scroll view, so once the content exceeds the space the driver cannot reach "Save and verify" or "Confirm POD" at all — on the two screens that move money. On these screens the recovery (dismiss the keyboard, tap the button) is not obvious to someone who has never used the app.

*Fix:* The ListView half of the fix is sound and matches the register screen's existing pattern (L449). The pinned-button fallback is not the right second option — do not nest a Scaffold inside DriverShell's body just to get `bottomNavigationBar`; that adds a second Material surface and a second inset-handling layer under a Scaffold that already resizes (and whose body is handed a MediaQuery with the bottom view inset already removed, so the inner Scaffold would not resize anyway — the pinning would work by accident, not by design).

Use one of these instead.

Option A, scrolls everything (preferred, matches L449):

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text("Collect once before your first transfer. KYC may be required by your payment provider.",
            style: TextStyle(color: DriverTheme.muted)),
        const SizedBox(height: 16),
        TextField(controller: _name, decoration: const InputDecoration(labelText: "Account holder name")),
        TextField(controller: _ifsc, decoration: const InputDecoration(labelText: "IFSC / bank identifier")),
        TextField(controller: _accountNumber, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: "Bank account number",
                helperText: "Required to receive real transfers")),
        const SizedBox(height: 24),
        FilledButton(onPressed: _busy ? null : _save, child: ...),
      ],
    );

Note that `ListView` has `crossAxisAlignment: stretch` behaviour for free (children are stretched to the cross-axis extent), so dropping `crossAxisAlignment: CrossAxisAlignment.stretch` from the old Column loses nothing — the FilledButton stays full width.

Option B, keeps the button pinned at the bottom of the resized body while the fields scroll — no nested Scaffold, and it preserves the current visual exactly:

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: ListView(children: [ <intro>, <SizedBox 16>, <the TextFields> ])),
          const SizedBox(height: 16),
          FilledButton(...),
        ],
      ),
    );

`Expanded(child: ListView(...))` replaces `const Spacer()` at L2032 and L1858 and is what makes the shrinking body safe: the list absorbs the squeeze instead of the Column overflowing.

Apply the same shape to DriverPodScreen (L1847-1867) — the `TextField(... maxLines: 3)` at L1857 is the item most likely to push past the edge at large text scale.

Whichever option is taken, verify against text scale, not just device height: the defect reproduces far more reliably on a 360x640 device with the system font size raised than at 1.0 scale, and that is the realistic configuration for this user group. Neither option can be confirmed without a run; the absence of a scroll view can.

*Needs a device to confirm.*


**HIGH — Publishing a lane requires hand-typing ISO-8601 timestamps into fields labelled with API field names**  
`apps/driver_pilot/lib/driver_flow.dart:2226` · form-ux  

*What goes wrong:* Publishing an anchor lane is the core carrier task, and the only way to change the pickup window is to edit an ISO-8601 string by hand on a phone QWERTY keyboard. "windowStart" and "ISO" mean nothing to a truck driver. A malformed edit is sent to the API unchecked, and comes back as a raw HTTP error. In practice the driver's only safe move is the "Reset pickup window (today–tomorrow, IST)" button at L2200-2204, which means the window cannot really be set at all.

*Fix:* The direction (replace both TextFields with a date-range picker) is right, but the proposed wiring would write incorrect timestamps and cannot produce the labels it describes.

1. Do not pass `showDateRangePicker` output into `formatIstIsoFromUtc` directly. That function (pilot_api.dart:127-128) takes a UTC instant and *adds* 5h30m: `final ist = utc.add(const Duration(hours: 5, minutes: 30));`. The picker returns local, non-UTC `DateTime`s at midnight, so feeding them straight in shifts the window forward by 5.5 hours. Follow the pattern `defaultAnchorTripWindow` already uses at pilot_api.dart:141: build the instant as `DateTime.utc(year, month, day).subtract(const Duration(hours: 5, minutes: 30))` from the picked `DateTimeRange.start` calendar fields, then format.

2. The end of the window must be end-of-day. `defaultAnchorTripWindow` line 143 does this deliberately: `DateTime.utc(y, m, d + 2).subtract(const Duration(hours: 5, minutes: 30)).subtract(const Duration(seconds: 1))` — 23:59:59 of the closing day. Writing the picked end date as plain midnight truncates the final day of the lane to zero, which on a money path means a customer cannot book on the day the carrier thinks is open. Compute the end as `DateTime.utc(end.year, end.month, end.day + 1).subtract(const Duration(hours: 5, minutes: 30)).subtract(const Duration(seconds: 1))`.

3. `formatTripWindowRange` cannot label two separate buttons. It returns one combined string (pilot_api.dart:251-255: `return "$a – $b";`, collapsing to a single date when `a == b`), and its `dayMonth` helper is a private closure inside it, not reachable. Either render one button showing the whole range via `formatTripWindowRange(_w1.text, _w2.text)` under a single label "Pickup window", or lift `dayMonth` to a top-level `String formatWindowDay(String? iso)` in pilot_api.dart and call it per button.

Recommended shape: one full-width `OutlinedButton.icon` with `Icons.date_range`, label `"Pickup window: ${formatTripWindowRange(_w1.text, _w2.text)}"`, opening `showDateRangePicker` with `firstDate: today` and `lastDate: today + 90 days`, writing both controllers in `setState` through the corrected conversions above. Keep the L2200-2204 reset button as the secondary action, but move it below the picker so the primary control reads first. The controllers and the L2169-2170 payload stay unchanged, as the finding says.

One addition the finding misses: main.dart:1134-1135 is the developer lab and is staying, so leave those two TextFields as they are — a lab screen labelled with API field names is correct for its audience. Only driver_flow.dart:2226-2227 should change.


**HIGH — Vehicle class is a free-text field for a three-value enum, unvalidated on the registration screen**  
`apps/driver_pilot/lib/driver_flow.dart:461` · form-ux  

*What goes wrong:* A driver with a small truck must edit this field, and anything other than the three exact tokens fails. "Small truck", "7 ton", "mini" all pass client-side on the registration screen and kill the whole registration POST with a raw error that does not say which of the six fields was wrong. The label itself leaks the API's pipe-delimited enum to the user. Where validation does exist, the message is written in API terms: L1322 "vehicleClass must be SMALL, MEDIUM, or LARGE." and L2158 the same.

*Fix:* The fix is sound in direction but breaks the profile screen as written, and one severity-supporting claim should be softened.

1. Profile screen seeding. driver_flow.dart:1299 does `_vehClass.text = DriverSession.vehicleClass ?? "MEDIUM";`. DropdownButtonFormField asserts its `value` matches zero or one item, so assigning an unexpected server token straight into `String _vehicleClass` would throw during build instead of merely displaying oddly. Seed defensively:
   `const vehicleClasses = {"SMALL", "MEDIUM", "LARGE"};`
   `_vehicleClass = vehicleClasses.contains(DriverSession.vehicleClass) ? DriverSession.vehicleClass! : "MEDIUM";`
   Same guard anywhere else a dropdown value comes from the API.

2. Keep, do not delete, the two existing validation blocks' intent at the API boundary. Deleting the client-side blocks at 1321 and 2157 is fine once the widget cannot produce an invalid value, but nothing then stops a future caller passing a bad token; if the team wants belt-and-braces, replace them with the same `vehicleClasses.contains(...)` set rather than three inline string comparisons.

3. Copy. Use `labelText: "Vehicle class"` on all four, with items rendered via `vehicleClassLabel` (pilot_api.dart:180) so the driver reads "Small truck" / "Medium truck" / "Large truck". Note the publish screen's label at 2228 is `"vehicleClass (SMALL|MEDIUM|LARGE)"` (camelCase API name, not the "Vehicle class" spelling the other three use) and its neighbours at 2226-2227 and 2229 are `"windowStart (ISO)"`, `"windowEnd (ISO)"`, `"capacityKg"` — that whole screen is written in API terms, which is a separate finding, not this one.

4. Evidence wording. "a raw error that does not say which of the six fields was wrong" overstates what the source proves. pilot_api.dart:74 returns `"HTTP ${status ?? "?"}: ${body ?? e.message ?? e.toString()}"`, so the user sees a raw status-plus-body dump; whether that body names the field is server-side and was not checked. Phrase it as "surfaces a raw HTTP status and response-body dump" and drop the claim about the six fields.


**MEDIUM — "Challenge id" is an editable input in the driver sign-in path**  
`apps/driver_pilot/lib/driver_flow.dart:363` · form-ux  

*What goes wrong:* The verify screen shows a driver two fields when there is one thing to do. The first holds an opaque internal id they did not choose, cannot interpret and have no reason to touch — but can edit or clear, after which "Verify" fails with an error that mentions nothing about it. It also makes the screen read as unfinished software at the exact moment the user is deciding whether to trust the app with their carrier account.

*Fix:* The fix is sound in shape; two adjustments before implementing.

1. The trim must go, and a null guard must replace it. Swapping `TextEditingController` for `String? _challengeId` means :302 becomes `if (id != null) _challengeId = id;` and :320 becomes `"challengeId": _challengeId,` — dropping `.text.trim()`, since the value is already a server-issued string. But that changes the failure mode: today a failed `_resend()` leaves the field empty and sends `""`; with a nullable field it would send `null`. So disable the Verify button until the id has arrived — change :367 from `onPressed: _verifying ? null : _verify` to `onPressed: (_verifying || _challengeId == null) ? null : _verify`, and show `Text("Could not send the code. Tap Resend code to try again.")` when `_challengeId == null && !_starting`, so a driver whose `/otp/start` failed sees a recoverable state rather than a dead button.

2. The route-passing clause overstates the dependency. `challengeId` is obtained inside this screen at :301-302, so deleting the field needs no route change at all — this fix stands alone and can ship independently of the double-SMS finding. Route-passing only becomes necessary if that other fix removes the `_resend()` call in `didChangeDependencies` (:288-295), which is where the id currently comes from. Implement them in that order — delete the field first, then change where the id originates — or the second change silently strips the only source of the value.

Leave main.dart:571 alone. It is inside the developer lab, which the product owner has kept, and an operator pasting a challengeId by hand is the actual job of that screen.


**MEDIUM — Driver OTP code field has no numeric keyboard, no length limit and no SMS autofill, while the customer one in the same binary does**  
`apps/driver_pilot/lib/driver_flow.dart:364` · form-ux  

*What goes wrong:* Tapping the code field raises a full QWERTY keyboard, so the driver has to find the number row or switch modes to type six digits, one-handed, while the SMS notification is still on screen. Nothing stops a seventh character. Android's SMS code autofill never offers the code because the field does not declare `oneTimeCode`, so the driver has to memorise or copy it manually. The customer flow gets the better treatment on the same screen concept.

*Fix:* The fix is directionally right but will not compile as written, and one of its rationales is wrong. Corrected version:

1. Add the missing import. `FilteringTextInputFormatter` lives in `package:flutter/services.dart`, and driver_flow.dart imports only `dart:async`, `package:flutter/material.dart`, geolocator, go_router, google_maps_flutter and the six local files (lines 1-13). Add `import "package:flutter/services.dart";` in the package import block, double quotes to match the file's existing style.

2. Replace driver_flow.dart:364 with:
```dart
TextField(
  controller: _code,
  decoration: const InputDecoration(labelText: "6-digit code", counterText: ""),
  keyboardType: TextInputType.number,
  maxLength: 6,
  autofillHints: const [AutofillHints.oneTimeCode],
  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
  textInputAction: TextInputAction.done,
  autofocus: true,
  onSubmitted: (_) { if (!_verifying) _verify(); },
),
```
and wrap the ListView at driver_flow.dart:352 in an `AutofillGroup` so the hint is actually active.

3. Correct the autofocus rationale in the write-up. It is not "the only thing to do on the screen" — driver_flow.dart:363 renders a "Challenge id" TextField directly above it. The real reason autofocus belongs on the code field is that the challenge id is filled programmatically by _resend() (driver_flow.dart:301) and the driver should never have to touch it, so the code field is the only field the driver types into.

4. Apply the same change to customer_flow.dart:448-453 rather than leaving it behind, otherwise the inconsistency just flips direction. In particular, the driver field would gain `counterText: ""` while the customer field keeps showing a "0/6" counter under it. Either give both `counterText: ""` or give neither; do not ship the two differing.

5. One thing to check before shipping, not assume: that the backend OTP is always exactly 6 digits and always numeric. `maxLength: 6` plus `digitsOnly` makes a longer or alphanumeric code untypeable, which turns a cosmetic gap into a hard block on login. The label at line 364 already asserts 6 digits and the debug prefill path at driver_flow.dart:304-306 writes the server's debugCode straight into _code, so confirm against the /v1/auth/otp/start implementation. I did not verify the server side.


**MEDIUM — No form in the app sets textInputAction, so multi-field forms need a tap per field**  
`apps/driver_pilot/lib/driver_flow.dart:457` · form-ux  

*What goes wrong:* On registration the driver types a value, sees a keyboard "return" key that does nothing useful, dismisses or ignores it, hunts for the next field under the keyboard, taps it, and repeats six times. On a mid-range phone in a vehicle that is where people abandon a signup. The keyboard also never advances focus, so there is no way to complete the form without lifting the thumb between every field.

*Fix:* The fix is real but overbuilt, and it will not compile as written on two of the four screens.

Two concrete defects in the proposed fix:

1. The per-field `FocusNode` plus `onSubmitted: (_) => FocusScope.of(context).requestFocus(_nextNode)` plumbing is unnecessary. Flutter's `EditableText._finalizeEditing` already calls `widget.focusNode.nextFocus()` when the action is `TextInputAction.next` and no `onEditingComplete` is supplied. Setting `textInputAction: TextInputAction.next` alone advances focus through the default traversal order. The FocusNode version adds six fields to declare, six to `dispose()`, and a `context`-capturing closure per field, for behaviour the framework gives free — and it is exactly the unearned complexity the house rules reject.

2. The FocusNode version is actively wrong on DriverFleetInviteScreen. The field after `_phone` (L645) is a `DropdownButtonFormField` (L646), not a text field, and `_reg`/`_vehClass`/`_cap` (L664-666) are inside an `if (_role == "DISPATCHER") ... else ...` branch (L657, L663). A hardcoded `requestFocus(_nextNode)` chain targets nodes whose widgets are not mounted when the role is DISPATCHER. `TextInputAction.next` degrades correctly here because traversal resolves against the tree that actually exists.

Corrected fix — add one parameter per field, nothing else:

- driver_flow.dart:457-461: add `textInputAction: TextInputAction.next`. L462 (`_cap`, the last field): `textInputAction: TextInputAction.done` and `onSubmitted: (_) { if (!_busy) _submit(); }`.
- Payout setup L2022-2023: `TextInputAction.next`. L2024-2031 (`_accountNumber`, last): `TextInputAction.done`, `onSubmitted: (_) { if (!_busy) _save(); }` — the method is `_save` (L2034), not `_submit`.
- Fleet invite L645 (`_phone`) and L664-665: `TextInputAction.next`. L666 (`_cap`, last): `TextInputAction.done`, `onSubmitted: (_) { if (!_inviting) _invite(); }` — the busy flag is `_inviting` (L672) and the method `_invite`, so the finding's `if (!_busy) _submit()` does not compile here. When `_role == "DISPATCHER"` only `_phone` renders, so give it `next` regardless and let traversal land wherever the tree allows.
- Publish L2226-2228: `TextInputAction.next`. L2229 (`_cap`, last): `TextInputAction.done`, `onSubmitted: (_) { if (!_submitting) _submit(); }` — the busy flag is `_submitting` (L2236), not `_busy`.

Keep `_notes` at L1857 (`maxLines: 3`) on `TextInputAction.newline`; a multi-line notes field should keep its newline key.

While editing these screens, note that a related gap sits on the same lines and is cheaper to close in the same pass than later: none of these fields set `autofillHints`, so the phone field at 458 and the name field at 457 get no platform autofill. That is a separate finding, not part of this fix.


### Accessibility

10 findings, 4 high.


**HIGH — The muted token fails AA on the app background, and it is the colour of nearly all body text**  
`lib/driver_theme.dart:8` · contrast  

*What goes wrong:* I computed #64748B on #F4F7FA = 4.43:1, against the 4.5:1 floor for normal text (WCAG 1.4.3). It is a near miss on paper and a real one in a truck cab: this token carries the sentence that explains what the POD button is about to do (driver_flow.dart:1853, "Ops will release customer payment to your carrier ledger after review") and the one that explains the payout screen (driver_flow.dart:2018). On white Cards the same token measures 4.76:1 and does pass, so the text gets legibly darker when it happens to sit on a card and lighter when it sits on the page — the driver has no way to predict which. In direct sunlight on a mid-range panel the 4.43:1 lines are the first to disappear.

*Fix:* The token change is sound as written and needs no alteration: driver_theme.dart:8 becomes `static const Color muted = Color(0xFF5B6B82);`. I confirmed 5.05:1 on #F4F7FA and 5.43:1 on #FFFFFF. No call-site edits are required, and every other consumer of the token improves rather than regresses — the `Icon(Icons.search, size: 20, color: DriverTheme.muted)` at driver_flow.dart:1013 and the unselected NavigationBar label and icon at driver_theme.dart:64 and :70 all get darker.

Two corrections to the rest of the fix:

1. Drop driver_flow.dart:1149 from the font-size remedy. It is inside the `Card` at driver_flow.dart:1121 on `Colors.white` (driver_theme.dart:45) at 4.76:1, so it is not the lowest-contrast text and bumping it to 12 is an unrelated change. If the eleven-pixel window timestamp is worth enlarging on legibility grounds for a driver holding the phone one-handed in a cab, raise it on that reasoning and say so — but it does not belong under a contrast finding. Replace it with customer_flow.dart:109, which is the genuine case: 11px muted inside the `AppBar` at customer_flow.dart:103, which has no `backgroundColor` and therefore inherits driver_theme.dart:16 `backgroundColor: background` — 11px at 4.43:1. Raise that to 12 and, for the 4 muted sites among the five, keep the token fix as the thing that does the contrast work.

2. Add a check the original fix omits. Darkening `muted` narrows the gap between the unselected NavigationBar label (driver_theme.dart:64 `return const TextStyle(color: muted, fontSize: 11);`) and the selected one (driver_theme.dart:62, `color: navy, fontWeight: FontWeight.w600`). The distinction survives on weight and on the `indicatorColor: navy.withOpacity(0.12)` pill at driver_theme.dart:59, so no change is needed — but confirm it visually once Flutter is available rather than assuming, because selected-state legibility in a nav bar is exactly the kind of thing a token change degrades quietly.


**HIGH — Every error message in both flows uses Colors.red, which fails AA on both surfaces**  
`lib/driver_flow.dart:1681` · contrast  

*What goes wrong:* `Colors.red` is #F44336. I computed 3.42:1 on the #F4F7FA page and 3.68:1 on a white Card, both under the 4.5:1 floor. This is the colour of the only text that tells a carrier why a booking would not accept (driver_flow.dart:755), why a trip would not publish (driver_flow.dart:2232), and what went wrong on the active trip (driver_flow.dart:1681) — the messages a driver most needs to read and act on, rendered in the least readable colour in the app. The legacy pilot-lab screens actually get this right (main.dart:704 uses `Theme.of(context).colorScheme.error`, which resolves to the M3 default #B3261E at 6.54:1 on white), so the newer driver and customer flows regressed against the older code.

*Fix:* The fix is sound and compiles as written — `static const Color danger` keeps every `const TextStyle(color: DriverTheme.danger)` const, so no site loses its const constructor. Three corrections before it is implemented:

1. Count and threshold. 20 of the 21 sites are text at 4.5:1. The 21st, customer_flow.dart:1037 `icon: const Icon(Icons.delete_outline, color: Colors.red),` is a non-text UI component, judged against the 3:1 floor, which #F44336 already clears at 3.68:1 on white. Change it for token consistency, but do not report it as a contrast failure — one wrong item in the list gives the owner a reason to doubt the other twenty.

2. Do not leave two error colours in the codebase. The finding correctly notes main.dart:704, 808 and 1106 use `Theme.of(context).colorScheme.error`. Adding a literal `danger` token without touching those keeps two sources of truth, just with the roles swapped. Either change those three to `DriverTheme.danger` in the same commit, or define the token from the scheme instead of a literal. Pick one and apply it to all 24 sites.

3. The "same red as fromSeed" rationale is unverified — do not put it in the commit message as fact. With Flutter unavailable, nobody has confirmed what `ColorScheme.fromSeed(seedColor: Color(0xFF122C53))` resolves error to on the Flutter version this pubspec allows. Hardcoding `Color(0xFFB3261E)` is still the right call because its contrast is arithmetic and holds regardless, but justify it as "M3 error reference tone, 6.08:1 on #F4F7FA and 6.54:1 on #FFFFFF" rather than as "matches what the scheme already produces." Confirm the scheme value on a machine with Flutter before claiming the app now has one red.

One addition the finding does not cover and should, since these are money-path screens: colour is currently the only thing marking these strings as errors, which fails WCAG 1.4.1 independently of the ratio. When touching all 24 sites anyway, wrap the error text in a small shared widget that pairs `DriverTheme.danger` with a leading `Icon(Icons.error_outline, size: 18, color: DriverTheme.danger)` and a `Semantics(liveRegion: true)`, so the message is announced and is still identifiable to a driver in sunlight or with a red-green colour deficiency. That is one widget, not an abstraction layer, and it removes 24 copies of the same TextStyle.


**HIGH — Text input boundaries are drawn at 1.23:1, far below the 3:1 required for control boundaries**  
`lib/driver_theme.dart:41` · contrast  

*What goes wrong:* I computed #E2E8F0 against the white fill at 1.23:1 and against the #F4F7FA page at 1.15:1 — and the white fill itself is only 1.08:1 against the page. WCAG 1.4.11 Non-text Contrast requires 3:1 for the visual boundary that identifies a control, and a text input's outline is the canonical example in the Understanding document. The practical result is that an unfocused, empty text field is a barely-tinted rectangle: on the payout screen the driver is asked to type a bank account number into a box whose edge is three times below the legibility floor, and there is nothing else on that screen marking where the field starts. Anyone with reduced contrast sensitivity, and anyone holding the phone in sunlight, is guessing where to tap.

*Fix:* The token split and the #7E8A9C value are right — keep both. Fix the carve-out, which calls two control boundaries decorative.

Add to driver_theme.dart alongside line 7:

    static const Color controlBorder = Color(0xFF7E8A9C);

Use it in the `enabledBorder` borderSide at line 41, and add the explicit focus ring in the same block so the radius and width are not left to a fallback:

    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: controlBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: navy, width: 2),
    ),

Three corrections to what the finding said to leave alone:

1. Line 31 is NOT a decorative hairline. It is `side: const BorderSide(color: border)` inside `outlinedButtonTheme` (lines 28-34), and it draws the boundary of all 25 OutlinedButtons in the app (main.dart 8, customer_flow.dart 10, driver_flow.dart 7) — including driver_flow.dart:667 `OutlinedButton(onPressed: () => context.push("/driver/onboarding/join"), child: const Text("New driver? Register account first"))`. That outline is the only thing separating an outlined button from a text button. Either move line 31 to `controlBorder` too, or decide deliberately that the navy label identifies the button and write that decision down — but do not file it under "card hairline".

2. Line 53 is NOT a chip hairline either. `chipTheme`'s `side: const BorderSide(color: border)` is inherited by the interactive FilterChips at driver_flow.dart:1032 and 1057 (`selected: active, onSelected: (_) => setState(...)`, vehicle-class and trip-status filters). chipTheme sets no `backgroundColor`, so an unselected chip on the #F4F7FA page is an #E2E8F0 outline at 1.15:1 — worse than the text fields, and this one is a state indicator, which 1.4.11 covers explicitly. Point line 53 at `controlBorder` as well. Line 1114-1118's non-interactive `Chip(...)` widgets share the same theme, so they get the darker outline too; that is acceptable, and if it reads as heavy, give the static chips a local `side` rather than weakening the token.

3. Line 49 (`cardTheme` side) is the only one of the three that genuinely stays on `border`. Keep it.

Net: `border` retains one consumer (line 49), `controlBorder` takes lines 31, 41 and 53, plus the new focusedBorder. Name the two tokens for what they mean, not what they are — `border`/`controlBorder` is acceptable, but `cardHairline`/`controlBorder` reads better and makes the misclassification impossible to repeat.

Report-copy fix: replace "there is nothing else on that screen marking where the field starts" with "the field's extent is marked only by a 1.08:1 fill and a 1.23:1 outline; the labelText is legible but does not delineate where the input begins or ends." And do not assert anything about the current focus ring's appearance — Flutter is not installed and the M3 fallback was not verified.


**HIGH — Four driver screens put the submit button after a Spacer in a non-scrolling Column, so it is clipped at large font sizes**  
`lib/driver_flow.dart:2032` · text-scaling  

*What goes wrong:* `Spacer` is `Expanded(child: SizedBox.shrink())`. In a bounded Column, Expanded receives whatever height is left after the inflexible children; when those already exceed the box it gets zero and the Column overflows, and the overflow is clipped at the bottom — which is exactly where the submit button is. Two everyday conditions trigger it. First, opening the keyboard: `resizeToAvoidBottomInset` defaults to true, so tapping the bank-account field on the payout screen removes roughly 40% of the body height while three fields and a paragraph are still laid out above the button. Second, an Android system font scale above about 1.5, which is a setting drivers with presbyopia actually use. When it clips there is no scroll view to reach the button, so the task is not merely hard, it is impossible — on the screen where a carrier enters the bank details they get paid into, and on the POD screen that releases payment. This is WCAG 1.4.4, loss of functionality on resize, not just loss of polish. The exact scale and device where it first clips needs a real handset; the clipping mechanism itself follows from Flutter's Column layout rule and is not in doubt.

*Fix:* Two corrections, one to the stated mechanism and one to the fix, which is not implementable as written.

MECHANISM. "the overflow is clipped at the bottom" is imprecise. Flutter's Flex defaults to `clipBehavior: Clip.none`, and this file sets no clipBehavior anywhere, so RenderFlex paints the overflowing children rather than clipping them. The button is therefore laid out below the Column's own bounds: it is painted over by the Scaffold's bottomNavigationBar (DriverShell passes showBottomNav default true, driver_flow.dart:42 and 118), or it falls off the physical screen. Either way it is also untappable, because RenderBox.hitTest rejects a position outside the parent's size before it ever reaches the child. The user-facing consequence the finding describes — button unreachable, no scroll to recover it — is unchanged, so the severity stands. Only the word "clipped" should change to "laid out past the Column's bounds, painted under the navigation bar or off-screen, and not hit-testable."

FIX, PART ONE. Replacing `Padding(child: Column(...))` with `ListView(padding: const EdgeInsets.all(20), children: [...])` and deleting the Spacer does solve the overflow, but it silently changes the design: the action stops being bottom-anchored and rides up under the content. That is probably acceptable on the payout and POD screens; on DriverWelcomeScreen the Spacer at 171 is the only thing separating a two-line paragraph from a five-button stack, and top-aligning it leaves a large void below. Where the bottom anchor should survive, use the scroll-with-minimum-height idiom instead: `LayoutBuilder(builder: (context, constraints) => SingleChildScrollView(padding: const EdgeInsets.all(20), child: ConstrainedBox(constraints: BoxConstraints(minHeight: constraints.maxHeight - 40), child: IntrinsicHeight(child: Column(...)))))`, keeping the Spacer. Note that a bare Spacer inside a SingleChildScrollView throws, because Expanded in an unbounded Column is an error — the IntrinsicHeight is what makes it legal, and it must not be dropped.

FIX, PART TWO — this part is wrong as written. "move the FilledButton into the Scaffold's `bottomNavigationBar` slot" cannot be done from these screens. None of the four owns a Scaffold; they are the `child` handed to DriverShell (2262-2266), and DriverShell's Scaffold has already filled `bottomNavigationBar` with the five-tab NavigationBar (driver_flow.dart:118-145). `persistentFooterButtons` is likewise the shell's to give. Two workable routes: either pin the action inside the screen — `Column(children: [Expanded(child: ListView(padding: const EdgeInsets.all(20), children: [fields])), SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 12), child: FilledButton(...)))])`, which needs no shell change and sits above the navigation bar — or add a `Widget? bottomAction` parameter to DriverShell and have the shell compose it above the NavigationBar, which touches the shell and every route that uses it. Prefer the first; it is contained to the four files under discussion. Also drop the claim that the bottomNavigationBar slot "rides above the keyboard": I did not verify Scaffold's inset handling for that slot and it should not be stated as fact.


**MEDIUM — The driver app bar back button has no accessible name**  
`lib/driver_flow.dart:103` · accessibility  

*What goes wrong:* IconButton derives its accessible name from `tooltip`; with none, and with a bare `Icon` that has no `semanticLabel`, TalkBack announces the control as an unlabelled button. This is the back affordance on every pushed driver route — active trip, POD, earnings, payout setup, payout history, fleet invite — so a driver using TalkBack has no spoken name for the only way out of those screens. It is also the single miss in an otherwise consistent codebase, which makes it cheap to close. Note this is the opposite of the case the brief flagged: the "Switch to driver" button at customer_flow.dart:119-125 is correctly labelled.

*Fix:* Replace the whole `IconButton(...)` at driver_flow.dart:103-106 with `BackButton(onPressed: () => context.pop())`. BackButton pulls its tooltip from `MaterialLocalizations.of(context).backButtonTooltip`, so it is labelled and will translate for free when localisation is added. If the explicit IconButton is preferred, add `tooltip: "Back"` as the first argument.


**MEDIUM — The empty-map message on the driver active-trip screen is 4.23:1 and carries its own off-palette greys**  
`lib/location_editor.dart:212` · contrast  

*What goes wrong:* I computed #757575 on #F5F5F5 at 4.23:1, under the 4.5:1 floor for 13px text. This block is not decorative: it is the only explanation the driver gets for why the map on the live-trip screen is blank, and it contains the two actions that would fix it (allow location, or republish with pins). It also introduces #F5F5F5, #E0E0E0 and #757575 — three greys that exist nowhere in DriverTheme — so the panel reads as a different product, and its border sits at 1.21:1 against its own fill.

*Fix:* The finding stands, but the fix as written is incomplete and carries a false dependency.

1. MISSING IMPORT. location_editor.dart does not import driver_theme.dart. Its imports are dart:math, package:flutter/material.dart, package:google_maps_flutter, google_geocoding.dart and maps_config.dart (lines 1-7). Referencing DriverTheme.border and DriverTheme.muted will not compile without adding `import "driver_theme.dart";`. This is safe: location_editor.dart is imported by driver_flow.dart, customer_flow.dart and main.dart, and all three already import driver_theme.dart, so DriverTheme is not a driver-only dependency being dragged into shared code.

2. DROP THE FALSE DEPENDENCY. The fix says the ratio only works "once muted is corrected to #5B6B82 per the first finding". That is wrong and could cause an implementer to defer this edit behind another one. DriverTheme.muted as it stands today (#64748B) on white computes to 4.759:1 - already clear of the 4.5:1 floor for 13px text. The fix is correct and shippable standalone, on the current token.

3. THE BORDER COMPLAINT IS NOT ACTUALLY FIXED, AND DOES NOT NEED TO BE. The finding criticises the #E0E0E0 border sitting at 1.21:1 against its own fill, but its own remedy lands DriverTheme.border #E2E8F0 on white at 1.233:1 - the same place. That is fine: a container hairline is decorative, not a UI component conveying state, so WCAG 1.4.11's 3:1 floor does not apply. But the border sentence should be reframed as a palette-consistency point only, not a contrast failure, or the implementer will try to solve a non-problem by darkening the border and end up off-palette again.

Corrected edit, at location_editor.dart:201, 203, 212, plus the import:
  color: Colors.white,
  border: Border.all(color: DriverTheme.border),
  style: const TextStyle(color: DriverTheme.muted, fontSize: 13),
giving 4.76:1 for the text on white today. White fill is the right choice rather than DriverTheme.background, because it matches the existing cardTheme (Colors.white with a BorderSide(color: border), driver_theme.dart:44-51) and the panel sits on the #F4F7FA scaffold, so it reads as a card rather than dissolving into the page.


**MEDIUM — Shipment timeline step state is conveyed only by icon glyph, with no text or semantic equivalent**  
`lib/customer_flow.dart:2126` · accessibility  

*What goes wrong:* A screen-reader user hears "Carrier accepted. Carrier confirmed they will carry your load" whether that step has happened or not, and the same for all five steps — so the entire tracking timeline reads as if every stage is already done. The visual affordance is fine (three distinct glyph shapes, not just colour, so 1.4.1 is satisfied for sighted users), but there is no text alternative for the state, which is WCAG 1.3.1. This is the customer web tracking page, so it is not on the Android driver path, but it is the screen a customer opens to find out where their freight is.

*Fix:* Wrap the Row at customer_flow.dart:2122 in `Semantics(container: true, excludeSemantics: true, label: "${steps[i].label}. ${steps[i].complete ? 'Done' : steps[i].current ? 'In progress' : 'Not started'}. ${steps[i].subtitle}", child: Row(...))`. Adding `semanticLabel` to the Icon alone would work too but reads worse, because the state would be announced before the step name.


**MEDIUM — Field validation errors exist only as transient SnackBars and are never attached to the field**  
`lib/driver_flow.dart:228` · error-state  

*What goes wrong:* The message names a rule ("10 digits") but never points at the field, and a SnackBar auto-dismisses after about four seconds. A driver who looks away mid-message has lost the only error text on screen, with no way to bring it back and nothing marking which of the six fields on the register screen was wrong. Flutter's SnackBar is a live region so TalkBack does announce it, but when the user then swipes back through the form the field reports itself as valid — the error is not programmatically associated with the input it belongs to (WCAG 3.3.1). The payout screen is the sharpest case: `_save` at driver_flow.dart:1984 validates nothing at all client-side, so an empty IFSC or account-holder name is posted and the driver only learns what was wrong from whatever the server returns into a SnackBar.

*Fix:* The finding stands and the fix is directionally right, but two things need correcting before it is implemented.

1. The title's "exist only as transient SnackBars" is overbroad for the app as a whole, and the fix is incomplete because of it. A persistent screen-level error pattern already exists in this codebase: `String? _error` plus `Text(_error!, style: const TextStyle(color: Colors.red))`. It appears on at least seven screens — declared at driver_flow.dart:559, 697, 882, 1210, 1435, 2119 and customer_flow.dart:327, rendered at driver_flow.dart:642, 679, 755, 1071, 1257, 1681, 2232. The most pointed case is that the exact same validation rule is implemented both ways: driver_flow.dart:416 raises "Enter a positive vehicle capacity." as a SnackBar, while driver_flow.dart:2153 raises "capacityKg must be a positive number." as a persistent `_error`; and "Enter a 10-digit mobile number." is a SnackBar at driver_flow.dart:228 but a persistent `_error` at customer_flow.dart:352. So the real defect is three competing error surfaces (SnackBar, screen-level red Text, nothing at all on the payout screen), and the fix must say which one wins app-wide, not just convert six call sites. Otherwise the codebase ends up with four patterns instead of three.

Also note the existing red Text uses raw `Colors.red`, and driver_theme.dart has no error token. Whichever pattern wins, add an error colour token to DriverTheme and point both `errorText` and any remaining screen-level Text at it, or the inline errors will be unthemed and their contrast on #F4F7FA is unverified.

2. Drop the claim that `errorText` gives "the correct SemanticsProperties association for free." I cannot verify that from source here and have reason to doubt it: Flutter's `InputDecorator` renders error text as a sibling node in the decoration subtree rather than binding it to the editable the way `aria-describedby` and `aria-invalid` do, and on Flutter web that mapping is a known gap. Treat it as unchecked. The WCAG 3.3.1 benefit that does survive is the part that needs no runtime evidence: the message becomes persistent and is positioned under the field it belongs to, so it is still on screen when the driver looks back. If the a11y association matters, it has to be built explicitly — wrap the field in `Semantics(label: ..., hint: _phoneError)` or equivalent — and then tested on a real TalkBack device, which nobody has done.

Two additions worth folding in while the files are open:

3. Fix the payout screen as its own change, not as a sixth conversion. driver_flow.dart:1984 `_save()` currently posts unconditionally. Add checks before the `api.post`: account holder name non-empty; IFSC non-empty and matching the standard Indian format `^[A-Z]{4}0[A-Z0-9]{6}$` (four letters, a zero, six alphanumerics) with the input upper-cased first, the same way `_saveVehicle` upper-cases vehicleClass at driver_flow.dart:1315. Set `_ifscError` / `_nameError` in state rather than posting. This is the money path — a payout row written against an empty IFSC is a failed weekly transfer the driver learns about days later — and on its own it is high, not medium.

4. The account number field at driver_flow.dart:2026-2030 carries `helperText: "Required to receive real transfers"` while `_save` treats it as optional (`if (acct.isNotEmpty)`). Copy and behaviour disagree. Either enforce it or change the helper to "Needed before your first transfer; you can add it later." Decide this at the same time as the validation, since both land in the same `_save`.

Keep the SnackBar at driver_flow.dart:237 and the other `formatApiError(e)` sites as they are — those have no owning field and the finding is right to exempt them.


**LOW — A navy disc sits in the app bar action slot with no label, no role and no action**  
`lib/driver_flow.dart:113` · accessibility  

*What goes wrong:* This renders a 36dp solid navy circle in the position every Android user reads as the account or profile control, on every driver screen. It has no semantics node, so a screen-reader user never encounters it — which is correct for decoration — but a sighted driver will tap it and nothing happens, with no feedback explaining why. It is a dead target sitting in the highest-value slot in the app bar, and it duplicates the Profile destination already in the bottom nav (driver_flow.dart:142).

*Fix:* Prefer the deletion branch, and reword the scope. Primary fix: delete driver_flow.dart:111-114 outright, leaving `actions: [if (actions != null) ...actions!],`. Profile is already a labelled bottom-nav destination at :142, the shell's `actions` parameter is never populated by the only caller (:2262-2266) so nothing else depends on the list being non-empty, and removing a dead 36-pixel target from the highest-value app-bar slot costs a one-handed driver in sunlight nothing. The proposed IconButton alternative must not be implemented as written: `DriverSession.userFullName` is `static String?` (driver_session.dart:8), set only inside `DriverSession.refresh()` (driver_session.dart:30), so it is null before sign-in, and it is a bare static with no Listenable while `DriverShell` is a StatelessWidget — the initial would render blank pre-sign-in and would not repaint when refresh() completes. If a profile affordance in the app bar is wanted anyway, it needs all three of: a non-null fallback (`Icon(Icons.person_outline, color: Colors.white, size: 18)` when userFullName is null or empty), a text colour set explicitly to `Colors.white` on navy for AA contrast since CircleAvatar with a colour-only background applies no foreground token, and a rebuild trigger — make the session a `ValueNotifier<String?>` and wrap the avatar in a `ValueListenableBuilder` — otherwise the initial is stale. Also fix the finding's scope line to "every in-shell driver screen": the four onboarding routes at driver_flow.dart:2301-2304 sit outside the ShellRoute and never show this AppBar.


**LOW — The bottom-nav selection indicator is drawn at 1.25:1 against the nav bar**  
`lib/driver_theme.dart:59` · contrast  

*What goes wrong:* I computed #E3E6EB on #FFFFFF at 1.25:1, so the selection pill is very nearly invisible and will be fully invisible in sunlight. This does not fail WCAG 1.4.11, because selection is redundantly carried by two cues that do pass: the selected icon switches from outlined to filled (driver_flow.dart:126-142, e.g. `Icons.home_outlined` to `Icons.home`) and the label goes navy w600 against muted (driver_theme.dart:60-71), which I measured at 12.93:1 against the white bar. So the state is identifiable — the pill just contributes nothing, and a driver glancing down at the bar in daylight is relying entirely on the icon fill difference. Recording it because bright-sunlight use is the stated context, not because it blocks anyone.

*Fix:* The diagnosis is right but `withOpacity(0.22)` does not fix it. I computed the composite: 0.22 navy over white is #CBD1D9, not the "roughly #CFD4DC" claimed, and it measures 1.54:1 against the white bar — nowhere near "the 3:1 region". It would leave the pill still contributing nothing, after a commit spent on it. Measured ladder for navy #122C53 over white: 0.12 -> #E3E6EA 1.25:1; 0.22 -> #CBD1D9 1.54:1; 0.30 -> #B8C0CB 1.84:1; 0.40 -> #A0ABBA 2.33:1; 0.50 -> #8896A9 3.01:1. So pick one of two honest options. (a) Leave the opacity alone and close this as won't-fix: selection is already carried at 13.90:1 by the label and by the outlined-to-filled icon swap, so the pill is decoration and 1.4.11 is satisfied without it. (b) If the pill should actually carry state at 3:1 in sunlight, it needs about 0.50, not 0.22 — `indicatorColor: navy.withValues(alpha: 0.50)` giving #8896A9 at 3.01:1 against the bar. I checked the knock-on: the navy selected icon sitting on that pill is 4.62:1, still above AA, and the 11px label sits outside the M3 indicator so driver_theme.dart:62 is unaffected. Do not split the difference at 0.30-0.40; those land at 1.84:1 and 2.33:1 and buy a visibly grey pill that still misses the bar. Separately, replacing `withOpacity` with `withValues(alpha:)` is correct on the merits (withOpacity was deprecated in Flutter 3.27) but I could not verify it fires as a lint here: pubspec.yaml pins only `sdk: ">=3.3.0 <4.0.0"` with `flutter_lints: ^4.0.0`, and Flutter is not installed to check the resolved SDK. Treat the deprecation as a reason to touch the line, not as evidence the analyzer is currently complaining. Also drop "will be fully invisible in sunlight" from the write-up or mark it as unverified — nobody ran this on a device.


### The visual system

12 findings, 3 high.


**HIGH — Colors.red is the app's only error colour and fails WCAG AA on both surfaces, across all 21 error sites**  
`apps/driver_pilot/lib/driver_flow.dart:2232` · accessibility  

*What goes wrong:* Every failure message a driver or carrier sees is drawn in the app's least-legible colour. These are not cosmetic strings: driver_flow.dart:2232 is the publish-trip failure, 755 is the shipments-list load failure, 1681 is the active-trip failure on the screen that gates POD, and the payout and booking paths use the same construction. A carrier who cannot read why a publish or a payout-setup failed will retry blindly or call support, and on a mid-range Android outdoors a 3.4:1 red on a near-white page is the first thing to wash out.

*Fix:* The fix is sound and implementable as written; two refinements. First, the edit count is slightly mis-described: of the 21 Colors.red sites, 20 are the error-Text construction (7 driver_flow, 13 customer_flow) and one — customer_flow.dart:1037 `icon: const Icon(Icons.delete_outline, color: Colors.red)` — is an icon, not text. Replacing it with the same danger token is still right (#B3261E clears the 3:1 non-text floor comfortably at 6.54:1 on the white card), but it is a separate case, so the instruction is better phrased as "20 error-Text sites plus one destructive-action icon". Second, on `error: danger` in ColorScheme.fromSeed: the M3 default light error is already #B3261E, so the seeded scheme very likely resolves to the same value today and main.dart:704/808/1106 probably already pass AA. That does not make the override wrong — pinning it keeps the token and the scheme from drifting apart and makes the palette self-documenting — but it should not be sold as fixing the legacy lab, because the lab is probably not broken. Unchecked: I could not confirm what the seeded scheme resolves error to without running Flutter, which is not installed. Also note main.dart:1106 (`_rateError`) is a third scheme-error site the finding did not list; it needs no edit.


**HIGH — DriverTheme.muted is 4.43:1 on DriverTheme.background - the app's most-used text colour misses AA on the surface it is most often drawn on**  
`apps/driver_pilot/lib/driver_theme.dart:8` · accessibility  

*What goes wrong:* The miss is narrow but it lands on the app's default secondary-text colour, so a large share of every screen's explanatory copy is below the legibility floor - including driver_flow.dart:1854, the sentence on the POD screen that tells a carrier payment is released after ops review, and driver_flow.dart:2019 on payout setup. Several of these are additionally set at fontSize 11 and 12 (driver_flow.dart:1022, :1047, :1149), where a borderline ratio is least forgiving. The stated users are drivers reading one-handed in bright sunlight on mid-range screens, which is the worst case for a 4.43:1 grey.

*Fix:* The token change is sound -- darken it and keep the AA-on-background bar. Two corrections to the fix as written.

1. Drop driver_flow.dart:1149 from the evidence. That line sits inside the Card opened at driver_flow.dart:1121 (`return Card(`), whose colour is `Colors.white` per driver_theme.dart:45, so it renders at 4.76:1 and passes AA. The finding groups it with :1022 and :1047 as a small-size site where "a borderline ratio is least forgiving", but only those two are on #F4F7FA. Citing a passing site as failing is the kind of error that gets the whole finding waved off, and it is not needed -- :1022 and :1047 alone carry the fontSize-12-on-background point.

2. The fix says "one edit, all 61 call sites inherit it". Darkening the value is one edit, but the rename to `textSecondary` is 63 edits: the 61 call sites plus driver_theme.dart:64 and :70, which reference `muted` inside the theme itself. More important, those two lines are a behavioural side effect the fix does not handle. They set the NavigationBar's UNSELECTED label and icon colour, against `backgroundColor: Colors.white` at driver_theme.dart:58, while the selected state is `navy` (#122C53) at :62 and :68. Today the selected-versus-unselected colour separation is 2.92:1; swapping muted for #475569 collapses it to 1.83:1, so "which tab am I on" would lean almost entirely on the w600 weight and the `navy.withOpacity(0.12)` indicator pill at :59. That is a regression on a driver-facing navigation cue, traded for a contrast fix those two lines never needed -- unselected muted on white is already 4.76:1 and passing.

So make it two tokens, not a global swap:
- `static const Color textSecondary = Color(0xFF475569);` replacing `muted` at driver_theme.dart:8, and update the 61 call sites.
- Add `static const Color navUnselected = Color(0xFF64748B);` and point driver_theme.dart:64 and :70 at it, preserving the current nav bar appearance. It stays at 4.76:1 on the white nav background, which passes AA for its fontSize 11 label.

If a single token is strongly preferred, then the nav bar needs a separate compensating change in the same commit -- for example raising the indicator to `navy.withOpacity(0.18)` -- and the selected/unselected distinction should be confirmed by eye once Flutter is available. I could not check that here; nothing was run.


**HIGH — Cards have no perceivable boundary: elevation 0 with a 1.15:1 border and a 1.08:1 fill difference from the page**  
`apps/driver_pilot/lib/driver_theme.dart:44` · contrast  

*What goes wrong:* Cards are the app's only grouping device and they are used for every list row a driver acts on - the shipments list (driver_flow.dart:762), the POD list on the active-trip screen (driver_flow.dart:1756), the earnings stat tiles (driver_flow.dart:1948), the payout-batch history (driver_flow.dart:2090). At 1.08:1 fill difference and a 1.15:1 edge, where one tappable row ends and the next begins is carried almost entirely by the gap between them, not by a visible boundary. For a carrier scanning a list of loads to find the one to act on, and for anyone reading in glare, the structure that was designed into the screen does not reach the eye.

*Fix:* The fix is sound as far as it goes but stops short of the failure it argues for. `border` #E2E8F0 is the sole boundary token in four places, not two — driver_theme.dart:31 (OutlinedButton `side`), :41 (input `enabledBorder`), :49 (Card `side`) and :53 (Chip `side`) — and the two the fix omits are the clearer WCAG 1.4.11 failures, because an OutlinedButton and a Chip have no fill at all: the 1.15:1 edge against #F4F7FA is the only thing that makes them a control. OutlinedButton is the primary secondary action on money-adjacent screens (driver_flow.dart:1935 "Payout history", :1155 "Start", customer_flow.dart:1699 "Get quote").

Corrected fix: add `static const Color borderStrong = Color(0xFF7C8A9C);` next to driver_theme.dart:7 and switch all four sides to it — :31, :41, :49 and :53. Keep `border` #E2E8F0 for in-card dividers only (customer_flow.dart:265 `const Divider(height: 1)`, and customer_flow.dart:143 `const VerticalDivider(width: 1)`, which the finding did not spot and which is the same case).

Two smaller corrections. First, driver_theme.dart:38 `border: OutlineInputBorder(borderRadius: BorderRadius.circular(14))` passes no borderSide, so it falls back to the default near-black side for any input state not explicitly themed; set it to `borderStrong` too so the states stay consistent rather than jumping darker. Second, order the token so it reads as a scale — name the existing pale one `borderSubtle` and `borderStrong` as above, or leave `border` in place and add only `borderStrong`; do not end up with `border` meaning "the weak one" in a file where three of its four uses are now the strong one.

The advice against reaching for elevation is correct and worth keeping: a shadow over a 1.08:1 fill difference does not create a 3:1 boundary, and a solid edge is cheaper on the mid-range Android hardware this ships to.

*Needs a device to confirm.*


**MEDIUM — No semantic status colour exists anywhere in the app, so every trip status renders as an identical chip**  
`apps/driver_pilot/lib/driver_flow.dart:1114` · status-encoding  

*What goes wrong:* On the Loads screen - the carrier's main working surface, and the screen whose two filter rows are entirely about status - an in-progress load, a completed one, a full one and an open one are visually interchangeable. The driver has to read four same-looking chips per card, and status is also the first chip in a wrap that includes vehicle class and free capacity, so the meaningful token and the incidental ones compete equally. Not rated high because the labels are present and correct and the action button does change (driver_flow.dart:1160-1168 shows Track / Summary / View), so nothing is corrupted - it is scanning cost, paid on every load, every time.

*Fix:* The token additions and the contrast numbers are sound - keep them, and add the danger token from the error finding. The mapping is not sound: sending OPEN to navy defeats the fix's own stated goal, because the vehicle-class chip, the "kg available" chip and the "Has bookings" chip already render navy from driver_theme.dart:54, so on an OPEN card the status chip is still visually identical to its neighbours - and OPEN is the state a loads list spends most of its time in (it is also rank 1 of 4 in _statusRank, driver_flow.dart:917-930). Two changes. First, demote the incidental chips instead of only promoting the status one: in _LoadCard (driver_flow.dart:1113-1119) give the vehicle-class, "kg available" and "Has bookings" chips `labelStyle: const TextStyle(color: DriverTheme.muted, fontWeight: FontWeight.w500)` and `side: const BorderSide(color: DriverTheme.border)`. This is safe here and only here: muted #64748B is 4.76:1 on the white card surface (cardTheme color Colors.white, driver_theme.dart:45) but only 4.43:1 on the #F4F7FA page background, so do not reuse the muted-chip treatment for chips placed directly on the scaffold. Second, give OPEN a colour of its own rather than navy - reuse DriverTheme.navy only as the default fallback for an unrecognised status string, which tripStatusLabel already passes through unchanged (pilot_api.dart:174-176). A `Color statusColour(String status)` helper in driver_theme.dart maps IN_PROGRESS to inProgress, COMPLETED to success, FULL to warning, OPEN to a fourth distinct token, default to navy; the status chip alone takes `side: BorderSide(color: statusColour(status))` and `labelStyle: TextStyle(color: statusColour(status), fontWeight: FontWeight.w600)`. Keep the text label - colour stays a second channel, never the only one. Verify any new OPEN token to the same bar as the other three (at least 4.5:1 on both #FFFFFF and #F4F7FA) before it lands. One scope note the finding left out: tripStatusLabel is also rendered uncoloured at driver_flow.dart:1691 ("Status: ${tripStatusLabel(tripStatus)}"), so route the helper through that site too, or the same load reads as two different visual languages on the card and on the detail screen.


**MEDIUM — On the active-trip screen the load's state is drawn in the de-emphasis token while a lesser heading below it gets the strongest treatment**  
`apps/driver_pilot/lib/driver_flow.dart:1688` · hierarchy  

*What goes wrong:* This is the screen a driver is on while running a load, and the question it exists to answer -- is this load started, and can I still act on it -- is typeset as the least important thing on the page. The visually dominant element is instead the "Next pickup" / "Trip summary" label. A driver glancing at the phone in a cab reads the loudest thing first and gets the wrong answer about trip state, which is the state that gates GPS sharing (driver_flow.dart:1776) and the Complete load button.

*Fix:* The proposed fix has three defects; use this instead.

1. "Demote driver_flow.dart:1750 from fontSize 16 to the shared sectionTitle role at fontSize 18" is self-contradictory — 18 is LARGER than the 16 it currently has, so that raises the competing element rather than demoting it. Leave 1750 at `fontSize: 16, fontWeight: FontWeight.w700, color: DriverTheme.navy` unchanged. When not complete it renders "Next pickup: ${next["pickupAddress"]}" (driver_flow.dart:1748), which is the driver's actual next action, not a decorative label. It should stay a strong section header; it just should no longer be the loudest thing in the body.

2. The proposed status colours do not exist. driver_theme.dart:5-8 defines exactly four tokens — navy, background, border, muted. `DriverTheme.inProgress`, `.success` and `.textSecondary` are not in the file, so the fix as written does not compile until the separate status-token finding lands. Make that ordering explicit, or ship the typography change alone first.

3. fontSize 22 collides with the shell. driver_flow.dart:108 renders the AppBar title at `fontSize: 26, fontWeight: FontWeight.w700` and driver_flow.dart:27 supplies "Active trip" for this route, so a 22 w700 navy line directly beneath it reads as a second page title. Use `fontSize: 20, fontWeight: FontWeight.w700, color: DriverTheme.navy` at driver_flow.dart:1688 — clearly the lead of the scrolling body, clearly subordinate to the 26pt bar.

4. Add a deletion the finding missed. driver_flow.dart:1690-1693 renders `"Status: ${tripStatusLabel(tripStatus)}"`, and pilot_api.dart:171-174 maps IN_PROGRESS to "In progress" and COMPLETED to "Done". That is the same fact the promoted line already states, one line below it, in muted 13. Once 1688 carries the state at 20pt navy, delete the Text at 1690-1693 rather than leaving two restatements of trip state stacked.


**MEDIUM — Money is rendered four different ways, and the carrier's own payout figure gets the weakest treatment of the four**  
`apps/driver_pilot/lib/driver_flow.dart:850` · hierarchy  

*What goes wrong:* The carrier is paid on a weekly schedule and the number that matters to them is net-to-carrier. On the shipment detail screen (driver_flow.dart:839-866) that number is indistinguishable from the pickup address, and on the payout-history screen it is an unstyled list title. Meanwhile the customer-side price estimate gets the largest type in the app. The amount a carrier is owed should not be the least prominent money in the binary, and a driver scanning payout history for a figure has to read rather than glance.

*Fix:* Retitle to "Net-to-carrier is rendered five different ways across the driver flow, and the two screens where it is the reason for the screen give it the least weight." Drop the "weakest of the four" claim — driver_flow.dart:1914/:1916 already render carrier payout money through `_StatTile` at 22/w700.

Add one typography token to driver_theme.dart, alongside the existing colour tokens:

    static const TextStyle money = TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: navy, height: 1.2);
    static const TextStyle moneyLabel = TextStyle(fontSize: 12, color: muted);

Apply it at five sites, not three:

- driver_flow.dart:850 — split the concatenated string so the figure can carry its own style, and demote the header at :844 so the screen keeps one head. Replace :844's `fontSize: 20` with `fontSize: 16` (matching the section header at driver_flow.dart:1750, which is already `fontSize: 16, fontWeight: FontWeight.w700, color: DriverTheme.navy`), then replace :850 with a Column holding `Text("Net to carrier", style: DriverTheme.moneyLabel)` above `Text(formatInrFromPaise(s["netToCarrierPaise"] as num? ?? 0), style: DriverTheme.money)`. Insert `const SizedBox(height: 12)` after :849 so the amount stops reading as a third address line.
- driver_flow.dart:2092 — `title: Text(formatInrFromPaise(b["totalNetToCarrierPaise"] as num? ?? 0), style: DriverTheme.money),`. An explicit style overrides ListTile's theme titleTextStyle, so this works without touching ListTileTheme.
- driver_flow.dart:1954 — replace the inline TextStyle with `DriverTheme.money`. Identical values, so no visual change; it just stops being the only place the size is defined.
- driver_flow.dart:1759 — the site the finding missed. Split the amount out of the subtitle string and move it to `trailing` is not possible (trailing already holds the Accept / Confirm delivery TextButton), so instead render the subtitle as a Row: `Text(shipmentStatusLabel(st), style: DriverTheme.moneyLabel)` then `Text(formatInrFromPaise(s["netToCarrierPaise"] as num? ?? 0), style: DriverTheme.money.copyWith(fontSize: 16))` — 16 rather than 22 because a ListTile subtitle at 22 will overflow against the trailing button on a narrow mid-range Android screen. This makes the list figure the one intermediate size, deliberately, rather than by accident.

Leave customer_flow.dart:1735 at 24. The finding's reason for lowering it — "so one quantity has one size" — does not survive the fact that it is a different quantity (gross price, not net to carrier), on a different persona's surface, at desktop-web viewport width. Changing it buys consistency nobody sees and touches a screen on the customer money path for no user benefit. Same for customer_flow.dart:2083 and :2098: note them, do not change them in this pass.

One caveat I could not check: whether 22/w700 at driver_flow.dart:1759 or :2092 causes text overflow at the narrowest supported width. That needs a running app, which is not available here, so treat the 16px choice at :1759 as reasoning rather than a verified fit.


**MEDIUM — Page padding alternates between 16 and 20 across sibling screens inside the same shell**  
`apps/driver_pilot/lib/driver_flow.dart:157` · consistency  

*What goes wrong:* The content's left edge shifts by 4px as the driver moves between tabs and drills into detail screens, against a fixed app bar and fixed bottom nav that do not move. It reads as a rendering wobble rather than a design, and it is most visible on the exact transition a driver makes most often: Shipments list at 16 into shipment detail at 20.

*Fix:* The fix is sound but incomplete on the driver side and imprecise on the customer side.

1. It misses a third convention in the same shell. driver_flow.dart:1002, inside _DriverLoadsScreenState.build, is `padding: const EdgeInsets.symmetric(horizontal: 16),` — 16 on the sides and ZERO top, on the Loads tab root, which is a primary bottom-nav destination (DriverShell._pathForIndex index 2). So the driver moving Home -> Shipments -> Loads sees 20, then 16, then 16-with-no-top-gap, the first card hard against the app bar. Any standardisation pass must include :1002, changed to `EdgeInsets.all(DriverSpace.lg)`. Leaving it out means the next screen still has two precedents to copy.

2. The customer-side rationale needs restating. customer_flow.dart:403 is not a bare page inset: CustomerScaffold wraps every body in CustomerPageFrame (customer_flow.dart:96, `final page = CustomerPageFrame(child: bodyBuilder(context));`), which itself applies `EdgeInsets.symmetric(horizontal: wide ? 32 : 16, vertical: wide ? 8 : 0)` (customer_layout.dart:34). So the effective narrow-width inset at :403 is 36 against 32 for its siblings. Changing :403 to 16 is still the right call and still removes the 4px difference, but the fix should say "36 vs 32 effective" rather than "20 vs 16", or the next reader will double-pad it. Two other customer page bodies use `EdgeInsets.symmetric(vertical: 16)` (customer_flow.dart:189, :1631) and deliberately take their horizontal inset from the frame — do not blanket-convert those to all(16) or they will sit at 32 horizontal by accident.

3. Keep the constant driver-side only. Naming it DriverSpace and then using it in customer_flow.dart, where the frame owns horizontal spacing, spreads a driver token into a layout with a different spacing owner. Either name it neutrally (AppSpace) or just write the literal 16 at customer_flow.dart:403.

Severity medium is defensible but sits at the top of low: a 4px symmetric shift is real and traceable, though it is polish next to anything on the money path.


**MEDIUM — The Loads screen is the only shell screen with zero top padding, so its first element butts against the app bar**  
`apps/driver_pilot/lib/driver_flow.dart:1002` · consistency  

*What goes wrong:* Loads is the carrier's primary working screen and it is the one screen where the content starts flush under the app bar, with the summary box's top border sitting hard against the bar's lower edge. Against the near-invisible card borders documented separately, a container with no breathing room above it reads as part of the chrome rather than as content.

*Fix:* The padding change is right but the second half of the fix is not. Do NOT delete driver_flow.dart:1086.

Change driver_flow.dart:1002 to:

  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),

and leave line 1086 (`const SizedBox(height: 24),`) alone.

Why not `EdgeInsets.all(16)` plus deleting the spacer, as proposed: the spacer's job is clearance for the last `_LoadCard` above the NavigationBar, not symmetry with the top. Replacing 24 with 16 makes the bottom worse, not better, to fix a top-edge problem. `fromLTRB(16, 16, 16, 0)` adds exactly the missing 16 above the summary box and changes nothing else on the screen — a one-token diff with no second-order effect to re-check.

If matching `EdgeInsets.all(16)` to the other screens matters more than the diff being minimal, `all(16)` is also acceptable — but still keep the SizedBox at 1086, giving 40 of bottom clearance rather than 16. Either way the "delete the now-redundant trailing SizedBox" clause should be struck.

Also strike the "removes one of the four distinct EdgeInsets.symmetric shapes" sentence from the fix: the count is six call sites and five shapes, and consolidating them is not what this change does.


**MEDIUM — Four type sizes inside a single card, for three lines of equally secondary metadata**  
`apps/driver_pilot/lib/driver_flow.dart:1131` · typography  

*What goes wrong:* The three metadata lines in a load card - capacity, vehicle-and-booked-weight, pickup window - are equally important to a carrier deciding whether to act on a load, but they are typeset in three descending sizes, which implies a ranking that does not exist. The smallest, at fontSize 11 (the pickup window at driver_flow.dart:1149), is the one a driver most needs to read outdoors, and it is set in the muted colour that already misses AA on this surface.

*Fix:* Keep the token scale, drop the false AA sentence, and stop collapsing three roles into one.

1. Strike "set in the muted colour that already misses AA on this surface" from the user impact. Muted on the white card is 4.76:1 and passes AA. The real argument for raising 11 is legibility at arm's length in sunlight for a one-handed driver, which is a product judgment, not a spec violation — state it as such. (Muted at 4.43:1 on the #F4F7FA scaffold is a separate, genuine failure and belongs in its own colour finding, not here.)

2. Add the named roles to driver_theme.dart as proposed, but with `money 24/w700/navy` rather than 22, so customer_flow.dart:1735 `formatInrFromPaise(_quote!["grossPaise"] as num? ?? 0)` — the headline estimated price — is not shrunk. Money is the one place a house rule about costing someone money argues for keeping the larger size.

3. In `_LoadCard`, do not give 1133, 1139 and 1149 the same role. They occupy three structural slots, so "let position carry their order" is already true and size is not the only differentiator:
   - 1133 (`"$res / $cap kg"`) keeps navy/w600 as a header-row companion to the route title. Give it `label 13/w600/navy` — same size as the new caption floor, but the weight and navy retained, because demoting it to muted grey would strip the title-row pairing and lower its contrast for no gain.
   - 1139 and 1149 both take `caption 13/w400/muted`, raising 12 and 11 to 13. That is the change that actually serves outdoor reading.

4. Scope the 16/20/26 cleanup separately and ask before running it. driver_flow.dart:108 `fontSize: 26` is an AppBar title applied across driver screens and :1750 `fontSize: 16` is the next-pickup line; folding them into 18/22 is a cross-file visual change touching more than three files, which under the house rules is a pause-and-ask refactor, not a side effect of introducing tokens. Introduce the tokens first, migrate _LoadCard, then propose the sweep as its own change.


**MEDIUM — The section-title role is fontSize 18 in five places and fontSize 16 in one, on the active-trip screen**  
`apps/driver_pilot/lib/driver_flow.dart:1750` · typography  

*What goes wrong:* A single orphan size means the section heading on the active-trip screen sits one step lower than the visually identical heading on Fleet, Publish, and the customer detail screens, so the same rank reads as two ranks as a driver moves between screens. It is the kind of drift that compounds: with no named role, the next heading someone writes picks whichever nearby number they copy.

*Fix:* The fix as written is unsound on two counts. (1) It says "change to the shared `sectionTitle` role" — no such role exists. `grep -rn "sectionTitle"` returns nothing, and driver_theme.dart is 75 lines with four colour tokens and no typography. The role has to be created before anything can be changed to it. (2) More importantly, the slot at driver_flow.dart:1750 is not a section title in two of its three states. The ternary renders "Trip summary" (a heading), `"Next pickup: ${next["pickupAddress"]}"` (a variable-length postal address — a data line), or "No pending deliveries on this load" (an empty state). Promoting all three to 18/w700/navy would set a full Indian street address in heavy navy at 18sp, which on a 360dp mid-range Android wraps to two or three lines and reads as a headline rather than as the pickup detail it is. Corrected fix, in two parts. First, add one role to driver_theme.dart, e.g. `static const TextStyle sectionTitle = TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: navy);`, and point the five existing 18 literals at it (driver_flow.dart:633, :2192; customer_flow.dart:653, :934, :1650), so the role has a single definition. Second, split the 1750 slot by state rather than resizing it wholesale: emit a fixed `Text("Deliveries", style: DriverTheme.sectionTitle)` as the heading above the shipment list in every state, and render the variable part beneath it as body text — "Next pickup: {address}" at the existing 13sp muted style used at :1692 and :1699, "All deliveries confirmed" / "No pending deliveries on this load" likewise. That removes 16 from the codebase, gives the active-trip list a heading at the same rank as the other screens, and stops an address being typeset as a heading. If splitting the slot is out of scope for this pass, the minimum safe change is 1750 -> `DriverTheme.sectionTitle` only in the `tripComplete` branch, leaving the other two branches at body size. Worth folding in while the role exists: driver_flow.dart:1365 uses `Theme.of(context).textTheme.titleMedium` for the same job and should move to the same token, or the drift returns from the other direction.


**MEDIUM — location_editor.dart carries a second, unrelated palette that reaches driver screens, and its placeholder text fails AA**  
`apps/driver_pilot/lib/location_editor.dart:200` · consistency  

*What goes wrong:* `LocationEndpointEditor` is embedded directly in the driver Publish trip screen (driver_flow.dart:2206 and :2216) and `activeTripMap` in the active trip screen (driver_flow.dart:1666), so a driver sees a map container with a different corner radius, a different border colour and a different grey than every card around it on the same scroll. When there are no coordinates yet, the explanatory message telling the driver to republish with map pins - the text that tells them how to fix the problem - is the one string in that view below the contrast floor.

*Fix:* The fix is directionally right but wrong in three places as written.

1. Do NOT map #F5F5F5 to DriverTheme.background. driver_theme.dart:14 sets `scaffoldBackgroundColor: background` (#F4F7FA), and driver_flow.dart:1663-1667 places activeTripMap in a plain Padding inside the Column - not inside a Card. Filling the placeholder with the same token as the surface behind it leaves a bare 1px outline where a filled panel was specified. Use `Colors.white` for the fill and `DriverTheme.border` for the stroke, which is exactly what cardTheme at driver_theme.dart:43-50 gives the Cards in the ListView directly below it, so the empty state reads as one of them.

2. The radius change is incomplete and would make the widget inconsistent with itself. tripTrackingMap:113 and singlePointMap:155 - the two branches activeTripMap returns when coordinates DO exist - both use `BorderRadius.circular(12)`. Changing only :202 to 16 means the same slot on the same screen changes corner radius depending on whether GPS resolved. Either change all six map containers together (:43, :113, :155, :202, :308, :468) to 16, or leave all six at 12. My recommendation: leave them at 12 and drop this from the finding, because 12 is also the FilledButton and OutlinedButton radius (driver_theme.dart:24, :31), so map containers at 12 are already consistent with something in the theme.

3. `borderStrong` and `textSecondary` do not exist. driver_theme.dart:5-8 define four tokens only. The fix is contingent on a companion finding adding them, and should say so. Until it lands, the concrete edit is: add `import "driver_theme.dart";` after :7, then at :201 `color: Colors.white`, at :203 `border: Border.all(color: DriverTheme.border)`, and at :212 `style: const TextStyle(color: Color(0xFF475569), fontSize: 13)` pending the token.

One trap worth recording next to this: do not "fix" :212 by reaching for DriverTheme.muted. #64748B on #F4F7FA computes to 4.43:1 and on white to 4.76:1 - it clears AA on a card but fails on the scaffold. The fix's choice of #475569 (7.58:1 on white, 7.05:1 on #F4F7FA) is the right one and should be kept.

Finally, restate the impact honestly: the palette drift and the sub-AA string reach a driver through activeTripMap's no-coordinates branch on the active trip screen (driver_flow.dart:1666), not through LocationEndpointEditor on Publish. LocationEndpointEditor is theme-clean apart from its radius.


**MEDIUM — The two production flow files abandoned the textTheme and colorScheme that the legacy pilot lab still uses correctly**  
`apps/driver_pilot/lib/customer_flow.dart:107` · design-system  

*What goes wrong:* No direct user-visible defect from this line alone - it is the mechanism behind the other findings. Because the theme carries no typography, every screen author has had to pick numbers, and the numbers diverged: 9 sizes, 5 weights, 2 line heights, 4 page-padding conventions. The practical cost is that every fix above has to be applied at dozens of call sites instead of one, and the next screen written will diverge again. Worth recording plainly: the newer production code is the less theme-driven code, and the legacy lab is the better-behaved half.

*Fix:* The fix is sound on populating `textTheme:` in `DriverTheme.theme()` and converting call sites customer_flow-first. The app bar half needs correcting on two points.

Side effect the fix misses: main.dart:104 wires `theme: DriverTheme.theme(),` into the single `MaterialApp.router` at main.dart:102, so one ThemeData serves all three shells. Setting `appBarTheme.titleTextStyle` at driver_theme.dart:15-20 also changes the pilot lab app bar at main.dart:160 (`appBar: AppBar(title: Text(title), actions: actions),`), which today inherits the Material 3 default and sets no style of its own. That surface must be re-checked after the change; the finding never looked at it.

Second, "give the app bar one title size rather than two" is not obviously the right call. The driver shell (driver_flow.dart:108, 26px) runs on Android phones and the customer shell (customer_flow.dart:107, 20px) runs on web in a responsive layout that switches to a rail (customer_flow.dart:99, `customerUseRail(constraints.maxWidth)`). Two platform-appropriate scales are defensible; two arbitrary literals are not. Make each a named token rather than collapsing them:

- Set `appBarTheme.titleTextStyle` once in driver_theme.dart:15-20 to the driver/Android scale, and delete the literal at driver_flow.dart:108 so the driver shell inherits it.
- At customer_flow.dart:107, replace the literal with `Theme.of(context).textTheme.titleLarge` (or whichever role the new scale assigns 20px) so the web shell's smaller title is a chosen role, not a number. AppBar wraps its `title` widget in a DefaultTextStyle, so the Column at customer_flow.dart:104-116 inherits the theme style and the session subtitle at customer_flow.dart:108 keeps its own `fontSize: 11, color: DriverTheme.muted` by merging over it — that is reasoning from the framework's documented behaviour, not something I could run here, so confirm it visually on the first build.
- Then confirm main.dart:160 still reads correctly at the new inherited size.

Also worth folding into the same pass, since it is the same mechanism: the 21 `Colors.red` sites in the flow files should move to `Theme.of(context).colorScheme.error`, matching main.dart:704 and :808 — the theme has no error/success/warning tokens today, so that conversion depends on the colour tokens landing alongside the type scale, not after it.


### Fitness for the vehicle context

11 findings, 8 high.


**HIGH — Location permission denial is a silent dead end with no path to settings**  
`lib/driver_flow.dart:1458` · permissions  

*What goes wrong:* A driver who declines the system dialog, or who declined it on a previous trip and is now in `deniedForever`, gets a bare `return`. No snackbar, no banner, no state change. `_startTrip` (1515) still succeeds, the trip goes IN_PROGRESS, the screen still says "Load in progress" (1686), and the customer's tracking map never moves. The driver believes they are being tracked, the customer believes the driver has not started, and neither finds out until someone phones. On Android, two declines make the denial permanent and there is nothing in this app that can recover it — the driver would have to know to go to Android Settings, Apps, naviG8r, Permissions unaided.

*Fix:* The proposed fix is sound and should be implemented, with four corrections/additions:

1. Anchor is line 1663, not 1664. Insert the banner as the first child of the `Column` at 1661, above the `Padding(` at 1663.

2. Cover the device-location-off case, which the fix misses and which fails identically silently. `Geolocator.checkPermission()` returns `whileInUse` even when the phone's location toggle is off. Then 1460 `getCurrentPosition()` throws `LocationServiceDisabledException` into the bare `catch (_) {}` at 1461, and the stream at 1463-1468 uses `.listen(...)` with no `onError`, so the same exception on the stream is an unhandled async error with zero UI. Add at the top of `_startLocation`: `if (!await Geolocator.isLocationServiceEnabled()) { setState(() => _locationBlocked = true); return; }` with the button "Turn on location" calling `Geolocator.openLocationSettings()`, and add `onError: (_) { if (mounted) setState(() => _locationBlocked = true); }` to the `.listen` at 1466.

3. Fix lib/driver_flow.dart:936 in the same change. `SnackBar(content: Text("Load started — live tracking enabled."))` sits on a screen whose `_startTrip(String tripId)` (932-941) never calls `_startLocation()`. It asserts tracking that was never attempted. Change the copy to "Load started." to match line 1523, or route that screen to the active-trip screen which does start location.

4. Spell out the lifecycle wiring, which "moving _startLocation() into a didChangeAppLifecycleState resume branch" leaves underspecified: add `with WidgetsBindingObserver` to `_DriverActiveTripScreenState` (1427), `WidgetsBinding.instance.addObserver(this)` in `initState` (1442), and `WidgetsBinding.instance.removeObserver(this)` in `dispose` (1638) before `_stopLocationSharing()`. The existing guard at 1455 (`if (_posSub != null) return;`) already makes the resume call idempotent, but the resume branch must also clear `_locationBlocked` before retrying or the banner sticks after a successful grant.

On the new token: DriverTheme has only four colours, so `DriverTheme.warning` must be added with a stated value meeting WCAG AA for body text on both #F4F7FA and white card surfaces — an amber background tint with warm near-black text, not amber text on light.

One case the fix still leaves open, worth a separate finding rather than bolting on here: `LocationPermission.whileInUse` passes the 1458 guard, but on Android it stops delivering updates once the app is backgrounded. A driver who pockets the phone stops being tracked with the banner showing nothing. That needs `alwaysUse` plus a foreground service, which is an architecture decision, not a copy fix.


**HIGH — Live GPS sharing is bound to one screen's lifetime and stops when the driver taps any tab**  
`lib/driver_flow.dart:1638` · navigation  

*What goes wrong:* Mid-trip, a driver who taps Profile to check earnings, or Shipments to look at the next drop, unmounts the active-trip screen and silently kills GPS sharing. Nothing tells them. Nothing restarts it except navigating back into that exact trip screen. Because there is no foreground-service configuration and no background-location permission, the same thing happens when the driver locks the screen or takes a call — which is most of a driving day. The customer's live track freezes at whatever point the driver last had the screen open, and the app's own copy at 1776 keeps claiming GPS is being shared.

*Fix:* The fix is directionally right and compiles, but four corrections before implementing.

1. It names the wrong stop sites and would regress a real behaviour. There are FOUR calls to `_stopLocationSharing()`, not two: 1489 (in `_openPod`, when the reload shows the trip went COMPLETED), 1503 (`_completeLoad`), 1595 (in `_load`, `if (mounted && _trip?["status"] == "COMPLETED")`), and 1639 (`dispose`). The fix says "stopped only by `_completeLoad` (1497)". Implemented literally, a singleton would keep streaming after a load completes through the POD path or through any refresh that observes COMPLETED — GPS still being sent to a customer for a finished job, which is a worse defect than the one being fixed. Keep all three status-driven stops calling into the singleton; delete only the stop at 1639.

2. Guard the AndroidSettings by platform. `AndroidSettings` and `ForegroundNotificationConfig` are exported from `package:geolocator/geolocator.dart` (already imported at driver_flow.dart:4), so the snippet compiles — but this is one binary that also runs on web and iOS. Write:
`locationSettings: (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) ? AndroidSettings(distanceFilter: 25, foregroundNotificationConfig: const ForegroundNotificationConfig(notificationTitle: "naviG8r", notificationText: "Sharing your location with the customer for this load", enableWakeLock: true)) : const LocationSettings(distanceFilter: 25),`
`AndroidSettings` is not const-constructible (its constructor at geolocator_android-4.6.1 android_settings.dart:12 is non-const), so the existing `const` on line 1464 comes off.

3. Add a third permission. Alongside FOREGROUND_SERVICE and FOREGROUND_SERVICE_LOCATION, add `<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>` and request it at runtime — on Android 13+ the foreground-service notification is otherwise not shown, and the driver gets a silent background service with no visible indicator, which is both a trust problem and hard to debug. The fix is right that ACCESS_BACKGROUND_LOCATION is not needed: a location-type foreground service started while the app is in the foreground keeps location access without it.

4. Also fix the second false claim the finding did not name: DriverLoadsScreen `_startTrip` at 932-942 shows "Load started — live tracking enabled." (936) and no position stream exists in that state class. Once tracking is a singleton, have that handler start it too; until then, change the copy at 936 to "Load started. Open the load to share live location." The honest-fallback copy the finding proposes for the banner at 1776 should read "Keep this screen open while driving — live location is shared only while it is open," and the same correction applies to the marketing line at 1252, "open for live GPS tracking while in progress."

*Needs a device to confirm.*


**HIGH — The driver is told tracking is live only once there is nothing left to deliver**  
`lib/driver_flow.dart:1773` · glanceability  

*What goes wrong:* The only sentence in the app that tells a driver GPS is being shared appears exactly when there are no active shipments left — that is, after the last delivery, when it no longer matters. Through the entire run, with drops still outstanding, the screen shows no tracking state at all. Combined with the silent permission failure above, a driver has no way at any point to answer the one question that matters mid-trip: is the customer seeing me right now? It is also a 12px muted string at the bottom of a scrolling list, which is not something a driver reads at a traffic light.

*Fix:* The placement is right — 1664 is the `Padding` wrapping `activeTripMap`, so a status row inserted into the Column's children just before it works, though it needs its own `EdgeInsets.symmetric(horizontal: 16)` because that Padding supplies the gutter only for the map. Four corrections to the mechanics, one of which would otherwise reintroduce the exact mislead the finding objects to:

1. `_locationBlocked` does not exist. Grep over driver_flow.dart returns no hit; the state fields are 1428-1438. It has to be added and set in _startLocation where the denied path currently returns silently: replace the bare `return` at 1458 with `if (mounted) setState(() => _locationBlocked = true); return;`, and clear it to false on the success path after the stream subscribes at 1463-1469.

2. Do not drive "Last sent" from `_lastLocationPostAt`. Line 1538 assigns `_lastLocationPostAt = now` BEFORE the awaited POST at 1540-1549, and the `catch (_)` at 1550 never rolls it back. So it records the last attempt, not the last delivered fix: with the API unreachable, a chip driven by it would read "Sharing location" or "Last sent 30s ago" while the customer sees nothing. Add a separate `DateTime? _lastLocationAckAt`, set it inside setState immediately after the `await api.post` returns, and drive the chip from that field only.

3. The staleness threshold of two minutes will cry wolf. The stream is `LocationSettings(distanceFilter: 25)` (1464), so a truck parked at a dhaba or stuck in a jam emits no events and posts nothing, while the customer's last known position is still correct. Either post on a heartbeat (a Timer.periodic that re-posts the last known Position every 2 minutes while status is IN_PROGRESS) so the threshold means what it says, or raise the threshold to 10 minutes and word it neutrally as "Last sent 12 min ago" in navy, with the alarm styling reserved for `_locationBlocked`.

4. A relative-time chip needs its own rebuild trigger. Nothing rebuilds on elapsed time: 1538 is a plain assignment outside setState, and the only setState in the location path is on `_driverPos` (1466), which stops firing the moment the vehicle stops moving — precisely when the chip most needs to age. Add a `Timer.periodic(const Duration(seconds: 30), ...)` calling setState in initState (1442-1447) and cancel it in dispose alongside `_stopLocationSharing()` (1638-1641).

Copy: keep "Location off — customer cannot see you" for the blocked state, which is accurate and not confirmshaming. For the success state prefer "Customer can see your location" over "Sharing location" — it names the consequence the driver is actually asking about. Navy #122C53 on white clears WCAG AA at 14px.


**HIGH — Device location services being off is never checked, and the resulting errors are swallowed**  
`lib/driver_flow.dart:1459` · error-state  

*What goes wrong:* Location permission granted but the phone's location toggle switched off — extremely common on a mid-range Android where drivers turn it off to save battery — is a completely different failure from a denied permission, and it produces exactly the same nothing. `getCurrentPosition()` throws `LocationServiceDisabledException`, which `catch (_) {}` at 1462 discards. The position stream then also errors, and with no `onError` that error escapes to the zone rather than reaching any UI. The driver sees a map with no truck on it and, if the lane happens to geocode, not even the placeholder hint at 1674. The fix is one toggle away but the app never says so.

*Fix:* The diagnosis is right and the shape of the fix is right, but as written it has four defects that would show up the first time a driver actually hits it. Keep the substance, change these.

1. One flag, not two. The proposal sets `_locationServicesOff` in the guard and `_locationBlocked` in `onError`, then says both drive "the same banner". Use a single field on `_DriverActiveTripScreenState`: `bool _locationOff = false;`.

2. Guard `setState` with `mounted`. `Geolocator.isLocationServiceEnabled()` is awaited, so the widget can be disposed before it returns. The surrounding code already does this at 1461. Write `if (mounted) setState(() => _locationOff = true);`.

3. Cancel the subscription in `onError`, or the retry can never re-arm. `_startLocation` begins at 1455 with `if (_posSub != null) return;`. After a stream error `_posSub` is still non-null, so every later call to `_startLocation` returns immediately and location sharing is dead for the rest of the trip. The onError must be `onError: (Object e) { _posSub?.cancel(); _posSub = null; if (mounted) setState(() => _locationOff = true); }`.

4. Give it a recovery path. The proposed early `return` is one-shot: nothing re-checks when the driver turns location back on. The only other caller is `_startTrip` at line 1522, `if (_posSub == null) await _startLocation();`, which the driver cannot reach again once the trip is IN_PROGRESS — so the banner would stay up for the whole load even after the toggle is flipped. Two additions, both cheap:
   - Subscribe once in `initState` to `Geolocator.getServiceStatusStream()` (it exists in this version — geolocator.dart:207), store it in a `StreamSubscription<ServiceStatus>? _serviceSub`, and on `ServiceStatus.enabled` clear `_locationOff` and call `_startLocation()`. Cancel it in `dispose()` next to the existing `_stopLocationSharing()` at 1639.
   - Put a "Try again" `TextButton` on the banner calling the same thing, for the case where the status stream does not fire.

5. Theme the banner with tokens that exist. driver_theme.dart defines only navy, background, border and muted — there is no warning or error token, so do not reach for red. Render it as a white `Container` with `border: Border.all(color: DriverTheme.border)`, a leading `Icon(Icons.location_off, color: DriverTheme.navy)`, title text in `DriverTheme.navy` at `FontWeight.w600`, and a `FilledButton` (navy on white, already AA) reading "Open location settings" that calls `Geolocator.openLocationSettings()`.

Copy: "Location is off on this phone. Turn it on so the customer can see this load moving." That names the cause, the action and the consequence in one line, without urgency language. The proposed "Turn on Location on your phone to share your position" is acceptable but says nothing about why it matters.

Placement: inside the `ListView` at driver_flow.dart:1676, above the status `Text` at 1679, so it sits with the trip state rather than floating over the map.

One scope note the finding should carry: the denied-permission branch at 1458 is a bare `return` with no UI either. If the banner is built for services-off and permission-denied still fails silently, the driver gets the same blank map for the other half of the cases. Reuse the same banner with the copy "Allow location access so the customer can see this load moving." and `Geolocator.openAppSettings()`, driven by a second value on the same field rather than a second banner.


**HIGH — The POD screen never says which delivery it is confirming**  
`lib/driver_flow.dart:1846` · money-path  

*What goes wrong:* A load can carry several shipments — the active-trip screen maps over `_shipments` at 1753 — and the driver reaches this screen by tapping a `TextButton` labelled "Confirm delivery" (1765) in a card row. Once the screen opens, every identifying detail is gone: no customer name, no drop address, no weight, no amount. A driver with three drops on one lane, confirming the second one at a loading dock in the rain, has no way to check they are about to file POD against the right shipment. This is an irreversible POST (1825) on the money path and there is no confirmation step anywhere in driver_flow.dart (`showDialog` appears zero times in the file).

*Fix:* The finding is right; the fix as written does not compile and misses an entry point. Three problems: (1) _openPod at 1484 is `Future&lt;void&gt; _openPod(String shipmentId)` and takes only an id, so there is no `shipment` variable in scope at 1485 — `extra: shipment` requires changing the signature and both call sites (1764, where `s` is in scope, and 1787, where `next` is); (2) DriverShipmentDetailScreen pushes the same route at 861 with `context.push("/driver/shipment/${widget.shipmentId}/pod")` and no extra, so `state.extra` would be null on that path and the card would render blank or "null"; (3) go_router's `extra` is not restored after Android process death or a deep link, so the card would vanish on the exact low-memory mid-range devices this app targets.

Use the pattern the file already has instead. Give _DriverPodScreenState an initState and a _load that mirror _DriverShipmentDetailScreenState._load at 817-829: GET "/v1/pilot/carrier/shipments", walk `r.data?["shipments"]`, match `s["id"] == widget.shipmentId`, setState a `Map&lt;String, dynamic&gt;? _shipment`. The active-trip list at 1569-1572 hits the same endpoint with an anchorTripId query, so the maps have the same shape and all four fields are confirmed present on it: customerOrgName and weightKg and netToCarrierPaise (1758-1759) and dropAddress (765, 849). This works identically from both entry points, needs no route or signature changes, and survives restore.

Render as the first child at 1852 a Card with customerOrgName in 16px w700 DriverTheme.navy, then `"Drop: ${_shipment!["dropAddress"]}"`, then a dense row of `"${_shipment!["weightKg"]} kg"` and `formatInrFromPaise(_shipment!["netToCarrierPaise"] as num? ?? 0)`. Keep the existing 1852-1855 paragraph directly under it.

Guard the money action on the fetch, since the whole point is that the driver can check what they are filing against: while `_shipment == null`, set the FilledButton at 1859 to `onPressed: null` and show `const Text("Loading shipment details")` in place of the card. Note that _load in the existing pattern swallows errors in a bare `catch (_) {}` at 829 — do not copy that here; on failure set an error string and keep the button disabled with copy such as "Cannot load shipment details. Check your connection and try again." Silently leaving the button live with no identity is the original defect wearing a spinner.

Leave the button label at 1863 short. "Confirm delivery" is the right change — it matches the TextButton copy at 1765 and the detail-screen FilledButton at 862, and fixes the "Confirm POD" jargon. Do not interpolate the org name into the button as the finding proposes: a real Indian carrier org name inside a stretched FilledButton will wrap or ellipsise on a mid-range phone, and the identity belongs in the card above where it stays readable.

Separately, and worth raising as its own finding rather than folding in here: 1825-1830 posts irreversibly with no confirmation, and grep confirms showDialog appears zero times in the file.


**HIGH — Developer error strings, including dart-define flags, are shown to drivers when a money action fails**  
`lib/pilot_api.dart:74` · error-state  

*What goes wrong:* A driver on a highway with two bars taps "Confirm POD", the request times out, and a SnackBar tells them to run with `--dart-define=API_BASE_URL=http://10.0.2.2:3000`. Or the server 500s and they get `HTTP 500: {"error":"internal"}` as a raw JSON blob in a four-second SnackBar. There is no indication of whether the POD was filed, no retry, and nothing actionable. For a user who may not be a first-language English reader, the message is worse than no message: it looks like the app broke in a way they caused.

*Fix:* The fix's direction is right but three parts need correcting before it is implemented.

1. Add the timeout types to the mapping. The proposed map says "connection/timeout" but the existing code branches only on `connectionError`/`unknown`. `driverFacingError` must switch on `DioExceptionType.connectionTimeout`, `sendTimeout`, `receiveTimeout`, `connectionError` and `unknown` together, or the 45s timeout path (pilot_api.dart:32-33) keeps falling through to the raw `HTTP ?:` string and the fix silently misses the most common highway case.

2. Drop "Pull down to refresh" from the 409 copy on the POD screen. `_DriverPodScreenState.build` (driver_flow.dart:1846-1866) is a `Padding > Column` with no `RefreshIndicator` and no scrollable, so pull-to-refresh does nothing there. Use "This delivery has already been confirmed." and pop back to the trip screen, which does reload via `_openPod`'s `await _load()` at driver_flow.dart:1486.

3. "Keep the current formatApiError for the pilot lab" understates the blast radius. `formatApiError` has 21 call sites in customer_flow.dart (365, 391, 518, 614, 637, 774, 819, 842, 860, 880, 894, 1116, 1246, 1329, 1506, 1562, 1617, 1782, 1899, 1917, 1949) — that is the web customer portal, also a real user-facing surface with the same raw strings. Either scope the finding's fix explicitly to driver_flow.dart and record customer_flow.dart as a separate follow-up, or make `driverFacingError` a general `userFacingError` and leave `formatApiError` used only by main.dart's pilot lab (10 sites: 204, 227, 395, 491, 523, 641, 775, 927, 945, 996). Do not claim the pilot lab is the only remaining consumer.

The inline-error-row-plus-"Try again" change to the POD screen is sound and needs a new `String? _error` field on `_DriverPodScreenState` (the class currently holds only `_notes` and `_busy`), rendered between the notes field and the Spacer so it sits above the FilledButton as proposed.


**HIGH — Publishing a lane requires typing an ISO-8601 timestamp and an enum by hand**  
`lib/driver_flow.dart:2226` · form-ux  

*What goes wrong:* An owner-operator publishing tomorrow's Gurugram-Jaipur lane from the cab has to hand-edit `2026-09-15T00:00:00+05:30` on a phone keyboard, and type `MEDIUM` in capitals into a free-text box or the submit is rejected at 2157 with "vehicleClass must be SMALL, MEDIUM, or LARGE." — an error message that names an API field. Realistically this is not completable one-handed, and the only path that works is accepting whatever `defaultAnchorTripWindow` prefilled, which means the pickup window is almost always wrong. The same free-text enum blocks a driver from correcting their own vehicle class on the Profile screen (1373).

*Fix:* The fix is sound in shape but has one crash risk and two copy errors.

1. CRASH RISK at 1373. The Profile screen seeds the controller at 1299 with `_vehClass.text = DriverSession.vehicleClass ?? "MEDIUM";`, and that value comes from the server unvalidated at driver_session.dart:76 (`vehicleClass = v["vehicleClass"]?.toString();`). DropdownButtonFormField asserts its value matches exactly zero-or-one item, so a server value outside the three would throw at build. Clamp before seeding: `final seededVehicleClass = const {"SMALL", "MEDIUM", "LARGE"}.contains(DriverSession.vehicleClass) ? DriverSession.vehicleClass! : "MEDIUM";` and hold the class in a `String` field rather than a TextEditingController at all four sites.

2. Drop the "in capitals" justification. All four submit paths already call `.trim().toUpperCase()` (2156, 1315, 419, 605), so case is not the problem. The reason for the dropdown is that a free-text box for a three-value enum admits typos and needs no keyboard; state it that way.

3. Add site 461 as the highest-impact one, not an afterthought. The registration submit at 419-426 posts `vc` to `/v1/pilot/driver/register` with no SMALL/MEDIUM/LARGE check at all, unlike 2157 and 1321. A typo there reaches the API silently. Replacing 461 with the dropdown closes an unvalidated write, not just a keyboard annoyance.

4. Also fix the error copy the fix leaves untouched: 2158 and 1322 both read "vehicleClass must be SMALL, MEDIUM, or LARGE." and 2153 reads "capacityKg must be a positive number." Once the field is a dropdown, 2157-2159 becomes unreachable, but 2153 stays and still names an API field. Change it to "Enter the weight you can carry, in kilograms."

5. Keep the ISO string in the controller behind the picker as proposed - verified compatible, since 2169-2170 post `_w1.text.trim()` / `_w2.text.trim()` raw. Keep the existing reset button at 2200-2203 as a "use the default window" escape hatch, and relabel it away from "(today-tomorrow, IST)" only if the picker's display already states the dates.

6. Drop "which means the pickup window is almost always wrong" from the impact claim. defaultAnchorTripWindow (pilot_api.dart:138-148) sets today 00:00 IST to end of tomorrow IST, which does cover a lane running tomorrow. Whether drivers need a narrower window cannot be settled from source.


**HIGH — The muted text token fails WCAG AA on the app background, and error text fails badly**  
`lib/driver_theme.dart:8` · contrast  

*What goes wrong:* `DriverTheme.muted` carries nearly every secondary string in the driver app, and it is applied at 11px, 12px and 13px — the pickup window on each load card (1149, 11px), the trip status line (1692, 13px), the earnings tile labels (1955, 12px), the filter group headers (1022, 1047, 12px). Indoors this is marginal. In a truck cab at midday with a phone at arm's length it is the layer of the interface that carries the times, the weights and the status, and it is the layer that disappears first. The error text is worse: at 3.43:1 the message telling a driver their POD failed is the least legible text on the screen.

*Fix:* The token change is sound. Four corrections before implementing.

1. Two of the four "user impact" examples are wrong and should be dropped from the writeup. driver_flow.dart:1149 (pickup window, 11px) is inside the `Card` opened at :1121, and :1955 (earnings tile label, 12px) is inside the `Card` opened at :1948. cardTheme sets `color: Colors.white` (driver_theme.dart:45), so muted on those measures 4.76:1 and PASSES AA today. Same for :1015, the loads summary line, which sits in a `Colors.white` Container at :1007. The genuine on-background muted failures are driver_flow.dart:1022, :1047 and :1692. The nav bar labels at driver_theme.dart:62 and :64 render on `backgroundColor: Colors.white` (:58), so they pass too. Changing the token still fixes everything and improves the card sites, so the fix does not change — but the impact paragraph should cite 1022/1047/1692, not the two card sites.

2. location_editor.dart does not import driver_theme.dart — its imports are dart:math, material, google_maps_flutter, google_geocoding.dart, maps_config.dart. Add `import "driver_theme.dart";` or the edits to :201 and :212 will not compile. (#475569 on #F4F7FA is 7.05:1, so the substitution itself is fine.)

3. Split out the font-size rider. "Raise every fontSize: 11 and 12 to 13 minimum" is not a WCAG requirement — WCAG sets no minimum font size — and no evidence was offered for it. It is a separate legibility recommendation and should be argued on its own, not carried in on the contrast finding. For scale: driver_flow.dart has exactly one `fontSize: 11` (line 1149) and eight `fontSize: 12`.

4. Scope note. Fixing only driver_flow.dart's seven literals leaves 14 more Colors.red in customer_flow.dart (456, 541, 662, 679, 948, 952, 1037, 1140, 1266, 1377, 1642, 1823, 2020, 2068). Customer is web-only so deferring is defensible, but say so rather than leaving it silently unfixed.

On severity: high is carried by the error red, not by muted. Colors.red at 3.42:1 on a POD or payment failure message is a wide miss on a money path. The muted token misses by 0.07 (4.43 against a 4.5 floor) — on its own that is medium. Keep high, but attribute it to the error text.


**MEDIUM — The mid-trip primary action is the last child of a list that grows with every shipment**  
`lib/driver_flow.dart:1780` · touch-target  

*What goes wrong:* "Mark arrived / POD" is the one thing a driver does on this screen once the load is moving, and it is below a 220px map, four status paragraphs, and one card per shipment. With three drops on a lane it is off-screen on arrival and has to be scrolled to — one-handed, parked at a dock. The "Complete load" button (1729), which the driver presses once per trip, sits far above it. The label itself is a slash-composite of a jargon acronym and an instruction, which is two things to parse at the moment the driver is least able to parse anything.

*Fix:* The structural move is right but the proposed version leaves a duplicate of the same problem and the copy breaks two house rules. Corrected:

1. STRUCTURE — pin ONE slot, not just the POD button. `canCompleteLoad` (1650: `tripStarted && _shipments.isNotEmpty && !_hasActiveShipments`) and the POD block's guard (1780: `tripStarted && _hasActiveShipments`) are mutually exclusive, so a single pinned slot can host whichever is live and will never show both. Delete the 1727-1735 `Complete load` block AND the 1780-1794 block from the `ListView`, and add a third child to the `Column` at 1662, after the `Expanded`:

```dart
if (tripStarted && !tripComplete)
  Container(
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: DriverTheme.border)),
    ),
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    child: FilledButton(
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
      onPressed: _hasActiveShipments
          ? (next != null && next["status"]?.toString() == "BOOKED"
              ? () => _openPod(next!["id"]?.toString() ?? "")
              : null)
          : (_completing ? null : _completeLoad),
      child: Text(_hasActiveShipments ? "Confirm delivery" : "Complete load"),
    ),
  ),
```

Do NOT "leave Complete load at 1729 in the scrolling list" as the finding proposes — it is state-advancing and sits behind the same growing card list, so the fix would be reintroducing the defect it removes.

2. Drop the `Row`/`Expanded` wrapper at 1782-1791. With `minimumSize: Size.fromHeight(56)` the button is already full width; the Row adds a level of nesting for nothing.

3. COPY — use "Confirm delivery", not "Delivered — confirm now". Three reasons: (a) `_openPod` (1787) opens the POD capture screen, it does not record a delivery, so "Delivered" states as done something the driver has not yet proved — what the user sees must match what they get; (b) "now" is manufactured urgency; (c) the identical action already reads "Confirm delivery" on each shipment card at 1765, and one concept gets one word everywhere. The finding is right that "Mark arrived / POD" is bad — a slash-composite of an acronym and an instruction, aimed at drivers who may not have English as a first language — but the replacement is the string already in the codebase.

4. `minimumSize: Size.fromHeight(56)` is worth keeping for a reason the finding did not give: the current `FilledButton` at 1785 takes the Material 3 default height of 40 logical px, under the 48 px minimum. Pinning it also fixes that.

5. No extra bottom inset is needed. `DriverShell` wraps the body in `SafeArea` (driver_flow.dart:117) above the `NavigationBar` (118-119), so the pinned bar already lands directly above the nav bar as intended.

6. Leave the GPS note at 1773-1778 in the list. It is the `!_hasActiveShipments` branch and is informational, not an action.


**MEDIUM — The bottom nav is live and unauthenticated on the landing screen, and dead-ends in an API error**  
`lib/driver_flow.dart:2269` · navigation  

*What goes wrong:* A driver's very first screen on Android shows a five-tab bar under a sign-in menu. The natural first tap is a tab, not one of the five stacked buttons above it. That tap fires an authenticated API call with no token and paints `HTTP 401: {...}` in red on the Shipments screen, with no sign-in prompt and no way back except the Home tab. It is the first impression the app makes, and it is a failure the driver did not cause.

*Fix:* The first half of the proposed fix is sound but should be written `showBottomNav: path != "/driver"` rather than the ternary. The second half, the redirect, would break signed-in drivers and must not ship as written.

Why the redirect breaks: `DriverSession.hasCarrierOrg` (driver_session.dart:16) is in-memory only, and nothing calls `DriverSession.refresh()` at startup — main() (main.dart:62-66) does `api = Api(resolveApiBaseUrl()); runApp(...)` and nothing else, and all ten refresh() callers are inside screens the user has already reached. So on every cold start hasCarrierOrg is false even when a valid token is sitting in secure storage. A `redirect` keyed on it would bounce an already-signed-in driver off any deep link into /driver/shipments or a POD link back to the welcome screen, which is a worse failure than the one being fixed, and on the money path.

A second problem with `path != "/driver"`: /driver is also the Home tab (`_pathForIndex` case 0, line 76-78). For a signed-in driver, tapping Home would make the tab bar disappear, which is a new bug. Gate on session, not path.

Concretely:
1. At 2262-2266, pass `showBottomNav: DriverSession.hasCarrierOrg`. The ShellRoute builder re-runs on every navigation, and every sign-in path ends in a `context.go` into /driver/*, so the bar appears the moment a session exists and stays hidden before that. Add the `driver_session.dart` import usage at the top of the routes function only, no new state.
2. Replace the blanket redirect with an honest empty state on the screens themselves. In DriverShipmentsScreen.build, before the `_error` block at 754-756, render: when `_error != null && !DriverSession.hasCarrierOrg`, show `Text("Sign in to see your bookings.")` in DriverTheme.muted plus a `FilledButton(onPressed: () => context.go("/driver/onboarding/phone"), child: const Text("Sign in with phone"))`, and suppress the raw `_error` string. This also covers the expired-token case for a signed-in driver, which the redirect would not have caught.
3. Independently of this finding, the raw `HTTP ${status}: ${body}` from pilot_api.dart:74 should never reach a driver's screen. That string belongs behind the Developer lab; user-facing copy should be a plain sentence. Worth raising as its own finding rather than folding it in here.
4. If a route guard is still wanted later, it needs a startup `await DriverSession.refresh()` before runApp (with a loading route while it is in flight) so hasCarrierOrg means "no session" rather than "not asked yet". That is an architecture change, not a one-line addition, and should be a separate decision.


**MEDIUM — A returning signed-in driver gets the full sign-in menu every launch**  
`lib/driver_flow.dart:151` · empty-state  

*What goes wrong:* The token survives app restarts, so the driver is still signed in — but the screen cannot know that because it never asks. Every single launch, a driver who has been using the app for weeks is shown five options and has to work out that the third one, an outlined button reading "Continue as signed-in driver", is the one that applies to them. The primary-weighted button on the screen is "Sign in with phone", which is the wrong action for every returning user. If they press the third one and the network is patchy, `refresh()` returns false (driver_session.dart:85-87) and they get "Sign in first, or complete carrier registration." (190) — telling a signed-in driver they are not signed in.

*Fix:* The diagnosis is right; the fix needs three corrections before it is implementable.

1. The "token exists" branch cannot be written today. `Api` exposes only `setToken` (pilot_api.dart:48) and `clearToken` (49); `_storage` is a private top-level const (24), and grep over lib/ finds no reader outside the interceptor at 37. Add `Future<bool> get hasStoredToken async { final t = await _storage.read(key: "access_token"); return t != null && t.isNotEmpty; }` to `Api` first.

2. "Route to /driver/loads anyway when refresh() fails but a token exists" is wrong as stated, because driver_session.dart:85-87 catches everything and returns false identically for a 45s network timeout and for a 401 on an expired token. Sending an expired-token driver to `/driver/loads` lands them on a screen whose `_load()` (driver_flow.dart:888-909) will surface a 401 through `formatApiError(e)` at 905 with no sign-in button anywhere on it. Distinguish by status code instead: in `refresh()`, catch `DioException` separately and, on `e.response?.statusCode == 401`, call `api.clearToken()` and return false; keep returning false for everything else. Then the welcome screen branches on three states, not two — signed in, signed out, and "token present but unreachable" (route to `/driver/loads`, which does render its own error at 905).

3. The five-button layout cannot simply be replaced, for two reasons. `hasCarrierOrg` (driver_session.dart:16) is false until the async refresh resolves, so a naive stateful build flashes the full sign-in menu and then swaps it — specify a third `_checking` state that renders a `CircularProgressIndicator` in the `Spacer()` gap at driver_flow.dart:171 until refresh returns. And dropping "the other four" removes the only UI entry to `/pilot-lab` (the TextButton at 197); the `/pilot-lab` route at main.dart:82 would still exist but become unreachable by tapping. Since the brief says the lab stays, keep that TextButton in the signed-in branch too, or move it behind `DriverProfileScreen`.

Also: "Not {carrierOrgName}?" reads oddly — `carrierOrgName` (driver_session.dart:6) is the carrier organization, not the person. Use `DriverSession.userFullName` (8) if set, falling back to `userPhone` (9): "Not {userFullName}? Sign in as someone else". Keep that as a neutral `TextButton` — no confirmshaming copy.


### Copy and microcopy

12 findings, 11 high.


**HIGH — Every driver-facing error is a raw HTTP body or a build instruction**  
`apps/driver_pilot/lib/driver_flow.dart:1839` · error-state  

*What goes wrong:* A driver whose delivery confirmation fails — the step that captures payment — is told `HTTP 500: {error: membership_not_found}` or told to redeploy an API with CORS enabled. They cannot tell whether the delivery was recorded, whether to retry, or whether they just lost the payment. On patchy connectivity this is the most-seen screen state in the app.

*Fix:* The finding is right; the mapping table as written would introduce a new money-path lie and one impossible instruction.

1. Drop every "Nothing was sent" for the timeout case. pilot_api.dart:32-33 sets `connectTimeout: const Duration(seconds: 45)` and `receiveTimeout: const Duration(seconds: 45)`. A `DioExceptionType.receiveTimeout` means the POST reached the server and may have been committed — the driver-pod write may have succeeded while the response never arrived. Telling a driver "Nothing was sent" there is exactly the misleading-about-money failure the finding objects to, inverted. Split the cases:
   - `connectionError` / `connectionTimeout` / `unknown` with a host-lookup message: "No internet. Nothing was sent. Try again when you have signal." (safe — the connection never opened)
   - `sendTimeout` / `receiveTimeout`: "The network dropped before we got a reply. Your delivery may or may not be confirmed — open the trip to check before retrying."
   Apply the same split to the 5xx line: "NaviG8r is not responding" is fine, but delete "nothing was confirmed" — a 500 can be thrown after a partial write, and the client cannot know. Use "Try again in a minute. Check the trip before re-confirming."

2. Drop "Pull down to refresh and try again" from the 404/409/422 line. RefreshIndicator appears only at driver_flow.dart:744, 998 and 1246; DriverPodScreen (driver_flow.dart:1803-) has none, and neither do most of the other SnackBar sites. The copy would instruct a gesture the widget tree does not provide. Use "That did not work. Go back and open the trip again." for the generic case.

3. Handle 409 separately on the POD screen rather than folding it into the 404/422 bucket. On a confirm-once endpoint, 409 most likely means already confirmed — the one outcome where retrying is both harmless and pointless, and where the driver most needs to be told the money is safe: "This delivery is already confirmed. Nothing more to do." Whether the API actually returns 409 for that is unchecked — it needs confirming against the server route before the string ships.

4. Keep the finding's POD-specific string, minus the false part: "Delivery was not confirmed. Try again." rather than "...Nothing was sent. Try again."

The structural half of the fix is sound and should ship as proposed: add `driverErrorMessage(Object e)` beside formatApiError in pilot_api.dart, swap it into the SnackBar and `_error` sites in driver_flow.dart and customer_flow.dart, and leave formatApiError for the main.dart lab (10 call sites) where the CORS and --dart-define strings are addressed to a developer and are genuinely useful. Log the raw formatApiError output to console at each swapped site so field debugging does not lose the status code.


**HIGH — One object, four names: anchor trip, trip, load, lane**  
`apps/driver_pilot/lib/driver_flow.dart:986` · terminology  

*What goes wrong:* In Indian trucking a 'load' is the cargo you carry. This app puts published routes under a tab called 'Loads' and the actual cargo under 'Shipments', which inverts the driver's own vocabulary — so a driver looking for the goods they must accept goes to the wrong tab. 'Anchor' is internal data-model vocabulary with no meaning to a driver, and 'lane' is dispatcher English.

*Fix:* The fix is sound in direction but incomplete in two ways that matter, and one instruction in it is unsafe as written.

1. Do not do this as a find-and-replace on "load". driver_flow.dart:1673 reads `? "Could not load trip."` — "load" there is the verb for a failed fetch and must not become "trip". Change the listed strings individually.

2. Add the strings the fix missed, all driver-facing: line 1138 `"${_formatVehicle(vClass)} vehicle · $res kg booked on this lane"` -> "... kg booked on this trip"; 1492 "Load complete — all deliveries confirmed." -> "Trip complete. All deliveries confirmed."; 1506 "Load marked complete." -> "Trip marked complete."; 1523 "Load started." -> "Trip started."; 1706 "All bookings have proof of delivery — complete the load to stop tracking." -> "... finish the trip to stop tracking."; 1749 "No pending deliveries on this load" -> "No pending deliveries on this trip"; 1776 "Live GPS is shared with customers while the load is in progress." -> "... while the trip is in progress."

3. Correct the nav citation: the label is driver_flow.dart:135, not 136.

4. Fix the second half of the vocabulary problem the finding opened but left hanging. The proposal settles on "booking" for the customer's goods, yet leaves the tab called "Shipments" — so the same record would still carry two names. The code already calls it both: line 728 and 808 "Booking accepted.", line 857 "Accept booking", against nav label 130 "Shipments" and shell title 21 "Shipments", and line 1723 uses both in one sentence: "Accept customer bookings on Shipments before starting." Either rename nav label 130 and shell title 21 to "Bookings" and rewrite 1723 as "Accept customer bookings before starting.", or keep "Shipments" and change 728, 808 and 857 to "Shipment accepted." / "Accept shipment". Pick one and apply it in the same pass, otherwise the trip/load fix just relocates the defect.

5. Align the publish surface, which the fix only half-covers: shell title line 24 `return "Publish trip";` already says trip, so leave it, and change drawer 1394 "Publish anchor trip" -> "Publish a trip" as proposed so the two agree.

6. Keep the route paths as they are. `/driver/loads` appears at lines 56, 74, 187, 327, 1739, 2177 and 2284 and is a deep-link contract; renaming display strings without touching paths is the right call and the fix already does that. Same for the Dart identifiers DriverLoadsScreen, `_loadsSummary`, `canCompleteLoad`, `_completeLoad`, `defaultAnchorTripWindow` — renaming those is optional cleanup, not part of the user-facing fix, and mixing it in makes the diff harder to review.


**HIGH — The action that captures payment has three different labels and an unexplained acronym**  
`apps/driver_pilot/lib/driver_flow.dart:1789` · button-label  

*What goes wrong:* This is the step that releases the driver's money. A driver who learned the flow from the shipment list sees 'Confirm delivery', then from the active trip screen sees 'Mark arrived / POD' — a slash construction naming two different things — and on the final screen 'Confirm POD'. 'POD' is never expanded next to the button, and a non-first-language English reader has no way to decode it.

*Fix:* Keep the two button renames, drop the line-28 change as written, and do not replace the body copy.

1. driver_flow.dart:1789 — `child: const Text("Mark arrived / POD"),` becomes `child: const Text("Confirm delivery"),`. Justified beyond consistency: the handler at :1787 only pushes the POD route, so "Mark arrived" describes an action that does not exist.

2. driver_flow.dart:1863 — `: const Text("Confirm POD"),` becomes `: const Text("Confirm delivery"),`.

3. Do NOT change line 28 to "Confirm delivery". `path.startsWith("/driver/shipment/")` matches the detail route `/driver/shipment/:id` as well as the `/pod` leaf, so DriverShipmentDetailScreen is already titled "Proof of delivery" while showing status, pickup, drop, net-to-carrier and an "Accept booking" button (:852-858). The finding's edit would retitle that screen "Confirm delivery", making it worse. Split the branch instead, POD test first because both paths satisfy the startsWith:
     if (path.startsWith("/driver/shipment/") && path.endsWith("/pod")) return "Confirm delivery";
     if (path.startsWith("/driver/shipment/")) return "Shipment";

4. Do NOT replace line 1853 with "Confirming sends proof of delivery (POD) to NaviG8r." The current copy is "Confirming delivery submits proof of delivery to the platform. Ops will release customer payment to your carrier ledger after review." The proposed sentence deletes the second clause, which is the only statement on the screen that payment is not immediate — that is a hidden-cost regression on a money screen. Bind the acronym in place and keep both sentences: "Confirming delivery submits proof of delivery (POD) to the platform. Ops will release customer payment to your carrier ledger after review."

5. Same concern, one line the finding missed: driver_flow.dart:2088 reads `const Text("No payout batches yet. Complete POD on shipments and wait for batch settlement."),` — a bare "POD" on the payout-history screen, far from any expansion. Change to "Complete delivery confirmation on shipments and wait for batch settlement."


**HIGH — Payout history shows a raw epoch timestamp and ledger jargon instead of a date**  
`apps/driver_pilot/lib/driver_flow.dart:2093` · money-copy  

*What goes wrong:* A carrier owner checking whether last week's money arrived reads 'Cutoff 1757894400000 · 3 lines'. The one screen whose whole job is to answer 'was I paid, and for what' answers in milliseconds since 1970 and an accounting word. There is no date anywhere on the row.

*Fix:* The finding stands, but the proposed replacement string is wrong in three ways and would ship new inaccuracies onto a money screen.

1. "Paid for deliveries up to ..." asserts money moved. It has not necessarily moved. types.ts:234-239 defines `PayoutTransferStatus = "BOOKKEEPING_PAID" | "PROCESSING" | "PAID" | "FAILED" | "SKIPPED_NO_FUND_ACCOUNT"`, and types.ts:258-259 documents provider as `"BOOKKEEPING" (no money movement) or "RAZORPAYX" (real payouts)`. A batch with a FAILED or SKIPPED_NO_FUND_ACCOUNT transfer for this carrier still appears in this list. Labelling it "Paid" violates "what the user sees matches what they get". Use a status-neutral period label and derive the state word from this carrier's own transfer entry, e.g. subtitle `"Payment period ending $date - $n deliveries"` with a separate status line ("Sent to your bank", "Processing", "Could not be sent - add your bank account", "Recorded, not yet sent" for BOOKKEEPING).

2. `?? 0` silently renders 01 Jan 1970. On a payment screen a wrong date is worse than a missing one. Drop the date segment when the field is absent or not a num rather than defaulting to 0.

3. The count `(b["lineIds"] as List?)?.length` is not this carrier's delivery count. services.ts:2269 sets `lineIds: settledLineIds`, accumulated across every carrier in the batch (services.ts:2242 `settledLineIds.push(...lineIds)` inside the per-carrier loop). The same flaw hits the amount already on line 2092: services.ts:2266-2268 sums `netToCarrierPaise` across all transfers whose status is BOOKKEEPING_PAID, PAID or PROCESSING, so `totalNetToCarrierPaise` is the whole batch across all carriers, not this carrier's money. Renaming "lines" to "deliveries" without fixing this makes a wrong number more believable. Read the carrier's own entry instead: find the element of `b["transfers"]` whose `carrierId` equals `DriverSession.carrierOrgId`, and take `netToCarrierPaise` for the title and `lineIds.length` for the count. (The over-reporting amount is a separate defect worth its own finding; flagging it here only because the proposed fix would compound it.)

The mechanical part of the fix is sound. `formatIstDate` does belong beside `formatInrFromPaise` (pilot_api.dart:121-125), but note that `formatIstIsoFromUtc` (pilot_api.dart:127) takes a `DateTime`, not epoch ms, so the new helper converts first rather than calling it: `DateTime.fromMillisecondsSinceEpoch(epochMs.toInt(), isUtc: true).add(const Duration(hours: 5, minutes: 30))`, then format as a day-month-year string ("14 Sep 2026"), not ISO, since the reader is a driver or owner-operator. All lines in a batch share one cutoff (services.ts:2183 filters to `payoutBatchCutoffUtcMs === earliestCutoff`), so a single date on the row is factually correct.

The empty-state rewrite at line 2088 is sound as proposed and needs no correction.


**HIGH — The landing screen promises payment after "cooling-off", a term used once and never defined**  
`apps/driver_pilot/lib/driver_flow.dart:168` · money-copy  

*What goes wrong:* This is the first and often only sentence a driver reads before deciding to sign up, and it is the app's only statement about when they get paid. 'Cooling-off' is legal-contract English; a driver cannot tell whether it means one day or one month, and no later screen tells them. The earnings screen then says the money 'sits on the platform ledger' with no timeframe either.

*Fix:* The finding is right; the fix is not. "Payments are released N days after delivery" is a flat-N promise the backend does not make, and shipping it would replace vague copy with inaccurate copy on a money screen. Four corrections.

1. The real policy is a hold PLUS a weekly batch, not N days. packages/core/src/payoutSchedule.ts:11 `export const PAYOUT_HOLD_CALENDAR_DAYS = 7;` and its header comment: "Carrier net (X − C) is included in the next weekly batch cutoff that is >= (POD IST calendar date + 7 calendar days) at 00:00 IST." apps/api/src/config.ts:4-8 sets `cutoffWeekday: 3, // Wednesday`, `cutoffHour: 18`, `cutoffMinute: 0`. computePayoutBatchAssignment (payoutSchedule.ts) applies the 7-day hold, then rolls forward to the next Wednesday 18:00 IST cutoff. Real wait after delivery is therefore 7 to 14 days, not a fixed number. N is already settled in code — it just is not a single number, so the copy must state both parts.

Landing copy, driver_flow.dart:167-168, replacing both string fragments (keep "confirm your carrier organization" — the proposed fix silently dropped a real onboarding step):
  "Sign in with your phone, confirm your carrier organization, and run trips with live tracking. "
  "After proof of delivery, payment is held 7 days, then paid in the next weekly payout run (Wednesday)."

2. Do not promise payment on the driver's own confirmation. The proposed "get paid after you confirm delivery" contradicts driver_flow.dart:1853, which already tells the driver "Ops will release customer payment to your carrier ledger after review." Either keep ops review out of the landing summary (as above, which says "after proof of delivery") or name it — but do not imply the driver's tap is the last gate.

3. The earnings-screen placement is wrong as specified. driver_flow.dart:1925 is the true branch of a ternary whose condition is `kyc == "NOT_STARTED"` (line 1924); once KYC is SUBMITTED or APPROVED the widget renders line 1926 `"Payout profile status: $kyc"` instead, so timing copy pasted into 1925 disappears for exactly the drivers who are waiting on money. Add it as a separate const Text inside the same Card at driver_flow.dart:1920-1930, outside the ternary, so it renders in every KYC state:
  const Text(
    "After proof of delivery, payment is held 7 days, then paid in the next weekly payout run (Wednesday).",
    style: TextStyle(color: DriverTheme.muted),
  ),
Same string on the payout history empty state, driver_flow.dart:2088, which currently reads "No payout batches yet. Complete POD on shipments and wait for batch settlement." — "batch settlement" is the same undefined-jargon problem as "cooling-off".

4. The fix as proposed leaves the term alive server-side. apps/api/src/services.ts:1095 and :1109 both contain "Transfers run after POD, cooling-off, and batch settlement — not at signup.", and that message is shown verbatim to the driver via the SnackBar at driver_flow.dart:1998-2001. Change both API strings to the same plain sentence, otherwise a driver who saves a payout method still gets "cooling-off" with no definition.

Cross-check before implementing: I verified the 7-day hold and Wednesday 18:00 IST cutoff in source, but I have not verified that this is the policy the business has actually committed to pilot carriers. Confirm with the product owner that code matches policy before this number goes in front of a driver.


**HIGH — "Ops" is the named gatekeeper of the driver's money**  
`apps/driver_pilot/lib/driver_flow.dart:865` · jargon  

*What goes wrong:* 'Ops' is internal team shorthand. A truck driver or owner-operator reading 'Awaiting ops payment release' has no referent for it — it is not a person, a company name, or a process they can chase. It appears on exactly the screens where the driver is waiting for money, so it is the word standing between them and knowing who to call.

*Fix:* The three driver_flow.dart rewrites are sound, but the pilot_api.dart:157 rewrite is wrong and should not ship as written, for two reasons.

First, `shipmentStatusLabel` is shared, not driver-only. It has five call sites and one of them is the customer web portal: customer_flow.dart:1843 `final status = shipmentStatusLabel(s["status"]?.toString() ?? "");`, rendered into a ListTile subtitle at line 1849. The customer paid at booking; telling them "Payment being released" reads as money moving toward the reader and can be misread as a refund in progress. Any string in this function has to be true for a driver, a carrier owner, and a paying customer at once.

Second, "Payment being released" is inaccurate even for the driver. PENDING_RELEASE means the release has not happened. The proposed copy asserts an in-flight transfer the backend state does not claim, which trades one honesty problem for another.

Use instead, at pilot_api.dart:157: `return "Delivered — payment being processed";`. It is audience-neutral, keeps the not-yet-done sense, and matches copy the codebase already shows customers for this same state at pilot_api.dart:351 — `return "Delivered — proof submitted. Live tracking has ended while payment is processed.";` — so the two no longer contradict each other on the same screen.

Also add the instance the finding missed. driver_flow.dart:1853 is the standing body copy on the POD screen and carries the same jargon with the widest exposure: `"Confirming delivery submits proof of delivery to the platform. Ops will release customer payment to your carrier ledger after review.",` -> `"Confirming delivery sends your proof of delivery to NaviG8r. After a check, the customer's payment moves to your carrier ledger."`. Fixing 1833 (the SnackBar) while leaving 1853 (the explanation directly above the button that triggers it) means the same screen says "Ops" before the tap and "NaviG8r" after it.

One further note on the 1768 rewrite: "Being checked" as a bare ListTile trailing loses the money referent entirely — the row's subtitle at driver_flow.dart:1759 shows the net amount, so the trailing is the only thing saying what is pending. Prefer `const Text("Payment check", ...)` or `const Text("Payment pending", ...)`, keeping the existing `style: TextStyle(fontSize: 12, color: DriverTheme.muted)`. Note DriverTheme.muted (#64748B) on the card surface should be contrast-checked at 12sp regardless; that is a separate finding, not this one.


**HIGH — A driver-facing error tells the user to merge a pull request**  
`apps/driver_pilot/lib/driver_flow.dart:1587` · developer-string-leak  

*What goes wrong:* A driver on an active trip whose booking list fails to load is shown a raw HTTP error followed by an instruction to merge a named pull request. It is unactionable, it leaks internal branch names, and it reads as if the app is broken beyond recovery — which may cause the driver to abandon a trip that is actually fine.

*Fix:* The fix is right to delete the parenthetical, but its replacement copy is not supported by this screen. `grep -n RefreshIndicator driver_flow.dart` returns only 744, 998 and 1246 — all outside _DriverActiveTripScreenState (1427-1802) — and no button between 1682 and 1802 calls `_load`. So "Pull down to refresh." instructs an action the widget tree does not offer.

Do one of these instead:

(a) Add the affordance, then keep refresh copy. Wrap the ListView at driver_flow.dart:1678 in `RefreshIndicator(onRefresh: _load, child: ListView(...))` (ListView already scrolls, so the gesture will fire), and set:
    _error = "Could not load the bookings on this trip. Pull down to refresh.";

(b) Or keep the widget tree as-is and give the user a control. Set:
    _error = "Could not load the bookings on this trip.";
and replace the bare Text at 1681 with an error block that pairs it with `TextButton(onPressed: _load, child: const Text("Try again"))`.

Either way, move the deploy note to `debugPrint("shipments fetch failed: $msg")` as proposed, and do not put `$msg` in the user-visible string — formatApiError (pilot_api.dart:58-77) also emits "HTTP 404: ..." and "--dart-define=API_BASE_URL=..." text.

Two adjacent notes, out of scope for this finding but touching the same lines: `Colors.red` (#F44336) at 1681 on the #F4F7FA background is about 3.7:1, under WCAG AA 4.5:1 for body text, and the theme has no error token; and because the assignment at 1586 only writes when `_error == null`, a trip-fetch error at 1565 suppresses the shipments error entirely, so the driver sees one of two failures, never both.


**HIGH — "Debug OTP" and a "Challenge id" field sit on the driver's real sign-in screen**  
`apps/driver_pilot/lib/driver_flow.dart:363` · developer-string-leak  

*What goes wrong:* A pilot driver verifying their phone sees a field labelled 'Challenge id' holding an opaque string they did not type and cannot understand. It is editable: clearing or altering it makes verification fail with a raw HTTP error, and nothing on screen tells them how to recover. 'Debug OTP' above it announces that the app is in a test mode, which undermines trust on the screen that guards their account.

*Fix:* The finding is sound, but the proposed fix has one real hole and one thing to add.

Hole: `if (kDebugMode)` is the wrong guard for the pilot. `kDebugMode` is false in a release APK, and a pilot build handed to drivers is a release build talking to a pilot backend that still returns `debugCode`. So wrapping only line 360 hides the label while line 306, `        _code.text = dc;`, still silently pre-fills the "6-digit code" field with the server's code. That is worse than the current state: the driver sees a code box that fills itself from nowhere, and the OTP step becomes a tap-through that verifies without the driver ever reading an SMS. Guard the autofill and the label together, or drop both.

Corrected fix for driver_flow.dart:
- Delete line 363 entirely. Keep `final _challengeId = TextEditingController();` (280), the assignment at 302, the read at 320 and the `dispose()` at 345 unchanged — the user never needs to see or type this value.
- Replace the pair at 303-307 and the block at 358-361 with a single build-time flag, not `kDebugMode`: `const bool showPilotTestCode = bool.fromEnvironment("PILOT_SHOW_TEST_CODE");` at file top, passed via `--dart-define`. Gate both the `_code.text = dc;` autofill and the label on it. Label the text "Test code (pilot build)" rather than "Debug OTP".
- Add the recovery path the current screen lacks. With line 363 gone, an empty `_challengeId` after a failed `_resend()` is unrecoverable-looking, because the catch at 336-337 only shows `formatApiError(e)` in a snackbar. In `_verify`, before the POST at 318, add: `if (_challengeId.text.trim().isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not start verification. Tap Resend code."))); setState(() => _verifying = false); return; }`. The "Resend code" TextButton already exists at line 372, so that instruction points at something on screen.

For customer_flow.dart: apply the same flag to the 430-432 block and to the `_debugCode = dc;` assignment at 361 plus whatever autofill accompanies it. Note that this screen is the customer web login and has no "Challenge id" field, so only the label and autofill change there.


**HIGH — The Publish screen labels its inputs with raw API field names**  
`apps/driver_pilot/lib/driver_flow.dart:2226` · form-copy  

*What goes wrong:* Publishing a trip is one of the two things a carrier owner comes to this app to do, and the form asks them for 'windowStart (ISO)', 'capacityKg' and a pipe-delimited enum. A camelCase identifier is not readable as English at all to a non-first-language reader, and the ISO datetime field invites a format error whose only feedback is another camelCase string.

*Fix:* The Publish-screen half of the fix is sound as written. Three corrections before it is implemented:

1. Narrow the Profile claim. driver_flow.dart:1372, 1373 and 1377 already read "Vehicle registration", "Vehicle class (SMALL|MEDIUM|LARGE)" and "Vehicle capacity (kg)". Do not relabel them. What is actually wrong on Profile is the pipe-delimited enum as free text at 1373 (swap to the same DropdownButtonFormField) and the raw-identifier snackbar at 1322, which becomes "Choose a truck size." The same enum-as-free-text pair also exists at driver_flow.dart:461 and 665 and should be changed in the same pass for consistency.

2. A plain date picker is the wrong widget and would silently change the payload. The fields are prefilled in initState (driver_flow.dart:2124 `defaultAnchorTripWindow(_w1, _w2)`), and pilot_api.dart:138-148 sets start to midnight IST today and end to 23:59:59 two days out, formatted by `formatIstIsoFromUtc` (pilot_api.dart:127). Use a date-range picker labelled "Available from" / "Available until" whose selection is passed through `formatIstIsoFromUtc` before being written to `_w1`/`_w2`, so the strings posted at driver_flow.dart:2171-2172 keep the exact IST-offset format the API already receives. A date-only picker drops the time component and changes what the backend is sent.

3. The vehicle-class dropdown must keep feeding `_vehClass.text`, because `_submit` reads `final vc = _vehClass.text.trim().toUpperCase();` at driver_flow.dart:2156. Either write "SMALL"/"MEDIUM"/"LARGE" into the controller on change, or replace the controller with a `String?` field and update both 2156 and the dispose call at 2134. Build the items from `vehicleClassLabel` (pilot_api.dart:180) so the publish form and the customer-facing strings at customer_flow.dart:1410 stay on one vocabulary.

With a dropdown in place, the 2158 branch becomes unreachable for empty-state only; keep a "Choose a truck size." message for the unselected case rather than deleting the check.


**HIGH — Customer sees "Estimated price" then a button that charges a figure from a different API call**  
`apps/driver_pilot/lib/customer_flow.dart:1732` · money-copy  

*What goes wrong:* The customer reads a number labelled 'Estimated', taps a button that says it will pay, and the Razorpay sheet opens with a figure the screen never displayed. There is also no line for GST, platform fee or any surcharge on the same screen as the headline number, so the customer cannot tell what the total includes.

*Fix:* The proposed fix cannot be implemented as written and one line of it is a dark pattern in its own right.

1. DROP the GST / platform-fee breakdown. `FreightBreakdown` (services.ts:1556-1568) contains only: pricingMode, modelVersion, vehicleClass, laneKm, shipmentKm, distanceKmForPrice, paisePerKm, distanceComponentPaise, weightComponentPaise. Rendering a "GST" or "platform fee" row would mean inventing a charge the server never applies — showing a tax line for tax that is not collected is itself a dark pattern. The honest breakdown from fields that exist is: "Distance {distanceKmForPrice} km at {paisePerKm}/km — {distanceComponentPaise}" and "Weight {weightKg} kg — {weightComponentPaise}", then "Total {grossPaise}". When `pricingMode == "weight_only"` show only the weight row. If `grossPaise` exceeds the two components the minimum fare floor applied (services.ts:1399) and the card should say "Minimum fare applied" rather than silently showing components that do not add up.

2. DROP `Text("Pay ${formatInrFromPaise(_quote!["grossPaise"] ...)} and book")` on the button. Two problems: `_quote!` force-unwraps a field that is null in the screen's default state (declared `Map<String, dynamic>? _quote;` at customer_flow.dart:1441 and assigned only inside `_fetchQuote` at 1560), so it throws unless guarded; and putting the quote figure on the pay button promises a number the server may not charge in exactly the cases below.

3. Fix the real defect instead — the screen can present a figure that is not the one charged, in three concrete ways the finding did not identify:
   - `_quote` is never invalidated. It is assigned only at customer_flow.dart:1560. Editing weight, pickup, drop or the trip id leaves the old card on screen. Add `setState(() => _quote = null)` to an `onChanged` on `_weightKg`, `_anchorTripId`, and to the `onPositionChanged`/label callbacks for both LocationEndpointEditors, so the card disappears the moment its inputs stop being true.
   - Quote and book do not use the same vehicle class when no trip is selected. `quoteShipmentMarketplace` defaults `vehicleClass = "MEDIUM"` (services.ts:1430) when `anchorTripId` is absent, and the client sends it only when the field is non-empty (customer_flow.dart:1557-1558); `bookShipment` always uses `trip.vehicleClass` (services.ts:1573) and rejects an empty id (customer_flow.dart:1571-1574). So disable the "Get quote" OutlinedButton at customer_flow.dart:1697 when `_anchorTripId.text.trim().isEmpty`, with helper text "Choose a trip from the Trips tab to price this shipment" — the same precondition book already enforces.
   - Gate the pay action on a current quote. Change customer_flow.dart:1704 from `onPressed: _booking ? null : _book` to `onPressed: (_booking || _quote == null) ? null : _book`, so the Book & pay button cannot be tapped before a price has been shown.

4. Copy: relabel line 1732 from "Estimated price" to "Price for this shipment", and put a plain line under the total before the button: "This is the amount you pay now." That is accurate — `payment.amountPaise = grossPaise` at services.ts:1591 from the same pure function — once the three divergence paths above are closed. Keep "Book & pay" as the button label.


**HIGH — Every string is a hard-coded English literal with no localization layer**  
`apps/driver_pilot/lib/main.dart:102` · accessibility  

*What goes wrong:* The Android app targets truck drivers and owner-operators in India who may not read English, and the money path — confirm delivery, payout setup, earnings — is English-only with no path to a second language. Separately, because the strings are inline rather than in a table, there is nothing to hand a translator; the cost of adding Hindi or a regional language grows with every screen added.

*Fix:* The finding is right; the fix as written is over-scoped in one place and has a hole in another.

Over-scoped: "move the driver-flow strings out of the widget trees in the same pass as the terminology rename" is a ~254-literal edit across three files of 2305, 2149 and 1151 lines, bundled with a rename. That is a refactor well past the three-file threshold that needs an explicit go-ahead, and bundling it with a rename makes the diff unreviewable — a bad substitution in a payout label is exactly the kind of error a large mixed diff hides. Split it:

Step 1, small and independently worth doing now: add `flutter_localizations` (sdk: flutter) and `intl` to pubspec.yaml, and pass `localizationsDelegates: GlobalMaterialLocalizations.delegates` plus `supportedLocales: const [Locale("en"), Locale("hi")]` at main.dart:102-106. This alone fixes the framework-supplied strings (text selection menu, any picker) and is the prerequisite for everything else. It changes two files.

Step 2, scoped to the money path only: create `lib/l10n/app_en.arb` and `flutter: generate: true`, then extract only DriverPodScreen (driver_flow.dart:1803-1869), DriverEarningsScreen (1871), DriverPayoutSetupScreen (1963) and DriverPayoutHistoryScreen (2045). Land it as its own commit, separate from the rename. Leave the other 29 screens on literals until a second locale is actually funded — extracting all of them buys nothing today and costs reading time on every screen.

Hole in the fix: an ARB file does not reach the error text these screens actually show under failure. Every catch block on the money path renders `formatApiError(e)` (driver_flow.dart:1839 on POD, 2010 on payout setup, and 17 other sites), and pilot_api.dart:74 returns `"HTTP ${status ?? "?"}: ${body ?? e.message ?? e.toString()}"` — raw server body, plus hardcoded developer-facing English at pilot_api.dart:65-72 telling the user to "redeploy the API with CORS enabled" or pass `--dart-define=API_BASE_URL=...`. driver_flow.dart:1998 has the same shape for the success case: `final msg = r.data?["message"]?.toString() ?? "Saved.";`. So the fix needs a third part: map API failures to a small set of client-side message keys the ARB file owns (network unreachable, session expired, payout details rejected, server error) and keep the raw `formatApiError` string behind a details affordance for support. Otherwise a driver who cannot read English still gets an English wall of text at the exact moment a payout fails — the highest-stakes string in the app and the one localization would have missed.

Keep the finding's last sentence as written: record the English-only decision explicitly rather than letting it stand as a default.


**MEDIUM — Payout setup copy is written from the platform's point of view, not the driver's**  
`apps/driver_pilot/lib/driver_pilot_placeholder:2018` · money-copy  

*What goes wrong:* 'Collect once' is an instruction to whoever built the form, not to the driver entering their bank details — read as an imperative it tells the driver to collect something. 'Your payment provider' is wrong from the driver's side: the driver does not have one, NaviG8r does. 'Real transfers' implies there are fake ones, leaking the pilot context onto a bank-details screen. 'Save and verify' promises verification that the screen does not perform — it pushes to payout history (line 2002).

*Fix:* The diagnosis is sound but the proposed replacement copy introduces a new factual error and misses a mode-dependent claim.

1. Line 2018. The fix proposes "Your bank may ask you to complete KYC checks." That is wrong in the same direction as the original. KYC here is NaviG8r's, not the driver's bank's: `pilotSubmitPayoutSetup` stores `kycStatus` on the carrier Organization (services.ts:1103) and, in RazorpayX mode, sets it to "APPROVED" after `createRazorpayBankFundAccount` (services.ts:1085). The driver's own bank does nothing. Use instead: "Add your bank account once, before your first payment. NaviG8r checks these details before money is sent."

2. Line 2029. "Your payments go to this account." is an improvement, but the field is not unconditionally required, and the current helperText says "Required". services.ts:1072-1076 only throws `invalid_payout_profile` for a missing accountNumber when `razorpayPayoutsEnabled()`; README.md:44 states that otherwise "the optional accountNumber is accepted but not used." Either make the helperText unconditional and non-committal — "Your payments go to this account." — or drive a "Required"/"Optional" marker off the server's payout mode. Do not ship a static "Required" that the API does not enforce.

3. Line 2037. "Save bank details" is right. But do not put a static promise line under the button: `_save()` already surfaces the server's own message (:1998-2001), and that message differs by mode — "Payout details received for verification..." versus "Bank account registered for payouts..." (services.ts:1096-1108). A hardcoded "NaviG8r checks these details before your first payment." would contradict the RazorpayX-mode message. Better: keep the button as "Save bank details", and replace the transient SnackBar with a persistent status line on the payout screen driven by `DriverSession.kycStatus` (driver_session.dart:23 already derives `payoutSetupComplete` from "SUBMITTED"/"APPROVED"), so the driver can still see the state after navigating. That also fixes the underlying problem the finding gestures at: the only confirmation of a money-critical save is a SnackBar the user is navigated away from.

4. Out of scope for this finding but the same string family: driver_flow.dart:1388 `"Set up before first transfer"` should move to the same word as the rest of the fix — "Set up before your first payment".


### Honest UX

11 findings, 5 high.


**HIGH — Payout setup asks for a bank account number that the default backend mode throws away, then reports it as on file**  
`apps/driver_pilot/lib/driver_flow.dart:2029` · data-minimisation  

*What goes wrong:* On the two environments a pilot carrier will actually use, the app collects a live bank account number over the network for a feature that cannot use it, discards it, says it was received for verification, and then tells the carrier their payout method is on file. The carrier believes they are set up to be paid when no account exists anywhere, and no verification of any kind has run.

*Fix:* The fix is directionally right but not implementable as written; three corrections.

1. Drop the false evidence line. "Organization has no bank fields at all (types.ts:46-56)" is wrong — types.ts:53 and :55 declare `payoutContactId?: string;` and `payoutFundAccountId?: string;`, and the finding's own fix depends on the latter. Replace with the accurate and still-damning version: those fields are written only in the RAZORPAYX branch (services.ts:1088-1089), and the raw account number is never persisted in either mode.

2. The mode cannot arrive on the payout-setup response. `/v1/pilot/carrier/payout-setup` is POST-only (httpServer.ts:761), so a `payoutsMode` in its reply lands after the carrier has already typed the account number — exactly the collection the fix is trying to prevent. Expose the mode on something the screen can read before rendering: add `payoutsMode: razorpayPayoutsEnabled() ? "RAZORPAYX" : "BOOKKEEPING"` to the carrier earnings summary (the object returned at services.ts:1044-1053, which the earnings screen already fetches at driver_flow.dart:1893 and which already carries `kycStatus`), and pass it into DriverPayoutSetupScreen when pushing /driver/payout-setup, or read it from a small GET. Then hide the TextField at 2024-2031 when the mode is BOOKKEEPING.

3. DriverSession has no field to drive the subtitle from. `refresh()` reads only `kycStatus` out of the matched org (driver_session.dart:44). The fix needs a `static String? payoutFundAccountId;` added alongside `kycStatus` (line 10), set in that same loop from `o["payoutFundAccountId"] as String?`, cleared in the two places kycStatus is cleared (lines 60 and 96). pilotMe returns the whole Organization and httpServer.ts:564 serialises it as-is, so the value is already on the wire — no API change needed for this part.

Everything else in the fix stands: remove the field in BOOKKEEPING with body copy "Bank details are collected when real transfers are switched on for your carrier."; rename the button at 2037 from "Save and verify" to "Save payout details" since nothing is verified; and replace the driver_flow.dart:1388 ternary with a three-way subtitle — "Bank account registered" only when payoutFundAccountId is present, "Details submitted, not yet verified" for SUBMITTED, "Set up before first transfer" otherwise. Also update the body copy at driver_flow.dart:2018 ("Collect once before your first transfer. KYC may be required by your payment provider."), which makes the same implicit promise the button did.


**HIGH — No screen anywhere tells the carrier when the money actually arrives**  
`apps/driver_pilot/lib/driver_flow.dart:168` · money-disclosure  

*What goes wrong:* An owner-operator financing diesel cannot plan. Delivery to bank is 7 calendar days from the POD date and then the next Wednesday 18:00 IST batch - between 7 and 13 days, plus an ops release step with no stated SLA. "Cooling-off" and "batch settlement" are terms a pilot driver in India has no way to convert into a date, and the app never gives one even though the API returns the exact instant per shipment (Shipment.payoutBatchCutoffUtcMs, types.ts:187).

*Fix:* The finding stands, but the proposed fix is wrong in two places and would under-deliver on the exact screen that matters.

1. The gate `payoutBatchCutoffUtcMs != null` renders nothing during the window the driver cares about. submitDriverPod (services.ts:1686-1723) sets only status PENDING_RELEASE and podAtUtcMs; payoutBatchCutoffUtcMs is set only in finalizeDeliveredShipment (services.ts:1650-1660), which runs at ops release (services.ts:1956-1957). So between driver POD and ops release the field is null and DriverShipmentDetailScreen still shows just "Awaiting ops payment release." (driver_flow.dart:867). The date would appear only after the wait had already started.

   Corrected: have the carrier shipments route attach a projected cutoff for PENDING_RELEASE shipments. computePayoutBatchAssignment(podAtUtcMs, PAYOUT_BATCH_SCHEDULE) (payoutSchedule.ts:156-163) needs nothing but podAtUtcMs, which is already set at driver POD, so shipmentWithCarrierDisplay (services.ts:201-206) can add `projectedPayoutBatchCutoffUtcMs` in one call. Keep the rule in TypeScript; do not reimplement the IST-midnight-plus-7-then-next-Wednesday arithmetic in Dart next to formatIstIsoFromUtc (pilot_api.dart:127) — a money rule that exists in two languages will diverge. In Dart, render the confirmed value when DELIVERED and the projected value when PENDING_RELEASE, labelled as an estimate: Text("Expected in the batch of ${formatIstDateFromUtcMs(ms)}") and, for PENDING_RELEASE, a second muted line "Estimated. Confirmed once ops reviews your delivery."

2. The copy overstates precision on both ends. Worst case is longer than 13 days: eligibility is POD IST date + 7 at 00:00, and if that lands on a Thursday, nextWeeklyBatchCutoffUtcMs (payoutSchedule.ts:107-153) pushes to the following Wednesday 18:00, about 13 days 18 hours after the POD date. And the cutoff is batch inclusion, not bank credit — runPayoutBatch fires on a setInterval (apps/api/src/index.ts:26-30) and then goes through the payout provider, so "land" promises something the code does not guarantee.

   Corrected Earnings copy, placed directly under the stat-tile Row (after driver_flow.dart:1917): "After you confirm delivery, money is held 7 days, then sent in the next weekly batch (Wednesday 6pm IST). That is usually 7 to 14 days from delivery. Ops reviews each delivery first."

   Corrected payout-history empty state (driver_flow.dart:2088): "No payouts yet. After you confirm delivery, money is held 7 days and is sent in the next Wednesday batch."

3. Add a third change the finding missed: driver_flow.dart:2093 prints a raw epoch integer. Replace `"Cutoff ${b["cutoffUtcMs"]} · ..."` with the same formatIstDateFromUtcMs helper and a plain label, e.g. "Paid in the batch of 17 Sep 2026 · 3 lines".


**HIGH — Earnings screen silently shows zero rupees when the request fails**  
`apps/driver_pilot/lib/driver_flow.dart:1888` · error-state  

*What goes wrong:* On patchy connectivity beside a truck - the normal case for this user - a failed fetch is presented as the truthful answer "Pending 0, Paid out 0" and "No payout batches yet". A carrier is told they are owed nothing and have been paid nothing when the app simply could not reach the API. There is no error text, no retry, and no pull-to-refresh on either screen.

*Fix:* The fix is sound in substance; two implementation details in it will not compile or will not work as described.

1. `_StatTile` cannot take a null value as written. driver_flow.dart:1942 is `const _StatTile({required this.label, required this.value});` with `final String value;` (1944). Passing `s == null ? null : formatInrFromPaise(pending)` requires changing the field to `final String? value;` and the Text at 1948 to `Text(value ?? "—", ...)`. `_StatTile` is private and used only at 1914 and 1916, so the signature change is contained.

2. Copying DriverShipmentsScreen's RefreshIndicator shape verbatim will not give a working pull-to-refresh here. At 744 that screen keeps its ListView mounted during load and shows the spinner as a child (757), and its list always has content above the fold. Both money screens instead replace the whole body with `Center(child: CircularProgressIndicator())` while `_loading` (1906-1907, 2082-2083), and the payout list is empty in exactly the failure case that needs the pull. So: put the RefreshIndicator outside the `_loading` conditional, always build a scrollable child, and add `physics: const AlwaysScrollableScrollPhysics()` to both ListViews — without it a ListView shorter than the viewport does not accept the drag and the retry gesture silently does nothing.

3. Match the existing error presentation rather than inventing one. driver_flow.dart:755 renders errors as `Text(_error!, style: const TextStyle(color: Colors.red))`; driver_theme.dart has no error token, so either reuse that pattern or add the token deliberately — do not introduce a third convention. Keep the retry as an OutlinedButton labelled "Try again" as proposed, and keep the copy neutral about cause (for example "Could not load earnings. Check your connection and try again.") since formatApiError's own strings (pilot_api.dart:65-71) are developer-facing, mentioning CORS, --dart-define and 10.0.2.2, and must not be shown raw to a driver.

4. Also gate the KYC card, not just the tiles. Line 1905 falls back to `DriverSession.kycStatus ?? "NOT_STARTED"`, so a failed load shows the "No bank details required at signup" NOT_STARTED message to a carrier who may already be verified. When `_error != null`, render the error card in place of the tiles and the KYC card together.


**HIGH — "Pending (accrued)" excludes every delivery waiting on ops, so a carrier who has delivered sees zero owed**  
`apps/driver_pilot/lib/driver_flow.dart:1914` · money-disclosure  

*What goes wrong:* A carrier can deliver five loads, submit POD on all five, and open Earnings to see "Pending (accrued) ₹0". The money exists and is owed, but it does not appear in any total until a human at ops presses release. The label "Pending" is exactly the word a carrier reads as "what I am owed", so the screen reads as a denial of the debt rather than a status of the paperwork.

*Fix:* The finding is right; the fix needs three corrections before it is implementable.

1. Do not relabel pendingAccruedPaise "In cooling-off". That is wrong for a real and common case. The payout sweep filters `(l) => l.status === "ACCRUED" && l.payoutBatchCutoffUtcMs <= now` (services.ts:2164) and then explicitly leaves lines ACCRUED when the carrier has no fund account: "continue; // leave lines ACCRUED so they retry once payout setup completes" (services.ts:2214), with the same for errors at 2238 and 2258. So an ACCRUED total can mean "waiting out the 7-day hold plus the Wednesday 18:00 IST cutoff" (PAYOUT_HOLD_CALENDAR_DAYS = 7 in payoutSchedule.ts:11; cutoffWeekday 3 / cutoffHour 18 in config.ts:4-8) OR "stuck indefinitely because you never finished payout setup". Use the neutral label "Scheduled for payout", and when `kyc == "NOT_STARTED"` (driver_flow.dart:1905) show under that tile "Blocked until you add a payout method" rather than any wording implying a timer is running.

2. Keep the new server field, but a cheaper client-only option exists and should be named in the ticket: /v1/pilot/carrier/shipments already returns PENDING_RELEASE shipments with netToCarrierPaise per shipment (driver_flow.dart:705, 712; used at 850 and 1759). The server field is still the better call because the earnings screen makes exactly one request today (driver_flow.dart:1893) and a second round trip is the wrong thing to add on patchy rural connectivity - but say that, do not present the server change as the only route. Add the field as its own key, not by reusing bookedCount, which lumps PENDING_CARRIER_ACCEPT, BOOKED and PENDING_RELEASE together (services.ts:1049-1051).

3. The layout will not take a third tile as-is. Line 1912-1917 is a Row of two Expanded _StatTile, and _StatTile renders its value at fontSize 22, FontWeight.w700 (driver_flow.dart:1953). Three of those at ~360dp with a value like the formatted paise total will overflow. Specify the layout: keep the Row at two tiles ("Awaiting ops release" and "Scheduled for payout") and put "Paid out" on a second Row below, or drop the value to fontSize 18. Do not leave it as "add a third tile".

The explanatory copy is fine and is not a dark pattern, but drop any implied date for the ops-release bucket: a PENDING_RELEASE shipment has no payoutBatchCutoffUtcMs yet, since that is assigned in finalizeDeliveredShipment (services.ts:1651, 1676). "Both are money you have earned. The difference is which step it is on." is accurate; anything naming a payout date for the first tile is not.


**HIGH — Payout history row shows the whole batch total across all carriers as if it were this carrier's payment**  
`apps/driver_pilot/lib/driver_flow.dart:2092` · money-disclosure  

*What goes wrong:* Once more than one carrier settles in the same weekly batch, every carrier sees the platform-wide total presented as their payout, and a line count that includes other carriers' loads. It will look correct in a single-carrier pilot and silently become wrong at the moment the pilot grows. Alongside it, "Cutoff 1770000000000" is a raw epoch millisecond value shown to a truck driver, and a carrier whose transfer was skipped for a missing bank account sees no row and no explanation at all.

*Fix:* The direction is right (render the transfer, not the batch) but two parts of the fix as written will not work:

1. Keeping skipped rows visible CANNOT be done client-side. The server filters batches on `b.lineIds.some((id) => lineIds.has(id))` (services.ts:1125), and `lineIds` is `settledLineIds` (services.ts:2269), which the SKIPPED_NO_FUND_ACCOUNT branch never appends to — it pushes the transfer and `continue`s (services.ts:2213-2214), leaving the lines ACCRUED. A batch in which this carrier was skipped therefore contains none of the carrier's line ids and is never returned at all. To show that row, `pilotListCarrierPayoutBatches` must select on the transfer instead: `const batches = [...store.payoutBatches.values()].filter((b) => b.transfers.some((t) => t.carrierId === carrierOrgId));`. A FAILED transfer is dropped the same way and needs the same change. While that function is being touched, the right shape is to return only this carrier's slice — batch id, cutoffUtcMs, provider, plus the single matching transfer — so the platform-wide total never reaches the device at all and the client cannot regress into showing it again.

2. Match on the orgId the screen already resolved, not `DriverSession.carrierOrgId`. driver_flow.dart:2065 is `final orgId = DriverSession.carrierOrgId ?? lastRegisteredOrgId ?? "";` and that is what the request is keyed on (2066). Matching the transfer on `DriverSession.carrierOrgId` alone would show an empty amount for a just-registered carrier on the fallback path. Hoist that `orgId` into a field and match `t["carrierId"] == orgId`.

3. The date formatter has no package behind it. apps/driver_pilot/pubspec.yaml lists only cupertino_icons, dio, flutter_secure_storage, go_router, google_maps_flutter, geolocator, razorpay_flutter — no `intl`. Adding a dependency is a decision to raise before taking it; the cheaper route is a small local `formatBatchDate(num utcMs)` next to `formatInrFromPaise` in pilot_api.dart:121, building "12 Jun 2026" from `DateTime.fromMillisecondsSinceEpoch(utcMs.toInt())` with a const month-name list.

4. One copy correction: BOOKKEEPING_PAID must not read as money received. In BOOKKEEPING mode no money moves (services.ts:2155-2156 and the branch at 2200-2206), so the row is a record, not a payout. Use the finding's "Recorded in the ledger. No bank transfer in this pilot." and surface `b["provider"]` once at the top of the list rather than per row. Also demote the rupee figure from the ListTile title in that mode so a driver does not read a title-sized amount as money in their account.

The rest of the fix stands: title from the matching transfer's `netToCarrierPaise`, count from that transfer's `lineIds.length`, and PROCESSING / FAILED / SKIPPED_NO_FUND_ACCOUNT mapped to the plain-language strings given.


**MEDIUM — The 10% platform commission is never shown to the carrier, only the post-deduction figure**  
`apps/driver_pilot/lib/driver_flow.dart:850` · hidden-costs  

*What goes wrong:* The carrier is shown what they receive but never what the customer paid or what was deducted, and the word "net" is left to carry the whole explanation - to a reader whose first language may not be English. The house rule is that fees appear on the same screen as the headline number; here the fee is in the payload and is simply not rendered, so a carrier cannot check the platform's arithmetic on their own earnings.

*Fix:* The fix is sound in substance but has two flaws worth correcting before implementation.

1. Do not hardcode "10%" in the copy. COMMISSION_BPS lives at config.ts:10 on the server and is never sent in the shipment payload, so a literal "10%" in Dart silently becomes a lie the day the rate changes, on the one screen whose job is to let a carrier check the platform's arithmetic. Either drop the percentage and show only the rupee figure (which is authoritative, since commissionPaise comes from the payload), or derive it at render time from the two values already present: `final ratePercent = gross > 0 ? (commission / gross * 100).round() : null;` and label the row "Platform commission" plus the percentage only when ratePercent is non-null.

2. Do not let `?? 0` render the breakdown. Line 850's existing `as num? ?? 0` guard is fine for a single net figure, but applied to grossPaise it would print "Customer paid ₹0" on any legacy or partial record, which misleads worse than the current omission. Read them as nullable and gate the whole Card: `final gross = s["grossPaise"] as num?; final commission = s["commissionPaise"] as num?;` then render the three-row Card only `if (gross != null && commission != null && gross > 0)`, falling back to the current single "Net to carrier" line otherwise.

Otherwise implement as proposed: on DriverShipmentDetailScreen replace line 850 with one Card holding "Customer paid" / "Platform commission −" / a FontWeight.w700 "You get", using DriverTheme.muted for the first two labels and DriverTheme.navy for the total. The figures always reconcile exactly, because services.ts:143 computes net as `grossPaise - commissionPaise` by subtraction rather than a second floor, so a carrier checking the arithmetic will never see a rounding discrepancy. The list change at 1759 to "You get ₹X of ₹Y" is good and fits the dense-layout house preference; apply the same null gate there and keep the existing "net" wording when gross is unavailable.


**MEDIUM — "Invite driver" adds a person to the carrier org immediately, with no invitation and no notification**  
`apps/driver_pilot/lib/driver_flow.dart:615` · misleading-framing  

*What goes wrong:* The carrier owner believes an invitation was sent and waits for the driver to accept. The driver is silently attached to an organisation, with a vehicle record created against their user, and learns about it only by opening the app. Nobody is told what actually happened, and the driver was never asked.

*Fix:* The fix is directionally right but incomplete — as written it leaves the app saying "add" on one screen and "invite" on four others, which breaks the one-concept-one-word rule. Every string below was confirmed by grep.

Change all six user-facing strings in driver_flow.dart together:
1. Line 675 — the ternary has a DISPATCHER arm the proposed fix ignores. Change `Text(_role == "DISPATCHER" ? "Invite dispatcher" : "Invite driver")` to `Text(_role == "DISPATCHER" ? "Add dispatcher" : "Add driver")`.
2. Line 615 — snackbar. Make it role-aware rather than const, since the same handler serves both roles: `Text(_role == "DISPATCHER" ? "Dispatcher added to your carrier org. Tell them to sign in — they will see it next time they open the app." : "Driver added to your carrier org. Tell them to sign in — they will see it next time they open the app.")`. Note this drops the `const` on the SnackBar, so remove the `const` keyword.
3. Line 637 — heading: "Add a driver who has already registered their phone. Solo orgs become fleet when you add drivers." Drop the "(or used Join a fleet)" parenthetical, which points at a screen that only creates a personal account.
4. Line 582 — authorization error: "Only carrier owners and dispatchers can add drivers."
5. Line 1400 — nav tile `title: const Text("Fleet — invite drivers")` becomes "Fleet — add drivers".
6. Lines 506 and 524 — the driver-side copy still says "ask your carrier admin to invite you" and "so your carrier admin can invite you to their org". These become "ask your carrier admin to add you" and "so your carrier admin can add you to their org".

Leave unchanged, deliberately: the API route path `/v1/pilot/carrier/drivers/invite` (line 609), the `inviteCarrierDriver` function name, `DriverFleetInviteScreen`, `DriverSession.canInviteDrivers`, and the `_invite` method name. These are identifiers and a wire contract, not copy — renaming the route breaks a deployed endpoint for any client on the old build. Renaming the Dart-internal symbols is optional and belongs in a separate commit so the copy change stays reviewable.

One addition the proposed fix omits and the code justifies: the screen should tell the carrier owner before they press the button that this takes effect immediately, since it is irreversible from this screen — services.ts:1883-1886 throws `membership_already_exists` on a repeat, and there is no remove-driver call on this screen. Add a line under the heading at 637, in `DriverTheme.muted` at fontSize 12 to match the existing dispatcher hint at 657-660: "This takes effect straight away. The driver is not notified — tell them to sign in."

Keep the word "Invite" reserved for a future flow that writes a pending record and waits for acceptance, which the current `Membership` type (types.ts:65-70) cannot represent without a new field.


**MEDIUM — GPS sharing is disclosed only once there is nothing left to track, and cannot be stopped from the app**  
`apps/driver_pilot/lib/driver_flow.dart:1776` · consent  

*What goes wrong:* The one sentence explaining that a driver's live position goes to customers renders exactly when it no longer applies, and never while customers are actually watching. The driver sees only the OS location prompt, which says nothing about who receives the data or how often. There is also no in-app control to stop sharing during a break - the only way out is to finish the load or back out of the screen, which is not discoverable as a privacy control.

*Fix:* The "move the disclosure out of both conditionals" half is sound. The dialog half has three defects that would ship a worse bug than the one being fixed.

1. It misses a code path. `_startLocation()` is called from two places: initState (1445) and `_startTrip` (1522, `if (_posSub == null) await _startLocation();`). Gating only initState means a driver who taps "Start load" on this screen begins sharing with no dialog at all. Gate inside `_startLocation()` itself, at the top, before `Geolocator.checkPermission()` on 1456 — then both callers are covered.

2. "every 30 seconds" is wrong copy. Line 1464 sets `distanceFilter: 25`, so no stream event fires while the vehicle is parked, and 1535 is a minimum interval, not a cadence. Use: "Your location is sent to naviG8r while you are moving, at most once every 30 seconds, and shown to the customers on this load. It stops when the load is complete."

3. Defaulting to "Not now" creates a dead end. There is no re-enable control anywhere in the file, so a driver who declines cannot restart sharing without backing out of the screen and re-entering (which re-runs initState and re-asks). If a decline path exists it needs a visible way back.

Corrected fix:
- Move the Text at 1776 out of both conditionals, into the status block after line 1690, guarded by `if (tripStarted)` alone, with the copy above. Delete the 1773-1779 wrapper. Line 1706 ("All bookings have proof of delivery — complete the load to stop tracking.") stays as-is; it is a different sentence and does not duplicate.
- Add a stop control the finding asks for but does not specify: next to that disclosure, a `TextButton` labelled "Stop sharing" (neutral, not styled as destructive) calling `_stopLocationSharing()` plus `setState`. Track an explicit `bool _sharingPaused` field, since `_posSub == null` also means "never started". When paused, the same row reads "Location sharing is off. Customers cannot see where you are." with a `FilledButton.tonal` "Start sharing" calling `_startLocation()`. This is the state that must persist visibly — do not let a paused driver see nothing.
- For the first-run disclosure, put the same sentence in a non-dismissible-by-tap-outside `AlertDialog` at the top of `_startLocation()`, shown once per trip id, with two equally weighted neutral actions: "Start sharing" and "Not now". No confirmshaming on the decline. On "Not now", return early and set `_sharingPaused = true` so the persistent "Start sharing" row above is what the driver lands on. Default focus on neither button; do not pre-select.
- Leave the snackbar at 936 alone, and consider making 167 and 1252 consistent with the new sentence in a separate copy pass — out of scope for this fix.


**MEDIUM — A carrier can create an organisation in two taps but cannot leave it or close the account anywhere in the app**  
`apps/driver_pilot/lib/driver_flow.dart:1405` · roach-motel  

*What goes wrong:* Signing out is fine and easy to find, but a carrier who registered by mistake, or a driver who left the fleet, has no way to remove themselves or their vehicle registration from the platform. Registration is a two-tap commitment; undoing it requires knowing to contact a company they have no contact details for inside the app.

*Fix:* Two corrections.

1. The headline "two taps" is wrong and should be dropped from the title. driver_flow.dart:177-180 is one tap to REACH the register screen, not to complete registration. DriverRegisterScreen (379-476) requires six text fields (full name, phone, org display name, vehicle registration, vehicle class, capacity kg), two client-side validations (phone.length != 10, cap <= 0), a POST to /v1/pilot/driver/register, and then an OTP step — line 434: `context.go("/driver/onboarding/otp?phone=$phone")`. Re-title as something like "Registration creates a carrier org and vehicle record with no self-service way to undo it". The asymmetry argument survives; the "two taps" figure does not, and citing it will get the whole finding dismissed by anyone who opens the file.

2. "A new authenticated endpoint wrapping the existing ops soft-delete" will not work as written. services.ts:623 opens with `assertOpsAgent(store, params.actingUserId)`, and services.ts:629-631 throws explicitly on self-targeting: `if (userId === params.actingUserId) { throw new ApiError("cannot_delete_self", { detail: "Ask another ops admin to deactivate your account." }, 403); }`. httpServer.ts:503-510 gates the DELETE route on `assertOpsAgent` as well. So a carrier calling a wrapper with themselves as both actor and target hits a 403 on both guards. The backend work is a separate function that reuses the softDelete.ts `markInactive` primitive plus the same active-shipment and sole-owner-org checks opsDeleteUser already applies (opsDeleteUser.test.ts:62 shows active shipments block deletion without force), not a thin wrapper. Treat that as a backend change requiring its own design pass, not a small addition.

The interim shipping advice in the original fix stands and is the part to do first: add a ListTile below Sign out (insert after the block at 1405-1413), leading `Icon(Icons.no_accounts_outlined, color: DriverTheme.navy)`, title `Text("Close my account")`, pushing a screen that states plainly what happens to in-flight loads and unpaid earnings, gives the support phone number and email, and says closure is processed by ops within a stated number of days. Neutral copy, no confirmshaming on the way out.


**MEDIUM — Customer booking screen keeps a stale price card and charges without the app showing the amount**  
`apps/driver_pilot/lib/customer_flow.dart:1723` · bait-and-switch  

*What goes wrong:* A customer fetches a quote for 200 kg, edits the weight to 800 kg, and the card still shows the 200 kg price while Book & pay authorises the 800 kg amount. The Razorpay sheet does show the true amount, so the charge is not blind, but the app's own number and the charge can disagree at the moment of commitment - and a customer who never taps Get quote is taken to a payment sheet without the app having shown a price at all.

*Fix:* The diagnosis stands; two parts of the fix are not implementable or advisable as written.

1. "Add `onChanged: (_) => setState(() => _quote = null)` to the weight, pickup and drop inputs" only works for weight. The weight input is a real TextField at customer_flow.dart:1674, so `onChanged` can be added there. Pickup and drop are not TextFields on this screen - they are `LocationEndpointEditor` (1676-1684, 1686-1694), whose constructor (location_editor.dart:328-338) exposes only title, hint, labelController, markerId, markerHue, position, onPositionChanged and showApiKeyHint. There is no onChanged parameter; the inner TextField lives at location_editor.dart:435-436 inside the child's own state. Corrected: clear the quote from the callbacks and controllers the parent already owns - add `_quote = null` inside the existing `onPositionChanged: (p) => setState(() { _pickupPos = p; _quote = null; })` at 1683 and the matching drop callback at 1693, and in initState add `_pickup.addListener(_invalidateQuote)`, `_drop.addListener(_invalidateQuote)` and `_weightKg.addListener(_invalidateQuote)`, where `_invalidateQuote` does `if (_quote != null) setState(() => _quote = null);`. Controller listeners also catch the geocoder's own writes to the label (location_editor.dart:400, 421), which an `onChanged` on the inner field would miss. Note all three controllers are already disposed at 1487-1489, so listeners are cleaned up.

2. "Disable Book & pay until a quote for the current inputs exists" makes /shipments/quote a hard dependency of the money path for users on patchy connectivity, which is the stated field condition. Drop it. The confirmation sheet is what actually fixes the correctness problem, because it shows the server-returned `amountPaise` (1595) rather than the client's stale estimate. Keep "Book & pay" enabled and insert the sheet in `_book` between the response parse and `_checkout!.open(...)` at 1605-1610, with the amount, route, weight, the line "This amount is authorised now and captured after delivery", and neutral Pay / Cancel buttons. Cancel must return without opening checkout, and since `_book` already sets `_booking = true` at 1569, the `finally` at 1617-1619 must still clear it on the cancel path.

3. The report's own aside that "the Razorpay sheet does show the true amount" is not verified from this repo. What the source shows is `rzp.open({"key": ..., "amount": amountPaise, "currency": "INR", ...})` at customer_checkout_mobile.dart:50-57. Whether that amount is rendered to the user is razorpay_flutter's behaviour, unchecked here. Keep it as a hedge, not as a fact - if it turns out the sheet does not display the figure prominently, this finding is high, not medium.

4. Citation hygiene for the writeup: the quote card block is 1723-1741, not 1723-1740, and the `_checkout!.open(...)` call is 1605-1610, not 1608-1613 (1608 is the `amountPaise: amountPaise,` line inside it).


**MEDIUM — Developer lab sits in the driver landing button stack and opens forms pre-filled with someone else's identity**  
`apps/driver_pilot/lib/driver_flow.dart:199` · navigation  

*What goes wrong:* A pilot driver reading down the landing screen finds a fifth tappable option with no warning, and lands in a surface whose first button posts a carrier registration under a phone number and vehicle that are not theirs. Best case they get an error they cannot interpret; worst case they create junk records on the pilot server and believe they have registered.

*Fix:* The move-and-label half is right in intent but names a widget that will not compile: `IconButton` has no text label parameter. Use `TextButton.icon` — it matches the existing emphasis level and the surrounding `crossAxisAlignment: CrossAxisAlignment.stretch` Column. Concretely, replace driver_flow.dart:199 with a `const SizedBox(height: 16)`, a `const Divider()`, a `Text("For naviG8r staff", style: TextStyle(color: DriverTheme.muted, fontSize: 12))`, then `TextButton.icon(onPressed: () => context.go("/pilot-lab"), icon: const Icon(Icons.build_outlined), label: const Text("Developer lab - internal testing only"))`. Note that DriverTheme has no error/warning token (theme is four colours), so DriverTheme.muted is the only correct choice for that caption and it must clear WCAG AA on the #F4F7FA background — check #64748B on #F4F7FA before shipping rather than assuming. Also drop the `Spacer()` consequence from the plan: adding four widgets below the stack pushes the group up, which is fine, but the divider must sit above the caption so the caption reads as belonging to the lab, not to "Join a carrier fleet". Three corrections to the pre-fill half. First, scope it to identity only: main.dart:353-355 (phone, org, vehicle registration) are somebody's real-looking identity and should become bare `TextEditingController()` with `hintText` on each field, but 356-357 (`_vehClass` "MEDIUM", `_capKg` "5000") are an enum value and a number, not identity — clearing them removes staff convenience and buys no safety, so leave them. Second, the finding misses the same defect one screen over: main.dart:439 is `final _phone = TextEditingController(text: "9876543210");` in LoginScreen, and that form triggers an OTP flow, so a stray tap there sends an SMS challenge against a phone number that is not the tester's. Clear 439 the same way, or the fix leaves the worse instance in place. Third, a label alone does not stop a pilot driver who taps anyway. The durable fix is a guard on the route: make `GoRoute(path: "/pilot-lab")` (main.dart:82) redirect to "/driver" unless an internal flag is set (a `--dart-define` compile-time constant read via `bool.fromEnvironment`), so pilot builds cannot reach the lab at all while staff builds keep it. That satisfies "the lab stays" without relying on copy to hold the line. If the owner wants the lab reachable in pilot builds, the label fix is the minimum and should ship with the main.dart:353-355 and :439 clearing, not instead of it.


### Landing screen redesign

10 findings, 5 high.


**HIGH — Landing shows the same five-button wall to every visitor and never uses the session the app already holds**  
`apps/driver_pilot/lib/driver_flow.dart:172` · navigation  

*What goes wrong:* Every launch, a driver who signed in weeks ago sees five choices and has to work out that the third one — an OutlinedButton with the low-contrast border, ranked below "Register as new carrier" — is the one that gets them to work. A carrier owner registering a business and a driver joining someone else's fleet are given no language that names them; they are given four verbs. In a vehicle, one-handed, that is a guess with a 1-in-4 chance, and the wrong guesses are expensive: "Register as new carrier" creates an organization.

*Fix:* The three-state structure is sound; three specifics in it do not compile or do not work as described. Keep Option C, with these corrections.

1. STATE 1 MUST NOT AUTO-REDIRECT OFF "/driver". The proposal says state 1 should `context.go("/driver/loads")` from the welcome route. "/driver" is the Home tab: DriverShell._pathForIndex returns "/driver" for index 0 (driver_flow.dart:79-81), and PopScope sends Android back to "/driver" from every tab root (driver_flow.dart:96-97). A redirect on entering "/driver" makes the Home destination a bounce to Loads and makes hardware back from Shipments/Publish/Profile land on Loads, with NavigationBar.selectedIndex jumping 0 -> 2 (_indexForPath, driver_flow.dart:56). Instead render a real signed-in home on "/driver" in state 1: heading 22/w700/navy "{DriverSession.carrierOrgName}", muted line "Signed in as {DriverSession.userFullName}", then a full-width FilledButton `minimumSize: Size.fromHeight(56)` "Open today's loads" -> `context.go("/driver/loads")`, plus the same two-Card group demoted to TextButtons if needed. Zero-guess, one tap, and the tab model stays intact.

2. THE CLIPBOARD HELPER CANNOT BE REUSED AS WRITTEN. `_copyToClipboard` (main.dart:18) is library-private, and driver_flow.dart is a separate library (it has its own import block, driver_flow.dart:1-13; no `part`/`part of` anywhere in lib/). driver_flow.dart also does not import `package:flutter/services.dart`, so `Clipboard` is not in scope there. Either add `import "package:flutter/services.dart";` to driver_flow.dart and write a local `Future<void> copyPhoneToClipboard(BuildContext, String)`, or rename main.dart:18 to public `copyToClipboard` and move it into a shared file both libraries import. Do not leave the fix saying "reuse the helper at main.dart:18-22".

3. THE 6-SECOND DEADLINE NEEDS `onTimeout`. `DriverSession.refresh()` catches only its own Dio failure and returns false (driver_session.dart, `} catch (_) { return false; }`); `Future.timeout` throws TimeoutException past that catch. Write `final ok = await DriverSession.refresh().timeout(const Duration(seconds: 6), onTimeout: () => false);` so a slow cold start falls through to state 3 instead of throwing an unhandled error.

4. `showBottomNav: false` FROM THE SHELL BUILDER WILL GO STALE. DriverSession is a plain static store with no Listenable (driver_session.dart), and the router's `refreshListenable` is `CustomerSession.listenable` only (main.dart:78). A value computed in the ShellRoute builder (driver_flow.dart:2260-2267) is therefore recomputed only when the router navigates — on a cold start it is computed with `hasCarrierOrg == false`, and with correction 1 there is no navigation afterwards, so a signed-in driver would sit on a home screen with no bottom nav. Add a `static final ValueNotifier<int> revision` to DriverSession, bump it at the end of `refresh()` and in `clear()`, and set `refreshListenable: Listenable.merge([CustomerSession.listenable, DriverSession.revision])` at main.dart:78. Then `showBottomNav: DriverSession.hasCarrierOrg` in the shell builder is correct in all three states.

Unchanged and still right: state 2's "Copy my number" as the primary action (it matches the invite field at driver_flow.dart:645), the neutral "Sign out" wired exactly like the existing one at driver_flow.dart:1408-1411 (`api.clearToken(); DriverSession.clear();`), deleting "Continue as signed-in driver", and moving "Developer lab" out of the button stack. Also replace the post-OTP snackbar at driver_flow.dart:329-333, which currently names only "Register as new carrier" and omits the join-a-fleet route that exists at driver_flow.dart:2303 — with state 2 present, drop the snackbar and let `context.go("/driver")` (334) land the user on it.


**HIGH — The "Join a carrier fleet" path dead-ends and the app then tells that driver to register a carrier business they should not own**  
`apps/driver_pilot/lib/driver_flow.dart:331` · navigation  

*What goes wrong:* A driver joining an existing fleet does exactly what the app told them, signs in before their owner has added them, and is instructed to create a new carrier organization. If they follow that instruction they register a second carrier org against their own phone via /v1/pilot/driver/register (driver_flow.dart:421), which their employer does not control and which will then own trips and payouts. The instruction is wrong for the one person it is most likely to be shown to, and it is destructive rather than merely confusing.

*Fix:* The finding stands, but the fix as written breaks the happy path and depends on code that does not exist. Three corrections.

1. "Let the OTP screen route to /driver unconditionally" is wrong. driver_flow.dart:326-334 is an if/else: line 327 is `context.go("/driver/loads");` for the has-org case. Routing unconditionally to /driver would dump every owner-driver and dispatcher back on the welcome screen after a successful sign-in. Keep the branch; replace only the else body (:329-334). A transient SnackBar is also the wrong surface for a state the user has to act on outside the app — it disappears. Replace with `context.go("/driver?pending=1")` and have DriverWelcomeScreen (currently driver_flow.dart:151-204, a stateless Column with no state handling at all) render a Card above the Spacer when that query param is set: "Signed in as {DriverSession.userPhone}. This number is not in a carrier fleet yet." plus "If you drive for a carrier, ask the owner or dispatcher to add this number." plus a Copy number TextButton. Keep "Register as new carrier" exactly as it is, an OutlinedButton at :178-181 with neutral copy — the fix is to stop naming it as the instruction, not to hide or shame it.

2. Say "owner or dispatcher", not "owner". driver_session.dart canInviteDrivers returns true for OWNER_DRIVER, OWNER and DISPATCHER, and DriverFleetInviteScreen at driver_flow.dart:669 offers both roles. Copy that says only "owner" misroutes drivers at any carrier where a dispatcher does the adding.

3. The :506 copy change is sound and the :508 push is the right thing to remove, but spell out the replacement: drop `context.go("/driver/onboarding/phone")` at :508, set a local `_created = true` and rebuild DriverJoinScreen's ListView into a success state showing the submitted number, a Copy number FilledButton using `Clipboard.setData(ClipboardData(text: phone))` from `package:flutter/services.dart` (already a Flutter SDK import, no new dependency), and a secondary TextButton "I have been added — sign in" going to /driver/onboarding/phone for the case where the invite already landed.

One claim in the report should be softened before it ships. "Will then own trips and payouts" is a server-side assertion that cannot be checked from Dart. What driver_flow.dart:420-428 shows is that the client posts `orgDisplayName` to /v1/pilot/driver/register and stores the returned id in `lastRegisteredOrgId` (:429-430). Whether the backend even accepts a second org for a phone that already has a user record from /v1/pilot/customer/users/register (:497-500), and what that org ends up owning, is unverified here. Write it as "either a confusing server error or a second carrier org, and which one is unverified from the client source" — the UX defect is the same either way.


**HIGH — "Continue as signed-in driver" fires a network call with no pending state behind a 45-second timeout**  
`apps/driver_pilot/lib/driver_flow.dart:183` · error-state  

*What goes wrong:* On patchy connectivity the driver taps and the screen does nothing at all for up to 45 seconds. They tap again, and again, each tap starting another /v1/pilot/me request; the first one to return wins and may navigate under their finger. This is the single most-tapped control for a returning user, and it is the one with no feedback.

*Fix:* The fix is sound in substance; two implementation details in the snippet would misbehave as written.

1. Inside a State subclass, `context.mounted` should become `mounted`, and the busy flag must be reset under a mounted guard or setState can fire after dispose. The working shape, matching the existing convention at driver_flow.dart:258-263:

  bool _checking = false;

  Future<void> _continueAsSignedIn() async {
    setState(() => _checking = true);
    try {
      final ok = await DriverSession.refresh();
      if (!mounted) return;
      if (ok && DriverSession.hasCarrierOrg) {
        context.go("/driver/loads");
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(...)));
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

with `onPressed: _checking ? null : _continueAsSignedIn`. The `finally` matters because the success branch navigates away; without it the flag stays true if the user comes back to /driver via the router rather than a rebuild.

2. Fix the failure copy at the same time, or the spinner just makes a misleading message arrive more politely. refresh() returns false for a network timeout and for a genuinely signed-out user alike (driver_session.dart:85-87), so "Sign in first, or complete carrier registration." is wrong half the time. Either have refresh() distinguish the two — return a result that separates "request failed" from "no carrier org" — or, minimally, change the snackbar to copy that does not assert a cause: "Could not check your sign-in. Check your connection and try again, or sign in with your phone." One sentence, no blame, and it stays true in both cases.


**HIGH — A network failure is reported to the driver as "Sign in first", because refresh() collapses every error into false**  
`apps/driver_pilot/lib/driver_session.dart:85` · error-state  

*What goes wrong:* A driver who is signed in, in a dead zone or with the API cold-starting, is told their account is the problem. The honest message is "we could not reach the server". The wrong message pushes them toward signing in again, or toward "Register as new carrier" — the destructive option — to fix a problem that is a bar of signal.

*Fix:* The diagnosis and the enum are right. Three parts of the fix are wrong or not implementable as written.

1. "Catch DioException separately" as phrased inverts the bug. A real 401 is also a DioException (type `badResponse`), so a single `on DioException` arm would label a genuinely signed-out driver "unreachable" — the same lie in the other direction. Branch on the response, not the type:

```dart
// driver_session.dart — needs `import "package:dio/dio.dart";` added at the top.
// pilot_api.dart imports dio at line 1 but only exports pilot_api_dns.dart (line 3),
// so DioException is not in scope today.
static Future<SessionRefreshResult> refresh() async {
  try {
    ... // unchanged, ends `return SessionRefreshResult.ok;` in place of line 84
  } on DioException catch (e) {
    final status = e.response?.statusCode;
    if (status == 401 || status == 403) return SessionRefreshResult.notSignedIn;
    if (e.response != null) return SessionRefreshResult.serverError;
    return SessionRefreshResult.unreachable;   // timeouts, DNS, no route
  } catch (_) {
    return SessionRefreshResult.serverError;   // malformed payload, not the driver's fault
  }
}
```
Four cases, not three: `{ ok, notSignedIn, unreachable, serverError }`. Keep `ok` meaning "the call succeeded"; the `hasCarrierOrg` check stays at the call site, because a 200 with no carrier org is the one case where the existing "or complete carrier registration" copy is honest.

Changing the return type is safe: the other two call sites (driver_flow.dart:324 and 577) are bare `await DriverSession.refresh();` statements that discard the value.

2. Drop `static bool lastRefreshWasNetworkFailure`. A mutable static used as a side channel on a class whose whole job is shared global state races if two refreshes ever overlap, and the enum return carries the same information with none of it. The finding offers both; only the enum should ship.

3. `RefreshIndicator` cannot be added here, and "state 3 of the redesigned landing" does not exist. DriverWelcomeScreen (driver_flow.dart:151) is a `StatelessWidget` whose body is `Padding` > `Column` with a `Spacer()` at line 171 — no scrollable, so RefreshIndicator has nothing to attach to, and a StatelessWidget cannot hold an error line at all. Implementable version, standalone:

- Convert DriverWelcomeScreen to a StatefulWidget holding `bool _busy` and `String? _connectionMessage`.
- In the handler at 183-193, switch on the result: `ok` + `hasCarrierOrg` goes to `/driver/loads`; `ok` without an org keeps today's "Sign in first, or complete carrier registration."; `notSignedIn` shows "Your session expired. Sign in with your phone again."; `unreachable` sets `_connectionMessage = "Could not reach naviG8r. Check your signal and try again."`; `serverError` sets "naviG8r is not responding right now. Try again in a minute."
- Render `_connectionMessage` as a persistent muted `Text` (DriverTheme.muted) directly under the paragraph ending at line 170, not as a SnackBar. A SnackBar auto-dismisses and is the wrong carrier for a message a driver in sunlight needs to read and act on; the existing "Continue as signed-in driver" button at 194 is already the retry affordance.
- Gate the button on `_busy` (`onPressed: _busy ? null : ...`, child swapped for a sized CircularProgressIndicator), matching the `_busy` pattern already used at driver_flow.dart:215 and 258-259. This is not optional polish here: with a 45-second connectTimeout (pilot_api.dart:32) an ungated button gives the driver three quarters of a minute of nothing, and invites repeat taps that queue more 45-second waits.

Verification note: none of this was compiled or run, since Flutter is not installed on this machine.


**HIGH — The signed-out landing sits inside the authenticated shell with all five bottom-nav tabs live**  
`apps/driver_pilot/lib/driver_flow.dart:2262` · navigation  

*What goes wrong:* The first-time visitor is not choosing between five buttons, they are choosing between ten targets. Four of the bottom tabs require an account that does not exist yet, and the reward for tapping one is an unstyled red API error string such as "HTTP 401: {error: unauthorized}". That is the first impression of the product, and it is also the reason the landing reads as a debug page.

*Fix:* The problem is real but `showBottomNav: DriverSession.hasCarrierOrg` at driver_flow.dart:2262 is not sufficient and introduces a new defect. Three reasons from the source: (1) The access token is persisted in FlutterSecureStorage (pilot_api.dart:47 `Future<void> setToken(String token) => _storage.write(key: "access_token", value: token);`, read back by the interceptor at :36-40), but DriverSession is in-memory statics (driver_session.dart:4-16) and main() (main.dart:62-66) never hydrates it. On a cold start a returning, genuinely signed-in driver lands on /driver (main.dart:77 `initialLocation: kIsWeb ? "/customer" : "/driver"`) with carrierOrgId still null, so the proposed fix hides the bottom nav from an authenticated user and strands them on the landing. (2) The ShellRoute builder is a pure function of router state, and `refreshListenable: CustomerSession.listenable` (main.dart:78) is the only thing that forces a router rebuild; DriverSession exposes no listenable (grep over driver_session.dart returns none, unlike customer_session.dart:8 `static final Listenable listenable = ValueNotifier<int>(0);`). A DriverSession.refresh() inside a child screen (for example driver_flow.dart:2125 in publish initState) calls setState on the child only and cannot rebuild the shell above it, so the bar would stay hidden until the next route change. (3) The obvious alternative of keying on the route — `showBottomNav: path != "/driver"` — is worse, because _pathForIndex(0) returns "/driver" (driver_flow.dart:79-81), so the Home tab targets the same route as the signed-out landing and the bar would disappear under the user's own Home tap.

Corrected fix, three files:
1. driver_session.dart — add `static final Listenable listenable = ValueNotifier<int>(0);` alongside the existing statics and bump it (`(listenable as ValueNotifier<int>).value++;`) at the end of refresh() and of the clear path at :91, mirroring customer_session.dart:8,17 exactly so there is one pattern for both sessions.
2. main.dart:78 — change `refreshListenable: CustomerSession.listenable,` to `refreshListenable: Listenable.merge([CustomerSession.listenable, DriverSession.listenable]),` so a driver session change reruns the ShellRoute builder.
3. main.dart:62-66 — hydrate before the first frame decides: in main(), after `api = Api(resolveApiBaseUrl());`, kick off `DriverSession.refresh()` when a persisted token exists (add `Future<bool> hasToken()` to Api over the same `_storage`), and while that is in flight keep the landing showing its signed-out state rather than flashing tabs on and off. Only then does driver_flow.dart:2262 take `showBottomNav: DriverSession.hasCarrierOrg`.

Keep the finding's second guard, and make it the copy, not raw error text: in DriverShipmentsScreen, when the failure is a 401/403, replace the `Text(_error!, style: const TextStyle(color: Colors.red))` at :755 with a signed-out empty state reading "Sign in to see customer bookings." plus a FilledButton "Sign in with phone" routing to /driver/onboarding/phone. Colors.red is also an untokenised colour in a theme that has no error token (driver_theme.dart) — worth recording separately rather than fixing inline here.

Note for the owner: this is a three-file change touching routing and session bootstrap, which is at the "pause and ask before a refactor touching more than three files" line, so it should be agreed before implementation rather than landed as the "one-argument change" the finding describes.


**MEDIUM — "Developer lab" is presented as a peer of the real onboarding actions, 8dp from "Join a carrier fleet"**  
`apps/driver_pilot/lib/driver_flow.dart:199` · navigation  

*What goes wrong:* A pilot driver reading down the list sees five options of descending prominence and no signal that the last one is not for them. An 8dp gap between two 40dp TextButtons is a realistic mis-tap in a moving vehicle. What they land on is a raw API console with prefilled test data ("Ravi Transport", "HR26AB1234" at main.dart:354-355) and a live register button — they can create junk records from it.

*Fix:* The fix's direction is right but its plumbing claim is false. It says "DriverShell already accepts an `actions` list (driver_flow.dart:49, :109-110), so this needs no new plumbing." `grep -n 'actions' driver_flow.dart` returns exactly four hits: 41 (`this.actions,`), 49 (`final List<Widget>? actions;`), 109 (`actions: [`), 110 (`if (actions != null) ...actions!,`). Lines 109-110 are the AppBar's own `actions`, not a caller. No caller anywhere passes `actions` — the parameter is declared and never used.

Worse, DriverWelcomeScreen cannot pass it. It builds no Scaffold and no AppBar (driver_flow.dart:155-157 is a bare `Padding` > `Column`); it is the `child` of a ShellRoute. The AppBar belongs to DriverShell, constructed at the single site driver_flow.dart:2262-2266, which passes only `title`, `currentPath` and `child`. A child widget cannot hand `actions` upward to its shell. So "add `actions:` to the landing's AppBar" is not something you can do from DriverWelcomeScreen at all.

Corrected fix — same end state, one extra edit:

1. Delete driver_flow.dart:198-199 (the `SizedBox` and the "Developer lab" TextButton). The `/pilot-lab` route in main.dart:82 stays untouched.

2. Edit the ShellRoute builder at driver_flow.dart:2260-2266 to pass `actions` only on the landing path, since `path` is already in scope at line 2261:

```dart
builder: (context, state, child) {
  final path = state.uri.path;
  return DriverShell(
    title: driverShellTitle(path),
    currentPath: path,
    actions: path == "/driver"
        ? [
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              tooltip: "More",
              onSelected: (value) {
                if (value == "lab") context.go("/pilot-lab");
              },
              itemBuilder: (_) => const [
                PopupMenuItem<String>(value: "lab", child: Text("Developer lab")),
              ],
            ),
          ]
        : null,
    child: child,
  );
},
```

The spread at line 110 then renders it before the existing CircleAvatar (lines 111-113), so the overflow icon and the avatar sit side by side in the top-right. `context` in the builder is a router context under the shell navigator, so `context.go` is valid there.

Two things the original fix left out that should go in the same change:

3. The "Back to driver app (welcome)" button at main.dart:255-257 is the only way back out of the lab, and it sits above the fold of a ListView. Leave it, but the lab's AppBar title is `"Driver Pilot"` (main.dart:242), which reads like the product, not like a debug surface. Change it to `"Developer lab"` so a user who does land there knows immediately they are off the pilot path. One-word edit, same string as the menu item, so the menu label and the destination title match.

4. Optional but cheap, and it is the part that actually stops the junk record: the prefills at main.dart:354-355 ("Ravi Transport", "HR26AB1234") make the live POST at :380 a single tap from a fresh screen. Either clear them to empty and let the labels at :411-412 carry the meaning, or change them to obviously-not-real values ("SAMPLE ORG", "SAMPLE0000"). Prefer clearing them — an empty field plus the existing 10-digit phone guard at :376 means the form cannot be submitted meaningfully by accident.


**MEDIUM — The landing is the only driver screen that is not scrollable, and it uses a Spacer that will collapse before it overflows**  
`apps/driver_pilot/lib/driver_flow.dart:171` · layout  

*What goes wrong:* Three paragraph lines plus five stacked buttons plus 20dp padding inside a shell that also carries an AppBar and a NavigationBar leaves very little slack on a small mid-range Android screen. Raise the system font scale — common for older owner-operators — and the Spacer goes to zero first, then the Column overflows and Flutter paints the yellow-and-black stripe over the bottom button, which on this screen is a navigation control. The user cannot scroll to recover it.

*Fix:* The fix direction is sound but the justification and scope need correcting.

Fix as proposed, with one addition. Replace the `Padding` + `Column` + `Spacer` at driver_flow.dart:156-171 with `ListView(padding: const EdgeInsets.all(20), children: [...])` and delete `const Spacer()` on :171, replacing it with `const SizedBox(height: 24)` so the action group stays visually separated from the paragraph without a flex that can collapse. Dropping `crossAxisAlignment: CrossAxisAlignment.stretch` is safe here: ListView gives each child a tight cross-axis constraint, so the FilledButton and OutlinedButtons still render full width. A fixed 24dp gap also suits the house preference for dense over airy better than a Spacer that pushes the actions to the bottom edge of the viewport.

Strike the consistency argument. Do not write "this also matches the five sibling screens" — it is false. Write instead that the same non-scrolling Padding+Column shape appears on four other driver screens and should be fixed as one batch, and rank them by what overflow costs:
- DriverPayoutSetupScreen, :2012-2032. Highest risk of the group: three TextFields with the soft keyboard up already removes roughly half the viewport, and the overflowing child is the `FilledButton` "Save and verify" at :2033. A carrier who cannot reach that button cannot set up the account that pays them.
- DriverPodScreen, :1847-1858. The overflowing child is the `FilledButton` "Confirm POD" at :1859, with a `TextField(controller: _notes, ..., maxLines: 3)` above it. This is the screen that captures payment.
- DriverShipmentDetailScreen, :838-851. The overflowing children are the conditional "Accept booking" and "Confirm delivery" FilledButtons at :852-864.
- DriverPhoneScreen, :245-266. Lowest risk, short content, but same shape.
On the two money screens the correct treatment is not a plain ListView. Put the scrolling content in the ListView and pin the primary action outside it, as `Scaffold(bottomNavigationBar: ...)` or a `SafeArea` footer, so "Confirm POD" and "Save and verify" are always on screen regardless of font scale or keyboard. Those two are high severity, not medium.

Correct the impact sentence for the landing itself. Overflow clips the `TextButton` "Developer lab" (:199) first and "Join a carrier fleet" (:197) second; the primary "Sign in with phone" FilledButton (:172) is fourth from the bottom. The real cost on this screen is the yellow-and-black overflow stripe on the first screen a driver sees, plus an unreachable fleet-join path — not a lost primary action.

Everything about the overflow threshold stays unverified. No device or emulator is available, Flutter is not installed, and nothing in this review was run. State that in the report rather than implying a threshold was measured.

*Needs a device to confirm.*


**MEDIUM — Landing copy is written for an operations reader, not for a driver, and introduces a term that appears nowhere else**  
`apps/driver_pilot/lib/driver_flow.dart:166` · copy  

*What goes wrong:* The first sentence a truck driver reads contains an ampersand heading that names two roles without saying which is theirs, the phrase "confirm your carrier organization", and an unexplained "cooling-off" that in context sounds like a delay to their money. For a reader whose first language is not English this is four abstractions before a single actionable word, and none of it helps answer the only question they have: which button is mine.

*Fix:* The finding stands, but three parts of the proposed fix need correcting before it is implementable.

1. "upload proof of delivery" is wrong about the app. DriverPodScreen (driver_flow.dart:1811-1868) contains only a notes TextField (`TextField(controller: _notes, decoration: const InputDecoration(labelText: "Notes (optional)"), maxLines: 3)`) and a "Confirm POD" FilledButton; there is no image picker, camera, or signature capture anywhere in the tree, and the POST at 1825-1828 sends `{}` or `{"notes": ...}` only. Body copy should read "Run trips, confirm delivery, and get paid." Promising an upload the screen does not offer is the same class of mismatch the finding is objecting to.

2. "Move any payment-timing explanation to the earnings screen" is a move to a place that has nothing to move into. DriverEarningsScreen (1900-1936) states no timing at all — the only explanatory string is the KYC card at 1925 ("Customer payments sit on the platform ledger until you add a verified payout method..."). So this is an addition, not a move, and the added sentence must reuse the vocabulary already in the code rather than inventing a fourth: "Payment is released after ops review, then paid in a settlement batch" matches line 1853 and line 2088. Dropping the delay from the landing without writing it somewhere the driver will actually reach is a what-you-see-is-not-what-you-get problem, so the earnings-screen sentence is a required part of this fix, not an optional follow-up.

3. The relabelling covers three of five buttons. DriverWelcomeScreen has five actions: FilledButton "Sign in with phone" (176), OutlinedButton "Register as new carrier" (179), OutlinedButton "Continue as signed-in driver" (192), TextButton "Join a carrier fleet" (197), TextButton "Developer lab" (199). The proposed labels address 176, 179 and 197 and leave 192 and 199 unstated, which would ship a screen with two task sentences and two leftover noun phrases. Complete it: keep 176 as the only FilledButton, relabelled "Sign in with mobile number" (consistent with the existing validation string at line ~220, "Enter a 10-digit mobile number."); make 179 and 197 the two OutlinedButtons, "I own a truck or transport business" and "I drive for a transport company", so the two registration paths sit at equal weight instead of one OutlinedButton and one TextButton; demote 192 to a TextButton labelled "Already signed in" since it is a shortcut, not a fourth role choice; and leave 199 as the lowest-weight TextButton, relabelled "Developer lab (internal)" so a pilot driver reads it as not-for-me.

Heading "Drivers and carriers" is correct as proposed.


**LOW — The app bar on the landing shows a filled avatar circle for a user who is not signed in and cannot be tapped**  
`apps/driver_pilot/lib/driver_flow.dart:113` · consistency  

*What goes wrong:* A solid navy circle in the top-right of a sign-in screen reads as an account or profile button. It does nothing when tapped, and there is no account behind it. It is a small thing, but on the one screen whose whole job is telling a stranger where to go, a decoy control works against that job.

*Fix:* The proposed fix will not compile as written: CircleAvatar has no `onTap` parameter (its API is backgroundColor / backgroundImage / foregroundColor / child / radius / minRadius / maxRadius / onBackgroundImageError). It also leaves a 36dp target (radius 18) where Material asks for 48dp — a problem for a one-handed user in a moving vehicle. Wrap it in an IconButton instead, which gives the 48dp target and the ink response for free, and guard on a non-empty name rather than non-null, since DriverSession.userFullName is set straight from the API payload (driver_session.dart:29) and can come back as an empty string. In DriverShell.build, replace lines 111-114 with:

  if ((DriverSession.userFullName ?? "").trim().isNotEmpty)
    Padding(
      padding: const EdgeInsets.only(right: 8),
      child: IconButton(
        tooltip: "Profile",
        onPressed: () => context.go("/driver/profile"),
        icon: CircleAvatar(
          backgroundColor: DriverTheme.navy,
          radius: 18,
          child: Text(
            DriverSession.userFullName!.trim()[0].toUpperCase(),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    ),

White on navy #122C53 is roughly 14:1, so the initial clears WCAG AA. Use context.go, not context.push, to match how the bottom nav moves between tab roots (:148). Two things to know: DriverShell is a StatelessWidget reading static mutable DriverSession state, so the avatar only appears once the shell rebuilds — which a route change does, and every sign-in path ends in one (:187) — and the same static-read pattern is already used for the Fleet tile at :1397, so this adds no new coupling. Separately, the signed-out landing still shows the Profile destination in the bottom nav; if the goal is to remove signed-out decoys, pass showBottomNav: false from the ShellRoute builder when the path is exactly "/driver" and the session is empty, and track that as its own change rather than folding it in here.


**LOW — The only widget test asserts nav labels the driver landing does not render, so it cannot protect this redesign**  
`apps/driver_pilot/test/widget_test.dart:9` · test-coverage  

*What goes wrong:* No user impact directly. It matters for this work: there is no test standing behind the landing screen, so any of the three redesign options can be built without a regression signal, and whoever builds it should not assume a green suite means the landing still works.

*Fix:* The finding is sound but its fix is not implementable as written, for two reasons. (1) It asserts copy strings — 'Sign in with mobile number' and 'I drive for a transport company' — that appear nowhere in the repo; grep for "mobile number" in driver_flow.dart returns only line 228, a snackbar reading "Enter a 10-digit mobile number." Those strings belong to a proposed redesign state that does not exist yet, so a test written against them fails on day one and stays failing until someone happens to choose that option with that exact wording. (2) It never seeds the `api` global. pilot_api.dart:56 declares `late Api api;` and main.dart:64 is the only assignment, so a test that pumps DriverPilotApp without running main() leaves it uninitialized. That does not throw on the first pump today (DriverWelcomeScreen touches api only inside onPressed, via DriverSession.refresh at driver_flow.dart:184), but any test that taps through to onboarding gets a LateInitializationError rather than a useful failure. Corrected fix, in three parts. First, land a test NOW against strings that exist, so there is a regression signal before the redesign rather than after it: in setUp, `api = Api("http://test");` mirroring customer_integrations_screen_test.dart:13; then `await tester.pumpWidget(const DriverPilotApp()); await tester.pumpAndSettle();` and assert `find.text("Sign in with phone")` (driver_flow.dart:174), `find.text("Register as new carrier")` (driver_flow.dart:179), and `find.text("Shipments")` (driver_flow.dart:130, proving the DriverShell bottom nav rendered and not PilotScaffold). Delete the five stale assertions at widget_test.dart:9-13. Second, update those three literals in the same commit as the redesign, so the test moves with the copy instead of being written against copy that does not exist. Third, the DriverSession hook recommendation stands and should be a separate small change: add to driver_session.dart the two members mirroring customer_session.dart:90-91 and 107-108 — a `@visibleForTesting static void applyForTest({String? carrierOrgId, String? carrierOrgName, String? carrierRole, String? userFullName, String? userPhone, String? kycStatus})` and a `@visibleForTesting static bool skipRefreshInTests = false` early-returned from refresh() the way customer_session.dart:25-28 does — otherwise the signed-in landing branch cannot be tested at all. Also fix the finding's own anchor: cite widget_test.dart:10 (the first failing assertion, `expect(find.text('Register'), findsOneWidget);`), not line 9, which asserts 'Home' and passes.

*Needs a device to confirm.*

---

## 4. Driver journey findings

<a id="journeys"></a>

A separate pass walked the ten driver and carrier journeys end to end. **Provenance differs from
section 3 and you should weigh it accordingly:** these were not put through the two adversarial
verifiers, because that lens failed in the run and was re-done as a single pass. The items promoted
into section 2 were re-checked by hand against the source; the rest carry one reading only. Treat a
line here as a lead to confirm, not a settled finding.

Items already in section 2 are cross-referenced rather than repeated.

| ID | Sev | What goes wrong | Where | Fix |
|---|---|---|---|---|
| J-C1 | high | Every error shown to a driver is a raw API code, e.g. `HTTP 400: {error: shipment_not_deliverable}` | `pilot_api.dart:74` | See [2.10](#210-every-error-a-driver-sees-is-a-raw-api-code) |
| J-C2 | high | Every result on the money path is a 4-second snackbar. Miss it and there is no history, no log, no way to tell whether it worked | `driver_flow.dart` accept `:728`, start `:936`, POD `:1830`, publish `:2176` | For accept, start, POD and complete, replace the snackbar with a persistent status change on the card plus an inline confirmation row that survives navigation |
| J-C4 | medium | Rupee amounts have no Indian digit grouping, so a payout renders `₹1250000` | `pilot_api.dart:123` | Group as `₹12,50,000` in `formatInrFromPaise`. No dependency needed |
| J-C5 | medium | Nothing survives a dropped connection: every screen fetches on `initState` into widget state, no cache, no queue, no retry | app-wide | For POD only, persist the attempt and retry when back online. Do not extend to accept — accepting stale is worse than failing |
| J-1.1 | high | A carrier accepts a binding load without seeing the price, and the tap to the screen showing it is disabled | `driver_flow.dart:764-772` | See [2.1](#21-a-carrier-accepts-a-binding-load-without-ever-seeing-what-it-pays) |
| J-1.4 | medium | Loads list offers Start when any kilos are reserved; the trip screen requires an accepted shipment. The list offers an action the detail screen refuses | `driver_flow.dart:1111` vs `:1649` | Gate on accepted shipments, not `reservedKg`. Until the API returns that count, drop Start from the list card |
| J-1.5 | medium | Start, a state-changing action, sits 8dp from View, with the heavier visual treatment on the harmless one | `driver_flow.dart:1154-1159` | Move Start to its own full-width row and confirm it |
| J-1.6 | medium | A search icon inside a white rounded bordered box that is not a search field and has no tap handler | `driver_flow.dart:1004-1017` | Delete the icon and the box; render the summary as plain text |
| J-1.8 | medium | Pickup window renders as a raw ISO date, while `formatTripWindowRange` already produces "12 - 14 Jun" and is used on the customer screens | `driver_flow.dart:1195` | Delete `_formatWindow` and call the existing formatter |
| J-2.1 | high | After POD from the shipment detail, the screen still says the delivery is pending and still offers Confirm delivery. Tapping again returns a raw error | `driver_flow.dart:859-863` | Await the push and reload, mirroring `_openPod` at `:1484` |
| J-2.2 | high | A failed detail fetch spins forever: the catch is empty, so there is no error, no retry, no way back | `driver_flow.dart:817-830`, `:835-837` | Set an error state and render a retry |
| J-2.3 | medium | Delivered shipments vanish from the only list that showed them, and payout history shows totals without naming jobs. A driver paid wrongly has nothing to check against | `driver_flow.dart:712` | Add a Done filter including `DELIVERED` |
| J-2.4 | medium | On a first-load failure the screen shows a red error and, beneath it, "No shipments to deliver." One of those is a lie | `driver_flow.dart:753-777` | Guard the empty state on `_error == null` and give the error branch its own retry |
| J-3.2 | high | Denying location permission is a bare `return`. No message, no state, and the screen still says live GPS is being shared | `driver_flow.dart:1456-1458` | Track the denial and render a persistent row with a route into system settings |
| J-3.3 | high | The primary POD button submits for whichever shipment the API returned first and its label names nobody. On a multi-drop load this releases the wrong customer's payment | `driver_flow.dart:1786-1789` | Put the customer name in the label; with more than one booked shipment, drop the single primary button |
| J-3.4 | medium | Internal engineering instructions are shown to drivers: "Shipment list needs API deploy - merge driver-onboarding PR" | `driver_flow.dart:1586-1588` | Delete the parenthetical |
| J-3.5 | medium | One action, two names: "Confirm delivery" and "Mark arrived / POD" | `driver_flow.dart:1765` vs `:1789` | Use "Confirm delivery" everywhere; spell out proof of delivery in prose only |
| J-3.6 | medium | "Complete load" is advertised as a required step, but the server auto-completes on the last POD, so the button is normally unreachable | `driver_flow.dart:1702-1733` | Drop the instruction copy and relabel it as the recovery action it is |
| J-3.7 | medium | No pull-to-refresh on the screen a driver lives on, while three sibling screens have it. Leaving and returning tears down the location stream | `driver_flow.dart:1660-1677` | Wrap in `RefreshIndicator` with `AlwaysScrollableScrollPhysics` |
| J-4.1 | high | The POD screen never says which delivery it is about: no customer, no address, no amount, before the one irreversible action in the app | `driver_flow.dart:1846-1867` | Render a summary card above the notes field |
| J-4.2 | high | POD is irreversible, unconfirmed, and labelled with an acronym | `driver_flow.dart:1859-1863` | Relabel "Confirm delivery" and gate on a dialog naming the customer and drop address |
| J-4.3 | high | Both money sentences say "after review" and neither gives a timeframe, on the screen where an owner-operator decides whether they can buy diesel tomorrow | `driver_flow.dart:1833`, `:1853` | One sentence naming the real schedule, used on POD, earnings, payout setup and payout history |
| J-4.4 | medium | POD is a free-text note and nothing else. No photo, no receiver name, no signature. In a dispute the carrier has nothing to point at | `driver_flow.dart:1857` | Smallest useful step: one required "Who received the load?" field |
| J-5.1 | high | A failed earnings request renders ₹0 earned | `driver_flow.dart:1888-1904` | See [2.4](#24-a-failed-request-tells-the-driver-they-have-earned-nothing) |
| J-5.2 | high | The earnings screen never says when money arrives, and labels the tile "Pending (accrued)" | `driver_flow.dart:1914-1925` | Relabel "Earned, not yet paid" and add the timing sentence from J-4.3 |
| J-5.3 | medium | Raw KYC enum shown to the driver: "Payout profile status: SUBMITTED" | `driver_flow.dart:1926` | Add `payoutStatusLabel`, matching the four label helpers that already exist |
| J-5.4 | medium | Earnings is two taps deep behind Profile, while Publish gets a nav tab. For an owner-operator that ranking is backwards | `driver_flow.dart:1385-1390` | Swap the Publish tab for Earnings, or surface pending earnings on the Loads header |
| J-6.1 | high | The account number is optional in the request but the screen says it is required, and there is no validation. A driver can save a blank account and believe payouts are set up | `driver_flow.dart:1995`, `:2027-2030` | Validate before the post and send the field unconditionally |
| J-6.2 | high | No re-entry confirmation and no masked display of what is on file. A mistyped account number is money sent to a stranger, and it is the one error nobody can reverse | `driver_flow.dart:2022-2031` | Add a confirm field, show the saved method masked, and omit blank fields on update |
| J-6.3 | high | A failed payout-history fetch tells the driver, in confident language, that they have never been paid | `driver_flow.dart:2062-2088` | Same fix as J-5.1 |
| J-6.4 | medium | Payout rows show a raw epoch: "Cutoff 1757894400000 · 3 lines" | `driver_flow.dart:2093` | Format the date and say "deliveries", not "lines" |
| J-6.5 | medium | Saving a payout method pushes the driver to a screen reading "No payout batches yet" | `driver_flow.dart:2001-2002` | Pop back to Earnings and show the masked method and status |
| J-7.1 | medium | `DriverTrackScreen` is unreachable dead code | `driver_flow.dart:1200-1272` | See [2.7](#27-a-whole-screen-is-unreachable) |
| J-8.1 | medium | After inviting a driver there is no way to see who was invited, and no revoke | `driver_flow.dart:612-615` | List org members under the form, following the customer-side revoke pattern |
| J-8.2 | medium | Vehicle class is a free-text field asking the user to type an uppercase enum, next to a proper dropdown for role | `driver_flow.dart:665`, also `:461`, `:1373`, `:2228` | One dropdown at all four sites; deletes three validation branches that exist only to catch typos |
| J-8.3 | low | Truck fields carry over between invites, silently reusing the previous truck | `driver_flow.dart:612-613` | Reset all four controllers |
| J-9.1 | high | The publish form ships pre-filled with a real bookable lane | `driver_flow.dart:2110-2117` | See [2.3](#23-the-publish-form-ships-pre-filled-with-a-real-bookable-lane) |
| J-9.2 | high | Four publish labels are raw API parameter names | `driver_flow.dart:2226-2229` | See [2.6](#26-publish-field-labels-are-raw-api-parameter-names) |
| J-9.3 | medium | A published lane cannot be edited or withdrawn anywhere in the app, which is what makes J-9.1 expensive rather than annoying | no control exists | Either add Withdraw for `OPEN` trips with nothing booked, or state the constraint on the publish screen |
| J-10.1 | medium | Sign out is one unguarded tap, visually identical to the navigation rows above it, with no check for an active trip | `driver_flow.dart:1405-1413` | Confirm it, and warn when a trip is in progress |
| J-10.2 | medium | The app bar avatar is a filled navy circle with no image, no initials and no tap handler. Top-right circle is the universal account affordance | `driver_flow.dart:111-114` | Give it initials and a route to Profile, or delete it |
| J-O.1 | medium | The OTP screen shows a "Challenge id" field and prints the server's debug code | `driver_flow.dart:359-364` | Hide the field, and gate the debug line on `kDebugMode` |

---

## 5. Build and tooling

<a id="tooling"></a>

Not a UX finding, recorded here because it is the first thing a new contributor hits and it costs
them an hour before they see a single screen.

### 5.1 A fresh clone will not build on a current Android Studio

`android/gradle/wrapper/gradle-wrapper.properties` pins **Gradle 8.7**, and `android/settings.gradle`
pins **AGP 8.3.2** and **Kotlin 1.9.22**. Gradle 8.7 reads class files up to Java 22.

Android Studio now bundles **OpenJDK 25**, and Flutter uses the bundled JDK for Gradle when no other
is configured. The result, verified on 2026-09-16 on a machine with Android Studio and no separate
JDK installed:

```
FAILURE: Build failed with an exception.
BUG! exception in phase 'semantic analysis' in source unit '_BuildScript_'
Unsupported class file major version 69
```

Major version 69 is Java 25. Nothing about the Dart code is involved; `flutter build apk` fails
before compiling any of it.

**What worked**, verified by building a debug APK end to end (151 MB, `assembleDebug` in 153 s):

```bash
brew install openjdk@17
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
export PATH="$JAVA_HOME/bin:$PATH"
```

**What did not work:** `flutter config --jdk-dir=<path to 17>`. The setting is accepted and appears
in `flutter config --list`, but `flutter doctor -v` still reported Java 25 and Gradle still used the
bundled JDK. `JAVA_HOME` is what actually takes effect. Why the config key is ignored here is
unchecked — it may be specific to Flutter 3.22.3.

**Fix, one of two.** Either write the JDK requirement into the repo so it is not folklore —
`apps/driver_pilot/README.md` and a `gradle.properties` comment — or raise Gradle and AGP to versions
that accept a current JDK. The second is the larger change and drags the AGP and Kotlin pins with it,
so it wants its own branch and a CI check that actually builds the Android app, which none of the
four workflows does today.
