# Design brief: NaviG8r ops console

> **Status:** Draft for team review · **Written:** 2026-09-27 · **For:** claude.ai/design
> **Build window:** after the 30 Sep Phase 1 deadline, on a branch, shown to the team before it replaces anything

Paste this whole file into claude.ai/design, attach the screenshots listed in section 4, and iterate there.
The output wanted is in section 9.

## 1. Surface

The internal operations web console at `/ops` (and `/admin`, the same page). One page today, served by the
API server, used in a laptop browser. It is where the team approves carriers, watches payments waiting for
release, accepts proof of delivery and manages who can do what.

This brief covers that page only. The driver and carrier Android app is a separate brief, later.

## 2. Who uses it, and for what

**Users:** the three people building NaviG8r, acting as operators during the pilot. They know the product
well, use the console a few times a week from a laptop or desktop (not phones, for now), and switch between being engineers and operators. The developers hold the OPS and FINANCE roles. No
dedicated ops staff yet.

**Jobs, ranked by how often they came up in the last four weeks** (from the repo, team chat and
comparable freight marketplaces' public job descriptions):

| # | Job | Supported today | Where it happens when the console falls short |
|---|---|---|---|
| 1 | Find one carrier, shipper or shipment and see everything about it: members, approval status, shipments, payment state, last error | No | Team chat, pasted raw records |
| 2 | Approve or reject a carrier waiting for approval, with a reason | Yes, since 26 Sep | Before that, chat and help from teammates |
| 3 | Take a delivered trip to money: check proof of delivery, release payment, fail and refund a trip, see payout status | Partly: release is on the page, the rest is API only | Command line, not at all yet |
| 4 | Manage team access: give or remove a role | Partly: roles only, by typing raw IDs | Command line |

Out of scope for this design: matching or reassigning loads (not yet defined), disputes, pilot metrics
dashboards, WhatsApp messaging.

**Roles decide what each person sees** (a person can hold more than one):

| Role | Can |
|---|---|
| OPS | Approve or reject carriers; see shipments; payments are read only |
| FINANCE | Release payments; see payouts and ledgers |
| ADMIN | Manage roles and team access |

Nobody can approve their own organization.

## 3. Success criteria

- A teammate approves or rejects a waiting carrier in under 2 minutes from sign-in, without looking anything
  up outside the console. (The first real approval, on 24 Sep, took over half an hour and help from others.)
- Every action's result or error appears inside the card that was acted on, next to its button.
- No raw system code (such as `PENDING_RELEASE`) is the main status text anywhere.
- Every text and control meets WCAG AA contrast, has a visible focus state and is reachable by keyboard.
- Shown the page for 10 seconds, a teammate can say what each section is for.

## 4. Current state

Attach two screenshots when pasting, both on synthetic test data:
- The ops page as it is on main today, signed in as an ops user.
- The same page with the per-carrier reason boxes from open PR #134.

What is wrong today, in the team's words and from review:
- It looks like a plain 1990s page: default browser buttons, stacked sections, no visual separation between
  "Carrier compliance review" and "Review by organization ID".
- "Carrier" and "organization" are used for the same thing. (A carrier is one kind of organization; so is a
  shipper, and NaviG8r itself.)
- Raw status words on shipments (`PENDING_RELEASE`) and raw IDs everywhere.
- Errors appear at the top of the page, far from the button that was clicked.
- Payment lines, proof of delivery and roles each need an ID typed by hand; there is no search.
- The page background is pure white and the text a cool navy, against the team's colour rules below.

## 5. Brand

- **Design system:** build on the NaviG8r design system (https://claude.ai/artifact/Y5Y3QwE9ZRBB4XuHLN2YXD).
  It holds the colours, type, spacing, corner sizes, status labels, logos and base components. Where this brief
  and the system disagree on how something looks, the system wins; this brief decides what the page must do.
- **Colours, in short:** navy `#16233D` for primary actions, selected states and focus; gold `#E8A33D` only on
  navy, never as text on a light ground; page `#F8F7F2`; white only for cards; text `#2B2620`; status shown
  as a word on a tinted label (good, attention, problem, in progress).
- **Voice:** plain, short, specific. Say what happened and what to do next. Use the product's own words
  (carrier, shipper, shipment, proof of delivery, payment release), not system codes.
- **Type:** Poppins for headings, Manrope for everything else, a monospace face for IDs; at most three sizes
  and three contrast levels on one screen; tabular figures for money, weights and dates.
- **Density:** dense and scannable. These are expert, repeat users; prefer tables and compact cards over
  spacious layouts.

## 6. Hard constraints (not negotiable)

- **Light mode is the default.** Warm off-white page background (`#f8f7f2` or `#fafaf6`), never pure white;
  white only for raised cards. Warm near-black text (`#1a1a1a` or `#2b2620`), never pure black. Dark mode
  only as an explicit setting, never switched on automatically from the system setting.
- **No emoji anywhere.**
- **WCAG AA:** 4.5:1 for text, 3:1 for large text, control borders and focus rings. Colour is never the only
  signal: every status has words.
- **Status messages** added by script are announced to screen readers (`role="status"`, errors
  `role="alert"`).
- **No dark patterns:** no manufactured urgency or scarcity; no hidden costs (any fee shows beside the amount);
  no pre-checked options; declining or cancelling is as easy to find as accepting; neutral decline wording, no
  confirmshaming; what a button says is what it does; nothing ranked or suggested for reasons other than the
  user's benefit; no asking for data the task does not need.
- **Honest copy:** loading says what is loading; errors say what went wrong and what to do; empty states say
  what will appear and when.

## 7. What this surface is not

- Not a customer-facing page: no marketing, no onboarding tours, no upsell.
- Not a dashboard of charts: counts and lists, no vanity metrics.
- Not a place to approve money in one click: releasing a payment always shows the shipment, the amount and a
  confirmation naming both.
- Not a redesign of permissions: it shows what each role can already do, and explains (in words) why a
  control is read only.

## 8. What the page gets from the server

Field lists, not code. Everything below exists today unless marked **new**.

**Signed-in person**
- Name, phone; the organizations they belong to (name, kind); for the chosen organization: roles and
  permissions, and whether it is NaviG8r's own (internal) organization.

**Carriers not yet approved** (one row each)
- Carrier ID, carrier name, kind (owner-operator, fleet, older account), approval status, date joined.
- Approval status words: "Bank details submitted", "No bank details yet", "Rejected".
- Actions: Approve or Reject, each needing a reason code (capitals, numbers and underscores, for example
  `DOCUMENTS_REVIEWED`). The server returns the carrier's new status.
- Review of any carrier by ID stays possible (for carriers not in the list, such as taking back an approval).
  Nothing is preselected there: the person picks Approve or Reject explicitly.
- A carrier the signed-in person belongs to still shows, but its review buttons are disabled with the reason:
  "You can't review your own organization."
- A decision can be changed later from the carrier's detail view, with a new reason; the history keeps both.

**Shipments waiting for payment release** (one row each)
- Shipment ID, status, when proof of delivery arrived, whether the shipper accepted it, when the 48-hour hold
  ends, whether payment is ready.
- Status words: "Waiting for proof of delivery", "Payment held until the shipper accepts or <date>",
  "Ready for payment release".
- Release payment: FINANCE only, and only when ready. OPS sees the row read only, with the reason.
- The release confirmation shows the whole money picture before anyone commits: what the shipper paid,
  NaviG8r's commission and what the carrier receives, with Cancel as visible as Release.

**New, needed for job 1 (lookup) and job 3 (money):** search across carriers, shippers and shipments; one
detail view per organization (members, approval history, shipments) and per shipment (timeline, proof of
delivery, payment and payout state); fail-and-refund and payout status on screen. Design these now; they
need server work before they can ship.

**Edge cases to design for:** a list with one item and with 50; a carrier with no bank details; two carriers
with the same name (always show the ID beside the name); a person with several organizations; an action that
fails because someone else acted first ("Already approved by <person> at <time>"); a slow or failed load; a
person with no operator role at all. Each section shows when it was last refreshed and reloads after any
action, so no one acts on a stale list.

## 9. Output wanted from claude.ai/design

- **Layouts:** desktop at 1280 px, the only layout needed now: the team works from laptops and desktops

- **Structure to start from** (research-backed, change it if the design says otherwise):

```
+--------------------------------------------------------------------------+
| NaviG8r operations          Signed in as <name> · acting for <org> [Change] |
| [ Search carriers, shippers, shipments ...                             ] |
| Carriers waiting (2) · Payments waiting (3) · Proofs to accept (1)        |
+--------------------------------------------------------------------------+
| Carriers waiting for approval                                            |
|  +--------------------------------------------------------------------+  |
|  | Carrier name (ID)   Bank details submitted · joined 26 Sep         |  |
|  | Reason [____________]            [Approve]          [Reject]       |  |
|  | Result or error for this carrier appears here                     |  |
|  +--------------------------------------------------------------------+  |
+--------------------------------------------------------------------------+
| Review any carrier by ID  (its own card, its own reason box)            |
+--------------------------------------------------------------------------+
| Payments waiting for release  (table: shipment, status words, action)   |
+--------------------------------------------------------------------------+
| Proofs of delivery to accept                                             |
+--------------------------------------------------------------------------+
| Team access (roles)                                                      |
+--------------------------------------------------------------------------+
```

- **Components**, each with every state (default, hover, focus, disabled, loading, success, error, empty):
  header strip with acting organization; search; section card; carrier review card; payment row with release;
  proof-of-delivery row; role editor; status label; confirmation for payment release.
- **Tokens:** use the design system's tokens by name. List any token the design needs that the system lacks
  (name, value, contrast ratio on its background) instead of writing new values inline.
- **Copy:** every label, button, status, error and empty-state line.
- **Accessibility notes:** heading order, focus order, what screen readers announce after each action.

## 10. Principles behind the structure

Evidence labels: **study** (peer-reviewed; sample noted), **practitioner** (in-house research, little data),
**design system** (self-description, not evidence), **standard** (a requirement). No study covers
approval or payout screens directly.

1. **One bordered card per job.** A shared boundary groups what is inside it. Study (Palmer 1992; replication
   unchecked); practitioner warns against decorative boxes.
2. **Results and errors inside the card, under the button pressed, keeping what was typed.** The best-supported
   point here. Study (Seckler 2012, n=303; 2014, n=65, 42% to 78% error-free first tries with a bundle of
   guidelines).
3. **Controls sit with the thing they act on.** Practitioner.
4. **Plain-word statuses, never colour alone.** Practitioner, design systems, WCAG. Colour-vision deficiency
   was 8.7% of 1,352 men in one Indian sample (single study).
5. **Confirm only what matters, naming the object and outcome** ("Release payment for shipment NG-1042:
   carrier receives Rs 12,400"). Practitioner; warnings people see repeatedly stop being read (one lab's studies).
6. **Keep Reject apart from Approve, styled differently.** Practitioner; no study sets the distance.
7. **Require a reason for a rejection; show who decided what, and when.** Observational study (32 million posts,
   unreplicated); Stripe does this (vendor docs); a moderator survey (n=110) found most leave the queue for
   context and many had two people act on one item.
8. **Keep the acting organization visible under the header, with a Change link.** Design system.
9. **One page of cards rather than tabs, for a handful of jobs seen together.** Practitioner; not settled by
   any study.
10. **No keyboard shortcuts yet.** Study (n=251): even experienced users rarely use them.
11. **Legend** Use legend where applicable to make clear to user what is what

Not settled by evidence: tabs versus one page, density for experts, undo versus confirmation, label placement.

Sources: Palmer 1992 (pubmed.ncbi.nlm.nih.gov/1516361); Seckler 2012 and 2014 (sciencedirect S0953543812000173;
dl.acm.org 10.1145/2556288.2557265); nngroup.com articles on common region, error messages, closeness of actions,
confirmation dialogs, proximity of consequential options, tabs, visual hierarchy, accelerators;
design-system.service.gov.uk (summary list, tag); design-patterns.service.justice.gov.uk (timeline,
organisation switcher); WCAG 2.2 understanding documents (use of colour, non-text contrast, status messages,
error prevention); docs.stripe.com (account reject, reviewing actionable accounts); Jhaver 2019 CSCW
(10.1145/3359252); CHI 2026 moderator survey (arxiv 2509.07314); Lane 2005 (10.1207/s15327590ijhc1802_1);
Indian colour-vision sample (pmc PMC3595632).

## 11. Questions for the team before the build

1. Who holds OPS and FINANCE in production, and has anyone released a payment or refunded by hand yet? A. The developers for now
2. Do you do ops work from a phone? A. Only laptop/desktop for now
3. Should "matching" (assigning a load to a carrier) be part of this page, and what does it mean for the pilot? A. Not sure, need others to weigh in
4. What does approval need beyond bank details: PAN, GSTIN, documents? A. Not sure, need others to weigh in
5. When a driver or shipper is stuck, how do they reach you, and what did you need to see to help? A. Not sure, research best practices and apply. Answered from research in section 13.

## 12. Dark pattern screen

```
DARK PATTERN SCREEN — ops console redesign brief — 2026-09-27
Screened: this brief, sections 1 to 11 (internal console; no customer-facing flow)
Verdict: PASS WITH CHANGES
Findings:
  1. Actionability — FAIL — a teammate's own carrier would show review buttons the server refuses —
     show the carrier with the buttons disabled and the reason (section 8).
  3. Full cost on the same screen — FAIL — the release confirmation named one amount — show what the
     shipper paid, the commission and what the carrier receives before commit (section 8).
  5. Defaults — FAIL — the review-by-ID form preselected APPROVED — nothing preselected (section 8).
  6. Exit — FAIL — no stated way to reverse a mistaken review; Cancel prominence unstated — decisions
     can be changed from the detail view with a reason; Cancel as visible as Release (section 8).
  8. Promise matches delivery — FAIL — lists could go stale while a teammate acts — each section shows
     its refresh time and reloads after any action; a late action says who acted first (section 8).
  Passed: 2 honest comparison (nothing compared; counts match lists), 4 urgency (only the real 48-hour
  hold is shown), 7 decline copy (Cancel, Reject: neutral), 9 data (only the reason code, which the audit
  record needs), 10 money (no revenue-driven order; never sort by commission), 11 reversal test.
Re-screened 2026-09-27 after section 13 was added: PASS. 9 data: the contact log keeps only what helping needs,
  notes exclude bank details, documents and codes, preferred language is optional. 4 urgency: no response time
  is promised unless the team keeps it. 1 actionability: publish only hours the team can cover.
Re-screened 2026-09-27 after section 5 moved to the design system: PASS. Only colours, type and tokens
  changed; no flow, default, cost, copy or data request changed.
Re-screened 2026-09-30 after the team's review (reason codes picked from a list per action; release
  wording moved to "ledger balance"): PASS WITH ONE OPEN ITEM. 5 defaults: no reason is preselected.
  7 decline copy: Cancel stays neutral. 8 promise matches delivery: release credits the ledger now, and the
  copy names the first Wednesday 18:00 IST batch on or after the 7th day after delivery, or minutes after a late release, as the
  payout code does when real payouts are on (alpha and beta only book them). 9 data: nothing new is asked.
  Open, from finding 8 of the first screen: the "someone acted first" message is not built, because the
  server overwrites a review without detecting a conflict. Needs server work, or Rishabh accepting it for
  the beta; not accepted here.
Accepted risks: none
```

## 13. Helping someone who is stuck (answer to question 5)

From research on 27 Sep. Sources were opened by research agents and not re-checked by hand. No source studied
Indian truck drivers or freight shippers directly.

**How they reach us during the pilot, in order**

1. One phone number the team answers, which also takes WhatsApp voice notes. Voice beat text for
   low-literacy users in Indian studies (study, Medhi 2011, about 90 people; qualitative, Gupta 2022, 30
   people). This is a phone, not a console feature.
2. Email or a typed form, mainly for shippers.
3. Later, in the Android app: a "call me back" button on every blocked screen that sends the person's role,
   account and shipment automatically (a separate brief).

Publish only hours the team can cover. Point emergencies to 112, not to support.

**What the console shows so nobody repeats themselves**

Add to the organization and shipment detail views in section 8 (**new** means server work):

- Who: name, phone, role, organization and ID, preferred language (**new**).
- What blocks them: approval status and reason, current shipment, payment held until when, last app error.
- Contact log (**new**): channel, reason, status at the time, notes, any promise made and its time. Notes are about the issue only: no bank details, documents or codes pasted into them. Preferred language is optional.
- One owner and a status per contact (**new**): open, waiting on us, waiting on them, done, with "waiting since".
- Actions: copy phone, log a contact, add a note, take ownership, change status. Approve, reject and release
  keep their role rules.
- Shipment view: route, status in words, proof of delivery, payment and payout state, hold end, carrier and
  driver, related contacts.

Why: 56% of customers had to re-explain their issue and 62% contacted more than once (practitioner, CEB,
75,000+ customers). One owner stops two teammates answering the same person, or nobody (inference).

**Leave out at pilot scale:** canned replies, response timers, routing, dashboards, a help centre, a status
page, a chatbot, a phone menu. Self-service fully resolved only 14% of issues (practitioner, Gartner).

**Prevent contacts instead:** every blocked screen in the app says the status, why, the one next action and
who acts next (the carrier banner in PR #133 does this), and every change of approval or payment status is
sent as a notification. Proactive guidance cut new customers' questions by about 20% in the first week, then
faded (study, Retana 2016, 2,673 customers).

**Not settled:** how Indian drivers and fleet owners prefer to reach support; the response times they
expect; whether one combined screen resolves cases faster than separate tools.

Sources: Medhi 2011 (microsoft.com research ToCHI2711_Medhi.pdf); Gupta 2022 (microsoft.com research
compass22-34-taps.pdf); CEB "Stop trying to delight" (beyondphilosophy.com); Gartner via destinationcrm.com;
Retana 2016 (econpapers, M&SOM 18:1); Uber Freight and Uber driver help pages; Swiggy delivery-partner
emergency support release.
