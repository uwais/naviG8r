# Autonomous review, test and merge, as far as beta

What it would take for an agent to open a PR and have it reviewed, tested, merged and deployed to
beta without a human, so a person sees one reviewable batch only at the beta-to-production gate.

Measured against `origin/main` at `acf0e96` on 2026-09-22. Provenance labels follow
[`PR-STANDARD.md`](PR-STANDARD.md): `ran` = executed and saw the result, `read` = read it in the
source, `docs` = stated in a vendor's own documentation, `estimate` = calculated here, not quoted
by anyone. Method is at the bottom so anyone can redo it.

## In sixty seconds

- **The deploy half is already autonomous.** `main` to alpha to beta runs with no human, with
  tests between each stage. Only the production step is gated. `read`
- **The tests that matter do not run before a merge.** `npm test` lives only in `release.yml`,
  which triggers on push to `main`. A PR that breaks every API test merges with green ticks. `ran`
- **The ruleset gates nothing.** It blocks branch deletion and force-push. It does not require a
  PR, an approval, or a single passing check. `ran`
- **The AI reviewer has never once blocked a PR** — 16 approvals, 0 change requests across the
  last 30. It approved a real bug in #122 two minutes after the push. `ran`
- **Production is the only stage with no verification at all.** Alpha and beta wait for the
  services and run tests. Production fires three deploy hooks and the job ends. `read`
- **Five of the six steps below are free** and need no new vendor. Only the AI reviewer costs
  money, and it is the least important of the six.

---

## 1. What already works

`release.yml` runs on push to `main` and needs nobody:

| Stage | What runs | Where |
|---|---|---|
| Test | `npm test`, the full API suite | `release.yml:63` |
| Build | three images to GHCR, addressed by digest | `release.yml:65-130` |
| Alpha | deploy, wait for all three services, run integration tests | `release.yml:131-207` |
| Beta | deploy, wait for all three services, run smoke tests | `release.yml:208-288` |
| Production | deploy, gated on the `production` environment | `release.yml:289-334` |

The production gate is real and correctly set up: three required reviewers, and
`prevent_self_review` is on. `ran`

So roughly 60 percent of the target state exists. **The missing work is almost entirely on the
pull request side, before the merge.**

---

## 2. The four gaps

### Gap 1 — the tests that matter do not run before merge

`npm test` appears in exactly one workflow, `release.yml`, on `push` to `main`. That is *after*
the merge. What actually ran on #122, a PR that changed `apps/api`: `ran`

```
analyze-and-test   pass   flutter analyze + flutter test   (apps/driver_pilot only)
build              pass   docker build                     (no test step in any Dockerfile)
build              pass   docker build                     (no test step in any Dockerfile)
Cursor Approval Agent      pass
Cursor Security Agent      pass
```

None of those runs an API test. A PR that breaks all of them merges with a full set of green
ticks. This is the blocking defect: **a merge cannot be automated when the evidence for the merge
decision is produced after the merge.**

### Gap 2 — the ruleset does not gate anything

Ruleset "Sanity check mainline" is active and targets the default branch, with two rules:
`deletion` and `non_fast_forward`. `ran`

It stops `main` being deleted or force-pushed. It does not require a pull request, an approval, or
any passing check, and there is no `CODEOWNERS` file. The green ticks are decoration — nothing
consumes them.

### Gap 3 — auto-merge is off at the repository level

`allow_auto_merge` is `false`. `ran` No hands-off merge is possible until it flips, whatever else
is configured.

### Gap 4 — production deploys are never verified

Alpha waits for three services then runs integration tests. Beta waits for three services then
runs smoke tests. Production sends three deploy hooks and the job ends — `release.yml` finishes at
line 334 on the last one. `read`

A deploy hook returning 200 means the host accepted the request, not that the new image is
serving. **Resolved 2026-09-22: production deploys do take.** The live production API,
`navig8r.onrender.com`, which the driver app and customer web call, reports `9cc20cc9` (PR #107),
the last release approved at the gate. The `ad0572e6` reading came from `navig8r-api.onrender.com`,
a separate service that `render.yaml` names as production but nothing uses. It still runs 10 Sep
code. `ran`, both `/health` endpoints on 2026-09-22

Nothing in the pipeline would have caught either fact, which is the gap.

**Corrected 2026-09-22.** An earlier version of this paragraph said GitHub "recorded a successful
production deployment of `4461e67`". It did not. `4461e67` reached alpha and beta but never
production; it sat at the approval gate with state `waiting` until it was cancelled. The deployments list carries no state, and a record was
misread as a success. The statuses endpoint is the one to trust.

**The most protected stage in the pipeline is the least verified one.**

---

## 3. Why the merge gate must not be an AI approval

An AI reviewer is already installed: `cursor[bot]` reviews and approves PRs here today. The
obvious design — let it approve, then auto-merge on that approval — is the one thing this
document argues against, and the repository's own history is the evidence.

Across the last 30 PRs it left a review on 19: `ran`

| Verdict | Count |
|---|---|
| `APPROVED` | 16 |
| `COMMENTED` only | 2 |
| `DISMISSED` then re-approved | 1 |
| **`CHANGES_REQUESTED`** | **0** |

**It has never requested changes.** A gate that has never closed is not a gate.

The individual case is worse than the aggregate. On #122: `ran`

| Time (UTC) | Event |
|---|---|
| 13:59:35 | `ddaea7e` pushed. The validator rejects `&` in account holder names |
| 14:01:16 | `cursor[bot]` submits `APPROVED` |
| 15:43:10 | `afab40d` pushed, the ampersand fix |

It approved, two minutes after the push, a validator that refused `Kumar & Sons Transport` and
`M/s Sharma & Co.` — ordinary Indian carrier names — and so would have blocked those carriers from
payout onboarding. A separate review pass found it later. There was no re-review after the fix, so
the approval standing on that PR is an approval of the broken version.

This is the same finding `PR-STANDARD.md` already records in a different form: *"A bot approving
its own work is not a review."* The data says the weaker version also holds — a bot approving
anyone's work, on this repo, has approved everything.

**So: deterministic checks decide merges. AI review is additive and advisory.** An AI that says
"this looks fine" produces an unfalsifiable claim. Use it to generate findings and tests, not
permission.

---

## 4. The build, in order

### Step 1 — run the API tests on pull requests (free)

Note before building this: `release.yml` also carries `workflow_dispatch` and a `paths-ignore`
list covering `docs/**`, `**.md` and `.github/**`. So a new workflow added under `.github/` is not
exercised on its own merge - it is exercised on the next source merge instead. That is deliberate
and documented in `release.yml:11-16`, but it means a broken PR-test workflow will look fine until
the merge after the one that introduced it. `read`

A `pull_request`-triggered job running `npm test` on **Node 22**, which is what `release.yml:56`
already sets and what `Dockerfile` and `Dockerfile.www` both ship. Match it exactly. A PR test job
on a different runtime from the post-merge job and the shipped container is the drift
`flutter-app.yml` has a comment about avoiding. `ran`

Highest value change in this document; nothing else works without it.

### Step 2 — make the ruleset a real gate (free)

Add to "Sanity check mainline":

- `pull_request` — one required approval, **dismiss stale approvals on push**
- `required_status_checks` — naming the job names exactly, including the new API test job

Dismissing stale approvals is what would have caught the #122 sequence: the approval of the
broken commit would not have survived the fix commit.

### Step 3 — turn on auto-merge, only once the tests can catch a regression (free)

**Not yet.** Auto-merge trusts green checks, so it is only as safe as the tests behind them. Once
step 1 lands, a PR runs the API suite, which includes one journey over HTTP: sign in, book,
accept, upload proof of delivery, release payment, against a server the test starts itself
(`apps/api/src/rbacHttp.test.ts`). It uses a temporary file for storage and the mock payment
provider. A PR also runs the app's screen tests. Nothing drives the driver app or customer web
through a journey, so a PR can break a screen flow and still go green. Two browser test files
exist but no workflow runs them, and they check pages and access rules, not journeys. `read`,
`origin/main` at `6722529` on 2026-09-23.

Precondition: journey tests through both apps run on every PR, and have been seen failing on a
deliberately broken PR. That work is not yet scoped in this document. Then set
`allow_auto_merge`, and have agents finish with `gh pr merge --auto --squash`. The merge fires
once required checks pass, never if one fails.

### Step 4 — narrow, blocking AI checks (paid, and optional)

Not "is this good?" — questions with a checkable answer, emitted as a **status check that can
fail**, never as an approval:

- Does every user-visible element added in this diff have a named test?
- Does every `ran` row in the Verified table name a command that appears in the diff or a CI log?
- Does the diff touch money, auth or PII with no corresponding test change?

Keep `cursor[bot]` alongside as advisory comments. Two vendors with different failure modes is
worth something; two vendors both rubber-stamping is not.

### Step 5 — the beta digest (free)

The real problem is not review quality. It is that change arrives faster than a person can track,
so the beta-to-production approval approves something nobody has seen whole. Fix that by
generating the thing being approved.

The last production SHA is queryable, which makes this cheap, with one trap: the newest
deployment *record* is not the last release, because the list carries no state. Walk each
record's statuses and take the newest that reached `success`. `ran`

```
gh api repos/uwais/naviG8r/deployments/<id>/statuses --jq '[.[].state]'
```

On each beta deploy, diff that against `HEAD` and post to the release channel:

- every PR merged in the range, title and author
- changed files grouped by area, not alphabetically
- anything touching money, auth or PII, called out separately
- test count before and after
- **which changed modules the beta smoke tests did not exercise**

The last line is the one worth building. *"14 PRs merged. Beta smoke tests covered 3 of the 11
changed modules."* turns a blind approval into an informed one, and states honestly what the
automation does and does not know.

### Step 6 — verify the production deploy (free)

Give production the same wait-and-smoke treatment alpha and beta already have.
`scripts/wait-for-release.sh` and `scripts/beta-smoke.mjs` exist; they are simply not called for
production. Without this, a production deploy that silently did not take reads as a success.

---

## 5. Cost

| Thing | Cost on the current plan | Source |
|---|---|---|
| Actions minutes | **Free, unlimited** — standard runners, public repo | `docs` |
| Rulesets, required checks, required approvals | **Free** on public repos | `ran`, in use here |
| Environments and required reviewers | **Free** — the production gate runs on this plan today | `ran` |
| CodeQL code scanning | **Free** on public repos, paid only on private | `docs` |
| Dependabot | **Free** | `docs` |
| **Merge queue** | **Not available.** Requires an organization-owned repo; this one is owned by a personal account. Free once moved | `docs` + `ran` |
| Claude Code Action | **Paid**, per token. Roughly $0.15–0.30 per PR review at Sonnet rates - arithmetic from published token prices, not a figure Anthropic quotes | estimate |
| Copilot code review | **Paid.** AI credits, and since 2026-06-01 it also consumes Actions minutes | `docs` |
| Cursor agents | **Already installed and running.** Payer and tier not established | — |

**Steps 1, 2, 3, 5 and 6 are free and need no new vendor.**

---

## 6. Three things to decide

**Where agents get product direction.** This proposal does not cover it. Agents should read the
current PRD before they start work, so direction is set at the start rather than argued at review.
Review against a PRD cannot be a pass-or-fail check, so it does not belong in step 4. The latest
PRD is in a Drive folder (per Uwais on #123), which a GitHub job cannot read without a Drive
credential. A copy in the repository is already proposed in #86, and a copy goes stale. Which is
the source of truth is a team call, and it decides #86 too.

**Merge queue needs an organization.** It is the feature that stops two independently-green PRs
from breaking `main` when merged together — exactly the failure a high merge rate produces. It is
free, but only for org-owned repositories. Transferring moves ownership and needs the integrations
and identifiers checked first. Cheaper to do before the merge rate climbs than after.

**`can_admins_bypass` is `true` on the production environment.** `ran` Any admin can deploy to
production without the review the gate exists to require. That is a reasonable escape hatch for a
small team, but it makes the production gate a convention rather than a control. Worth deciding
which it should be.

The evidence since points the other way, though. On 21-22 Sep the gate was not bypassed; it
went unanswered. One release waited 41 hours at the gate with every stage green. The next could
not start behind it: it sat 25 hours without running a single stage, then waited another 6 at the
gate once green. `ran`, jobs endpoint for runs 35557611123 and 35645505581

The comment in `release.yml` calls a blocked queue "visible and therefore the better failure".
Queueing was the right trade, but visible did not mean seen. A gate that blocks unnoticed fails the
same way as one that is bypassed: the release does not ship. Alerting the approvers matters more
than tightening the gate. Whether GitHub already notifies required reviewers is unchecked.

---

## 7. Not verified

- **Whether `cursor[bot]`'s approval satisfies a required-approval rule.** GitHub documents that a
  GitHub App can satisfy required approvals, explicitly for Copilot, but that was not confirmed
  for Cursor. Test it on one PR before relying on it.
- **Live beta and production behaviour.** Outbound network access to the deploy hosts was
  unavailable when this was written, so everything about the running services comes from the repo,
  the workflow files and GitHub's deployment records — not from observing them. The one exception
  is a single production `/health` reading from 21 Sep, taken in an earlier session.
- **Every `docs` row in the cost table.** Those are vendor pricing pages read while writing this,
  not anything executed, and vendor pricing moves. Re-check before committing money.
- **Who pays for Cursor, and on what tier.**
- **Whether Cursor can emit a failing status check** instead of an approval, which is what would
  make it usable as a gate rather than advisory.

---

## Method

Everything marked `ran` came from one of these, on 2026-09-22 against `acf0e96`:

```
gh api repos/uwais/naviG8r --jq '{visibility,allow_auto_merge,plan:.owner.type}'
gh api repos/uwais/naviG8r/rulesets/15994825 --jq '{conditions,rules:[.rules[].type]}'
gh api repos/uwais/naviG8r/environments/production
gh api repos/uwais/naviG8r/deployments/<id>/statuses --jq '[.[].state]'
gh api "repos/uwais/naviG8r/actions/runs/<run>/jobs?filter=all" --jq '.jobs[]|[.name,.created_at]'
gh pr checks 122
gh api repos/uwais/naviG8r/pulls/122/reviews
grep -rn "npm test" .github/workflows/
```

The AI reviewer verdict counts came from looping the reviews endpoint over the last 30 PRs and
collecting `.state` for `cursor[bot]`:

```
for n in $(gh pr list --state all --limit 30 --json number --jq '.[].number'); do
  gh api repos/uwais/naviG8r/pulls/$n/reviews \
    --jq '[.[]|select(.user.login=="cursor[bot]")|.state]|join(",")'
done
```
