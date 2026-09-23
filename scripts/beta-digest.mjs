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
 *      `success` only means the three deploy hooks returned 2xx - `release.yml` never checks that
 *      the new image is serving - so the wording stays "accepted a deploy hook", not "released".
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

function git(args, { allowFail = false } = {}) {
  try {
    return execFileSync("git", args, { encoding: "utf8", maxBuffer: 32 * 1024 * 1024 }).trim();
  } catch (err) {
    if (!allowFail) failures.push(`git ${args.slice(0, 2).join(" ")}: ${String(err.message).split("\n")[0]}`);
    return null;
  }
}

/** Returns the output, or null when the call FAILED. Null and "" mean different things here. */
function gh(path, jq) {
  const args = ["api", path];
  if (jq) args.push("--jq", jq);
  try {
    return execFileSync("gh", args, { encoding: "utf8", maxBuffer: 16 * 1024 * 1024 }).trim();
  } catch (err) {
    failures.push(`gh api ${path.split("?")[0]}: ${String(err.message).split("\n")[0]}`);
    return null;
  }
}

const HEAD = process.env.GITHUB_SHA || git(["rev-parse", "HEAD"]);

/**
 * The newest production deployment whose status actually reached `success`.
 *
 * One list call gets id, sha and created_at together; only the per-deployment statuses need a
 * second call. The previous version fetched each sha separately, which was 30 wasted requests.
 *
 * A statuses call that fails is recorded as unknown rather than assumed non-successful, because
 * assuming would invent a failed deployment out of a network error and walk past a good one.
 */
function lastSuccessfulProduction() {
  const raw = gh(
    `repos/${REPO}/deployments?environment=production&per_page=30`,
    '.[]|"\\(.id)\\t\\(.sha)\\t\\(.created_at)"',
  );
  if (raw === null) return null;

  const notSucceeded = [];
  for (const line of raw.split("\n").filter(Boolean)) {
    const [id, sha, createdAt] = line.split("\t");
    const states = gh(`repos/${REPO}/deployments/${id}/statuses`, '[.[].state]|join(",")');
    if (states === null) {
      notSucceeded.push({ sha: sha.slice(0, 8), states: "could not read" });
      continue;
    }
    if (states.split(",").includes("success")) return { sha, createdAt, notSucceeded };
    notSucceeded.push({ sha: sha.slice(0, 8), states: states || "no status recorded" });
  }
  return { sha: null, createdAt: null, notSucceeded };
}

/** Releases that reached the production gate and are still sitting there. */
function waitingForApproval() {
  const raw = gh(
    `repos/${REPO}/actions/workflows/release.yml/runs?per_page=20`,
    '[.workflow_runs[]|select(.status=="waiting" or .status=="pending")|{sha:.head_sha,created:.created_at,url:.html_url}]',
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
  const webhook = process.env.SLACK_RELEASE_WEBHOOK;
  if (!webhook) {
    say("Slack alert **not sent**: the `SLACK_RELEASE_WEBHOOK` secret is not set.");
    return;
  }
  const runUrl = process.env.GITHUB_RUN_ID
    ? `${process.env.GITHUB_SERVER_URL || "https://github.com"}/${REPO}/actions/runs/${process.env.GITHUB_RUN_ID}`
    : null;
  const text = [
    "*A release is waiting for production approval*",
    alertFacts.commits === null
      ? "The summary could not be built. Open the release for details."
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
    else failures.push(`Slack alert failed: HTTP ${res.status}`);
  } catch (err) {
    // The cause code, never the message: a message can echo the URL, and the URL is the secret.
    failures.push(`Slack alert failed: ${err.cause?.code || err.name}`);
  }
}

/** Every exit goes through here, so a broken digest is never a blank one. */
async function finish() {
  await alertSlack();
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
    `deployed. Ages below are from that moment, not from when you are reading this.`);
  emit();
  process.exit(failures.length ? 1 : 0);
}

say("## What beta has that production does not");
say();

const prod = lastSuccessfulProduction();

if (prod === null || !prod.sha) {
  say(prod === null
    ? "**Could not read the production deployment history**, so the range below cannot be computed."
    : "**No production deployment in the last 30 records reached `success`.** That is worth a look " +
      "at the production environment history.");
  if (prod && prod.notSucceeded.length) {
    say();
    for (const d of prod.notSucceeded) say(`- \`${d.sha}\` — ${d.states}`);
  }
  await finish();
}

const range = `${prod.sha}..${HEAD}`;
const files = git(["diff", "--name-only", range], { allowFail: true });

if (files === null) {
  say(`**The last production commit \`${prod.sha.slice(0, 8)}\` is not in this clone**, so the ` +
    "range could not be computed. The checkout needs `fetch-depth: 0`, or that commit was removed " +
    "from the branch by a force-push.");
  failures.push(`git diff ${range}: revision not present`);
  await finish();
}

const fileList = files.split("\n").filter(Boolean);
const commits = (git(["log", "--oneline", range]) || "").split("\n").filter(Boolean);
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

const hours = Math.round((Date.now() - Date.parse(prod.createdAt)) / 3600000);
const age = hours >= 48 ? `${Math.round(hours / 24)} days` : `${hours} hours`;
alertFacts.commits = commits.length;
alertFacts.age = age;

say(`Production last accepted a deploy hook for \`${prod.sha.slice(0, 8)}\`, **${age} ago**.`);
say();
say(`> A \`success\` deployment status means the three deploy hooks returned 2xx. \`release.yml\` ` +
  `never checks that the new image is serving, so this is the last deploy *attempted*, not ` +
  `confirmed. Run \`/health\` against production if you need to know what it is actually running.`);
say();
say(`Beta is at \`${HEAD.slice(0, 8)}\`: **${commits.length} commits**, ${fileList.length} files` +
  (prs.length ? `, from ${prs.map((n) => `#${n}`).join(", ")}` : "") + ".");
say();

if (prod.notSucceeded.length) {
  const waiting = prod.notSucceeded.filter((d) => d.states.includes("waiting") && !d.states.includes("error"));
  const errored = prod.notSucceeded.filter((d) => d.states.includes("error"));
  say(`**${prod.notSucceeded.length} newer production deployment records did not succeed.**`);
  if (errored.length) {
    say(`- ${errored.length} with state \`error\`: ${errored.map((d) => `\`${d.sha}\``).join(", ")}. ` +
      "That usually means the run was cancelled at or before the approval gate, not that the build broke.");
  }
  if (waiting.length) {
    say(`- ${waiting.length} still \`waiting\`: ${waiting.map((d) => `\`${d.sha}\``).join(", ")}. ` +
      "Sitting at the approval gate with nothing wrong.");
  }
  say();
}

const queued = waitingForApproval();
if (queued.length) {
  say(`**${queued.length} release${queued.length > 1 ? "s" : ""} waiting for production approval:**`);
  for (const w of queued) {
    say(`- \`${w.sha.slice(0, 8)}\` — waiting ${Math.round((Date.now() - Date.parse(w.created)) / 3600000)}h — ${w.url}`);
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
say("- **Production: nothing.** `release.yml` fires three deploy hooks and the job ends. No wait,");
say("  no health check, no smoke test.");
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
  failures.push("could not read the source diff, so the payout warning below may be missing");
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
