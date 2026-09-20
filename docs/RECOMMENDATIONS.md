# Recommendations

Things that work as designed, where the design should change. Defects belong in
[`BUGS.md`](BUGS.md); the evidence and sources for everything below are in
[`RESEARCH-DRIVER-APPS.md`](RESEARCH-DRIVER-APPS.md), and the UX detail in
[`UX-REVIEW.md`](UX-REVIEW.md).

Ranked by what it is worth to a driver, not by build cost. **Nothing here is scheduled** — this
is the intake queue for `ROADMAP.md`, and the Monday standup is where items graduate.

---

## Check this before the next design cycle

The app is built for two personas weighted equally. One measured source disagrees: a SaveLIFE
Foundation study of 1,217 drivers across 10 cities found **93% of Indian truck drivers are
employees and about 6% drive a self-owned truck**. It is six years old, surveyed drivers at
transport hubs rather than app users, and predates the current smartphone wave — so it is not a
reason to drop the owner-operator, who is the person deciding whether the truck uses naviG8r at
all. But a 50/50 split of design effort is currently an assumption, not a finding.

**This is answerable from our own database, not from research.** Query the sign-up mix.

---

## The five worth doing, in order

- [ ] **1. A trip record that cannot silently die.** Replace "GPS shared while one screen is
  open" with a foreground service plus disk-persisted queues for accept, start, breadcrumb and
  confirm delivery, replayed when signal returns, and a server-side gap detector. Three
  independent lines of evidence converge here: the Xiaomi, Oppo, Vivo and Realme power managers
  kill background work regardless of the standard battery-optimisation API; NHAI told TRAI in
  January 2026 that ~1,750 km of national highway has inadequate mobile coverage; and Uber's
  Optimistic Mode is the published worked answer. **Largest build of the five, and far cheaper
  before there are live trips to migrate.**
- [ ] **2. Put the economics on the offer card.** Not just the freight number — the distance to
  the loading point, net per kilometre after diesel and tolls, and days committed. Tolls alone
  run ₹16,000-18,000 a month for a typical operator, so a gross figure makes the driver do that
  arithmetic on a phone at a dhaba. Pair it with a **one-way ratchet**: publish that the quoted
  rate can rise if the load changes and can never fall below what was shown at acceptance.
- [ ] **3. Detention and waiting priced automatically, not disputed afterwards.** Compute wait
  time from our own GPS, pay on that evidence, and chase the customer separately. Publish a
  versioned rate card for every non-freight charge. When a claim is refused, render the specific
  rule it failed. This is the single most common way Indian road freight loses a driver money.
- [ ] **4. Proof of delivery that is actually proof.** Today the POD screen sends optional free
  text and nothing else — no camera, no picker, no signature anywhere in the app. Gate completion
  on a photo plus a short consignee code issued at dispatch, queued offline. A code beats a
  signature because it validates with no signal.
- [ ] **5. Settlement on one screen.** What the shipper paid, our commission, detention and
  tolls, and what reaches the driver — together, with the commission visible. Undisclosed take
  rates get reconstructed by outsiders and published less favourably than the truth.

## Smaller, and cheap

- [ ] **Language picker before login,** independent of device language, on the first screen.
- [ ] **Sort loads by what pays** — deadhead, rate per km, total, weight — not by recency.
- [ ] **A hold button on an offer,** so it can be read safely rather than under a countdown. For
  someone in a moving truck this is a safety feature.
- [ ] **"Why did I see this load?"** — one sentence. We match on declared lanes, so it is nearly
  free to explain.
- [ ] **An e-way bill validity countdown.** One day per 200 km; a real legal deadline with a
  check-post consequence, and no consumer app surfaces it.
- [ ] **Confirm the four irreversible actions.** There is not one `showDialog` in the driver flow.
- [ ] **Date pickers instead of typed ISO timestamps**, dropdowns instead of free-text vehicle
  class, and real keyboard types and autofill hints.
- [ ] **One word for the central object.** It is currently anchor trip, trip, load and lane.
- [ ] **A type and spacing scale in the theme,** so screens stop improvising.

## Asked for by pilot users

From #navig8r-pilot, 2026-09-14. Verbatim requests, not my interpretation.

- [ ] **GPS tracking integration with a device on the truck** (they named Wheels Eye). This is
  the same conclusion the research reached independently as recommendation 1 — the phone alone is
  not a reliable position source on these handsets or these highways. Two separate lines of
  evidence pointing at one change is the strongest signal on this page.
- [ ] **Drivers in an org visible to the carrier admin.** There is a fleet screen today but no
  roster view.
- [ ] **"Match my Route"** — search loads against a route the driver already runs, rather than
  browsing everything.

Also raised 2026-09-17: changes are *"stuck in beta"* and pilot requests should be vetted into
beta too. That is a release-process question, not a product one, and belongs on the standup.

## Never build these

Drawn from what the incumbents are being criticised or sued over:

- Gating load information behind an acceptance rate. What a driver needs to judge a load is not
  a reward.
- Counting a timeout as a refusal. A driver may be loading, eating, or out of coverage.
- Letting a driver's past willingness to accept low rates feed the rate offered to them.
- Charging a fee to reach money already earned.
- Suspending an account without notice, evidence or a right of reply. Ola, Uber and Porter all
  scored zero on this in Fairwork India 2024.
- Icon-only navigation adopted as a literacy fix. Abstract glyphs are opaque to exactly the users
  the simplification was meant to help.
- Auto-penalising on an LLM sentiment score over code-mixed text, where measured benchmark
  performance is near chance on a two-way task.

---

## The feedback feature — the minimum worth building

Requested 2026-09-20. **Blocked on `BUGS.md` Critical:** production currently loses its store on
every redeploy, so feedback written today is deleted on the next deploy.

The shape the research supports:

- One required tap on a **category chip**, then optional free text or a voice note. Typing is the
  last resort, not the entry fee.
- **Auto-attach what the app already knows** — screen, app version, device, load id, role, org,
  locale, last API error. Asking the user for any of it is effort spent on data we already have.
- **Screenshot pre-captured, shown, removable.** Never send one the user did not see.
- **Store raw first.** The driver's own words in their own script are the record; detected
  language, transliteration and any model label are derived columns written beside it.
- **Triage as an offline job with a held-out eval set,** not an inline LLM call, and with a
  recoverable bucket — a model must never be able to delete feedback.
- **A reference number and a visible status.** Every incumbent in this market is accused of never
  closing the loop, so closing it visibly is cheap differentiation.

Not shake-to-invoke: the phone is mounted in a truck. A persistent entry point instead.

## Hindi — roadmap, not a build item

Explicitly not a must-have. What it would take and what it would buy:

- **Cheap first step that commits to nothing:** store a detected script and the raw text on every
  feedback row now, and add a language picker before login. That makes a later localisation
  possible and tells us whether anyone would use it, without translating a single string.
- **The real cost is maintenance, not translation.** Flutter's fallback is silent, so a stale
  locale degrades into a half-Hindi screen with no error. The defence is free: fail the build on
  a non-empty untranslated-messages list.
- **Do not bundle a Devanagari font on Android** — the system fallback carries it. The web build
  is where it actually breaks.
- **Leave numerals in Latin digits.** Rupee amounts and weights are the part a low-literacy
  driver reads most reliably; "completing" the localisation removes it.
- **For acting on feedback: transliterate, do not translate, before classifying** — and keep the
  driver's original text visible to whoever acts on it. An English-only ops view makes any
  mistranslation invisible and permanent.
