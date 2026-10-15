/**
 * Reading a form posted to the practice e-way bill site: the body within a size and time limit, refused when it was
 * sent from another site.
 */
import type { IncomingMessage, ServerResponse } from "node:http";
import { sendHtml } from "./ewayDemoPortalPages.ts";
import type { Persona } from "./ewayDemoPortalRules.ts";

const MAX_FORM_BODY_BYTES = 8 * 1024;
/** A form body not complete by then is dropped, so a slow sender cannot hold a connection open. */
export const FORM_BODY_TIMEOUT_MS = 5000;

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

/** The rest of the body is never read: the connection is closed once the refusal is out, however much is still coming. */
function sendTooLarge(req: IncomingMessage, res: ServerResponse, persona: Persona | null): void {
  res.on("finish", () => req.socket.destroy());
  sendHtml(res, 413, "Too large", "<h1>Practice site: that form is too large</h1><p>Forms on this site are up to 8 KB. Shorten what you typed and try again.</p>", persona, true);
}

/** A browser always names the page a form came from; a form posted from another site could act as the signed-in user. */
function sentFromAnotherSite(req: IncomingMessage): boolean {
  const origin = req.headers.origin;
  if (origin === undefined) return false;
  try {
    return new URL(origin).host.toLowerCase() !== String(req.headers.host ?? "").toLowerCase();
  } catch {
    return true;
  }
}

/**
 * Every POST reads its body before looking at who is signed in or where it came from: a refusal sent mid-body would
 * leave a trickling sender's connection open past the timeout.
 */
export async function readPostedForm(req: IncomingMessage, res: ServerResponse, persona: Persona | null): Promise<URLSearchParams | null> {
  const body = await readFormBody(req);
  if (body.outcome === "timedOut") return null;
  if (body.outcome === "tooLarge") {
    sendTooLarge(req, res, persona);
    return null;
  }
  if (sentFromAnotherSite(req)) {
    sendHtml(res, 403, "Not allowed", "<h1>Practice site: form refused</h1><p>This form was not accepted because it came from a different site. Open the practice site again and resubmit.</p>", persona);
    return null;
  }
  return body.fields;
}

export function field(fields: URLSearchParams, name: string): string {
  return (fields.get(name) ?? "").trim();
}
