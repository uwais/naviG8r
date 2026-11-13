import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import https from "node:https";
import test, { mock } from "node:test";
import { postWebhookToPublicAddress, WEBHOOK_ADDRESS_NOT_ALLOWED } from "./integrationWebhookAddress.ts";
import { mockWebhookAddressLookup, webhookReceiver } from "../test/webhookReceiver.ts";

const JSON_HEADERS = { "content-type": "application/json" };

test("a webhook is sent only to a public address, with one sentence for every refusal", async (t) => {
  mockWebhookAddressLookup(t);
  const received: string[] = [];
  await webhookReceiver(t, (req, res) => {
    received.push(String(req.url));
    res.end("ok");
  });
  for (const url of [
    "http://127.0.0.1:3000/hook",
    "http://0.0.0.0/hook",
    "http://[::1]/hook",
    "http://[::]/hook",
    "http://[::ffff:127.0.0.1]/hook",
    "http://[::7f00:1]/hook",
    "http://10.0.0.5/hook",
    "http://172.16.0.1/hook",
    "http://192.168.1.1/hook",
    "http://100.100.100.200/hook",
    "http://169.254.169.254/latest/meta-data",
    "http://192.0.0.8/hook",
    "http://192.0.2.10/hook",
    "http://198.18.0.1/hook",
    "http://198.19.255.1/hook",
    "http://198.51.100.7/hook",
    "http://203.0.113.9/hook",
    "http://240.0.0.1/hook",
    "http://255.255.255.255/hook",
    "http://[fe80::1]/hook",
    "http://[fd00:ec2::254]/hook",
    "http://[fec0::1]/hook",
    "http://[64:ff9b::a00:1]/hook",
    "http://[2002:a00:1::1]/hook",
    "https://internal.example.com/hook",
    "https://mixed.example.com/hook",
    "https://no-such-name.example.com/hook",
  ]) {
    const result = await postWebhookToPublicAddress(url, JSON_HEADERS, "{}");
    assert.deepEqual(result, { ok: false, httpStatus: 0, error: WEBHOOK_ADDRESS_NOT_ALLOWED }, url);
  }
  assert.equal(WEBHOOK_ADDRESS_NOT_ALLOWED, "The webhook address must resolve to a public internet address.");
  assert.deepEqual(received, []);

  const result = await postWebhookToPublicAddress("http://erp.example.com/hook?ref=1", JSON_HEADERS, "{}");
  assert.equal(result.ok, true);
  assert.deepEqual(received, ["/hook?ref=1"]);
});

test("a webhook connects to the address that passed the check, without a second lookup", async (t) => {
  const { lookups } = mockWebhookAddressLookup(t);
  const { connectedTo } = await webhookReceiver(t, (_req, res) => res.end("ok"));

  const result = await postWebhookToPublicAddress("http://erp.example.com/hook", JSON_HEADERS, "{}");
  assert.equal(result.ok, true);
  assert.deepEqual(lookups, ["erp.example.com"]);
  assert.deepEqual(connectedTo, ["93.184.215.14"]);
});

test("an HTTPS webhook keeps its host name for the certificate check while connecting to the checked address", async (t) => {
  mockWebhookAddressLookup(t);
  let sent: https.RequestOptions | undefined;
  let lookedUp: unknown;
  const requestMock = mock.method(https, "request", (options: https.RequestOptions) => {
    sent = options;
    options.lookup?.(String(options.hostname), { all: true }, (_error: unknown, addresses: unknown) => { lookedUp = addresses; });
    const fakeRequest = Object.assign(new EventEmitter(), {
      end: () => setImmediate(() => fakeRequest.emit("error", new Error("test stops here"))),
    });
    return fakeRequest;
  });
  t.after(() => requestMock.mock.restore());

  const result = await postWebhookToPublicAddress("https://erp.example.com/hook", JSON_HEADERS, "{}");
  assert.deepEqual(result, { ok: false, httpStatus: 0, error: "test stops here" });
  assert.equal(sent?.hostname, "erp.example.com");
  assert.equal(sent?.servername, undefined);
  assert.equal(sent?.rejectUnauthorized, undefined);
  assert.deepEqual(lookedUp, [{ address: "93.184.215.14", family: 4 }]);
});

test("a webhook redirect is not followed and counts as a failed delivery", async (t) => {
  mockWebhookAddressLookup(t);
  const received: string[] = [];
  await webhookReceiver(t, (req, res) => {
    received.push(String(req.url));
    res.writeHead(302, { location: "http://erp.example.com/elsewhere" });
    res.end();
  });
  const result = await postWebhookToPublicAddress("http://erp.example.com/hook", JSON_HEADERS, "{}");
  assert.equal(result.ok, false);
  assert.equal(result.httpStatus, 302);
  assert.deepEqual(received, ["/hook"]);
});

test("only the start of a failed webhook reply is read", async (t) => {
  mockWebhookAddressLookup(t);
  const chunk = "x".repeat(64 * 1024);
  let bytesWritten = 0;
  await webhookReceiver(t, (_req, res) => {
    res.writeHead(500);
    const writeMore = () => {
      while (bytesWritten < 50 * 1024 * 1024 && !res.destroyed) {
        bytesWritten += chunk.length;
        if (!res.write(chunk)) return res.once("drain", writeMore);
      }
      res.end();
    };
    writeMore();
  });
  const result = await postWebhookToPublicAddress("http://erp.example.com/hook", JSON_HEADERS, "{}");
  assert.equal(result.ok, false);
  assert.equal(result.httpStatus, 500);
  assert.equal(result.error, "x".repeat(500));
  assert.ok(bytesWritten < 50 * 1024 * 1024, `the reply was read to the end (${bytesWritten} bytes)`);
});
