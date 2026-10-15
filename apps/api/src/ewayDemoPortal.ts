/**
 * A fake government e-way bill site for product demos, so shipper, carrier and ops can practise the
 * copy-and-paste flow without touching the real portal. Served only when EWAY_DEMO_PORTAL=1.
 *
 * Bills live in memory and vanish on restart. Pages are plain server-rendered HTML with no script at all,
 * so the content-security-policy can forbid scripts outright. The real portal cannot send data back to
 * naviG8r, so nothing here talks to the rest of the app.
 *
 * Over 500 lines on purpose: most of it is the page text of one small site, and every page shares the
 * escaping, the banner and the in-memory bills; splitting by page would scatter those for no gain.
 */
import { randomInt } from "node:crypto";
import type { IncomingMessage, ServerResponse } from "node:http";

type DemoBill = {
  billNumber: string;
  billDate: string;
  generatedAtUtcMs: number;
  makerGstin: string;
  invoiceNumber: string;
  invoiceDate: string;
  transporterName: string;
  vehicleNumber: string | null;
  validUntilUtcMs: number | null;
};

const MAX_BILLS = 500;
const MAX_FORM_BODY_BYTES = 8 * 1024;
/** A form body not complete by then is dropped, so a slow sender cannot hold a connection open. */
export const FORM_BODY_TIMEOUT_MS = 5000;
const SEEDED_BILL_NUMBER = "123456789012";
const INDIA_OFFSET_MS = 5.5 * 60 * 60 * 1000;
const MONTH_NAMES = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const GSTIN_PATTERN = /^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$/;
const PRINTABLE_ASCII = /^[\x20-\x7E]+$/;
const DATE_PATTERN = /^([0-9]{4})-([0-9]{2})-([0-9]{2})$/;
const DATE_TIME_PATTERN = /^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2})$/;

const billsByNumber = new Map<string, DemoBill>();
let seededBillAdded = false;

/**
 * The demo seed (scripts/rbac-manual.mjs) gives shipment load-a-with-bill this exact bill, so the portal
 * must know it too or ops' look-up would say "No e-way bill matches" for it. Change both together.
 */
function addSeededBillOnce(): void {
  if (seededBillAdded) return;
  seededBillAdded = true;
  billsByNumber.set(SEEDED_BILL_NUMBER, {
    billNumber: SEEDED_BILL_NUMBER,
    billDate: "2026-10-01",
    generatedAtUtcMs: Date.UTC(2026, 9, 1) - INDIA_OFFSET_MS,
    makerGstin: "29ABCDE1234F1Z5",
    invoiceNumber: "SYN/2026/001",
    invoiceDate: "2026-10-01",
    transporterName: "Synthetic Carrier A",
    vehicleNumber: null,
    validUntilUtcMs: null,
  });
}

const BANNER_TEXT = "naviG8r DEMO. This is a practice site, not the government e-way bill portal. Nothing here is real.";

const PAGE_STYLE = `
body{margin:0;background:#f8f7f2;color:#1a1a1a;font:16px/1.5 system-ui,sans-serif}
.banner{background:#fff1c2;color:#1a1a1a;border-bottom:3px solid #8a5a00;padding:12px 16px;font-weight:700;text-align:center}
main{max-width:720px;margin:0 auto;padding:16px}
h1{font-size:1.5rem;margin:0.6em 0}
h2{font-size:1.15rem;margin:1.4em 0 0.4em}
a{color:#0b4f8a}
label{display:block;margin-top:14px;font-weight:600}
input{display:block;width:100%;box-sizing:border-box;margin-top:4px;padding:10px;font:inherit;color:#1a1a1a;background:#fff;border:1px solid #5c564d;border-radius:6px}
button{margin-top:18px;padding:12px 20px;font:inherit;font-weight:600;color:#fff;background:#1f4d3a;border:0;border-radius:6px;cursor:pointer}
.error{background:#fde8e4;border:1px solid #9b2c1f;color:#1a1a1a;padding:10px 12px;border-radius:6px;margin:12px 0}
.box{background:#fff;border:1px solid #5c564d;border-radius:8px;padding:12px 16px;margin:16px 0}
.number{font:700 2.2rem/1.2 ui-monospace,Menlo,monospace;letter-spacing:0.06em;margin:12px 0}
.mono{font-family:ui-monospace,Menlo,monospace}
ol li{margin:6px 0}
ul.links li{margin:10px 0;font-size:1.1rem}
dl{margin:0}dt{font-weight:600;margin-top:8px}dd{margin:0}
`;

export function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function renderPage(title: string, bodyHtml: string): string {
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${escapeHtml(title)} - naviG8r demo</title><style>${PAGE_STYLE}</style></head>
<body><div class="banner" role="note">${escapeHtml(BANNER_TEXT)}</div>
<main>${bodyHtml}
<p><a href="/demo/eway-portal">Portal home</a> | <a href="/demo/eway-guide">Demo guide</a></p></main></body></html>`;
}

function sendHtml(res: ServerResponse, status: number, title: string, bodyHtml: string, closeConnection = false): void {
  const html = renderPage(title, bodyHtml);
  res.writeHead(status, {
    "content-type": "text/html; charset=utf-8",
    "content-length": Buffer.byteLength(html),
    "content-security-policy": "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'",
    "x-content-type-options": "nosniff",
    "cache-control": "no-store",
    ...(closeConnection ? { connection: "close" } : {}),
  });
  res.end(html);
}

function indiaDateParts(utcMs: number): Date {
  return new Date(utcMs + INDIA_OFFSET_MS);
}

function indiaDateIso(utcMs: number): string {
  return indiaDateParts(utcMs).toISOString().slice(0, 10);
}

function formatDay(isoDate: string): string {
  const match = DATE_PATTERN.exec(isoDate);
  if (!match) return isoDate;
  return `${Number(match[3])} ${MONTH_NAMES[Number(match[2]) - 1]} ${match[1]}`;
}

function formatIndiaDateTime(utcMs: number): string {
  const parts = indiaDateParts(utcMs);
  const hours = String(parts.getUTCHours()).padStart(2, "0");
  const minutes = String(parts.getUTCMinutes()).padStart(2, "0");
  return `${parts.getUTCDate()} ${MONTH_NAMES[parts.getUTCMonth()]} ${parts.getUTCFullYear()}, ${hours}:${minutes}`;
}

function groupsOfFour(billNumber: string): string {
  return billNumber.replace(/(.{4})(?=.)/g, "$1 ");
}

function isRealCalendarDate(text: string): boolean {
  const match = DATE_PATTERN.exec(text);
  if (!match) return false;
  const [year, month, day] = [Number(match[1]), Number(match[2]), Number(match[3])];
  const date = new Date(Date.UTC(year, month - 1, day));
  return date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day;
}

/** Reads a datetime-local value as India time and returns UTC milliseconds, or null if it is not a real time. */
function parseIndiaDateTime(text: string): number | null {
  const match = DATE_TIME_PATTERN.exec(text);
  if (!match) return null;
  const [year, month, day, hour, minute] = match.slice(1).map(Number);
  if (hour > 23 || minute > 59 || !isRealCalendarDate(`${match[1]}-${match[2]}-${match[3]}`)) return null;
  return Date.UTC(year, month - 1, day, hour, minute) - INDIA_OFFSET_MS;
}

function cleanBillNumber(text: string): string {
  return text.replace(/[\s-]/g, "");
}

function makeBillNumber(): string | null {
  for (let attempt = 0; attempt < 20; attempt += 1) {
    let digits = String(randomInt(1, 10));
    for (let position = 1; position < 12; position += 1) digits += String(randomInt(0, 10));
    if (!billsByNumber.has(digits)) return digits;
  }
  return null;
}

type FormReadResult = { outcome: "read"; fields: URLSearchParams } | { outcome: "tooLarge" } | { outcome: "timedOut" };

/** EWAY_DEMO_PORTAL_BODY_TIMEOUT_MS exists only so a test can wait milliseconds instead of seconds. */
function formBodyTimeoutMs(): number {
  const override = Number(process.env.EWAY_DEMO_PORTAL_BODY_TIMEOUT_MS);
  return Number.isFinite(override) && override > 0 ? override : FORM_BODY_TIMEOUT_MS;
}

function readFormBody(req: IncomingMessage): Promise<FormReadResult> {
  return new Promise((resolve) => {
    const chunks: Buffer[] = [];
    let totalBytes = 0;
    let finished = false;
    const finish = (result: FormReadResult) => {
      if (finished) return;
      finished = true;
      clearTimeout(timer);
      resolve(result);
    };
    const timer = setTimeout(() => {
      finish({ outcome: "timedOut" });
      req.destroy();
    }, formBodyTimeoutMs());
    req.on("data", (chunk: Buffer) => {
      if (finished) return;
      totalBytes += chunk.length;
      if (totalBytes > MAX_FORM_BODY_BYTES) {
        finish({ outcome: "tooLarge" });
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => finish({ outcome: "read", fields: new URLSearchParams(Buffer.concat(chunks).toString("utf8")) }));
    req.on("error", () => finish({ outcome: "read", fields: new URLSearchParams() }));
  });
}

function textField(label: string, name: string, value: string, type = "text", hint = ""): string {
  const hintHtml = hint ? `<small>${escapeHtml(hint)}</small>` : "";
  return `<label for="${name}">${escapeHtml(label)}</label>${hintHtml}<input id="${name}" name="${name}" type="${type}" value="${escapeHtml(value)}" autocomplete="off">`;
}

function errorBox(message: string): string {
  return message ? `<p class="error" role="alert">${escapeHtml(message)}</p>` : "";
}

// ---------- home ----------

function showHome(res: ServerResponse): void {
  sendHtml(res, 200, "E-way bill practice site", `<h1>E-way bill practice site</h1>
<p>Choose what to practise. Bills made here are kept in memory and disappear when the demo server restarts.</p>
<ul class="links">
<li><a href="/demo/eway-portal/generate">Generate a new e-way bill</a></li>
<li><a href="/demo/eway-portal/vehicle">Add a vehicle to a bill (Part B)</a></li>
<li><a href="/demo/eway-portal/check">Look up a bill</a></li>
</ul>`);
}

// ---------- generate ----------

type GenerateTyped = { makerGstin: string; invoiceNumber: string; invoiceDate: string; transporterName: string };

function showGenerateForm(res: ServerResponse, typed: GenerateTyped, errorMessage: string, status = 200): void {
  sendHtml(res, status, "Generate an e-way bill", `<h1>Generate a new e-way bill</h1>${errorBox(errorMessage)}
<form method="post" action="/demo/eway-portal/generate">
${textField("GSTIN of whoever makes the bill", "makerGstin", typed.makerGstin, "text", "15 letters and digits, for example 29ABCDE1234F1Z5")}
${textField("Invoice number", "invoiceNumber", typed.invoiceNumber)}
${textField("Invoice date", "invoiceDate", typed.invoiceDate, "date")}
${textField("Transporter name (optional): the carrier who will add the vehicle", "transporterName", typed.transporterName)}
<button type="submit">Generate e-way bill</button>
</form>`);
}

function checkGenerateInput(typed: GenerateTyped): string {
  if (!GSTIN_PATTERN.test(typed.makerGstin)) {
    return "The GSTIN is 15 letters and digits, for example 29ABCDE1234F1Z5.";
  }
  if (typed.invoiceNumber.length < 1 || typed.invoiceNumber.length > 32 || !PRINTABLE_ASCII.test(typed.invoiceNumber)) {
    return "Type the invoice number, up to 32 characters.";
  }
  if (!isRealCalendarDate(typed.invoiceDate)) return "Choose the invoice date.";
  if (typed.transporterName.length > 60 || (typed.transporterName && !PRINTABLE_ASCII.test(typed.transporterName))) {
    return "The transporter name is up to 60 characters.";
  }
  return "";
}

function showGeneratedBill(res: ServerResponse, bill: DemoBill): void {
  const transporterLine = bill.transporterName
    ? `<p>Transporter named on the bill: ${escapeHtml(bill.transporterName)}</p>`
    : "<p>No transporter is named on this bill.</p>";
  sendHtml(res, 200, "E-way bill generated", `<h1>E-way bill generated</h1>
<p class="number">${escapeHtml(groupsOfFour(bill.billNumber))}</p>
<p>Generated on ${escapeHtml(formatDay(bill.billDate))}</p>
<div class="box"><h2>Practice bill, not a real e-way bill</h2>
<h2>Copy these four details into the naviG8r app: bill number, bill date, GSTIN, invoice number</h2>
<dl>
<dt>Bill number</dt><dd class="mono">${escapeHtml(bill.billNumber)}</dd>
<dt>Bill date</dt><dd>${escapeHtml(formatDay(bill.billDate))} (${escapeHtml(bill.billDate)})</dd>
<dt>GSTIN</dt><dd class="mono">${escapeHtml(bill.makerGstin)}</dd>
<dt>Invoice number</dt><dd class="mono">${escapeHtml(bill.invoiceNumber)}</dd>
</dl></div>
${transporterLine}
<p><strong>Part B is empty. Practice rule: Until a vehicle is added this bill is not valid for movement.</strong></p>
<p>Go back to the naviG8r app tab and paste them there.</p>`);
}

/** A Map keeps insertion order, so the first key is the oldest. The seeded bill stays: the guide's ops look-up needs it. */
function dropOldestBill(): void {
  for (const billNumber of billsByNumber.keys()) {
    if (billNumber === SEEDED_BILL_NUMBER) continue;
    billsByNumber.delete(billNumber);
    return;
  }
}

async function handleGenerate(req: IncomingMessage, res: ServerResponse): Promise<void> {
  const emptyTyped: GenerateTyped = { makerGstin: "", invoiceNumber: "", invoiceDate: "", transporterName: "" };
  if (req.method === "GET") return showGenerateForm(res, emptyTyped, "");
  if (req.method !== "POST") return sendMethodNotAllowed(res);
  const body = await readFormBody(req);
  if (body.outcome === "timedOut") return;
  if (body.outcome === "tooLarge") return sendTooLarge(req, res);
  const typed: GenerateTyped = {
    makerGstin: (body.fields.get("makerGstin") ?? "").replace(/\s/g, "").toUpperCase(),
    invoiceNumber: (body.fields.get("invoiceNumber") ?? "").trim(),
    invoiceDate: (body.fields.get("invoiceDate") ?? "").trim(),
    transporterName: (body.fields.get("transporterName") ?? "").trim(),
  };
  const problem = checkGenerateInput(typed);
  if (problem) return showGenerateForm(res, typed, problem, 400);
  if (billsByNumber.size >= MAX_BILLS) dropOldestBill();
  const billNumber = makeBillNumber();
  if (!billNumber) return showGenerateForm(res, typed, "Could not make a free bill number. Try again.", 503);
  const nowUtcMs = Date.now();
  const bill: DemoBill = {
    billNumber,
    billDate: indiaDateIso(nowUtcMs),
    generatedAtUtcMs: nowUtcMs,
    makerGstin: typed.makerGstin,
    invoiceNumber: typed.invoiceNumber,
    invoiceDate: typed.invoiceDate,
    transporterName: typed.transporterName,
    vehicleNumber: null,
    validUntilUtcMs: null,
  };
  billsByNumber.set(billNumber, bill);
  showGeneratedBill(res, bill);
}

// ---------- vehicle (Part B) ----------

type VehicleTyped = { billNumber: string; vehicleNumber: string; validUntil: string };

function showVehicleForm(res: ServerResponse, typed: VehicleTyped, errorMessage: string, status = 200): void {
  sendHtml(res, status, "Add a vehicle (Part B)", `<h1>Add a vehicle to a bill (Part B)</h1>${errorBox(errorMessage)}
<p>On the real portal only the person who made the bill, or the transporter named on it, can do this.</p>
<form method="post" action="/demo/eway-portal/vehicle">
${textField("E-way bill number", "billNumber", typed.billNumber)}
${textField("Vehicle number", "vehicleNumber", typed.vehicleNumber, "text", "For example KA01AB1234")}
${textField("Valid until", "validUntil", typed.validUntil, "datetime-local", "India time")}
<button type="submit">Add vehicle</button>
</form>`);
}

async function handleVehicle(req: IncomingMessage, res: ServerResponse): Promise<void> {
  if (req.method === "GET") return showVehicleForm(res, { billNumber: "", vehicleNumber: "", validUntil: "" }, "");
  if (req.method !== "POST") return sendMethodNotAllowed(res);
  const body = await readFormBody(req);
  if (body.outcome === "timedOut") return;
  if (body.outcome === "tooLarge") return sendTooLarge(req, res);
  const typed: VehicleTyped = {
    billNumber: (body.fields.get("billNumber") ?? "").trim(),
    vehicleNumber: (body.fields.get("vehicleNumber") ?? "").trim(),
    validUntil: (body.fields.get("validUntil") ?? "").trim(),
  };
  const bill = billsByNumber.get(cleanBillNumber(typed.billNumber));
  if (!bill) return showVehicleForm(res, typed, "No e-way bill with this number.", 404);
  const vehicleNumber = typed.vehicleNumber.replace(/[\s-]/g, "").toUpperCase();
  if (!/^[A-Z0-9]{6,12}$/.test(vehicleNumber)) {
    return showVehicleForm(res, typed, "The vehicle number is 6 to 12 letters and digits, for example KA01AB1234.", 400);
  }
  const validUntilUtcMs = parseIndiaDateTime(typed.validUntil);
  if (validUntilUtcMs === null) return showVehicleForm(res, typed, "Choose the date and time the bill is valid until.", 400);
  if (validUntilUtcMs <= Date.now()) return showVehicleForm(res, typed, "The valid-until time is in the past. Choose a later time.", 400);
  bill.vehicleNumber = vehicleNumber;
  bill.validUntilUtcMs = validUntilUtcMs;
  sendHtml(res, 200, "Vehicle added", `<h1>Vehicle added</h1>
<p class="number" style="font-size:1.4rem">Vehicle ${escapeHtml(vehicleNumber)} added. Valid until ${escapeHtml(formatIndiaDateTime(validUntilUtcMs))}.</p>
<p>Copy the vehicle number and the valid-until time into the naviG8r app.</p>
<p>On the real portal only the person who made the bill, or the transporter named on it, can do this.</p>`);
}

// ---------- check (look up) ----------

type CheckTyped = { number: string; billDate: string; gstin: string; invoiceNumber: string };

function checkFormHtml(typed: CheckTyped): string {
  return `<form method="get" action="/demo/eway-portal/check">
${textField("E-way bill number", "number", typed.number)}
${textField("Bill date", "billDate", typed.billDate, "date")}
${textField("GSTIN of whoever made the bill", "gstin", typed.gstin)}
${textField("Invoice number", "invoiceNumber", typed.invoiceNumber)}
<button type="submit">Look up</button>
</form>`;
}

function showCheck(res: ServerResponse, url: URL): void {
  const typed: CheckTyped = {
    number: (url.searchParams.get("number") ?? "").trim(),
    billDate: (url.searchParams.get("billDate") ?? "").trim(),
    gstin: (url.searchParams.get("gstin") ?? "").trim(),
    invoiceNumber: (url.searchParams.get("invoiceNumber") ?? "").trim(),
  };
  let resultHtml = "";
  if (url.searchParams.has("number")) {
    const bill = billsByNumber.get(cleanBillNumber(typed.number));
    const differing: string[] = [];
    if (bill) {
      if (bill.billDate !== typed.billDate) differing.push("bill date");
      if (bill.makerGstin !== typed.gstin.replace(/\s/g, "").toUpperCase()) differing.push("GSTIN");
      if (bill.invoiceNumber !== typed.invoiceNumber) differing.push("invoice number");
    }
    if (bill && differing.length === 0) {
      const vehicleLine = bill.vehicleNumber && bill.validUntilUtcMs !== null
        ? `<dt>Vehicle</dt><dd class="mono">${escapeHtml(bill.vehicleNumber)}</dd><dt>Valid until</dt><dd>${escapeHtml(formatIndiaDateTime(bill.validUntilUtcMs))}</dd>`
        : "<dt>Vehicle</dt><dd>No vehicle added yet</dd>";
      resultHtml = `<div class="box"><h2>Found (practice site)</h2><dl>
<dt>Bill number</dt><dd class="mono">${escapeHtml(groupsOfFour(bill.billNumber))}</dd>
<dt>Bill date</dt><dd>${escapeHtml(formatDay(bill.billDate))}</dd>
<dt>GSTIN</dt><dd class="mono">${escapeHtml(bill.makerGstin)}</dd>
<dt>Invoice number</dt><dd class="mono">${escapeHtml(bill.invoiceNumber)}</dd>
${vehicleLine}</dl></div>`;
    } else {
      const reason = bill ? ` The number exists, but the ${differing.join(" and the ")} ${differing.length > 1 ? "differ" : "differs"}.` : "";
      resultHtml = `<p class="error" role="alert">No e-way bill matches these four details.${escapeHtml(reason)}</p>`;
    }
  }
  sendHtml(res, 200, "Look up a bill", `<h1>Look up a bill</h1>
<p>Anyone with the four details can look a bill up: number, bill date, GSTIN and invoice number.</p>
${resultHtml}${checkFormHtml(typed)}`);
}

// ---------- guide ----------

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

function showGuide(req: IncomingMessage, res: ServerResponse): void {
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
</ul>
<h2>Which shipment to use</h2>
<ul>
<li>The seeded shipment load-a-with-bill already has a bill (1234 5678 9012) that this practice site knows, so ops can look it up and see a Found straight away.</li>
<li>The shipment load-a-booked has no bill yet. It is the first one the shipper adds a bill to by hand, and it is the one that follows this whole guide.</li>
</ul>
<h2>Step 1. Shipper adds the bill</h2>
<ol>
<li>Open <a href="${appAddress}/#/customer/shipments/load-a-booked">${appAddress}/#/customer/shipments/load-a-booked</a>. Its E-way bill card says No e-way bill added yet.</li>
<li>Tap Open the practice e-way bill portal. It opens this practice site in a new tab. (A build without the practice address says Open the government e-way bill portal and opens the real site.)</li>
<li>Choose <a href="/demo/eway-portal/generate">Generate a new e-way bill</a>. Use a GSTIN in the right shape, such as 29ABCDE1234F1Z5 (two digits, five letters, four digits, a letter, then a digit or letter, Z and a digit or letter), and any invoice number.</li>
<li>Name the carrier as the transporter, then tap Generate e-way bill.</li>
<li>Copy the bill number, the GSTIN and the invoice number, and note the date shown as Generated on.</li>
<li>Go back to the app tab and tap Add e-way bill. Paste the number, the GSTIN and the invoice number, then tap Bill date: choose the date and pick the day the practice site showed as Generated on. The practice site stamps that date itself, and ops' look-up needs all four details to match exactly.</li>
<li>Tap Save e-way bill. The card shows the number in groups of four and Entered by you. Not checked yet.</li>
</ol>
<h2>Step 2. Carrier (owner) adds the truck</h2>
<ol>
<li>Open the shipment in Shipments. The E-way bill card shows the bill number, Add truck and Open the practice e-way bill portal.</li>
<li>Tap Open the practice e-way bill portal and choose <a href="/demo/eway-portal/vehicle">Add a vehicle to a bill (Part B)</a>.</li>
<li>Type the bill number, vehicle KA01AB1234, and a valid-until time tomorrow, then tap Add vehicle.</li>
<li>Copy the vehicle number and note the valid-until time. It is India time.</li>
<li>Switch back to the app (on a phone, switch apps; nothing returns you automatically). Tap Add truck, paste the truck number, tap Valid until: choose the date and Time in India: choose the time to match the practice site, then tap Save truck.</li>
</ol>
<h2>Step 3. Ops checks the bill</h2>
<ol>
<li>Open <a href="/ops/beta">/ops/beta</a> and find E-way bills to check. Each row shows the four details with a Copy button on each.</li>
<li>Tap Open the government portal, then choose <a href="/demo/eway-portal/check">Look up a bill</a>.</li>
<li>Paste the four details from the row and tap Look up. The page says Found and shows the vehicle.</li>
<li>Back on the ops page, tap Mark as found on the portal.</li>
</ol>
<h2>Step 4. Driver reads it</h2>
<ol>
<li>Sign in as 8000000009 and open the shipment.</li>
<li>The driver's part is read only by design. The driver sees the bill number in large type, the truck, the valid-until time and the ops line, and once fewer than 12 hours are left, how many hours remain. There are no buttons.</li>
<li>At a check-post the driver quotes the bill number. The driver creates nothing and changes nothing.</li>
</ol>
<h2>Step 5. What to try next</h2>
<ol>
<li>As ops, look up the seeded bill on load-a-with-bill: number 123456789012, bill date 1 Oct 2026, GSTIN 29ABCDE1234F1Z5, invoice number SYN/2026/001. The page says Found, with no vehicle added yet.</li>
<li>As the shipper, edit the invoice number and watch the ops check clear.</li>
<li>Remove the bill.</li>
</ol>
<div class="box"><strong>What is real:</strong> the app, the checks and who sees what.
<strong>What is pretend:</strong> this site. The real portal cannot send data back to naviG8r, so people copy and paste.
The real portal's own login, captcha and rules are not shown here.</div>`);
}

// ---------- shared replies and routing ----------

function sendMethodNotAllowed(res: ServerResponse): void {
  sendHtml(res, 405, "Not allowed", "<h1>That is not allowed here</h1><p>This page takes a normal page visit or a form submit only.</p>");
}

function sendTooLarge(req: IncomingMessage, res: ServerResponse): void {
  sendHtml(res, 413, "Too large", "<h1>That form is too large</h1><p>Forms on this site are up to 8 KB. Shorten what you typed and try again.</p>", true);
  req.resume();
}

function withoutTrailingSlash(pathname: string): string {
  return pathname.length > 1 ? pathname.replace(/\/+$/, "") : pathname;
}

/** True only when the practice site is switched on and the path belongs to it. */
export function isEwayDemoPortalPath(pathname: string): boolean {
  if (process.env.EWAY_DEMO_PORTAL !== "1") return false;
  const path = withoutTrailingSlash(pathname);
  return path.startsWith("/demo/eway-portal") || path === "/demo/eway-guide";
}

/** Returns false, touching nothing, unless the practice site is switched on and the path belongs to it. */
export async function handleEwayDemoPortal(req: IncomingMessage, res: ServerResponse, url: URL): Promise<boolean> {
  if (!isEwayDemoPortalPath(url.pathname)) return false;
  const path = withoutTrailingSlash(url.pathname);
  addSeededBillOnce();

  if (path === "/demo/eway-guide") {
    if (req.method !== "GET") sendMethodNotAllowed(res);
    else showGuide(req, res);
    return true;
  }
  if (path === "/demo/eway-portal") {
    if (req.method !== "GET") sendMethodNotAllowed(res);
    else showHome(res);
  } else if (path === "/demo/eway-portal/generate") {
    await handleGenerate(req, res);
  } else if (path === "/demo/eway-portal/vehicle") {
    await handleVehicle(req, res);
  } else if (path === "/demo/eway-portal/check") {
    if (req.method !== "GET") sendMethodNotAllowed(res);
    else showCheck(res, url);
  } else {
    sendHtml(res, 404, "Page not found", "<h1>No such page on the practice site</h1>");
  }
  return true;
}
