# Test the new ops page on your Mac

Everything here is fake test data. Nothing touches alpha, beta or production.

## Start it (once)

1. In Terminal, go to the repo folder with the ops page branch checked out, and paste the line below. It
   needs Node 24: if `node --version` shows v20, use `/opt/homebrew/opt/node@24/bin/node` in place of `node`.
   ```
   RBAC_MANUAL_PORT=3145 node --experimental-strip-types scripts/rbac-manual.mjs
   ```
   **Right:** a table of test phone numbers, then "Open http://127.0.0.1:3145/ops".
   **Wrong:** "address already in use". Change 3145 to 3146, and use that number below.
2. In Chrome, open **http://127.0.0.1:3145/ops/beta**.
   **Right:** a warm off-white page, the NaviG8r logo, "Operations", and a Sign in card.

To sign in: type the phone number and click **Send code**. The test server fills the code in, and the
button counts down before another code can be sent. Then click **Sign in**.
To switch person: click **Sign out**, or use a new private window.

| Phone | Who |
|---|---|
| 8000000005 | Operations (OPS) |
| 8000000006 | Finance (FINANCE) |
| 8000000007 | Admin (ADMIN) |
| 8000000011 | All three operator roles |
| 8000000004 | A carrier owner (no operator role) |

## A. Operations (8000000005)

3. Find the **Synthetic Carrier B** card and click **Reject**.
   **Right:** a reason list appears with only reasons to reject, and nothing chosen. Click **Cancel**: Approve and Reject come back.
4. Click **Approve**, then **Confirm approval** without choosing a reason.
   **Right:** a red message inside that card: "Not approved yet. Choose a reason from the list."
   **Wrong:** the message appears at the top of the page.
5. Choose **Documents reviewed** and click **Confirm approval**.
   **Right:** a green message in the card: "Approved by you at HH:MM IST: Documents reviewed…". The label changes to Approved,
   and the "Carriers waiting" count at the top drops by one.
6. Look at **Payments waiting for release**.
   **Right:**
   - Both Release buttons are grey, with "Only FINANCE can release payments. You hold OPS."
   - There's no "Ledger credit" column; a line says amounts are shown to FINANCE only.
7. In **Review any carrier by ID**, check that neither Approve nor Reject is picked and the Reason list is greyed out.
   Type `carrier-b` and click **Record review**.
   **Right:** "Not recorded yet. Pick Approve or Reject." Pick **Reject**: the Reason list opens, and includes "Approval taken back".

## B. Finance (8000000006)

8. **Right:**
   - The carriers card says "Only OPS can review carriers. You hold FINANCE."
   - The ID form is greyed out and says the same.
9. In the payments table, row **load-a-hold** has a grey button and "Hold ends …".
10. In row **load-a-expired**, click **Release payment…**.
    **Right:** a box shows Shipper paid ₹50, NaviG8r commission − ₹5, Credited to the ledger balance ₹45. It says the credit
    is paid out in a weekly payout batch. Cancel is highlighted.
11. Press **Esc**. **Right:** the box closes. Open it again and click **Cancel**. **Right:** it closes again.
12. Open it once more and click **Release ₹45**.
    **Right:** the box closes, the row says "Payment released by you at HH:MM IST. ₹45 is credited to the carrier's ledger
    balance…", and its label turns green.

## C. Admin (8000000007)

13. In **Team access**, check that no role is ticked. Type `user-ops` and `platform`, then click **Save roles**.
    **Right:** "Not saved yet. Tick at least one role."

## D. Someone without an operator role (8000000004)

14. **Right:** "You're signed in, but you don't have an operator role for Synthetic Carrier B." No lists are shown.

## E. Today's pages are untouched

15. Open **http://127.0.0.1:3145/ops** and **http://127.0.0.1:3145/ops/v1**.
    **Right:** today's compact page and the full dashboard, working as before.

## Stop it

16. In Terminal, press **Ctrl+C**.
