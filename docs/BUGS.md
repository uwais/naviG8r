# Bugs

Defects only: the system does something other than what it claims or intends. Losing data,
moving money to the wrong place, a screen that states something untrue, a control that errors,
a promise the code does not keep.

Anything that works as designed and could merely be designed better lives in
[`RECOMMENDATIONS.md`](RECOMMENDATIONS.md). The evidence behind the app rows is in
[`UX-REVIEW.md`](UX-REVIEW.md) and is not repeated here.

**How to read the provenance column.** `ran` means I executed something and saw the result.
`read` means I read it in the source. `claimed` means it comes from a PR author or a doc and I
have not independently confirmed it.

**Re-verified against `4461e67` on 2026-09-21**, after the RBAC restructure reached `main`. That
push closed three of the items below without a PR. Rows it did not close are marked with what is
still true. Per-PR evidence is in [`PR-TRIAGE.md`](PR-TRIAGE.md).

---

## Critical — live in production now

Stated at impact-and-module level on purpose: **this repository is public and these fixes have not
merged.** Reproduction detail is held outside it — see the note at the end of this section.

- [ ] **A debug sign-in path is honoured in production, which is a complete authentication
  bypass** — not a log leak, the login itself. Both the driver app and the ops portal auto-fill
  whatever code the server hands back. `read`
  **Fix in PR #100**, unreviewed since 31 Aug. It still merges, but **its tests do not run** — one
  identifier needs updating for the new fixtures, and then the suite passes. `ran`
  **Exposure is narrower than it looks and someone should confirm it:** `render.yaml` disables the
  debug path in beta and production and enables it only in alpha `read`, but the live production
  service predates the blueprint and is configured by hand. **Read the production environment in
  the Render dashboard** — that decides whether this is defence-in-depth or an open door.
- [ ] **An authorized payment is downgraded to failed by a later webhook for a different attempt
  on the same order,** and the reference to the successful payment is overwritten with the failed
  attempt's. A customer who fails once then succeeds can end up recorded as not having paid.
  **Proven live on `4461e67`** with a test that fails before the fix and passes after. `ran`
  **Fix in PR #13**, which merges clean and passes the full suite. Unreviewed since 12 May.
- [ ] **Production persistence writes to a path that is discarded on every redeploy,** so each
  deploy starts from an empty store. `render.yaml` is correct; the live service predates it and is
  set up by hand. Still the default on `main`. `read` Fix in PR #102, now conflicting.
- [ ] **Nothing refuses to boot when the persistence path is wrong.** A missing `AUTH_SECRET`
  exits 1; a data path pointing at disposable storage does not. Still true on `main` — startup
  checks only `AUTH_SECRET`. `read` This turns a config slip into silent total data loss, and
  **PR #102 does not address it** — the guard is still unwritten.
- [ ] **Sensitive API routes are reachable without authentication.** Fix in PR #2, unreviewed
  since **1 May — 143 days**, and now 115 commits behind. `claimed`
  **Re-check this one before acting.** The RBAC restructure moved authorization out of the route
  layer and into the domain functions, so the specific routes #2 named may already be closed. I
  did not verify #2's list. A skipped check is a failed check until someone names it.
- [ ] **Concurrent RazorpayX payouts can double-pay.** Fix in PR #85, unreviewed since 11 Aug,
  now conflicting. `claimed` — not independently confirmed.

### Closed by the RBAC restructure, not by a PR

Verified by reading both sides at `9cc20cc` and `4461e67`. Their PRs should be closed as superseded.

- [x] **An invited fleet driver can redirect the carrier's entire weekly payout to their own bank
  account.** Payout setup now requires a permission granted only to owner subroles, and a unit test
  pins it. `read` PR #82's payout half is superseded; its other two fixes still need review.
- [x] **Stored XSS in the production ops portal shipment tables.** The portal moved to its own
  module and builds rows as DOM nodes with `textContent`. The old code concatenated the
  customer-supplied organization name into `innerHTML`. `read` PR #87 superseded.
- [x] **Carrier payout history leaks other carriers' settlements.** Batch listing now filters
  transfers and ledger lines to the requesting carrier and recomputes the total from the filtered
  set. `read` PR #98 superseded.

That three security fixes arrived with no PR, no review and no release note is itself the finding.
Nobody would have known they were fixed, and nobody would have known if they had been broken.

> **Where the detail lives.** File, line and mechanism for the open rows are in
> `SECURITY-DETAIL.md`, which is listed in `.git/info/exclude` and mirrored to the internal doc.
> Move each row's detail back into this file once its fix is merged.
>
> **One thing to re-check before acting:** `/health` returned `"persistence":"file"` when
> measured on 2026-09-16, while `ROADMAP.md` records `PERSISTENCE=DB` on Postgres as achieved.
> Those disagree. Confirm which is true.

## High — money and irreversible actions

- [ ] **A failed request tells the driver they have earned nothing.** `_load()` is
  `try`/`finally` with no `catch` (`driver_flow.dart:2132-2142`) and the render falls back to
  `?? 0` (`:2147-2148`), so a dead network renders `₹0` under "Pending (accrued)" and "Paid out".
  Payout history has the same defect and says "No payout batches yet". `ran`
- [ ] **The publish form ships pre-filled with a real, bookable lane** behind one unguarded tap
  on a nav tab, and nothing can withdraw a published lane. `read`
- [ ] **On a multi-drop load the POD button submits for whichever shipment returned first,**
  releasing the wrong customer's payment. `read`
- [ ] **A carrier accepts a binding load without seeing what it pays.** The price is absent from
  the accept card and the tap through to the screen that shows it is disabled for exactly those
  rows. `read`
- [ ] **The payout account number is optional in the request while the label says required,**
  and there is no re-entry confirmation. A mistyped account is the one error nobody can reverse.
  `read`
- [ ] **A payout renders as `₹1250000`,** ungrouped. `read`

## High — the app states things that are not true

- [ ] **Location is shared only while the active-trip screen is on top,** while the customer is
  promised updates for the whole load. The 30-second interval is real
  (`driver_flow.dart:1779`); the duration is not. `ran`
- [ ] **A denied location permission is a bare `return`** — no message, no state change, and the
  screen goes on claiming GPS is being shared. `read`
- [ ] **After POD the shipment screen still says pending** and still offers Confirm delivery;
  tapping again returns a raw error. `read`
- [ ] **`hasCarrierOrg` can be true for an account with no carrier org,** because the lookup
  falls back to the first organization of any kind. That flag gates the nav, the landing state
  and the org id three money screens send. Detail in `SECURITY-DETAIL.md`. `ran`
- [ ] **A developer instruction is rendered to drivers** — one screen tells them to "merge
  driver-onboarding PR". `read`

## High — reported by pilot users

From #navig8r-pilot. These came from real customers and drivers, not from review.

- [ ] **Customers are signing in on the driver screen and getting stuck.** Reported 2026-09-12:
  *"We have posted load from drivers login but it's not showing on my login ID and showing in
  Azaad's login but unable to book the load."* PR #107 rebuilt the landing for drivers, which was
  the assigned action — but **the landing still has no mention of customers at all** (`ran`,
  checked against `origin/main`). A shipper who arrives there has no path and no explanation. The
  fix is one line of signposting to the web portal, not a customer flow on Android.
- [ ] **Trip status wording is wrong at two points.** Reported 2026-09-17. At load start it should
  read *"Load started - waiting for driver GPS"*, and the in-transit state should say *"In
  transit"*. Today the status is a raw enum.

## Medium — broken flows and dead ends

- [ ] **Start is gated on reserved kilos, not on an accepted shipment,** so the list offers an
  action the trip screen refuses with a raw error. `driver_flow.dart:1355`. `ran`
- [ ] **Every error a driver sees is a raw API code.** Two of them instruct the driver to
  redeploy the API with CORS enabled. `read`
- [ ] **The shipment list shows an error and "No shipments to deliver" at the same time;** the
  shipment detail spins forever on failure. `read`
- [ ] **`/driver/track` is registered and unreachable** — nav index 3 goes to Publish and nothing
  pushes it. `ran`
- [ ] **Two different screens both show "Proof of delivery" in the app bar,** because the title
  is a `startsWith` prefix match on `/driver/shipment/` (`driver_flow.dart:29`). `ran`
- [ ] **The Verify code screen has no way back** — `context.go` leaves no pop history and its
  only text button is Resend code (`:616`). `ran`
- [ ] **Ops-tombstoned marketplace trips are still bookable and listed.** `claimed` — PR #106.

## Medium — accessibility defects

- [ ] **Error text is `Colors.red` at 3.42:1,** failing WCAG AA. The text a driver most needs to
  read is the lowest-contrast text in the app. `read`
- [ ] **No `Semantics` widget exists anywhere in the app,** so every icon-only control is
  unlabelled for a screen reader. `read`

## Medium — build and pipeline

- [ ] **A fresh clone does not build on a current Android Studio.** It bundles JDK 25; the repo
  pins Gradle 8.7, which reads to Java 22, so `assembleDebug` dies with `Unsupported class file
  major version 69`. `flutter config --jdk-dir` is accepted and has no effect; `JAVA_HOME` is
  what works. `ran`
- [ ] **No workflow runs `flutter analyze`, `flutter test` or an Android build,** so a green tick
  on a PR says nothing about the app. A broken widget test sat red unnoticed until this review.
  `ran`

---

## The review queue is itself the biggest defect

Measured 2026-09-20 with `gh pr list --limit 200` (`ran`). An earlier count in this file said 40;
that was my error — I had capped the query at 40 and read the cap as the total.

| | |
|---|---|
| Open PRs | **71** |
| With any review decision | **1** (#103) |
| Oldest open PR | **#2, 2026-05-01 — 142 days**, "Require auth for sensitive API routes" |
| Opened per month, still open | May 23 · Jun 8 · Jul 20 · Aug 15 · Sep 5 |
| Merged in the last 7 days | 1 |

**Most of that queue is one bot re-opening the same two PRs.** Two near-daily clusters:

| Cluster | Range | Count | Theme |
|---|---|---|---|
| A | #12-#36 | 23 | production auth, payout routes, Razorpay webhook state |
| B | #52-#80 | 29 | ERP integration state loss |
| — | #2, #7, #11 and #81-#106 | 19 | distinct, individually-titled fixes |

Verified by diffing file sets: in cluster A, #25 and #33 touch an identical set and #17 all but
one; in cluster B, #65, #73 and #80 are identical and #57 all but one. These are repeated
attempts at the same two problems, not 52 separate fixes.

So the genuine queue is about **19 items, not 71** — and it contains the fix for nearly every
Critical row at the top of this page. The volume is what makes it invisible.

**Recommended order, highest value first:** #82 (payout hijack) · #102 plus a boot guard (data
loss) · #100 (auth bypass) · #2 (unauthenticated sensitive routes, open since May) · #87 (XSS) ·
#98 (payout leak) · #85 (double-pay). Then close each cluster down to its newest member, which is
a bulk operation, not a review.

**And stop the bot re-opening them,** or this page will say 90 next month. Nobody has reviewed a
PR here since #103 on 4 September, and that one is still unmerged.
