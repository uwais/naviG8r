# Build brief: NaviG8r ops console redesign

> **For:** Claude Code · **Written:** 2026-09-27 · **Status:** Ready to build after the 30 Sep Phase 1 deadline
> **Design:** https://claude.ai/artifact/6k2NVVczVcKp7xtzCEVkfU (canvas "NaviG8r ops console")
> **Design system:** https://claude.ai/artifact/Y5Y3QwE9ZRBB4XuHLN2YXD (NaviG8r)
> **Product brief:** `docs/CLAUDE-DESIGN-BRIEF-ops-console.md`

Build the redesigned `/ops` page (also served at `/admin`) from the design canvas. Work on a branch,
behind a beta switch, so the team can compare it with the current page before it replaces anything.
Do not merge or remove the current page without the team's say-so.

## 0. Before writing code

1. Read the current `/ops` page's code and the API routes it calls. Write down (in the PR description) the
   stack, the file(s) that serve the page, and every endpoint used, with its request and response fields.
   Do not assume a framework; match what is there.
2. Read the design. Either open the canvas link above with your Artifact tool (read `project/canvas.json`,
   then each `project/*.dc.html`), or use the export the team hands you (Handoff to Claude Code, zip or HTML),
   stored at `docs/design-ops-console/`. The artboards:

   | Artboard | What it shows | Phase |
   |---|---|---|
   | `Current.dc.html` | Today's page and PR #134, with the problems to fix | Reference only |
   | `Main.dc.html` | The whole console, signed in with OPS and FINANCE | A |
   | `ShipmentRelease.dc.html` | Shipment detail with the payment release confirmation open | A (confirmation), B (detail page) |
   | `CarrierDetail.dc.html` | Carrier detail: approval history, shipments, members, contact log | B |
   | `States.dc.html` | Every component state, and the copy for each | A |

3. Read the design system's `project/README.md` and `project/tokens.json`. Where the design and the system
   disagree on looks, the system wins. Where either disagrees with the product brief on behaviour, the brief wins.
4. Check PR #134 (per-carrier reason boxes) and PR #133 (carrier banner). Build on #134 if it has merged;
   otherwise say how you handled the overlap.

## 1. Scope and phasing

**Phase A: ships with today's server.** Build this first, as one PR.
- Header strip, status key, jump links with counts
- Carriers waiting for approval (per-card reason, Approve, Reject, inline result)
- Review any carrier by ID (nothing preselected)
- Payments waiting for release, with the release confirmation (FINANCE only)
- Proofs of delivery to accept, **only if** an accept endpoint exists today (the brief says proof handling
  is "API only"). If it does not, leave the section out and say so.
- Team access, read only unless the viewer holds ADMIN; if a role-change endpoint exists, wire it for ADMIN
  with a person picker instead of a typed raw ID
- Every state on `States.dc.html` that applies to the above

**Phase B: needs server work. Do not build until the team agrees the server changes.** List the endpoints
and fields you would need in the PR description instead.
- Search across carriers, shippers and shipments (the header search box is hidden in Phase A, not shown dead)
- Carrier detail and shipment detail pages
- Contact log, owner and status per contact, preferred language
- Fail and refund; payout status

**Out of scope entirely:** matching or reassigning loads, disputes, metrics dashboards, WhatsApp messaging,
keyboard shortcuts, a phone layout, dark mode.

## 2. Tokens

Turn `tokens.json` into CSS custom properties with the same names and use them by name. No raw hex values
in components. The one value the system lacks:

| Name | Value | Use |
|---|---|---|
| `scrim` | `#0d1524` at 45% (`rgba(13,21,36,0.45)`) | Behind the release confirmation |

Add `scrim` as a local variable and flag it in the PR so it can be added to the design system. Do not add any
other new colour; if you think one is needed, stop and list it (name, value, contrast ratio on its ground).

Fonts: Poppins (600, 700) for headings, Manrope (400, 600, 700) for everything else, the system mono stack
for IDs. Use `font-variant-numeric: tabular-nums` on money, weights, counts, dates and times.
On one screen use only three sizes: 18px headings, 15px body, 13px captions/labels/IDs.

## 3. Layout (Main, 1280 px)

- Page background `page`; cards `card` with a 1px `line` border and `radius-card`. No shadows.
- 16px side gutter (`space-4`), 24px between sections (`space-6`), 16px card padding.
- A three-column grid:
  - Row 1: Carriers waiting for approval (2 columns) · Review any carrier by ID (1 column)
  - Row 2: Payments waiting for release (3 columns)
  - Row 3: Proofs of delivery to accept (2 columns) · Team access (1 column)
- Every section header: heading, item count, "Updated HH:MM IST", and a quiet Reload button.
- Must stay usable down to 1024 px wide (the right column may drop below); no phone layout needed.

## 4. Components and behaviour

Build these as reusable pieces in whatever the codebase uses. Every interactive element gets a 2px
`focus` outline with 2px offset.

**Status label.** A word on a tint plus a small shape icon, never colour alone:
`good`/`good-tint` + check (done); `attention`/`attention-tint` + clock (someone must act);
`problem`/`problem-tint` + alert (blocked or failed); `navy`/`info-tint` + arrow (in progress).
Map server codes to words in one place; never show a raw code (for example `PENDING_RELEASE`) as the main
text anywhere.

| Server state | Label | Kind |
|---|---|---|
| Carrier: bank details submitted | Bank details submitted | attention |
| Carrier: no bank details | No bank details yet | problem |
| Carrier: rejected | Not approved | problem |
| Carrier: approved | Approved | good |
| Shipment: no proof yet | Waiting for proof of delivery | info |
| Shipment: held | Payment held until the shipper accepts or {D Mon} | info |
| Shipment: ready | Ready for payment release | attention |

Confirm the real server codes in step 0 and complete this table in the PR.

**Buttons.** Primary (navy fill, white text), secondary (white, `control-border`, navy text), destructive
(white, `problem` border and text), quiet (no border). Hover per the system README. Disabled: `sunken`
fill, `slate` text, no border, and the reason in words next to it (`aria-describedby`). Loading keeps the
label as a verb in progress ("Approving…") with a spinner and `aria-busy="true"`; the button is not
clickable twice.

**Carrier review card** (one per carrier in the list):
- Name (link to detail in Phase B; plain text in Phase A) + ID in mono beside it, always; kind, join date,
  member count; status label on the right.
- "Reason code" field (mono), Approve right beside it, Reject at the far right of the row.
- Validation, client and server: `^[A-Z0-9_]{3,64}$`. Helper text: "3 to 64 capitals, numbers or
  underscores. Needed for both Approve and Reject."
- On a result, show a message **inside that card, under the buttons**, keeping the typed value:
  - Success (`role="status"`): "Approved by you at {HH:MM} IST with {CODE}. {Carrier} can now accept
    shipments. It leaves this list on the next reload." (Reject: "Not approved by you at …")
  - Invalid code (`role="alert"`, field gets a 2px `problem` border, `aria-invalid`): "Not approved yet.
    Reason code must be 3 to 64 capitals, numbers or underscores, for example DOCUMENTS_REVIEWED. What you
    typed is kept above."
  - Someone acted first (`role="alert"`): "Already approved by {person} at {HH:MM} IST. Your review was not
    recorded. The list has reloaded."
  - Server error (`role="alert"`): "Couldn't save the review: {plain reason}. Nothing changed. Try again;
    your reason code is kept."
- Own organization: the carrier still shows, both buttons disabled, with "You can't review your own
  organization. Ask another teammate with OPS."
- After any action the section reloads and its "Updated" time changes.

**Review any carrier by ID.** Carrier ID (mono), a Decision radio group (Approve / Reject) with **nothing
selected**, Reason code, Record review. Result and errors appear under the button, as above. Helper copy:
"For carriers not in the list, such as taking back an approval. The change and your reason are kept in the
carrier's history."

**Payments table.** Columns: Shipment (ID + route), Carrier (name + ID), Status, Proof of delivery (arrival
time; shipper accepted or not), Carrier receives (right-aligned ₹), Action.
- FINANCE and ready: "Release payment…" opens the confirmation.
- Not ready: disabled button plus the reason ("Hold ends 29 Sep, 16:53 IST", "Needs proof of delivery first").
- OPS without FINANCE: disabled plus "Only FINANCE can release payments. You hold OPS."
- If the list endpoint has no amount, drop the column in Phase A and list the missing field; the confirmation
  still needs the amounts (below).

**Release confirmation** (modal dialog, `ShipmentRelease.dc.html`):
- Title: "Release payment for shipment {ID}?"
- Body: "{Carrier} ({carrier ID}) receives ₹{amount} in the bank account on file. This can't be undone from
  the console."
- A breakdown: Shipper paid · NaviG8r commission (shown as a minus) · Carrier receives (bold). Show any other
  fee as its own line. If the server can't give all three amounts, do not ship the release button; say so.
- Two equal-width buttons: "Cancel" (secondary) and "Release ₹{amount}" (primary). Focus starts on Cancel;
  Esc and the scrim close it as Cancel; focus is trapped while open and returns to the row's button.
- After release: the row's message reads "Payment released by {you} at {HH:MM} IST" (`role="status"`) and the
  list reloads.

**Header.** Logo (`logo-horizontal-light-transparent` from the design system's Logos group, aspect ratio
locked, 32px high) · "Operations" · signed-in name and role chips · "Acting for {org}" with a Change control
(the current org select, restyled) · Sign out.
Below: jump links with counts ("Carriers waiting 2", "Payments waiting 3", "Proofs to accept 1", "Team
access") and the status key (Done · Someone must act · Blocked or failed · In progress).

**Section states** (copy from `States.dc.html`):
- Loading (`role="status"`): "Loading {what}…"
- Empty: "No carriers are waiting for approval." + "Carriers appear here after they sign up." (write the
  matching line for each section)
- Failed load (`role="alert"`): "Couldn't load {what}. Check your connection, then reload. Last loaded
  {HH:MM} IST." + Reload
- Long lists: 20 at a time, oldest first, "Show 20 more"
- No operator role: "You're signed in, but you don't have an operator role for {org}." + "Ask a teammate with
  ADMIN to add OPS or FINANCE, or change the organization you're acting for."

## 5. Words

- "Carrier" for carriers everywhere; "organization" only for "Acting for" and "your own organization".
- Dates "26 Sep 2026" (year optional inside the current year in tables), times "16:40 IST", 24-hour.
- Money "₹12,400", no decimals unless paise matter.
- Sentence case. No emoji anywhere, including icons.

## 6. Hard rules (check each before opening the PR)

- Light mode only; nothing reads `prefers-color-scheme`. Page never pure white; text never pure black.
- WCAG AA: text 4.5:1, large text, control borders and focus rings 3:1. Use `control-border` (not `line`)
  for anything that identifies a control.
- Everything reachable and operable by keyboard in a sensible order: header, search (Phase B), jump links,
  then sections top-left to bottom-right; inside a carrier card: reason field, Approve, Reject.
- Heading order: one h1 ("Operations"), an h2 per section.
- Real `<button>`, `<a href>`, `<label for>`, `<fieldset>`/`<legend>` for the radio group.
- Messages added by script: `role="status"`; errors `role="alert"`.
- No dark patterns: nothing preselected; Cancel as visible as Release; neutral decline wording; the full
  money picture before commit; no fake urgency; lists sorted oldest first, never by commission.

## 7. Done means

1. On the beta switch, a teammate approves or rejects a waiting carrier in under 2 minutes from sign-in.
2. Every action's result or error appears in the card acted on, next to its button.
3. No raw status code is main text anywhere (grep the rendered page for `_` in status cells).
4. axe (or the repo's existing a11y check) reports no contrast, label or role errors; tab through the page
   and confirm a visible focus ring on everything.
5. Tests for: reason-code validation; the status-word map; role gating (OPS, FINANCE, ADMIN, none); own-org
   disable; the "acted first" conflict; release confirmation amounts and Cancel.
6. Screenshots of the new page at 1280 px beside `Current.dc.html`, attached to the PR, on synthetic data.
7. The PR description lists: the stack and endpoints found in step 0, the completed status map, any field
   the server lacks, the `scrim` token, and every place you departed from the design and why.

## 8. Open questions (don't guess; leave a clear placeholder)

- What approval needs beyond bank details (PAN, GSTIN, documents). Shown as [TO CONFIRM] in the design.
- Whether "matching" belongs on this page. Not in this build.
