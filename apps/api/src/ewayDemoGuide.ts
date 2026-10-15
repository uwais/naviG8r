/**
 * The step-by-step demo guide at /demo/eway-guide: who signs in as whom on the practice site, what they copy
 * into the app, and which of the site's rules come from the notifications and which are assumed.
 */
import type { IncomingMessage, ServerResponse } from "node:http";
import { escapeHtml, sendHtml } from "./ewayDemoPortalPages.ts";
import type { Persona } from "./ewayDemoPortalRules.ts";

/**
 * The guide is opened from another machine on the same network as often as from this one, so its addresses
 * follow the Host the visitor used. The app is served by the demo script on port 8087 of the same machine.
 */
function guideAddresses(req: IncomingMessage): { guideAddress: string; appAddress: string } {
  try {
    const visited = new URL(`http://${req.headers.host ?? ""}`);
    return { guideAddress: `${visited.origin}/demo/eway-guide`, appAddress: `http://${visited.hostname}:8087` };
  } catch {
    return { guideAddress: "http://127.0.0.1:3139/demo/eway-guide", appAddress: "http://127.0.0.1:8087" };
  }
}

const RULES_MODELLED = `<div class="box"><h2>Rules I modelled</h2>
<p>From the notifications (CGST Rule 138 as substituted by Notification 12/2018, amended by 31/2019 and 94/2020, read on gstcouncil.gov.in):</p>
<ul>
<li>The supplier makes Part A, or a transporter does so on the supplier's behalf: Rule 138(1) first proviso and 138(3).</li>
<li>Without Part B (the vehicle) a bill is not valid for movement by road: Rule 138(3), Explanation 2.</li>
<li>Whoever filed Part A, or the transporter, updates the vehicle; once the transporter has updated it, the Part A filer may not assign the bill to another transporter: Rule 138(5) and 138(5A).</li>
<li>Validity is one day per 200 km or part of it (it was 100 km): Notification 94/2020, paragraph 10, from 1 Jan 2021.</li>
<li>A day ends at midnight of the day after the start date, and each further day adds one: Rule 138(10), Explanation 1. Shown here as 23:59 India time.</li>
<li>The transporter may extend validity in exceptional circumstances: Rule 138(10), second proviso. Only within eight hours from the time of expiry: Notification 31/2019, paragraph 18(b).</li>
<li>A bill can be cancelled within 24 hours of generation: Rule 138(9).</li>
</ul>
<p>Assumed, my reading or a practice simplification:</p>
<ul>
<li>Counting starts when the first vehicle is entered. The text counts from generation; under Rule 138(2) a bill is generated after Part B, and the real portal is reported to count from Part B.</li>
<li>Once a transporter has updated the vehicle, the supplier can no longer update it at all. The text only stops the supplier reassigning the bill to another transporter.</li>
<li>Someone else, a party to nothing, cannot generate a bill. The rules let any registered person who causes movement do so.</li>
<li>Signed in as the Supplier, A.1 must be your own GSTIN. A Transporter that leaves Transporter ID empty is named on the bill itself.</li>
<li>Full details go to the supplier and the named transporter only. Rule 138(4) also makes the bill number available to the recipient, who is not a practice user here.</li>
<li>An expired bill's vehicle cannot be changed.</li>
<li>Only whoever generated a bill can cancel it. Rule 138(9) names no one. The rule that a bill verified in transit cannot be cancelled is not modelled.</li>
<li>First Time is the reason for the first vehicle and is refused after it. The reason list (Break Down, Transhipment, Others, First Time) and the extension reasons come from secondary sources, not the notifications.</li>
<li>An extension is counted from the moment it is made, over the remaining distance. The notifications do not say how.</li>
<li>Extending in the eight hours before expiry, which the real portal is reported to allow, is not in these notifications and is not modelled.</li>
<li>Distance is capped at 4000 km. The 15-day limit for entering Part B after Part A (Rule 138(9), second proviso) is not modelled.</li>
</ul></div>`;

export function showGuide(req: IncomingMessage, res: ServerResponse, persona: Persona | null): void {
  const addresses = guideAddresses(req);
  const guideAddress = escapeHtml(addresses.guideAddress);
  const appAddress = escapeHtml(addresses.appAddress);
  sendHtml(res, 200, "Demo guide", `<h1>Demo guide: one e-way bill, four people</h1>
<h2>Before you start</h2>
<ul>
<li>Open ${guideAddress} to come back to this page.</li>
<li>The demo server is running with the practice site switched on. Restarting it resets everything, including the bills on this practice site.</li>
<li>Shipper app: <a href="${appAddress}/#/customer/login">${appAddress}/#/customer/login</a>. Sign in as 8000000001.</li>
<li>Carrier: the Android emulator, or <a href="${appAddress}/#/driver">${appAddress}/#/driver</a>. Sign in as 8000000003 (the owner).</li>
<li>Driver: the same carrier app. Sign in as 8000000009.</li>
<li>Ops: <a href="/ops/beta">/ops/beta</a>. Sign in as 8000000005.</li>
<li>Tap Send code and the code fills in for you.</li>
<li>On the practice site you choose who you are on <a href="/demo/eway-portal/sign-in">Choose who you are</a>: Supplier (Synthetic Shipper A), Transporter (Synthetic Carrier A, Transporter ID 29TRNSP1234A1Z7) or Someone else. There is no password. Switch user is at the top of every page.</li>
</ul>
<h2>Which shipment to use</h2>
<ul>
<li>The seeded shipment load-a-with-bill already has a bill (1234 5678 9012) that names Synthetic Carrier A as transporter and has no vehicle yet.</li>
<li>The seeded shipment load-a-with-truck has a bill (2345 6789 0123) whose transporter already added vehicle KA01AB1234, valid up to 20 hours after the demo server started.</li>
<li>The shipment load-a-booked has no bill yet. It is the one that follows this whole guide.</li>
</ul>
<h2>Step 1. Shipper generates the bill</h2>
<ol>
<li>Open <a href="${appAddress}/#/customer/shipments/load-a-booked">${appAddress}/#/customer/shipments/load-a-booked</a>. Its E-way bill card says No e-way bill added yet.</li>
<li>Tap Open the practice e-way bill portal. It opens this practice site in a new tab. (A build without the practice address says Open the government e-way bill portal and opens the real site.)</li>
<li>Choose who you are: Supplier. Then choose <a href="/demo/eway-portal/generate">Generate a new e-way bill</a>.</li>
<li>A.1 is your own GSTIN. Fill in Part A with any sensible values, for example recipient 33AAACT5678L1Z2, PINs 560099 and 600032, document number SYN/2026/101, today's date, value 75000, HSN 8471, reason Supply.</li>
<li>Type an approximate distance, for example 350 km. Leave the vehicle empty and type Transporter ID 29TRNSP1234A1Z7, then tap Generate e-way bill.</li>
<li>The bill says Part B not entered: not valid for movement. Copy the bill number, the supplier GSTIN and the document number, and note the bill date.</li>
<li>Back in the app, tap Add e-way bill. The supplier GSTIN goes in GSTIN of whoever made the bill and the document number in Invoice number. Pick the bill date the practice site showed. Tap Save e-way bill.</li>
</ol>
<h2>Step 2. Carrier (owner) adds the vehicle</h2>
<ol>
<li>Open the shipment in Shipments and tap Open the practice e-way bill portal.</li>
<li>Switch user to Transporter, then choose <a href="/demo/eway-portal/vehicle">Update vehicle (Part B)</a>.</li>
<li>Type the bill number and vehicle KA01AB1234, choose the reason First Time, then tap Update vehicle.</li>
<li>The page shows Valid up to: one day per 200 km, so 350 km gives two days, ending at 23:59 India time.</li>
<li>Switch back to the app. Tap Add truck, paste the vehicle number, choose the Valid until date and time to match, then tap Save truck.</li>
</ol>
<h2>Step 3. Ops verifies the bill</h2>
<ol>
<li>Open <a href="/ops/beta">/ops/beta</a> and find E-way bills to check. Each row shows the four details with a Copy button on each.</li>
<li>Tap Open the government portal, then choose <a href="/demo/eway-portal/check">Verify an e-way bill</a>. No sign-in is needed.</li>
<li>Paste the four details and tap Verify. The page says Found and shows the vehicle and Valid up to.</li>
<li>Back on the ops page, tap Mark as found on the portal.</li>
</ol>
<h2>Step 4. Driver reads it</h2>
<ol>
<li>Sign in as 8000000009 and open the shipment.</li>
<li>The driver's part is read only by design: the bill number in large type, the truck, the valid-until time and the ops line, and once fewer than 12 hours are left, how many hours remain.</li>
<li>At a check-post the driver quotes the bill number. The driver creates nothing and changes nothing.</li>
</ol>
<h2>Step 5. What to try next</h2>
<ol>
<li>Switch user to Someone else and open the bill's details from the home page: it is refused.</li>
<li>Switch user to Supplier and try Update vehicle on the same bill: it is refused, because the transporter already updated it.</li>
<li>As the Transporter, change the vehicle with reason Break Down: the Valid up to stays the same.</li>
<li>As the Supplier, generate a second bill and cancel it on <a href="/demo/eway-portal/cancel">Cancel an e-way bill</a>. Verify then says Cancelled.</li>
<li>As the Transporter, try <a href="/demo/eway-portal/extend">Extend validity</a> on 234567890123: it is refused until that bill expires, and works only in the eight hours after.</li>
<li>Verify the seeded bills: 123456789012, 1 Oct 2026, 29ABCDE1234F1Z5, SYN/2026/001 (Part B not entered), and 234567890123, 2 Oct 2026, 29ABCDE1234F1Z5, SYN/2026/002 (vehicle KA01AB1234).</li>
</ol>
${RULES_MODELLED}
<div class="box"><strong>What is real:</strong> the app, its checks and who sees what, and the e-way bill rules listed above with their sources.
<strong>What is pretend:</strong> this whole site and every page on it, the sign-in (no password, no captcha), working out the distance from the PIN codes (you type it), and the bill numbers. The real portal cannot send data back to naviG8r, so people copy and paste.</div>`, persona);
}
