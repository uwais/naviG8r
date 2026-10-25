import assert from "node:assert/strict";
import test from "node:test";
import { checkWebhookAddress, lookupOnly, webhookAddressLookup } from "./integrationWebhookAddress.ts";

function answering(t: { after(fn: () => void): void }, answers: Record<string, string[]>): void {
  const before = webhookAddressLookup.addresses;
  webhookAddressLookup.addresses = async (hostname) => {
    const found = answers[hostname];
    if (!found) throw Object.assign(new Error(`getaddrinfo ENOTFOUND ${hostname}`), { code: "ENOTFOUND" });
    return found;
  };
  t.after(() => { webhookAddressLookup.addresses = before; });
}

test("documentation, benchmarking, reserved and IPv4-carrying IPv6 answers are refused", async t => {
  const blocked = ["64:ff9b::7f00:1", "2002:7f00:1::1", "::7f00:1", "fec0::1", "192.0.0.8", "198.18.0.1", "198.19.255.1", "240.0.0.1", "192.0.2.1", "198.51.100.1", "203.0.113.1"];
  answering(t, Object.fromEntries(blocked.map((address, index) => [`blocked${index}.example.com`, [address]])));
  for (const [index, address] of blocked.entries()) {
    assert.equal(await checkWebhookAddress(`https://blocked${index}.example.com/hook`, false), null, address);
  }
});

test("a name that does not resolve is refused like a private one, and an address literal needs no lookup", async t => {
  answering(t, {});
  assert.equal(await checkWebhookAddress("https://missing.example.com/hook", false), null);
  assert.deepEqual(await checkWebhookAddress("https://93.184.216.34/hook", false), [{ address: "93.184.216.34", family: 4 }]);
  assert.equal(await checkWebhookAddress("http://[::7f00:1]/hook", false), null);
});

test("a public name passes with every address it resolved to, and the socket lookup answers only those", async t => {
  answering(t, { "public.example.com": ["93.184.216.34", "2606:2800:220:1:248:1893:25c8:1946"] });
  const checked = await checkWebhookAddress("https://public.example.com/hook", false);
  assert.deepEqual(checked, [{ address: "93.184.216.34", family: 4 }, { address: "2606:2800:220:1:248:1893:25c8:1946", family: 6 }]);

  const lookup = lookupOnly(checked!);
  const all = await new Promise((resolve) => lookup("public.example.com", { all: true }, (_error, addresses) => resolve(addresses)));
  assert.deepEqual(all, checked);
  const one = await new Promise((resolve) => lookup("public.example.com", {}, (_error, address, family) => resolve([address, family])));
  assert.deepEqual(one, ["93.184.216.34", 4]);
});

test("with private addresses allowed (NODE_ENV=test) a loopback answer passes", async t => {
  answering(t, { "webhook.invalid": ["127.0.0.1"] });
  assert.deepEqual(await checkWebhookAddress("http://webhook.invalid:9/hook", true), [{ address: "127.0.0.1", family: 4 }]);
  assert.equal(await checkWebhookAddress("http://webhook.invalid:9/hook", false), null);
});
