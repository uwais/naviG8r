# Monday standup — 19:30 IST, 30 minutes

One page. The detail lives in [`BUGS.md`](BUGS.md), [`RECOMMENDATIONS.md`](RECOMMENDATIONS.md)
and [`ROADMAP.md`](../ROADMAP.md); this is the agenda, not the record.

The meeting exists to surface **blockers and decisions**. Status that could have been read is not
worth thirty minutes of everyone's Monday evening — which is why the numbers below are generated
before the call, not recited during it.

---

## Run sheet

| | Item | Who | Min |
|---|---|---|---|
| 1 | **The numbers.** Read from the prep block, not discussed unless one moved the wrong way | chair | 2 |
| 2 | **Production health.** Anything users hit this week. Incidents, not deploys | chair | 5 |
| 3 | **Shipped since last Monday.** Merged only. A PR that is open did not ship | each | 5 |
| 4 | **Blocked.** One line each: what is stuck, on whom, since when | each | 5 |
| 5 | **Roadmap.** Progress against the current `ROADMAP.md` section, and whether the dates still hold | chair | 7 |
| 6 | **New recommendations.** Anything from research or review that should enter the roadmap | proposer | 4 |
| 7 | **Decisions and owners.** Every open decision gets a name and a date, or it is dropped | chair | 2 |

Rule for item 3: if it is not merged, it belongs in item 4.

---

## Prep — run this before the call, paste the output into item 1

```bash
cd "$(git rev-parse --show-toplevel)"
echo "Open PRs:            $(gh pr list --state open --limit 200 --json number -q 'length')"
echo "  reviewed:          $(gh pr list --state open --limit 200 --json reviewDecision -q '[.[]|select(.reviewDecision!=null and .reviewDecision!="")]|length')"
echo "  oldest:            $(gh pr list --state open --limit 200 --json number,createdAt -q 'sort_by(.createdAt)|.[0]|"#\(.number) \(.createdAt[0:10])"')"
echo "Merged last 7 days:  $(gh pr list --state merged --search "merged:>=$(date -v-7d +%F 2>/dev/null || date -d '7 days ago' +%F)" --json number -q 'length')"
echo "Open bugs (docs):    $(grep -c '^- \[ \]' docs/BUGS.md)"
echo "  critical:          $(awk '/^## Critical/,/^## High/' docs/BUGS.md | grep -c '^- \[ \]')"
echo "Prod health:         $(curl -s https://navig8r-customer.onrender.com/api/health)"
```

The last line matters most. `"persistence":"file"` means production is still on the JSON store
and **is losing data on every redeploy** — see the Critical section of `BUGS.md`. It should read
`"persistence":"db"`.

---

## Standing items until they are closed

These stay on the agenda every week until they are gone. Remove a line only when it is merged.

- [ ] **PR #82** — an invited fleet driver can redirect the carrier's weekly payout. Fix written,
  unreviewed since 8 Aug.
- [ ] **PR #102 plus a boot guard** — production loses its store on every redeploy, silently.
- [ ] **PR #100** — `OTP_DEBUG` honoured in production is a full auth bypass.
- [ ] **PR #2** — sensitive API routes without auth. Open since 1 May. 142 days.
- [ ] **Close the two duplicate clusters.** #12-#36 (23 PRs) and #52-#80 (29 PRs) are a bot
  re-attempting the same two fixes daily. They hide the ~19 real ones. Close each down to its
  newest member, and stop the bot re-opening them.
- [ ] **No CI runs the Flutter app.** A green tick currently says nothing about the phone app.

---

## This week

> Replace this block each Monday. Move the previous week's copy to `STANDUP-ARCHIVE.md`;
> do not let this file grow.

**Week of 2026-10-12**

- Numbers (generated 12 Oct): 80 open PRs, 9 with a review decision, oldest #2 (1 May); 5 merged in
  the last 7 days; 30 open bugs in `BUGS.md`, 6 critical. Production health: not run.
- Incidents: _none recorded here_
- Shipped, merged only: #142 shipment notifications and conversation timeline (Sundeep); #143 to #146
  bank-details wording and checks, rejection reasons, and a message for text typed after Save.
  Deployed (US Eastern dates): #143 to #145 on 11 Oct, #142 and #146 on 12 Oct once Uwais approved
  the production step. Runs checked, not the live service.
- Blocked, approved by the Cursor bot only: #139 payouts and #140 paid booking merge cleanly and have
  been idle since 3 Oct. #120 merges cleanly; since 26 Sep it has asked Uwais: merge as it is, or
  restore #107's landing? #141 sign-in limit (Rishabh's) conflicts with main in `docs/pilot-api.md`
  since #142 and needs a rebase.
- Decisions needed:
  1. Merges: who merges each PR above, and by when?
  2. "Live and stable": what it means, who judges it, by when. The split of `driver_flow.dart`
     (2,827 lines) waits on it.
  3. #146 on a device: who tries it with a slowed network, and when? It has not yet been tried.
  4. Bank-details save: does one waiting server change go ahead? Rishabh to explain.
  5. Rejected carriers: which contact channel in the app, who answers, what hours?
  6. Carrier approval: which documents it needs, and may carriers upload files; both checks (documents
     and bank details) or one; the bank-name rule (does an account in the owner's own name match the
     carrier?); a message when a carrier is approved.
  7. Uwais: does the live API keep its data across deploys? (standing item above, PR #102)
