# E-way bill link-out demo: contract

Status: demo build, 14 Oct 2026. Built from `docs/CLAUDE-DESIGN-BRIEF-ewaybill.md` (the 3 Oct brief, on the
unpushed branch `docs/standup-2026-10-05`). The claude.ai/design step in section 9 of that brief was not done;
this is built straight from the brief's rules.

The app never makes, changes or imitates an e-way bill. The shipper makes it on the government portal and types
its details here. Ops looks it up on the portal by hand. The carrier reads it.

## In this demo

| Who | Does what |
|---|---|
| Shipper | Adds the bill's four details, or says none is needed with a reason. Edits, removes. Opens the government portal from the shipment. Sees the ops check. |
| Carrier and driver | Read the bill number and the ops check, also before accepting. Cannot change anything. |
| Ops (`/ops/beta`) | Two lists: bills to check, and shipments with no bill. Opens the portal, copies each detail, marks "found" or "problem". |

## Not in this demo, and why

| Left out | Why |
|---|---|
| Blocking trip start | Depends on the team's questions 1 to 3 and 5. |
| Truck number, valid-until, time left | The truck per trip does not exist yet (question 1); without it there is nothing to compare. |
| PDF upload | Own route, size cap, and a retention answer (question 8). |
| Naming a truck, "Start without this shipment" | Questions 1 and 2. |
| Reading offline | The app keeps nothing on the phone, and a failed refresh replaces every screen. Not cheap. |
| Pickup time on the ops "Missing" list | Needs a trip lookup; rows show the booking time instead. |
| Carrier trip screen | Detail screen only, to keep the driver file edit to two lines. |

## Data

One optional record on the shipment, `ewayBill`. A shipment without it is exactly as before.

| Field | Meaning |
|---|---|
| `kind` | `BILL` (details entered) or `NOT_NEEDED` (shipper's statement) |
| `billNumber` | 12 digits |
| `billDate` | `YYYY-MM-DD`, not later than today in India |
| `makerGstin` | 15 characters, GSTIN of whoever made the bill |
| `invoiceNumber` | 1 to 32 characters |
| `notNeededReason` | `BELOW_THRESHOLD`, `GOODS_EXEMPT` or `OTHER` |
| `notNeededNote` | the shipper's words, 3 to 140 characters, only with `OTHER` |
| `enteredAtUtcMs`, `enteredByUserId` | who and when; the user id is never sent to the app |
| `check` | `{ result: FOUND or PROBLEM, problemReason?, checkedAtUtcMs, checkedByUserId }`; cleared by any edit |

Format checks catch typos only. A passing number is not proof the bill exists.
Problem reasons: `NOT_FOUND`, `CANCELLED`, `DETAILS_DO_NOT_MATCH`, `OTHER`.

## What each role gets back

The record is cut by role before it leaves the server (nested objects are not filtered by the general
serializer, so `ewayBill` is built per role in `ewayBill.ts`).

| Role | Gets |
|---|---|
| Shipper (own shipment), Ops | everything above except the two user ids |
| Carrier owner, dispatcher, driver | `kind`, `billNumber`, `notNeededReason`, `notNeededNote`, `check` result, reason and time. Never the bill date, the maker's GSTIN or the invoice number |
| Finance, Admin | nothing |
| ERP integration responses | nothing (stripped) |
| Open trips, marketplace | nothing |

## Routes

| Route | Who | Does |
|---|---|---|
| `POST /shipments/:id/eway-bill` | Shipper, permission `eway_bill.write` | Body `{ kind: "BILL", billNumber, billDate, makerGstin, invoiceNumber }` or `{ kind: "NOT_NEEDED", reason, note? }`. Replaces the record and clears the check. 200 `{ shipment }` |
| `POST /shipments/:id/eway-bill/remove` | Shipper | Back to "nothing added". 200 `{ shipment }` |
| `GET /ops/eway-bills` | Ops, permission `eway_bill.check` | `{ toCheck, missing, notNeeded }`, each a list of shipments, oldest first |
| `POST /ops/eway-bills/:shipmentId/check` | Ops | Body `{ result: "FOUND" }` or `{ result: "PROBLEM", problemReason }`. Only on a `BILL` |

Errors: `{ error, detail, field? }` with a plain sentence in `detail`. Another shipper's shipment answers 404.
A shipment already delivered, accepted or refunded answers 409 `eway_bill_locked`. Editing or removing is open
until delivery is accepted.

Audit rows (`shipment`): `EWAY_BILL_ENTERED`, `EWAY_BILL_NOT_NEEDED_STATED`, `EWAY_BILL_REMOVED`,
`EWAY_BILL_CHECKED`. States are words only (`ABSENT`, `BILL`, `NOT_NEEDED`, `UNCHECKED`, `FOUND`,
`PROBLEM_NOT_FOUND` and so on). No typed text ever goes in an audit row.

## Copy (screened before building)

Shipper card, title "E-way bill":

- Nothing added: "No e-way bill added yet." Two equal buttons: "Add e-way bill" and "No e-way bill needed".
  Nothing preselected.
- Add form note: "Copy these four details from the government portal. All four are needed to save. naviG8r
  does not make or change e-way bills." Fields: "E-way bill number (12 digits)", "Bill date", "GSTIN of
  whoever made the bill", "Invoice number"; under the last two: "Used only by naviG8r ops to find the bill on
  the portal." Above Save, when the bill had been checked: "Changing these details clears the check." Buttons:
  "Save e-way bill", "Cancel". Link: "Open the government e-way bill portal".
- Saved: number in groups of four, then date, GSTIN, invoice number. Check line, one of: "Entered by you. Not
  checked yet." / "Ops saw this bill on the government portal on 14 Oct 2026. It may have changed since." /
  a problem line by reason: "Ops could not find this bill on the portal on 14 Oct 2026." / "Ops saw on the
  portal that this bill was cancelled, on 14 Oct 2026." / "The details here did not match the portal when ops
  looked, on 14 Oct 2026." / "Ops found a problem with this bill on 14 Oct 2026." Each problem line adds
  "Check the details here and on the portal." Buttons: "Edit", "Remove e-way bill".
- Not needed: "You said no e-way bill is needed: Below the value that needs one." Buttons: "Change",
  "Remove e-way bill". Form: "Why is no e-way bill needed?" with three reasons, none preselected, and "Other"
  asks for the reason in words.
- Errors show the server's own sentence, never "HTTP 400".

Carrier card, same title, read only:

- Nothing added: "[Shipper] has not added an e-way bill or said none is needed."
- Not needed: "[Shipper] says no e-way bill is needed: [reason]. This is the shipper's statement. naviG8r has
  not checked it." The "Other" words are shown exactly as typed. Plain styling, not a warning.
- Bill: number in groups of four, the same check line as the shipper's (with the same date and "may have
  changed since"), and "Shown as the shipper entered it. naviG8r has not made or changed this bill, and has not
  checked the truck or the expiry." A problem adds "The shipper can see this on their shipment."
- Known limit: every login at a carrier sees every shipment of that carrier, so any of them sees any bill
  number and note on it (brief question 1). Not "only the people involved".

Ops page: "E-way bills to check" and "Missing". Each row shows the four details, a Copy button on each, a link
"Open the government portal", "Mark as found on the portal" and "Report a problem" (reason chosen from the four
above, none preselected). Results appear inside the row and say whether anything changed.

## Open and unchecked

- Permission keys `eway_bill.write` and `eway_bill.check` are new (code only; the database seeds them on save).
- Database mode needs one nullable JSON column, `ShipmentRow."ewayBill"`, applied by hand BEFORE this merges,
  because merging deploys to alpha and beta. Not applied by me.
- The portal address is `https://ewaybillgst.gov.in`, named in the brief from CBIC's FAQ. I have not opened it.
  Whether it has a page that takes a bill number directly, or needs a captcha, is unknown.
- Whether the team wants ops to check at all, or the GSTIN and invoice number collected, is the brief's open
  question 4 and the chartered accountant's question 7.
