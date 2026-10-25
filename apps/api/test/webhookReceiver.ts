import dns from "node:dns";
import http from "node:http";
import { once } from "node:events";
import { mock, type TestContext } from "node:test";
import type { AddressInfo } from "node:net";

/** Made-up public answers for the host names the webhook tests use; any other name does not resolve. */
const TEST_ADDRESSES: Record<string, string[]> = {
  "erp.example.com": ["93.184.215.14"],
  "internal.example.com": ["10.1.2.3"],
  "mixed.example.com": ["93.184.215.14", "127.0.0.1"],
};

/** Answers DNS lookups from TEST_ADDRESSES and counts them; a name not listed fails like a real unknown name. */
export function mockWebhookAddressLookup(t: TestContext, addresses: Record<string, string[]> = TEST_ADDRESSES) {
  const lookups: string[] = [];
  const lookupMock = mock.method(dns.promises, "lookup", async (host: string) => {
    lookups.push(host);
    const found = addresses[host];
    if (!found) throw Object.assign(new Error(`getaddrinfo ENOTFOUND ${host}`), { code: "ENOTFOUND" });
    return found.map((address) => ({ address, family: address.includes(":") ? 6 : 4 }));
  });
  t.after(() => lookupMock.mock.restore());
  return { lookups };
}

/**
 * A local server that stands in for the shipper's webhook host. Each outgoing http.request first asks the
 * sender's own lookup option which address it would connect to (recorded in connectedTo), then is sent here.
 */
export async function webhookReceiver(t: TestContext, handle: http.RequestListener) {
  const server = http.createServer(handle);
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  t.after(async () => {
    server.closeAllConnections();
    await new Promise<void>((resolve) => server.close(() => resolve()));
  });
  const port = (server.address() as AddressInfo).port;
  const realRequest = http.request;
  const connectedTo: string[] = [];
  const requestMock = mock.method(http, "request", (options: http.RequestOptions, callback: (res: http.IncomingMessage) => void) => {
    options.lookup?.(String(options.hostname), {}, (_error: unknown, address: unknown) => connectedTo.push(String(address)));
    return realRequest({ ...options, hostname: "127.0.0.1", port, lookup: undefined }, callback);
  });
  t.after(() => requestMock.mock.restore());
  return { connectedTo };
}
