/**
 * Routing for the practice e-way bill site used in product demos: it behaves like the real portal's rules so
 * shipper, carrier and ops can practise the copy-and-paste flow, and is served only when EWAY_DEMO_PORTAL=1.
 * The real portal cannot send data back to naviG8r, so nothing here talks to the rest of the app.
 */
import type { IncomingMessage, ServerResponse } from "node:http";
import { showGuide } from "./ewayDemoGuide.ts";
import {
  billDetailBody, cancelDoneBody, cancelFormBody, extendDoneBody, extendFormBody, generatedBillBody, generateFormBody,
  homeBody, refusalBody, securityHeaders, sendHtml, signInBody, signInNeededBody, vehicleDoneBody, vehicleFormBody, verifyBody,
} from "./ewayDemoPortalPages.ts";
import type { ExtendTyped, VehicleTyped } from "./ewayDemoPortalPages.ts";
import {
  cancelRefusal, cleanBillNumber, cleanGstin, cleanVehicleNumber, detailRefusal, extensionInputProblem, extensionRefusal,
  generateInputProblem, generateRefusal, indiaDateIso, parseDistanceKm, personaFromKey, validUpToAfterVehicleUpdate,
  validUpToUtcMs, vehicleInputProblem, vehicleUpdateRefusal, verifyBill,
} from "./ewayDemoPortalRules.ts";
import type { DemoBill, GenerateTyped, Persona } from "./ewayDemoPortalRules.ts";
import { addBill, findBill, newBillNumber } from "./ewayDemoPortalStore.ts";

export { SEEDED_TRUCK_VALID_UNTIL_UTC_MS } from "./ewayDemoPortalStore.ts";

const MAX_FORM_BODY_BYTES = 8 * 1024;
/** A form body not complete by then is dropped, so a slow sender cannot hold a connection open. */
export const FORM_BODY_TIMEOUT_MS = 5000;
const PERSONA_COOKIE = "eway_demo_persona";

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

/** Any cookie value that is not one of the three persona keys counts as signed out; the raw value is never printed. */
function personaFromRequest(req: IncomingMessage): Persona | null {
  for (const part of String(req.headers.cookie ?? "").split(";")) {
    const [name, ...rest] = part.trim().split("=");
    if (name === PERSONA_COOKIE) return personaFromKey(rest.join("="));
  }
  return null;
}

function sendMethodNotAllowed(res: ServerResponse, persona: Persona | null): void {
  sendHtml(res, 405, "Not allowed", "<h1>That is not allowed here</h1><p>This page takes a normal page visit or a form submit only.</p>", persona);
}

function sendTooLarge(req: IncomingMessage, res: ServerResponse, persona: Persona | null): void {
  sendHtml(res, 413, "Too large", "<h1>That form is too large</h1><p>Forms on this site are up to 8 KB. Shorten what you typed and try again.</p>", persona, true);
  req.resume();
}

/**
 * Every POST reads its body before looking at who is signed in: a refusal sent mid-body would leave a trickling
 * sender's connection open past the timeout.
 */
async function readPostedForm(req: IncomingMessage, res: ServerResponse, persona: Persona | null): Promise<URLSearchParams | null> {
  const body = await readFormBody(req);
  if (body.outcome === "timedOut") return null;
  if (body.outcome === "tooLarge") {
    sendTooLarge(req, res, persona);
    return null;
  }
  return body.fields;
}

function field(fields: URLSearchParams, name: string): string {
  return (fields.get(name) ?? "").trim();
}

// ---------- sign-in ----------

async function handleSignIn(req: IncomingMessage, res: ServerResponse, persona: Persona | null): Promise<void> {
  if (req.method === "GET") return sendHtml(res, 200, "Choose who you are", signInBody(), persona);
  if (req.method !== "POST") return sendMethodNotAllowed(res, persona);
  const fields = await readPostedForm(req, res, persona);
  if (!fields) return;
  const chosen = personaFromKey(field(fields, "persona"));
  if (!chosen) return sendHtml(res, 400, "Choose who you are", refusalBody("Choose who you are", "Pick one of the three practice users.") + signInBody(), persona);
  res.writeHead(303, {
    location: "/demo/eway-portal",
    "set-cookie": `${PERSONA_COOKIE}=${chosen.key}; Path=/demo; HttpOnly; SameSite=Lax`,
    "content-length": 0,
    ...securityHeaders(),
  });
  res.end();
}

// ---------- generate ----------

async function handleGenerate(req: IncomingMessage, res: ServerResponse, persona: Persona | null): Promise<void> {
  const blank: GenerateTyped = {
    supplierGstin: persona?.key === "supplier" ? persona.id : "", recipientGstin: "", dispatchPin: "", deliveryPin: "", documentNumber: "",
    documentDate: "", goodsValueRupees: "", hsnCode: "", transportReason: "", vehicleNumber: "", distanceKm: "", transporterId: "",
  };
  if (req.method !== "GET" && req.method !== "POST") return sendMethodNotAllowed(res, persona);
  const fields = req.method === "POST" ? await readPostedForm(req, res, persona) : new URLSearchParams();
  if (!fields) return;
  if (!persona) return sendHtml(res, 401, "Choose who you are first", signInNeededBody(), persona);
  const refusal = generateRefusal(persona);
  if (refusal) return sendHtml(res, 403, "Not allowed to generate", refusalBody("You cannot generate an e-way bill", refusal), persona);
  if (req.method === "GET") return sendHtml(res, 200, "Generate an e-way bill", generateFormBody(blank, ""), persona);

  const typed: GenerateTyped = {
    supplierGstin: cleanGstin(field(fields, "supplierGstin")),
    recipientGstin: cleanGstin(field(fields, "recipientGstin")),
    dispatchPin: field(fields, "dispatchPin"),
    deliveryPin: field(fields, "deliveryPin"),
    documentNumber: field(fields, "documentNumber"),
    documentDate: field(fields, "documentDate"),
    goodsValueRupees: field(fields, "goodsValueRupees"),
    hsnCode: field(fields, "hsnCode"),
    transportReason: field(fields, "transportReason"),
    vehicleNumber: cleanVehicleNumber(field(fields, "vehicleNumber")),
    distanceKm: field(fields, "distanceKm"),
    transporterId: cleanGstin(field(fields, "transporterId")) || (persona.key === "transporter" ? persona.id : ""),
  };
  const nowUtcMs = Date.now();
  const problem = generateInputProblem(typed, persona, nowUtcMs);
  if (problem) return sendHtml(res, 400, "Generate an e-way bill", generateFormBody(typed, problem), persona);
  const billNumber = newBillNumber();
  if (!billNumber) return sendHtml(res, 503, "Generate an e-way bill", generateFormBody(typed, "Could not make a free bill number. Try again."), persona);
  const distanceKm = parseDistanceKm(typed.distanceKm) ?? 1;
  const bill: DemoBill = {
    billNumber,
    billDate: indiaDateIso(nowUtcMs),
    generatedAtUtcMs: nowUtcMs,
    generatorId: persona.id,
    supplierGstin: typed.supplierGstin,
    recipientGstin: typed.recipientGstin,
    dispatchPin: typed.dispatchPin,
    deliveryPin: typed.deliveryPin,
    documentNumber: typed.documentNumber,
    documentDate: typed.documentDate,
    goodsValueRupees: typed.goodsValueRupees,
    hsnCode: typed.hsnCode,
    transportReason: typed.transportReason,
    transporterId: typed.transporterId,
    distanceKm,
    vehicleUpdates: typed.vehicleNumber
      ? [{ vehicleNumber: typed.vehicleNumber, reasonCode: "4", remark: "", byPersonaKey: persona.key, atUtcMs: nowUtcMs }]
      : [],
    extensions: [],
    validUpToUtcMs: typed.vehicleNumber ? validUpToUtcMs(nowUtcMs, distanceKm) : null,
    cancelledAtUtcMs: null,
  };
  addBill(bill);
  sendHtml(res, 200, "E-way bill generated", generatedBillBody(bill), persona);
}

// ---------- vehicle, extension, cancel ----------

async function handleVehicle(req: IncomingMessage, res: ServerResponse, persona: Persona | null): Promise<void> {
  if (req.method !== "GET" && req.method !== "POST") return sendMethodNotAllowed(res, persona);
  const fields = req.method === "POST" ? await readPostedForm(req, res, persona) : new URLSearchParams();
  if (!fields) return;
  if (!persona) return sendHtml(res, 401, "Choose who you are first", signInNeededBody(), persona);
  const typed: VehicleTyped = { billNumber: field(fields, "billNumber"), vehicleNumber: field(fields, "vehicleNumber"), reasonCode: field(fields, "reasonCode"), remark: field(fields, "remark") };
  if (req.method === "GET") return sendHtml(res, 200, "Update vehicle (Part B)", vehicleFormBody(typed, ""), persona);
  const bill = findBill(cleanBillNumber(typed.billNumber));
  if (!bill) return sendHtml(res, 404, "Update vehicle (Part B)", vehicleFormBody(typed, "No e-way bill with this number."), persona);
  const vehicleNumber = cleanVehicleNumber(typed.vehicleNumber);
  const nowUtcMs = Date.now();
  const problem = vehicleInputProblem(vehicleNumber, typed.reasonCode, typed.remark);
  if (problem) return sendHtml(res, 400, "Update vehicle (Part B)", vehicleFormBody(typed, problem), persona);
  const refusal = vehicleUpdateRefusal(bill, persona, typed.reasonCode, nowUtcMs);
  if (refusal) return sendHtml(res, 403, "Update vehicle (Part B)", vehicleFormBody(typed, refusal), persona);
  bill.validUpToUtcMs = validUpToAfterVehicleUpdate(bill, nowUtcMs);
  bill.vehicleUpdates.push({ vehicleNumber, reasonCode: typed.reasonCode, remark: typed.remark, byPersonaKey: persona.key, atUtcMs: nowUtcMs });
  sendHtml(res, 200, "Vehicle updated", vehicleDoneBody(bill), persona);
}

async function handleExtend(req: IncomingMessage, res: ServerResponse, persona: Persona | null): Promise<void> {
  if (req.method !== "GET" && req.method !== "POST") return sendMethodNotAllowed(res, persona);
  const fields = req.method === "POST" ? await readPostedForm(req, res, persona) : new URLSearchParams();
  if (!fields) return;
  if (!persona) return sendHtml(res, 401, "Choose who you are first", signInNeededBody(), persona);
  const typed: ExtendTyped = { billNumber: field(fields, "billNumber"), reasonCode: field(fields, "reasonCode"), remark: field(fields, "remark"), remainingDistanceKm: field(fields, "remainingDistanceKm") };
  if (req.method === "GET") return sendHtml(res, 200, "Extend validity", extendFormBody(typed, ""), persona);
  const bill = findBill(cleanBillNumber(typed.billNumber));
  if (!bill) return sendHtml(res, 404, "Extend validity", extendFormBody(typed, "No e-way bill with this number."), persona);
  const problem = extensionInputProblem(typed.reasonCode, typed.remark, typed.remainingDistanceKm);
  if (problem) return sendHtml(res, 400, "Extend validity", extendFormBody(typed, problem), persona);
  const nowUtcMs = Date.now();
  const refusal = extensionRefusal(bill, persona, nowUtcMs);
  if (refusal) return sendHtml(res, 403, "Extend validity", extendFormBody(typed, refusal), persona);
  const remainingDistanceKm = parseDistanceKm(typed.remainingDistanceKm) ?? 1;
  const newValidUpToUtcMs = validUpToUtcMs(nowUtcMs, remainingDistanceKm);
  bill.extensions.push({ reasonCode: typed.reasonCode, remark: typed.remark, remainingDistanceKm, atUtcMs: nowUtcMs, validUpToUtcMs: newValidUpToUtcMs });
  bill.validUpToUtcMs = newValidUpToUtcMs;
  sendHtml(res, 200, "Validity extended", extendDoneBody(bill), persona);
}

async function handleCancel(req: IncomingMessage, res: ServerResponse, persona: Persona | null): Promise<void> {
  if (req.method !== "GET" && req.method !== "POST") return sendMethodNotAllowed(res, persona);
  const fields = req.method === "POST" ? await readPostedForm(req, res, persona) : new URLSearchParams();
  if (!fields) return;
  if (!persona) return sendHtml(res, 401, "Choose who you are first", signInNeededBody(), persona);
  const typedNumber = field(fields, "billNumber");
  if (req.method === "GET") return sendHtml(res, 200, "Cancel an e-way bill", cancelFormBody(typedNumber, ""), persona);
  const bill = findBill(cleanBillNumber(typedNumber));
  if (!bill) return sendHtml(res, 404, "Cancel an e-way bill", cancelFormBody(typedNumber, "No e-way bill with this number."), persona);
  const nowUtcMs = Date.now();
  const refusal = cancelRefusal(bill, persona, nowUtcMs);
  if (refusal) return sendHtml(res, 403, "Cancel an e-way bill", cancelFormBody(typedNumber, refusal), persona);
  bill.cancelledAtUtcMs = nowUtcMs;
  sendHtml(res, 200, "E-way bill cancelled", cancelDoneBody(bill), persona);
}

// ---------- detail and verify ----------

function showBillDetail(res: ServerResponse, url: URL, persona: Persona | null): void {
  if (!persona) return sendHtml(res, 401, "Choose who you are first", signInNeededBody(), persona);
  const bill = findBill(cleanBillNumber(url.searchParams.get("number") ?? ""));
  if (!bill) return sendHtml(res, 404, "No such bill", refusalBody("No such bill", "No e-way bill with this number."), persona);
  const refusal = detailRefusal(bill, persona);
  if (refusal) return sendHtml(res, 403, "Not your bill", refusalBody("You cannot see this bill", refusal), persona);
  sendHtml(res, 200, "E-way bill details", billDetailBody(bill), persona);
}

function showVerify(res: ServerResponse, url: URL, persona: Persona | null): void {
  const typed = {
    billNumber: (url.searchParams.get("number") ?? "").trim(),
    billDate: (url.searchParams.get("billDate") ?? "").trim(),
    supplierGstin: (url.searchParams.get("gstin") ?? "").trim(),
    documentNumber: (url.searchParams.get("invoiceNumber") ?? "").trim(),
  };
  let looked = null;
  if (url.searchParams.has("number")) {
    const bill = findBill(cleanBillNumber(typed.billNumber));
    looked = { bill, result: verifyBill(bill, typed) };
  }
  sendHtml(res, 200, "Verify an e-way bill", verifyBody(typed, looked), persona);
}

// ---------- routing ----------

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
  const persona = personaFromRequest(req);
  const isGet = req.method === "GET";

  if (path === "/demo/eway-guide") {
    if (isGet) showGuide(req, res, persona);
    else sendMethodNotAllowed(res, persona);
  } else if (path === "/demo/eway-portal") {
    if (isGet) sendHtml(res, 200, "E-way bill practice site", homeBody(), persona);
    else sendMethodNotAllowed(res, persona);
  } else if (path === "/demo/eway-portal/sign-in") {
    await handleSignIn(req, res, persona);
  } else if (path === "/demo/eway-portal/generate") {
    await handleGenerate(req, res, persona);
  } else if (path === "/demo/eway-portal/vehicle") {
    await handleVehicle(req, res, persona);
  } else if (path === "/demo/eway-portal/extend") {
    await handleExtend(req, res, persona);
  } else if (path === "/demo/eway-portal/cancel") {
    await handleCancel(req, res, persona);
  } else if (path === "/demo/eway-portal/bill") {
    if (isGet) showBillDetail(res, url, persona);
    else sendMethodNotAllowed(res, persona);
  } else if (path === "/demo/eway-portal/check") {
    if (isGet) showVerify(res, url, persona);
    else sendMethodNotAllowed(res, persona);
  } else {
    sendHtml(res, 404, "Page not found", "<h1>No such page on the practice site</h1>", persona);
  }
  return true;
}
