import { lookup } from "node:dns/promises";
import { BlockList, isIP, type LookupFunction } from "node:net";

/** One sentence for every refused address, so the answer never says what a name resolves to inside a network. */
export const WEBHOOK_ADDRESS_REFUSED_SENTENCE = "This webhook address is not on the public internet, so it was not called.";

// Loopback, private, shared, link-local (where cloud metadata answers), multicast, documentation, benchmarking and
// reserved ranges, and the IPv6 forms that carry an IPv4 address inside (IPv4-compatible, NAT64, 6to4).
const blockedAddresses = new BlockList();
for (const [network, prefix] of [["0.0.0.0", 8], ["10.0.0.0", 8], ["100.64.0.0", 10], ["127.0.0.0", 8], ["169.254.0.0", 16], ["172.16.0.0", 12], ["192.0.0.0", 24], ["192.0.2.0", 24], ["192.168.0.0", 16], ["198.18.0.0", 15], ["198.51.100.0", 24], ["203.0.113.0", 24], ["224.0.0.0", 3]] as const) {
  blockedAddresses.addSubnet(network, prefix, "ipv4");
}
for (const [network, prefix] of [["::", 96], ["64:ff9b::", 96], ["2002::", 16], ["fc00::", 7], ["fe80::", 10], ["fec0::", 10], ["ff00::", 8]] as const) {
  blockedAddresses.addSubnet(network, prefix, "ipv6");
}

/** The DNS answer a webhook call checks before it is made. A test swaps it for fixed answers. */
export const webhookAddressLookup = {
  async addresses(hostname: string): Promise<string[]> {
    return (await lookup(hostname, { all: true })).map((answer) => answer.address);
  },
};

export type CheckedWebhookAddress = { address: string; family: 4 | 6 };

/**
 * Resolves the webhook's host once. Returns every address it resolved to, or null when the name does not resolve or
 * any address is blocked. With privateAllowed (NODE_ENV=test) nothing is blocked, so tests can reach this machine.
 */
export async function checkWebhookAddress(webhookUrl: string, privateAllowed: boolean): Promise<CheckedWebhookAddress[] | null> {
  const hostname = new URL(webhookUrl).hostname.replace(/^\[(.*)\]$/, "$1");
  let addresses: string[];
  try {
    addresses = isIP(hostname) ? [hostname] : await webhookAddressLookup.addresses(hostname);
  } catch {
    return null;
  }
  if (addresses.length === 0) return null;
  const checked = addresses.map((address): CheckedWebhookAddress => ({ address, family: isIP(address) === 6 ? 6 : 4 }));
  if (!privateAllowed && checked.some(({ address, family }) => blockedAddresses.check(address, family === 6 ? "ipv6" : "ipv4"))) return null;
  return checked;
}

/** The socket's own lookup, answering only the checked addresses, so the call goes where the check looked. */
export function lookupOnly(checked: CheckedWebhookAddress[]): LookupFunction {
  return (_hostname, options, callback) => {
    if (options.all) callback(null, checked);
    else callback(null, checked[0]!.address, checked[0]!.family);
  };
}
