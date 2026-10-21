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
   and the "Companies waiting" count at the top drops by one.
6. Look at **Payments waiting for release**.
   **Right:**
   - Both Release buttons are grey, with "Only FINANCE can release payments. You hold OPS."
   - There's no "Ledger credit" column; a line says amounts are shown to FINANCE only.
7. In **Review any company by ID**, check that neither Approve nor Reject is picked and the Reason list is greyed out.
   Type `carrier-b` and click **Record review**.
   **Right:** "Not recorded yet. Pick Approve or Reject." Pick **Reject**: the Reason list opens, and includes "Approval taken back".

## B. Finance (8000000006)

8. **Right:**
   - The approval card says "Only OPS can review companies. You hold FINANCE."
   - The ID form is greyed out and says the same.
9. In the payments table, row **load-a-hold** has a grey button and "Hold ends …".
10. In row **load-a-expired**, click **Release payment…**.
    **Right:** a box shows three lines, each with the amount shown for this load: Shipper paid, NaviG8r's share, and
    Credited to the ledger balance. The credited amount is the shipper's amount less NaviG8r's share. It says the credit
    is paid out in a weekly payout batch. Cancel is highlighted.
11. Press **Esc**. **Right:** the box closes. Open it again and click **Cancel**. **Right:** it closes again.
12. Open it once more and click **Release** (the button names the credited amount).
    **Right:** the box closes, the row says "Payment released by you at HH:MM IST." followed by the credited amount and
    "is credited to the carrier's ledger balance…", and its label turns green.

## C. Admin (8000000007)

13. In **Team access**, check that no role is ticked. Type `user-ops` and `platform`, then click **Save roles**.
    **Right:** "Not saved yet. Tick at least one role."

## D. Someone without an operator role (8000000004)

14. **Right:** "You're signed in, but you don't have an operator role for Synthetic Carrier B." No lists are shown.

## E. Today's pages are untouched

15. Open **http://127.0.0.1:3145/ops** and **http://127.0.0.1:3145/ops/v1**.
    **Right:** today's compact page and the full dashboard, working as before.

## F. E-way bills (Operations 8000000005, then Finance 8000000006)

The test server must have e-way bill examples loaded. If the two cards below are empty, ask the person who started it.

16. Signed in as Operations, scroll to **E-way bills to check**, beside **Team access**. In the "Needs someone" row at
    the top, a button "E-way bills to check" shows the same count.
    **Right:** each row shows the customer, the route, and four details: bill number in groups of four digits, bill date,
    GSTIN and invoice number. Every detail has its own **Copy** button.
    **Wrong:** a detail with no Copy button, or any word in capitals joined by underscores.
17. Click **Copy** next to the bill number, then paste it into any text box.
    **Right:** the word "Copied" appears beside the button, and what you paste is 12 digits with no spaces.
    **Wrong:** nothing appears, or a message other than "Copied" or "Select it and copy it yourself."
18. Click **Open the government portal**.
    **Right:** the government e-way bill site opens in a new tab and this page stays open.
    **Wrong:** the portal replaces this page.
19. Click **Report a problem**, then **Confirm problem** without choosing.
    **Right:** the list offers Not found on the portal, Cancelled on the portal, Details here do not match the portal and
    Other, with nothing chosen. A red message in the row says "Not reported yet. Choose a reason from the list."
    Click **Cancel**: the two buttons come back.
    **Wrong:** a reason is already chosen, or the message appears at the top of the page.
20. Click **Mark as found on the portal**.
    **Right:** a green message in the row: "Marked as found on the portal by you at HH:MM IST." and the count at the top
    drops by one. The row stays until you reload.
21. Look at **Missing**.
    **Right:** shipments with no e-way bill, with customer, route and booking time. Under them, "Shipper says no e-way bill
    is needed" lists each shipment with its reason, in plain words.
    **Wrong:** a reason shown in capitals with underscores.
22. Sign out and sign in as Finance (8000000006).
    **Right:** both cards say "Only OPS can check e-way bills. You hold FINANCE." and show no bills.

## Stop it

23. In Terminal, press **Ctrl+C**.
