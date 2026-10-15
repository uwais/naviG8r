/**
 * The practice e-way bill site's HTML. Plain server-rendered pages with no script, every printed value escaped.
 * It copies how the real portal behaves, never how it looks: no emblem, no government colours, a yellow
 * practice banner on every page.
 */
import type { ServerResponse } from "node:http";
import { EXTENSION_REASONS, INDIA_OFFSET_MS, PERSONAS, TRANSPORT_REASONS, VEHICLE_UPDATE_REASONS, currentVehicle, transporterName } from "./ewayDemoPortalRules.ts";
import type { GenerateTyped } from "./ewayDemoPortalFormChecks.ts";
import type { DemoBill, Persona, VerifyResult, VerifyTyped } from "./ewayDemoPortalRules.ts";

const BANNER_TEXT = "naviG8r DEMO. This is a practice site, not the government e-way bill portal. Nothing here is real.";
export const CONTENT_SECURITY_POLICY = "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'";
const MONTH_NAMES = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

const PAGE_STYLE = `
body{margin:0;background:#f8f7f2;color:#1a1a1a;font:16px/1.5 system-ui,sans-serif}
.banner{background:#fff1c2;color:#1a1a1a;border-bottom:3px solid #8a5a00;padding:12px 16px;font-weight:700;text-align:center}
.who{padding:8px 16px;border-bottom:1px solid #d8d3c8;text-align:center}
main{max-width:720px;margin:0 auto;padding:16px}
h1{font-size:1.5rem;margin:0.6em 0}
h2{font-size:1.15rem;margin:1.4em 0 0.4em}
a{color:#0b4f8a}
label{display:block;margin-top:14px;font-weight:600}
input,select{display:block;width:100%;box-sizing:border-box;margin-top:4px;padding:10px;font:inherit;color:#1a1a1a;background:#fff;border:1px solid #5c564d;border-radius:6px}
button{margin-top:18px;padding:12px 20px;font:inherit;font-weight:600;color:#fff;background:#2b2620;border:0;border-radius:6px;cursor:pointer}
.error{background:#fde8e4;border:1px solid #9b2c1f;color:#1a1a1a;padding:10px 12px;border-radius:6px;margin:12px 0}
.box{background:#fff;border:1px solid #5c564d;border-radius:8px;padding:12px 16px;margin:16px 0}
.number{font:700 clamp(1.25rem,6vw,2.2rem)/1.2 ui-monospace,Menlo,monospace;letter-spacing:0.06em;margin:12px 0}
.practice-mark{font-size:1.2rem;letter-spacing:0}
.mono{font-family:ui-monospace,Menlo,monospace}
ol li{margin:6px 0}
ul.links li{margin:10px 0;font-size:1.1rem}
dl{margin:0}dt{font-weight:600;margin-top:8px}dd{margin:0}
`;

export function escapeHtml(value: string): string {
  return value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;");
}

function signedInLine(persona: Persona | null): string {
  if (!persona) return 'Not signed in. <a href="/demo/eway-portal/sign-in">Choose who you are</a>';
  return `Signed in as ${escapeHtml(persona.role)}: ${escapeHtml(persona.name)} (${escapeHtml(persona.idLabel)} <span class="mono">${escapeHtml(persona.id)}</span>). <a href="/demo/eway-portal/sign-in">Switch user</a>`;
}

function renderPage(title: string, bodyHtml: string, persona: Persona | null): string {
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${escapeHtml(title)} - naviG8r demo</title><style>${PAGE_STYLE}</style></head>
<body><div class="banner" role="note">${escapeHtml(BANNER_TEXT)}</div>
<div class="who">${signedInLine(persona)}</div>
<main>${bodyHtml}
<p><a href="/demo/eway-portal">Practice site home</a> | <a href="/demo/eway-portal/check">Verify an e-way bill</a> | <a href="/demo/eway-guide">Demo guide</a></p></main></body></html>`;
}

export function securityHeaders(): Record<string, string> {
  return { "content-security-policy": CONTENT_SECURITY_POLICY, "x-content-type-options": "nosniff", "cache-control": "no-store" };
}

export function sendHtml(res: ServerResponse, status: number, title: string, bodyHtml: string, persona: Persona | null, closeConnection = false): void {
  const html = renderPage(title, bodyHtml, persona);
  res.writeHead(status, {
    "content-type": "text/html; charset=utf-8",
    "content-length": Buffer.byteLength(html),
    ...securityHeaders(),
    ...(closeConnection ? { connection: "close" } : {}),
  });
  res.end(html);
}

// ---------- formatting ----------

export function formatDay(isoDate: string): string {
  const match = /^([0-9]{4})-([0-9]{2})-([0-9]{2})$/.exec(isoDate);
  if (!match) return isoDate;
  return `${Number(match[3])} ${MONTH_NAMES[Number(match[2]) - 1]} ${match[1]}`;
}

export function formatIndiaDateTime(utcMs: number): string {
  const parts = new Date(utcMs + INDIA_OFFSET_MS);
  const hours = String(parts.getUTCHours()).padStart(2, "0");
  const minutes = String(parts.getUTCMinutes()).padStart(2, "0");
  return `${parts.getUTCDate()} ${MONTH_NAMES[parts.getUTCMonth()]} ${parts.getUTCFullYear()}, ${hours}:${minutes}`;
}

function groupsOfFour(billNumber: string): string {
  return billNumber.replace(/(.{4})(?=.)/g, "$1 ");
}

function validityLine(bill: DemoBill): string {
  if (bill.cancelledAtUtcMs !== null) return "Cancelled";
  if (bill.validUpToUtcMs === null) return "Part B not entered: not valid for movement";
  return `Valid up to ${formatIndiaDateTime(bill.validUpToUtcMs)} (India time)`;
}

function reasonWords(list: readonly { code: string; words: string }[], code: string): string {
  return list.find((reason) => reason.code === code)?.words ?? code;
}

// ---------- form pieces ----------

function textField(label: string, name: string, value: string, type = "text", hint = ""): string {
  const hintHtml = hint ? `<small>${escapeHtml(hint)}</small>` : "";
  return `<label for="${name}">${escapeHtml(label)}</label>${hintHtml}<input id="${name}" name="${name}" type="${type}" value="${escapeHtml(value)}" autocomplete="off">`;
}

/** Nothing is preselected: the first option is an empty "Choose". */
function selectField(label: string, name: string, options: readonly { code: string; words: string }[], selected: string): string {
  const optionHtml = options
    .map((option) => `<option value="${escapeHtml(option.code)}"${option.code === selected ? " selected" : ""}>${escapeHtml(option.words)}</option>`)
    .join("");
  return `<label for="${name}">${escapeHtml(label)}</label><select id="${name}" name="${name}"><option value="">Choose</option>${optionHtml}</select>`;
}

function errorBox(message: string): string {
  return message ? `<p class="error" role="alert">${escapeHtml(message)}</p>` : "";
}

export function refusalBody(heading: string, sentence: string): string {
  return `<h1>${escapeHtml(heading)}</h1>${errorBox(sentence)}`;
}

// ---------- sign-in and home ----------

export function signInBody(): string {
  const buttons = PERSONAS.map((persona) => `<form method="post" action="/demo/eway-portal/sign-in">
<input type="hidden" name="persona" value="${escapeHtml(persona.key)}">
<button type="submit">${escapeHtml(persona.role)}: ${escapeHtml(persona.name)} (${escapeHtml(persona.idLabel)} ${escapeHtml(persona.id)})</button>
</form>`).join("\n");
  return `<h1>Practice sign-in: choose who you are</h1>
<p>This is a demo sign-in: no password and no captcha. The real portal has its own login, which this site does not copy. Choosing only sets which practice user you are, until you switch.</p>
${buttons}`;
}

export function signInNeededBody(): string {
  return `<h1>Practice site: choose who you are first</h1><p>This page acts as a signed-in user. <a href="/demo/eway-portal/sign-in">Choose who you are</a>, then come back.</p>`;
}

export function homeBody(): string {
  return `<h1>Practice e-way bill site</h1>
<p>Choose what to practise. Bills made here are kept in memory and disappear when the demo server restarts.</p>
<ul class="links">
<li><a href="/demo/eway-portal/generate">Generate a new e-way bill</a></li>
<li><a href="/demo/eway-portal/vehicle">Update vehicle (Part B)</a></li>
<li><a href="/demo/eway-portal/extend">Extend validity</a></li>
<li><a href="/demo/eway-portal/cancel">Cancel an e-way bill</a></li>
<li><a href="/demo/eway-portal/check">Verify an e-way bill</a></li>
</ul>
<form method="get" action="/demo/eway-portal/bill">
${textField("Open a bill's full details (supplier and named transporter only)", "number", "")}
<button type="submit">Open bill</button>
</form>`;
}

// ---------- generate ----------

export function generateFormBody(typed: GenerateTyped, errorMessage: string): string {
  const reasons = TRANSPORT_REASONS.map((reason) => ({ code: reason, words: reason }));
  return `<h1>Practice e-way bill: generate a new bill</h1>${errorBox(errorMessage)}
<form method="post" action="/demo/eway-portal/generate">
<h2>Part A</h2>
${textField("A.1 GSTIN of Supplier", "supplierGstin", typed.supplierGstin, "text", "15 letters and digits, for example 29ABCDE1234F1Z5")}
${textField("A.2 Place of Dispatch (PIN code)", "dispatchPin", typed.dispatchPin)}
${textField("A.3 GSTIN of Recipient", "recipientGstin", typed.recipientGstin, "text", "Or URP for an unregistered recipient")}
${textField("A.4 Place of Delivery (PIN code)", "deliveryPin", typed.deliveryPin)}
${textField("A.5 Document Number", "documentNumber", typed.documentNumber, "text", "The invoice or challan number")}
${textField("A.6 Document Date", "documentDate", typed.documentDate, "date")}
${textField("A.7 Value of Goods (rupees)", "goodsValueRupees", typed.goodsValueRupees)}
${textField("A.8 HSN Code", "hsnCode", typed.hsnCode, "text", "4, 6 or 8 digits")}
${selectField("A.9 Reason for Transportation", "transportReason", reasons, typed.transportReason)}
<h2>Part B</h2>
${textField("Approximate distance (km)", "distanceKm", typed.distanceKm, "text", "The real portal works this out from the two PIN codes. Here you type it.")}
${textField("B.1 Vehicle Number for Road (optional if a transporter is named)", "vehicleNumber", typed.vehicleNumber, "text", "For example KA01AB1234")}
${textField("Transporter ID (optional)", "transporterId", typed.transporterId, "text", "The transporter who will add the vehicle, for example 29TRNSP1234A1Z7")}
<button type="submit">Generate e-way bill</button>
</form>`;
}

export function generatedBillBody(bill: DemoBill): string {
  const transporterLine = bill.transporterId
    ? `<p>Transporter named on the bill: ${escapeHtml(transporterName(bill.transporterId) || "unknown transporter")} (<span class="mono">${escapeHtml(bill.transporterId)}</span>)</p>`
    : "<p>No transporter is named on this bill.</p>";
  return `<h1>Practice e-way bill generated</h1>
<p class="number">${escapeHtml(groupsOfFour(bill.billNumber))} <span class="practice-mark">(practice)</span></p>
<p>Generated on ${escapeHtml(formatDay(bill.billDate))}</p>
<p><strong>${escapeHtml(validityLine(bill))}</strong></p>
<div class="box"><h2>Practice bill, not a real e-way bill</h2>
<h2>Copy these four details into the naviG8r app: bill number, bill date, supplier GSTIN, document number</h2>
<dl>
<dt>Bill number</dt><dd class="mono">${escapeHtml(bill.billNumber)}</dd>
<dt>Bill date</dt><dd>${escapeHtml(formatDay(bill.billDate))} (${escapeHtml(bill.billDate)})</dd>
<dt>Supplier GSTIN (the app calls it GSTIN of whoever made the bill)</dt><dd class="mono">${escapeHtml(bill.supplierGstin)}</dd>
<dt>Document number (the app calls it invoice number)</dt><dd class="mono">${escapeHtml(bill.documentNumber)}</dd>
</dl></div>
${transporterLine}
<p>Go back to the naviG8r app tab and paste them there. <a href="/demo/eway-portal/bill?number=${escapeHtml(bill.billNumber)}">See this bill's full details</a></p>`;
}

// ---------- vehicle, extension, cancel ----------

export type VehicleTyped = { billNumber: string; vehicleNumber: string; reasonCode: string; remark: string };

export function vehicleFormBody(typed: VehicleTyped, errorMessage: string): string {
  return `<h1>Practice e-way bill: update vehicle (Part B)</h1>${errorBox(errorMessage)}
<p>Practice rule: only whoever generated the bill, or the transporter it names, can update the vehicle. Once the transporter has updated it, the supplier cannot.</p>
<form method="post" action="/demo/eway-portal/vehicle">
${textField("E-way bill number", "billNumber", typed.billNumber)}
${textField("B.1 Vehicle Number", "vehicleNumber", typed.vehicleNumber, "text", "For example KA01AB1234")}
${selectField("Reason", "reasonCode", VEHICLE_UPDATE_REASONS, typed.reasonCode)}
${textField("Remarks (needed when the reason is Others)", "remark", typed.remark)}
<button type="submit">Update vehicle</button>
</form>`;
}

export function vehicleDoneBody(bill: DemoBill): string {
  return `<h1>Practice e-way bill: vehicle updated</h1>
<p class="number" style="font-size:1.4rem">Vehicle ${escapeHtml(currentVehicle(bill) ?? "")}. ${escapeHtml(validityLine(bill))}.</p>
<p>Copy the vehicle number and the Valid up to date and time into the naviG8r app.</p>
<p>Practice rule: the first vehicle starts the validity, one day per 200 km of the bill's distance; a later vehicle change keeps it.</p>`;
}

export type ExtendTyped = { billNumber: string; reasonCode: string; remark: string; remainingDistanceKm: string };

export function extendFormBody(typed: ExtendTyped, errorMessage: string): string {
  return `<h1>Practice e-way bill: extend validity</h1>${errorBox(errorMessage)}
<p>Practice rule: only the transporter named on the bill, after updating its vehicle, can extend it, and only in the eight hours after it expires.</p>
<form method="post" action="/demo/eway-portal/extend">
${textField("E-way bill number", "billNumber", typed.billNumber)}
${selectField("Reason", "reasonCode", EXTENSION_REASONS, typed.reasonCode)}
${textField("Remarks (needed when the reason is Other)", "remark", typed.remark)}
${textField("Remaining distance (km)", "remainingDistanceKm", typed.remainingDistanceKm)}
<button type="submit">Extend validity</button>
</form>`;
}

export function extendDoneBody(bill: DemoBill): string {
  return `<h1>Practice e-way bill: validity extended</h1>
<p class="number" style="font-size:1.4rem">${escapeHtml(validityLine(bill))}.</p>
<p>Copy the new Valid up to date and time into the naviG8r app.</p>`;
}

export function cancelFormBody(billNumber: string, errorMessage: string): string {
  return `<h1>Practice e-way bill: cancel a bill</h1>${errorBox(errorMessage)}
<p>Practice rule: whoever generated the bill can cancel it within 24 hours of generating it.</p>
<form method="post" action="/demo/eway-portal/cancel">
${textField("E-way bill number", "billNumber", billNumber)}
<button type="submit">Cancel this e-way bill</button>
</form>`;
}

export function cancelDoneBody(bill: DemoBill): string {
  return `<h1>Practice e-way bill cancelled</h1><p>Bill <span class="mono">${escapeHtml(groupsOfFour(bill.billNumber))}</span> is now Cancelled.</p>`;
}

// ---------- detail and verify ----------

export function billDetailBody(bill: DemoBill): string {
  const vehicleRows = bill.vehicleUpdates
    .map((update) => `<li><span class="mono">${escapeHtml(update.vehicleNumber)}</span>, ${escapeHtml(reasonWords(VEHICLE_UPDATE_REASONS, update.reasonCode))}${update.remark ? ` (${escapeHtml(update.remark)})` : ""}, by the ${escapeHtml(update.byPersonaKey)}, ${escapeHtml(formatIndiaDateTime(update.atUtcMs))}</li>`)
    .join("");
  const extensionRows = bill.extensions
    .map((extension) => `<li>${escapeHtml(reasonWords(EXTENSION_REASONS, extension.reasonCode))}${extension.remark ? ` (${escapeHtml(extension.remark)})` : ""}, ${extension.remainingDistanceKm} km left, on ${escapeHtml(formatIndiaDateTime(extension.atUtcMs))}, to ${escapeHtml(formatIndiaDateTime(extension.validUpToUtcMs))}</li>`)
    .join("");
  return `<h1>Practice e-way bill ${escapeHtml(groupsOfFour(bill.billNumber))}</h1>
<p><strong>${escapeHtml(validityLine(bill))}</strong></p>
<div class="box"><h2>Practice bill, not a real e-way bill</h2><dl>
<dt>Bill date</dt><dd>${escapeHtml(formatDay(bill.billDate))}</dd>
<dt>A.1 GSTIN of Supplier</dt><dd class="mono">${escapeHtml(bill.supplierGstin)}</dd>
<dt>A.2 Place of Dispatch</dt><dd>${escapeHtml(bill.dispatchPin)}</dd>
<dt>A.3 GSTIN of Recipient</dt><dd class="mono">${escapeHtml(bill.recipientGstin)}</dd>
<dt>A.4 Place of Delivery</dt><dd>${escapeHtml(bill.deliveryPin)}</dd>
<dt>A.5 Document Number</dt><dd class="mono">${escapeHtml(bill.documentNumber)}</dd>
<dt>A.6 Document Date</dt><dd>${escapeHtml(formatDay(bill.documentDate))}</dd>
<dt>A.7 Value of Goods</dt><dd>Rs ${escapeHtml(bill.goodsValueRupees)}</dd>
<dt>A.8 HSN Code</dt><dd>${escapeHtml(bill.hsnCode)}</dd>
<dt>A.9 Reason for Transportation</dt><dd>${escapeHtml(bill.transportReason)}</dd>
<dt>Approximate distance</dt><dd>${bill.distanceKm} km</dd>
<dt>Transporter</dt><dd>${bill.transporterId ? `${escapeHtml(transporterName(bill.transporterId) || "unknown transporter")} (<span class="mono">${escapeHtml(bill.transporterId)}</span>)` : "None named"}</dd>
</dl></div>
<h2>Vehicle history (Part B)</h2>${vehicleRows ? `<ol>${vehicleRows}</ol>` : "<p>No vehicle entered yet.</p>"}
${extensionRows ? `<h2>Extensions</h2><ol>${extensionRows}</ol>` : ""}`;
}

function verifyResultHtml(bill: DemoBill | undefined, result: VerifyResult): string {
  if (!bill || result.outcome === "noMatch") {
    const reason = result.differingDetail ? ` The number exists, but the ${result.differingDetail} differs.` : "";
    return `<p class="error" role="alert">No match. No e-way bill matches these four details.${escapeHtml(reason)}</p>`;
  }
  const heading = result.outcome === "cancelled" ? "Cancelled (practice site)" : "Found (practice site)";
  const vehicle = currentVehicle(bill);
  return `<div class="box"><h2>${heading}</h2><dl>
<dt>Bill number</dt><dd class="mono">${escapeHtml(groupsOfFour(bill.billNumber))}</dd>
<dt>Bill date</dt><dd>${escapeHtml(formatDay(bill.billDate))}</dd>
<dt>Supplier GSTIN</dt><dd class="mono">${escapeHtml(bill.supplierGstin)}</dd>
<dt>Document number</dt><dd class="mono">${escapeHtml(bill.documentNumber)}</dd>
<dt>Vehicle</dt><dd class="mono">${vehicle ? escapeHtml(vehicle) : "No vehicle added yet"}</dd>
<dt>Validity</dt><dd>${escapeHtml(validityLine(bill))}</dd>
</dl></div>`;
}

export function verifyBody(typed: VerifyTyped, looked: { bill: DemoBill | undefined; result: VerifyResult } | null): string {
  return `<h1>Practice e-way bill: verify a bill</h1>
<p>Type the four details: bill number, bill date, supplier GSTIN and document number. Anyone can use this page; no sign-in is needed.</p>
${looked ? verifyResultHtml(looked.bill, looked.result) : ""}
<form method="get" action="/demo/eway-portal/check">
${textField("E-way bill number", "number", typed.billNumber)}
${textField("Bill date", "billDate", typed.billDate, "date")}
${textField("Supplier GSTIN", "gstin", typed.supplierGstin)}
${textField("Document number", "invoiceNumber", typed.documentNumber)}
<button type="submit">Verify</button>
</form>`;
}
