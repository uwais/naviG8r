import test from "node:test";
import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import { httpFixture } from "../test/httpFixtures.ts";

const webhookSecret = "synthetic-webhook-secret";

function withWebhookSecret(t: { after(fn: () => void): void }): void {
  const previous = process.env.RAZORPAY_WEBHOOK_SECRET;
  process.env.RAZORPAY_WEBHOOK_SECRET = webhookSecret;
  t.after(() => {
    if (previous === undefined) delete process.env.RAZORPAY_WEBHOOK_SECRET;
    else process.env.RAZORPAY_WEBHOOK_SECRET = previous;
  });
}

async function send(base: string, path: string, method: string, body: string, headers: Record<string, string>) {
  const response = await fetch(base + path, { method, headers: { "content-type": "application/json", ...headers }, body });
  return { status: response.status, body: await response.json() };
}

test("the Razorpay webhook takes a body of up to 256 KB; a larger one is answered 413", async t => {
  withWebhookSecret(t);
  const f = await httpFixture(t);
  const tooLarge = JSON.stringify({ event: "payment.authorized", padding: "x".repeat(256 * 1024) });
  const signature = createHmac("sha256", webhookSecret).update(tooLarge).digest("hex");
  const refused = await send(f.base, "/v1/payments/razorpay/webhook", "POST", tooLarge, { "x-razorpay-signature": signature });
  assert.deepEqual([refused.status, refused.body.error], [413, "payload_too_large"]);

  const small = JSON.stringify({ event: "payment.authorized", padding: "x".repeat(1024) });
  const unsigned = await send(f.base, "/v1/payments/razorpay/webhook", "POST", small, { "x-razorpay-signature": "0".repeat(64) });
  assert.deepEqual([unsigned.status, unsigned.body.error], [401, "invalid_webhook_signature"], "a body under the cap still has its signature checked");
});

test("the ERP and integration settings routes take a body of up to 1 MB; a larger one is answered 413", async t => {
  const f = await httpFixture(t);
  const orgId = f.shipperA.org.id;
  const shipper = { authorization: `Bearer ${f.tokens.shipperA}` };
  const key = await send(f.base, `/v1/pilot/customer/integrations/keys?orgId=${orgId}`, "POST", JSON.stringify({ scopes: ["loads:read", "loads:write"] }), shipper);
  assert.equal(key.status, 201);

  const tooLarge = JSON.stringify({ displayName: "x".repeat(1024 * 1024) });
  const settings = await send(f.base, `/v1/pilot/customer/integrations/connection?orgId=${orgId}`, "PATCH", tooLarge, shipper);
  assert.deepEqual([settings.status, settings.body.error], [413, "payload_too_large"]);

  const load = await send(f.base, "/v1/integrations/loads", "POST", tooLarge, { authorization: `Bearer ${key.body.token}` });
  assert.deepEqual([load.status, load.body.error], [413, "payload_too_large"]);

  const small = await send(f.base, `/v1/pilot/customer/integrations/connection?orgId=${orgId}`, "PATCH", JSON.stringify({ displayName: "Synthetic ERP" }), shipper);
  assert.deepEqual([small.status, small.body.connection.displayName], [200, "Synthetic ERP"]);
});
