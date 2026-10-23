# NaviG8r mobile app redesign: build handoff

From the Claude Design canvas "NaviG8r mobile app redesign" (17 Oct 2026), made from
`docs/design-mobile-app/CLAUDE-DESIGN-BRIEF-mobile-app.md` and the NaviG8r design system.
This folder is everything Claude Code needs to build it in `apps/driver_pilot`.

## How to use it

1. Put this folder at `docs/design-mobile-app/handoff/` in the repo (it may already be there).
2. Open Claude Code in the repo root.
3. Follow `PROMPTS.md`: paste Prompt A, then PR 0. Read the recon report. Then one session per PR,
   in order, reviewing each with Prompt R before you merge.

## What is here

| Path | What it is |
|---|---|
| `PROMPTS.md` | The prompts: context, PR 0 to PR 10, and a review prompt |
| `spec/decisions.md` | Guardrails, design decisions, open placeholders, facts to verify. Read first |
| `spec/screens.md` | Every screen: when it shows, its primary action, the data it needs; tabs by role; the shipment step mapping |
| `spec/components.md` | The shared widgets, their states, and the format helpers |
| `spec/copy.md` | Every string, by screen. Use verbatim |
| `spec/accessibility.md` | Contrast, targets, heading and focus order, what is announced after each action |
| `spec/design-tokens.json` | Design system tokens plus the proposed additions |
| `spec/navig8r_theme.dart` | Reference Flutter theme built from the tokens (not wired in) |
| `screens/*.png` | 66 renders of the mockups (phones at 2x, 360 x 800 dp) |
| `mockups/index.html` | Gallery; open in a browser. Each screen is a static HTML file using `nv.css` |
| `mockups/assets/` | Logo and icon mark from `apps/www/public/brand/` |

## Screen groups

- Start and sign in: `Main`, `c-signin`, `c-code`, `c-code-error`, `c-menu`
- Shipper: `sh-*` (find a lane, book, shipment steps, e-way bill, lists)
- Carrier office: `ca-*` (bookings, accept sheet, trips, publish, profile)
- Driver: `dr-*`
- Components: `cp-*`
- Shipper web at 1280 px: `wb-*`
- Specs as boards: `sp-*` (the same content as `spec/copy.md` and `spec/accessibility.md`)

## Before build

Settle or accept the open items in `spec/decisions.md`: the change-or-cancel contact, the e-way
bill hint line, the truck size guide, tax on top of the price, and the e-way bill portal field
names (Transporter ID is believed to be Part A, not Part B).

Names, phone numbers, GSTINs, bill numbers and amounts in the mockups are synthetic.
