# How we write and review pull requests

For people and for agents. `.github/pull_request_template.md` enforces the shape; this page says
why, and gives the reviewer a way to judge a PR without reading the diff.

These rules exist because of what this repository actually did, not because they sound sensible.
Measured 2026-09-20: **71 open PRs, 70 with no review of any kind**, the oldest open since 1 May.
Two near-daily clusters — `#12`-`#36` and `#52`-`#80` — account for 52 of them and are repeated
attempts at the same two fixes. The rules below each answer one of those failures.

---

## For whoever opens the PR

**One problem per PR.** If a fix did not land, update the existing PR. Do not open a new one
tomorrow. Fifty-two of this repo's open PRs are the same two fixes re-attempted, and the volume
is why the other nineteen never got read.

**Say what you verified, and how.** Every claim carries a label:

| Label | Means |
|---|---|
| `ran` | You executed it and saw the result. Include the command and the output |
| `read` | You read it in the source. Cite file and line |
| `claimed` | Someone else said so and you did not confirm it |

A PR that says "fixes state regressions" and nothing else cannot be reviewed, only trusted.

**Name what you did not check.** A skipped check is a failed check until it is named. This is the
single most useful line in a PR description, because it tells the reviewer where to look.

**Keep it small.** A four-file diff can be reviewed by a non-coder with help. A forty-file diff
cannot be reviewed by anyone, including its author.

**Do not put exploit detail in a public PR.** This repository is public. For a security fix,
describe the impact and the owning module — not the file, line, and mechanism — until the fix is
merged. Afterwards it can be written up fully. See the Critical section of
[`BUGS.md`](BUGS.md) for the shape.

**Give a non-code check.** Steps someone can run on beta or the emulator to see the change work.
When there genuinely is not one, say so and name who has to read the diff. Do not leave it blank.

---

## For the reviewer who does not read code

You are not being asked to verify the code. You are being asked to judge whether the PR has made
itself checkable, and then to check what you can. Four questions, in order:

**1. Can I tell what it does?** If the "What this changes" section needs a translator, send it
back. That is not a competence problem on your side — an author who cannot explain a change in
plain English usually does not have a clear model of it either.

**2. Does it claim more than it shows?** Compare "Verified" against "Not verified". Look for a
claim with no `ran` behind it. "Tests pass" with no command and no numbers is not evidence.

**3. Do the checks that matter actually run?** Once
[the Flutter workflow](../.github/workflows/flutter-app.yml) is in place, a green tick means
`analyze` and `test` ran against the app. Before that workflow, the green ticks on this repo only
ever built the API Docker image and said nothing about the phone app.

**4. Can I see it work?** Follow the "How to check this without reading code" steps on beta. If
they do not work, that is a finding, and a real one.

**When to stop and ask for a code review.** Anything touching money, authentication, payouts, or
who is allowed to do what. Approving one of those on the strength of a well-written description is
how you get a second incident. Ask for a named human or a review agent, and say so on the PR.

**A bot approving its own work is not a review.** 67 of the 71 open PRs here were opened by the
Cursor bot. Its approval on its own PR is a rubber stamp with extra steps.

---

## For agents reviewing a PR

Comment against this standard, in this order. Be specific and quote the diff.

1. **Scope.** Does this PR do one thing? Name any unrelated change in it.
2. **Supersession.** Does an open PR already attempt this fix? Search open PRs by title and by
   changed file set before commenting. If one exists, say which should be closed.
3. **Claims.** For every "Verified" row, check the label is honest. Flag any `ran` you cannot
   corroborate from the diff, and any claim with no label at all.
4. **Gaps.** Is "Not verified" filled in and plausible? An empty one on a non-trivial change is
   itself a finding.
5. **Blast radius.** Grep for every caller of the changed function. A fix applied at one call site
   while others keep the old behaviour is not a fix — say which call sites you checked.
6. **Tests.** List the tests in the diff and say what each would catch and what it would miss.
   If the main claim has no test, say so plainly.
7. **Public-repo safety.** Flag any file, line, or mechanism detail for an unmerged security fix.

Do not soften a real problem to be agreeable, and do not invent one to look thorough. If the PR is
fine, say it is fine and stop. Never claim to have run something you did not run.

---

## What good looks like

PRs #108 to #111 on this repo were written to this standard and are worth copying: a plain-English
summary, a verification table with commands and exit codes, an explicit unverified item, and a
non-code check. #110 also names the limit of its own evidence — that the workflow had never run on
a GitHub runner at the time of writing — and a follow-up comment records the result once it did.
