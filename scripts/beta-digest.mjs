#!/usr/bin/env node

/**
 * What is sitting on beta that production does not have yet.
 *
 * Why this exists: the person approving the production gate is approving every change since the
 * last production release and has no way to see what that is. On 2026-09-22 that was 37 commits
 * over six days, with two releases already queued at the gate that nobody had noticed.
 *
 * The rule this file lives by: never imply more verification than happened, and never state
 * something it did not actually read. Three things make that hard, and all three are handled
 * explicitly rather than hopefully.
 *
 *   1. A failed API call must not look like a finding. The first draft of this script swallowed
 *      every `gh` error, then announced "no production deployment reached success" - a claim about
 *      thirty records it had not read - and exited 0 with an empty summary. Silent, confident and
 *      wrong is the worst outcome for a reporting tool, so `gh()` now separates "call failed" from
 *      "call returned nothing", and any failure makes the digest say so and exit non-zero.
 *
 *   2. A production deployment RECORD is not a production deployment. Five records since 16 Sep
 *      are `error` or `waiting`, and the list endpoint carries no state. This walks the statuses
 *      endpoint and takes the newest deployment that actually reached `success`. Even then,
 *      `success` only means the three deploy hooks returned 2xx - the Verify Production job checks
 *      the API afterwards, but a failed check does not change this record - so the wording stays
 *      "accepted a deploy hook", not "released".
 *
 *   3. Beta does not rehearse production's money path. PAYOUTS_MODE is BOOKKEEPING on alpha and
 *      beta and RAZORPAYX on production (render.yaml), so the branch inside
 *      runPayoutBatchAuthorized that creates a real transfer per carrier runs for the first time
 *      in production. Detecting that by filename alone missed apps/api/src/services.ts, which is
 *      where the branch actually lives, so this matches on diff content instead.
 */

import { execFileSync } from "node:child_process";
import { appendFileSync } from "node:fs";

const REPO = process.env.GITHUB_REPOSITORY || "uwais/naviG8r";

/** Anything that stopped this digest from knowing what it claims to know. Never empty silently. */
const failures = [];

/**
 * 30 seconds per call. Without a cap, one hung call runs into the step's 5-minute limit, which
 * kills the process before finish() - so the summary comes out blank, the one outcome this file
 * promises never to produce. With it, the hang is recorded as a failure and reported.
 */
const CALL_TIMEOUT_MS = 30_000;

/**
 * Reading deployment history is the only run of many network calls: one list plus up to 30
 * status reads, which at 30 seconds each would outlast the step's 5-minute limit. The budget
 * covers the list and the reads, and a read only starts if it can finish inside it. Worst case
 * for the whole script: 120s here, four local git calls, one runs call and the Slack post, 280s.
 */
const HISTORY_BUDGET_MS = 120_000;

/**
 * Node's own failures (timeout, buffer overflow, missing binary) carry a code, and for those the
 * message is the real cause even if the command had already written something. Otherwise the
 * command's first stderr line says more than Node's "Command failed".
 */
function errorText(err) {
  const commandSaid = err.code ? "" : String(err.stderr || "").trim().split("\n")[0];
  return commandSaid || String(err.message).split("\n")[0];
}

function git(args, { allowFail = false } = {}) {
  try {
    return execFileSync("git", args, { encoding: "utf8", maxBuffer: 32 * 1024 * 1024, timeout: CALL_TIMEOUT_MS }).trim();
  } catch (err) {
    if (!allowFail) failures.push(`git ${args.slice(0, 2).join(" ")}: ${errorText(err)}`);
    return null;
  }
}

/** Returns the output, or null when the call FAILED. Null and "" mean different things here. */
function gh(path, jq) {
  const args = ["api", path];
  if (jq) args.push("--jq", jq);
  try {
    return execFileSync("gh", args, { encoding: "utf8", maxBuffer: 16 * 1024 * 1024, timeout: CALL_TIMEOUT_MS }).trim();
  } catch (err) {
    failures.push(`gh api ${path.split("?")[0]}: ${errorText(err)}`);
    return null;
  }
}

const HEAD = process.env.GITHUB_SHA || git(["rev-parse", "HEAD"]);

/**
 * The newest production deployment whose status actually reached `success`.
 *
 * One list call gets id and sha; each record then needs one statuses read, newest status first.
 *
 * The age comes from when the status reached `success`, not from the record's creation. A record
 * is created when a release reaches the approval gate, which can be days before it goes out:
 * 9cc20cc9 was created on 16 Sep and succeeded on 18 Sep.
 *
 * Any record that cannot be read, or running out of time, makes the whole history unreadable
 * (null). Carrying on past a gap would end in "no deployment reached success" - a claim about
 * records never read - or walk past a good deployment to an older one.
 */
function lastSuccessfulProduction() {
  const started = Date.now();
  const raw = gh(`repos/${REPO}/deployments?environment=production&per_page=30`, '.[]|"\\(.id)\\t\\(.sha)"');
  if (raw === null) return null;

  const notSucceeded = [];
  for (const line of raw.split("\n").filter(Boolean)) {
    if (Date.now() - started + CALL_TIMEOUT_MS > HISTORY_BUDGET_MS) {
      failures.push(`stopped reading production deployment history after ${Math.round((Date.now() - started) / 1000)}s`);
      return null;
    }
    const [id, sha] = line.split("\t");
    const read = gh(
      `repos/${REPO}/deployments/${id}/statuses`,
      '([.[].state]|join(",")) + "\\t" + ([.[]|select(.state=="success")|.created_at][0] // "")',
    );
    if (read === null) return null;
    const [states, liveAt] = read.split("\t");
    if (liveAt) return { sha, liveAt, notSucceeded };
    notSucceeded.push({ sha: sha.slice(0, 8), states: states || "no status recorded" });
  }
  return { sha: null, liveAt: null, notSucceeded };
}

/** Releases that reached the production gate and are still sitting there. */
function waitingForApproval() {
  const raw = gh(
    `repos/${REPO}/actions/workflows/release.yml/runs?per_page=20`,
    '[.workflow_runs[]|select(.status=="waiting" or .status=="pending")|{sha:.head_sha,created:.created_at,url:.html_url,status:.status}]',
  );
  if (raw === null) return [];
  try {
    return JSON.parse(raw || "[]");
  } catch {
    failures.push("could not parse the workflow runs response");
    return [];
  }
}

/**
 * Area per changed path, most specific first.
 *
 * Test globs lead on purpose: API tests sit in the SAME folder as the code they cover
 * (payoutRazorpayx.test.ts next to razorpayPayouts.ts), so an apps/api/src rule placed above them
 * would file every test under Payments and overstate what changed.
 */
const AREAS = [
  [/(^|\/)(test|playwright)\/|\.test\.ts$|_test\.dart$|\.spec\.ts$|playwright.*\.config\.ts$/, "Automated tests", null],
  [/^apps\/api\/prisma\//, "Database schema and migrations", "money"],
  [/razorpay|payout|bankAccount/i, "Payments and payouts", "money"],
  [/^apps\/api\/src\/.*(auth|rbac)/i, "Who can do what", "auth"],
  [/^apps\/api\/src\/.*(services|store|persistence|types|softDelete|ledger)/, "Core API logic", "money"],
  [/^apps\/api\/src\/.*(httpServer|opsPortal|integrationHttp|integrationWebhooks)/, "API surface", "pii"],
  [/^apps\/api\//, "API, other", null],
  [/^apps\/driver_pilot\//, "Driver phone app", "pii"],
  [/^apps\/customer_web\//, "Customer web app", "pii"],
  [/^apps\/www\//, "Public website", "pii"],
  [/^packages\//, "Shared packages", null],
  [/^\.github\/workflows\//, "CI pipeline", null],
  [/^scripts\//, "Deploy and test scripts", null],
  [/^package(-lock)?\.json$/, "Dependencies", "money"],
  [/^render\.yaml$|^Dockerfile/, "Deployment config", "money"],
  [/^(docs\/|README|.*\.md$)/, "Documentation", null],
];

function areaOf(file) {
  for (const [pattern, area, sensitivity] of AREAS) {
    if (pattern.test(file)) return { area, sensitivity };
  }
  return { area: "Other", sensitivity: null };
}

const SENSITIVITY_RANK = { money: 0, auth: 1, pii: 2, null: 3 };
const SENSITIVITY_LABEL = { money: "**money**", auth: "**access control**", pii: "personal data" };

const lines = [];
const say = (s = "") => lines.push(s);

function emit() {
  const out = lines.join("\n");
  console.log(out);
  if (process.env.GITHUB_STEP_SUMMARY) {
    try {
      appendFileSync(process.env.GITHUB_STEP_SUMMARY, out + "\n");
    } catch (err) {
      console.error(`could not write the run summary: ${err.message}`);
    }
  }
}

/** Filled in as the digest learns things, so the Slack alert can say whatever is known. */
const alertFacts = { commits: null, age: null, touchesPayouts: false };

/** Kept apart from `failures`: a failed alert says nothing about whether the summary is right. */
let alertFailure = null;

/**
 * Tell the channel a release is waiting, instead of hoping someone opens the run page.
 *
 * On 2026-09-22 a release sat at the production gate for 40 hours unnoticed, and the one behind it
 * could not start, because release.yml's concurrency group lets one run wait at a time. A summary
 * that nobody is told about is not visible, whatever the release.yml comment says.
 *
 * Needs a Slack incoming webhook in the SLACK_RELEASE_WEBHOOK secret. Without it the digest says
 * the alert was not sent, so a missing alert can never pass for a sent one. Incoming webhooks take
 * Slack's own markup, not markdown: *bold*, <url|label>.
 */
async function alertSlack() {
  say();
  const webhook = process.env.SLACK_RELEASE_WEBHOOK;
  if (!webhook) {
    say("Slack alert **not sent**: the `SLACK_RELEASE_WEBHOOK` secret is not set.");
    return;
  }
  const runUrl = process.env.GITHUB_RUN_ID
    ? `${process.env.GITHUB_SERVER_URL || "https://github.com"}/${REPO}/actions/runs/${process.env.GITHUB_RUN_ID}`
    : null;
  // With any failure the counts may be wrong, so they are not sent. The payout warning still is:
  // it is only set after the source diff was actually read and matched, so when present it is true.
  const incomplete = failures.length > 0;
  const text = [
    "*A release is waiting for production approval*",
    incomplete
      ? "The summary is incomplete. Open the release before approving."
      : alertFacts.commits === null
        ? "Open the release for the summary."
        : `${alertFacts.commits} commits since production last took a deploy, ${alertFacts.age} ago.`,
    ...(alertFacts.touchesPayouts
      ? ["It changes payout code, which beta does not rehearse. Read the summary before approving."]
      : []),
    (runUrl ? `<${runUrl}|Open the release to review and approve.>` : "Open the latest release run to approve.") +
      " Whoever merged it cannot approve it.",
  ].join("\n");

  try {
    const res = await fetch(webhook, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ text }),
      signal: AbortSignal.timeout(10_000),
    });
    if (res.ok) say("Slack alert sent to the release channel.");
    else alertFailure = `HTTP ${res.status}`;
  } catch (err) {
    // The cause code, never the message: a message can echo the URL, and the URL is the secret.
    alertFailure = err.cause?.code || err.name;
  }
}

/** Every exit goes through here, so a broken digest is never a blank one. */
async function finish() {
  await alertSlack();
  if (alertFailure) {
    // Only vouch for the summary when nothing else failed; otherwise the next section says it is
    // partial, and the two lines would contradict each other.
    say(`Slack alert **failed** (\`${alertFailure}\`).` +
      (failures.length ? "" : " The summary above is complete; only the alert did not go out."));
  }
  if (failures.length) {
    say();
    say("### This digest is incomplete");
    say();
    say("Some of what it needs could not be read, so treat everything above as partial:");
    say();
    for (const f of failures) say(`- \`${f}\``);
  }
  say();
  say(`---`);
  say(`Generated ${new Date().toISOString().replace("T", " ").slice(0, 16)} UTC, when beta was ` +
    `deployed. Ages above are from that moment, not from when you are reading this.`);
  emit();
  process.exit(failures.length || alertFailure ? 1 : 0);
}

say("## What beta has that production does not");
say();

const prod = lastSuccessfulProduction();

if (prod === null || !prod.sha) {
  say(prod === null
    ? "**Could not read the production deployment history**, so the range below cannot be computed."
    : `**None of the last ${prod.notSucceeded.length} production deployment records reached \`success\`.** ` +
      "That is worth a look at the production environment history.");
  if (prod && prod.notSucceeded.length) {
    say();
    for (const d of prod.notSucceeded) say(`- \`${d.sha}\` — ${d.states}`);
  }
  await finish();
}

const range = `${prod.sha}..${HEAD}`;
// Not allowFail: the real error goes into failures, since a timeout and a missing commit need
// different fixes.
const files = git(["diff", "--name-only", range]);

if (files === null) {
  say(`**The range from the last production commit \`${prod.sha.slice(0, 8)}\` could not be ` +
    "computed.** Usually the checkout lacks `fetch-depth: 0`, or that commit was force-pushed " +
    "away. The exact error is listed below.");
  await finish();
}

const fileList = files.split("\n").filter(Boolean);
// Null when git log failed, so the headline says "unavailable" rather than a false "0 commits".
const commitLog = git(["log", "--oneline", range]);
const commits = commitLog === null ? null : commitLog.split("\n").filter(Boolean);
const subjects = (git(["log", "--format=%s", range]) || "").split("\n").filter(Boolean);

// A revert names the PR it undid, so counting it as included would over-report.
const reverted = new Set(
  subjects.filter((s) => s.startsWith("Revert")).flatMap((s) => [...s.matchAll(/#(\d+)/g)].map((m) => m[1])),
);
const prs = [...new Set(
  subjects
    .filter((s) => !s.startsWith("Revert"))
    .map((s) => /Merge pull request #(\d+)|\(#(\d+)\)/.exec(s))
    .map((m) => m && (m[1] || m[2]))
    .filter(Boolean),
)].filter((n) => !reverted.has(n));

const hours = Math.round((Date.now() - Date.parse(prod.liveAt)) / 3600000);
const age = hours >= 48 ? `${Math.round(hours / 24)} days` : `${hours} hours`;
alertFacts.commits = commits === null ? null : commits.length;
alertFacts.age = age;

say(`Production last accepted a deploy hook for \`${prod.sha.slice(0, 8)}\`, **${age} ago**.`);
say();
say(`> A \`success\` deployment status means the three deploy hooks returned 2xx. The Verify ` +
  `Production job's result is on that release's run, not on this record, so this is the last ` +
  `deploy *attempted*, not confirmed. Run \`/health\` against production if you need to know what ` +
  `it is actually running.`);
say();
say(`Beta is at \`${HEAD.slice(0, 8)}\`: ` +
  (commits === null ? "commit count unavailable" : `**${commits.length} commits**`) +
  `, ${fileList.length} files` +
  (prs.length ? `, from ${prs.map((n) => `#${n}`).join(", ")}` : "") + ".");
say();

if (prod.notSucceeded.length) {
  // By the newest status only. Every production record passes through `waiting`, so a deploy that
  // was approved and then failed still has "waiting" further down its history.
  // `in_progress` in the history means the deploy job actually started, so the release was approved.
  // Without it, nothing reached production, whatever the final state says.
  const kind = (d) => {
    const states = d.states.split(",");
    const started = states.includes("in_progress");
    if (states[0] === "waiting") return "waiting";
    if (states[0] === "error") return started ? "cancelled mid-deploy" : "cancelled";
    if (states[0] === "failure") return started ? "failed deploy" : "stopped before deploy";
    return `other (\`${states[0]}\`)`;
  };
  const meanings = {
    waiting: "last recorded waiting at the approval gate; not a build problem",
    cancelled: "usually a run cancelled at or before the approval gate, not a broken build",
    "cancelled mid-deploy": "**cancelled while deploying; some deploy hooks may already have fired**",
    "failed deploy": "**approved, then the deploy itself failed**",
    "stopped before deploy": "stopped before the deploy started, for example rejected at the gate",
  };
  say(`**${prod.notSucceeded.length} newer production deployment records did not succeed.**`);
  for (const k of [...new Set(prod.notSucceeded.map(kind))]) {
    const hits = prod.notSucceeded.filter((d) => kind(d) === k);
    say(`- ${hits.length} ${k} (${hits.map((d) => `\`${d.sha}\``).join(", ")})` + (meanings[k] ? `: ${meanings[k]}.` : "."));
  }
  say();
}

// `waiting` is at the approval gate; `pending` is queued behind another run and has not started.
const runs = waitingForApproval();
for (const [status, label] of [["waiting", "waiting for production approval"], ["pending", "queued, not yet started"]]) {
  const matching = runs.filter((w) => w.status === status);
  if (!matching.length) continue;
  say(`**${matching.length} release${matching.length > 1 ? "s" : ""} ${label}:**`);
  for (const w of matching) {
    say(`- \`${w.sha.slice(0, 8)}\` — ${Math.round((Date.now() - Date.parse(w.created)) / 3600000)}h — ${w.url}`);
  }
  say();
}

const byArea = new Map();
for (const f of fileList) {
  const { area, sensitivity } = areaOf(f);
  const row = byArea.get(area) || { count: 0, sensitivity };
  row.count += 1;
  byArea.set(area, row);
}

say("### What changed");
say();
say("| Area | Files | Handles |");
say("|---|---|---|");
const ordered = [...byArea].sort((a, b) => {
  const s = SENSITIVITY_RANK[a[1].sensitivity] - SENSITIVITY_RANK[b[1].sensitivity];
  return s !== 0 ? s : b[1].count - a[1].count;
});
for (const [area, row] of ordered) {
  say(`| ${area} | ${row.count} | ${SENSITIVITY_LABEL[row.sensitivity] || ""} |`);
}
say();

// "CI passed" reads as "this was tested". For the deployed environments that is close to false,
// so both tiers are stated separately. The gating test count is only the files npm test globs -
// Flutter tests and the Playwright specs are not in release.yml at all.
const gatingTests = fileList.filter((f) => /^(apps|packages)\/.*\/src\/.*\.test\.ts$/.test(f)).length;
const nonGatingTests = (byArea.get("Automated tests")?.count || 0) - gatingTests;

say("### What actually verified this release");
say();
say("- **Unit tests: blocking.** `npm test` gates the build, which gates every deploy. They run");
say("  against in-process fakes, not a deployed service.");
if (nonGatingTests > 0) {
  say(`  Of the ${gatingTests + nonGatingTests} test files changed, **${gatingTests} are run by \`npm test\`**; ` +
    `${nonGatingTests} are Flutter or Playwright files that no release job executes.`);
}
say("- **Alpha: 4 endpoints.** health, OTP start, OTP verify, `/v1/pilot/me`. Auth happy path only.");
say("- **Beta: 1 endpoint.** `/health` — checks `ok`, the payment provider string, and that the");
say("  release SHA matches. It exercises no application behaviour.");
say("- **Production: nothing yet.** After approval, Verify Production waits for the API's");
say("  `/health` to report this release. Customer web and www are not checked; no smoke test.");
say();

/**
 * Match on diff CONTENT, not filenames. The money branch lives in apps/api/src/services.ts, whose
 * path contains none of the payout words, so a filename test missed exactly the case that matters.
 * Tests and docs are excluded so a test-only change does not fire a warning about real bank
 * accounts.
 */
const PAYOUT_IDENTIFIERS = /payoutsMode|runPayoutBatch|RAZORPAYX|razorpayx|fundAccount|payoutBatch|ledgerLine/;
const sourceDiff = git(
  [
    "diff", "-U0", range, "--", "apps", "packages",
    ":(exclude)*.test.ts", ":(exclude)*_test.dart",
    ":(exclude)*/test/*", ":(exclude)*/playwright/*",
  ],
  { allowFail: true },
);
if (sourceDiff === null) {
  failures.push("could not read the source diff, so the payout warning above may be missing");
} else if (PAYOUT_IDENTIFIERS.test(sourceDiff)) {
  alertFacts.touchesPayouts = true;
  say("### Read this before approving");
  say();
  say("This release changes payout code, and **beta did not rehearse it**. `PAYOUTS_MODE` is");
  say("`BOOKKEEPING` on alpha and beta and `RAZORPAYX` on production (`render.yaml`). The branch");
  say("inside `runPayoutBatchAuthorized` that creates a real RazorpayX transfer per carrier runs");
  say("for the first time in production, against real bank accounts. Every green tick above");
  say("exercised the other branch.");
  say();
}

say(`Range \`${prod.sha.slice(0, 8)}..${HEAD.slice(0, 8)}\`. The last production SHA is the newest`);
say("deployment whose status reached `success`, which is not the same as the newest record.");

await finish();
