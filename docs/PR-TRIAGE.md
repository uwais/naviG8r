# Triage of the 71 open pull requests

Measured against `origin/main` at `4461e67` on 2026-09-21. Every number here came from a command
that was run, not from reading a PR description. Method is at the bottom so anyone can redo it.

Provenance labels follow [`PR-STANDARD.md`](PR-STANDARD.md): `ran` = executed and saw the result,
`read` = read it in the source, `claimed` = the PR author said so and nobody confirmed it.

## In sixty seconds

- **71 open PRs contain 50 unique changes.** 21 are byte-identical copies of another open PR and
  can be closed without reading them. `ran`
- **66 of 71 no longer merge.** The RBAC restructure that went to `main` on 20 Sep invalidated the
  backlog. Only #13, #53, #97, #100 and #103 still apply. `ran`
- **The backlog is not "71 PRs awaiting review."** It is 5 reviewable PRs, 21 duplicates, and 45
  that need their author to rebase before anyone can judge them.
- **Three security items were silently closed** by that same unreviewed push: the fleet-driver
  payout hijack, the ops-portal stored XSS, and the cross-carrier payout-history leak. `read`
- **Two things are still live.** A Razorpay webhook downgrades authorized payments — proven with a
  failing test on current `main` `ran` — and the store still defaults to an ephemeral path with no
  boot guard. `read`
- **Do not merge #103 as it stands.** 123 of its 190 line citations point into files that have
  changed since it was written. `ran`

## Merge now

Both verified end to end: merged into a scratch worktree off `4461e67`, full API suite run.

| PR | What it fixes | Verification |
|---|---|---|
| **#13** | A `payment.failed` webhook for a *failed attempt* downgrades an already-`AUTHORIZED` payment to `FAILED` and overwrites the successful payment reference with the failed attempt's. Open since 12 May. | Wrote an independent probe: **fails on `main`**, **passes with #13**. Suite **155/155**. `ran` |
| **#100** | Production must ignore `OTP_DEBUG`. The API currently returns a debug sign-in code whenever that variable is `1`, with no environment check, and both the driver app and the ops portal auto-fill it. | Merges, but **its tests do not run** — see below. With the one-word fix: **155/155**. `ran` |

**#100 needs one word before it is mergeable.** Its new test calls `registerSoloOwnerOperatorDriver`,
which the RBAC restructure replaced with fixtures. In `apps/api/src/pilotAuth.test.ts:84`:

```diff
-  const onboard = registerSoloOwnerOperatorDriver(store, {
+  const onboard = registerCompliantCarrier(store, {
```

The fixture takes identical parameters. That is the whole change; the suite then passes. This is
worth noticing on its own: **#100 is reported mergeable by GitHub and does not run.** Git merged the
text cleanly because the additions never overlapped. "Mergeable" is not "works", and only running it
tells you which.

**How exposed is the OTP bypass?** `render.yaml` sets `OTP_DEBUG: "0"` for beta and production and
`"1"` for alpha `read`, so by the blueprint it is not active in production. But the live production
service predates the blueprint and is configured by hand, so the blueprint does not prove what is
set. **Someone should read the production service's environment in the Render dashboard** — that is
a 30-second check and it decides whether this is defence-in-depth or an open front door. Unchecked
here: I did not probe the live endpoint, because starting an OTP sends a real message to a real
phone.

## Close without reading — 21 exact duplicates

Same patch, byte for byte, after normalising blob hashes and hunk offsets. Keep the lowest number of
each group; close the rest pointing at the keeper.

| Keep | Close |
|---|---|
| #54 | #55, #56 |
| #57 | #58 |
| #59 | #61, #62 |
| #63 | #64 |
| #65 | #66, #67, #68, #69, #70, #71, #72, #73, #74, #75, #76, #77, #78, #79, #80 |

Sixteen identical copies of one change, opened daily from 10 Jul to 5 Aug. Nobody was reading them,
so the bot kept reopening; the volume is why the rest went unread. This is the failure
[`PR-STANDARD.md`](PR-STANDARD.md) exists to stop.

## Already fixed on `main` — close as superseded

The RBAC restructure closed these. Verified by reading both sides, not by trusting the titles.

| PR | Claim | Why it is closed |
|---|---|---|
| **#82** (payout half) | Any invited driver can point the carrier's weekly payout at their own bank account | `pilotSubmitPayoutSetup` now requires `bank_account.create_token`, which is granted only to `OWNER_DRIVER` and `OWNER` subroles. An invited `DRIVER` is refused. Pinned by a test. `read` |
| **#87** | Stored XSS in the ops portal shipment tables | The portal was rewritten into its own module and builds rows with `createElement` and `textContent`. The old code concatenated the customer-supplied org name into `innerHTML`. `read` |
| **#98** | Carrier payout history leaks other carriers' settlements | Batch listing now filters transfers and ledger lines to the requesting carrier and recomputes the total from the filtered set. Before, whole batches were returned. `read` |

**#82 is not fully superseded.** Only its payout half is. It also carries a POD-before-start fix and
a stuck-payment recovery path, neither of which I checked. Rebase it rather than close it, and
re-review those two parts against the new model rather than against the PR description.

**One thing to know before reviewing any API route.** Authorization now lives in the domain layer,
not at the route. `POST /shipments/:id/fail-refund` and `/accept-pod` have no guard on the route
line — the check is inside `failCarrierAndRefund` and `acceptPod`, which call `requirePermission`
for `payment.refund` and `pod.accept`. `requirePermission` throws 401 when there is no principal, so
the routes are closed. `read` Anyone skimming `httpServer.ts` will otherwise report these as
unauthenticated money endpoints and be wrong. It is also why that file lost 811 lines.

## Still live

| What | Where it stands |
|---|---|
| **Authorized payments downgraded by a stale webhook** | #13 fixes it and merges clean. Proven live with a failing test. `ran` |
| **Production store on an ephemeral path** | Still defaults to a relative path, and the boot guard still does not exist — startup only checks `AUTH_SECRET`. #102 corrects the path but adds no guard, and it now conflicts. `read` |
| **Public trip responses still carry user ids** | Residual from #115. Not location, but correlating them across trips maps which driver runs which lanes. Needs its own small change. `read` |

## Do not merge #103 as it stands

#103 is the only approved PR in the repo and it is tempting, because it adds
`docs/CODEBASE_MAP.md` (422 lines) and `docs/ARCHITECTURE.md` (430) — documents this repo should
have. It was verified against `f96ccf9` on 4 Sep. Since then the RBAC restructure landed.

- **123 of its 190 line citations point into files that have changed.** 16 of the 29 files it cites
  were modified. `httpServer.ts` alone lost 811 lines. `ran`
- **It does not mention `rbac.ts`, `rbacRoutes.ts`, `rbacResponses.ts`, `opsPortal.ts`,
  `authorization_session.dart` or `organization_access.dart`** — the six files that now carry
  authorization. Its architecture section describes a model that no longer exists. `ran`
- It lists the public-GPS leak as open. That was closed by #115 on 20 Sep.

A map is trusted precisely because it is a map, so a stale one costs more than no map. Two honest
options: refresh it against `4461e67` before merging, or merge it with a dated banner saying it
describes `f96ccf9` and predates the authorization rewrite. Refreshing is better — the content is
good and mostly a line-number problem.

## Everything else — 45 PRs needing a rebase

Between 41 and 115 commits behind, all conflicting. None can be reviewed until its author rebases,
and no reviewer should spend time on them in this state. Ask the bot's owner to rebase the ones
worth keeping and close the rest. Ranked by what they claim to fix:

- **Worth rebasing:** #2 (unauthenticated sensitive routes, open since 1 May, 143 days), #82 (refund
  widening), #85 (concurrent payout double-pay), #101 (unbounded store growth), #102 (persistence
  path), #104 (legacy demo surface on beta), #106 (tombstoned trips still bookable).
- **Probably obsolete:** the #12–#36 cluster, 23 PRs of overlapping auth and Razorpay fixes from
  May and June. The authorization half is superseded; whether the Razorpay half survives needs one
  pass by someone who knows the payment flow. #13 is the one already confirmed to matter.
- **Needs a decision, not a review:** #86 (a 1,508-line product requirements document) and #89
  (Cursor environment notes) are not code and should not sit in the code queue.

## Method

Anyone can reproduce this; nothing here needs privileged access.

```bash
# 1. Every open PR's metadata
gh pr list --state open --limit 200 \
  --json number,title,author,createdAt,additions,deletions,changedFiles,files > prs.json

# 2. Duplicate detection: normalise blob hashes and hunk offsets, then hash the patch
gh pr diff "$n" | grep -v '^index ' | sed -E 's/^@@ .* @@/@@/' | shasum -a 256

# 3. Does it still apply? Trial-merge without touching the working tree
git fetch origin '+refs/pull/*/head:refs/remotes/pr/*'
git merge-tree --write-tree origin/main "refs/remotes/pr/$n"
#    non-zero exit  -> conflicts
#    tree == main's -> the change is already on main
```

Verifying a fix, rather than believing it:

```bash
git worktree add --detach /tmp/wt origin/main
cd /tmp/wt && git merge --no-edit pr/13
node --experimental-strip-types --test "apps/api/src/**/*.test.ts" "packages/**/src/**/*.test.ts"
```

The step that earned its keep was writing a test that **fails** on `main` before trusting the PR
that claims to fix it. #13's description was accurate; #100's was too, but its tests did not run.
Neither fact is visible from the PR page.
