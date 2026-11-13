# Using Claude Design for NaviG8r

How I know each step: **checked** = I tested it this session. **docs** = Anthropic's help pages say so.
**unknown** = I have not checked it.

## What exists already

- The NaviG8r design system: https://claude.ai/artifact/Y5Y3QwE9ZRBB4XuHLN2YXD
- **Checked:** it shows up as a design system choice for new designs. It is not your default yet.

## One-time setup

1. Open the design system link. Look over the cover, the colours and the seven components. I have not seen
   the previews render yet, so this is the first real look. Tell me anything that is wrong. I fix it in the
   system, not design by design.
2. Make it your default: claude.ai, then Settings, then Design systems. (**docs:** design systems are managed
   there. I have not seen that screen.)
3. To let Uwais and Sundeep open it, use the Share menu on its page. (**checked:** only you can open it now.)

## Starting the ops console design

Use A. B and C are fallbacks.

**A. In claude.ai (recommended).**
1. Start a new Design from the Artifacts tab, or ask for one in a new chat. (**docs**)
2. Paste `docs/CLAUDE-DESIGN-BRIEF-ops-console.md` and attach the two screenshots from `docs/design-ops-console/`.
3. Say: "Design the NaviG8r ops console from this brief, using the NaviG8r design system."
4. If it asks which system to use, pick NaviG8r.

**B. The standalone claude.ai/design site.**
- **unknown:** whether that site can see this system. The docs describe moving systems from that site into
  claude.ai, not the other way.
- If it cannot, make one there: choose Create new design system, then upload the logos, README and tokens
  (download them from the system page), or link the GitHub repo.
- That makes a second copy that will drift from the first. Use B only if A fails.

**C. I start it from Claude Code** with the brief and the system attached, and you carry on in the browser.
(**checked:** the Design option and the NaviG8r system are both available to me here.)

## Later conversations

- Reopen the same design from the Artifacts tab instead of starting a new one. (**docs**)
- Keep one design per product area: ops console, driver app, shipper portal, website. Each gets its own
  brief in the repo at `docs/CLAUDE-DESIGN-BRIEF-<area>.md`.
- Ways to change a design (**docs**):
  - For broad changes, use the chat.
  - For one element, click it and leave a comment.
  - For spacing or colour nudges, edit directly.
- There is no version history yet (**docs**). Before a big change, say "Save what we have and try a
  different approach".
- Brand changes go into the design system first, then into the designs. A colour chosen inside one design
  and never added to the system is how the app and the site drifted apart.
- Design work counts against your normal Claude usage limits. (**docs**)

## Getting a design into the code

1. When the team agrees, use Handoff to Claude Code, or export a zip or a standalone HTML file. (**docs**)
2. Give me the export. I put it in `docs/design-ops-console/` in the repo, then check it against the brief's
   hard rules before building: light mode, contrast, and no dark patterns.
3. Build it on a branch behind a beta switch, so the team can compare it with the current page before users
   move over.

## Sources

- Set up your design system in Claude Design: https://support.claude.com/en/articles/14604397-set-up-your-design-system-in-claude-design
- Get started with Claude Design: https://support.claude.com/en/articles/14604416-get-started-with-claude-design
- Claude Design now stays on brand for daily work (17 Jun 2026): https://claude.com/blog/claude-design-stays-on-brand-for-daily-work
