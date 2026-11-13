import dns from "node:dns";
import http from "node:http";
import https from "node:https";
import net from "node:net";

/** The one answer for a blocked address and for a name that does not resolve, so neither tells the caller more. */
export const WEBHOOK_ADDRESS_NOT_ALLOWED = "The webhook address must resolve to a public internet address.";

/**
 * This network, loopback, private, shared (carrier NAT), link-local, special-purpose, documentation, benchmarking
 * and reserved ranges, plus IPv6 forms that carry an IPv4 address (IPv4-compatible, NAT64, 6to4) and old site-local.
 * Cloud metadata services sit in these ranges.
 */
const NON_PUBLIC_ADDRESSES = new net.BlockList();
NON_PUBLIC_ADDRESSES.addSubnet("0.0.0.0", 8, "ipv4");
NON_PUBLIC_ADDRESSES.addSubnet("10.0.0.0", 8, "ipv4");
NON_PUBLIC_ADDRESSES.addSubnet("100.64.0.0", 10, "ipv4");
NON_PUBLIC_ADDRESSES.addSubnet("127.0.0.0", 8, "ipv4");
NON_PUBLIC_ADDRESSES.addSubnet("169.254.0.0", 16, "ipv4");
NON_PUBLIC_ADDRESSES.addSubnet("172.16.0.0", 12, "ipv4");
NON_PUBLIC_ADDRESSES.addSubnet("192.0.0.0", 24, "ipv4");
NON_PUBLIC_ADDRESSES.addSubnet("192.0.2.0", 24, "ipv4");
NON_PUBLIC_ADDRESSES.addSubnet("192.168.0.0", 16, "ipv4");
NON_PUBLIC_ADDRESSES.addSubnet("198.18.0.0", 15, "ipv4");
NON_PUBLIC_ADDRESSES.addSubnet("198.51.100.0", 24, "ipv4");
NON_PUBLIC_ADDRESSES.addSubnet("203.0.113.0", 24, "ipv4");
NON_PUBLIC_ADDRESSES.addSubnet("240.0.0.0", 4, "ipv4");
NON_PUBLIC_ADDRESSES.addSubnet("::", 96, "ipv6");
NON_PUBLIC_ADDRESSES.addSubnet("64:ff9b::", 96, "ipv6");
NON_PUBLIC_ADDRESSES.addSubnet("2002::", 16, "ipv6");
NON_PUBLIC_ADDRESSES.addSubnet("fc00::", 7, "ipv6");
NON_PUBLIC_ADDRESSES.addSubnet("fe80::", 10, "ipv6");
NON_PUBLIC_ADDRESSES.addSubnet("fec0::", 10, "ipv6");

const MAX_WEBHOOK_ERROR_BODY_BYTES = 4 * 1024;
const WEBHOOK_TIMEOUT_MS = 30_000;

type CheckedAddress = { address: string; family: 4 | 6 };

/** The first address the host resolves to, or null unless every address it resolves to is public. */
async function checkedPublicAddress(host: string): Promise<CheckedAddress | null> {
  let addresses: { address: string; family: number }[];
  if (net.isIP(host)) addresses = [{ address: host, family: net.isIP(host) }];
  else {
    try {
      addresses = await dns.promises.lookup(host, { all: true });
    } catch {
      return null;
    }
  }
  if (!addresses.length) return null;
  if (addresses.some((a) => NON_PUBLIC_ADDRESSES.check(a.address, a.family === 6 ? "ipv6" : "ipv4"))) return null;
  return { address: addresses[0]!.address, family: addresses[0]!.family === 6 ? 6 : 4 };
}

/**
 * POSTs one webhook to the exact public address its host name resolved to: the socket's own lookup hands back
 * that checked address, so the name is never resolved twice. The URL host name still goes to TLS for the
 * certificate check. Redirects are not followed; a 3xx is a failed delivery. Of a failed reply, only the start is read.
 */
export async function postWebhookToPublicAddress(
  webhookUrl: string,
  headers: Record<string, string>,
  body: string,
): Promise<{ ok: boolean; httpStatus: number; error?: string }> {
  const url = new URL(webhookUrl);
  const host = url.hostname.replace(/^\[|\]$/g, "");
  const checked = await checkedPublicAddress(host);
  if (!checked) return { ok: false, httpStatus: 0, error: WEBHOOK_ADDRESS_NOT_ALLOWED };

  const transport = url.protocol === "https:" ? https : http;
  return new Promise((resolve) => {
    let settled = false;
    const finish = (result: { ok: boolean; httpStatus: number; error?: string }) => {
      if (settled) return;
      settled = true;
      resolve(result);
    };
    const request = transport.request(
      {
        method: "POST",
        hostname: host,
        port: url.port || undefined,
        path: `${url.pathname}${url.search}`,
        headers: { ...headers, "content-length": String(Buffer.byteLength(body)) },
        lookup: (_hostname, options, callback) => {
          if (options.all) callback(null, [checked]);
          else callback(null, checked.address, checked.family);
        },
        signal: AbortSignal.timeout(WEBHOOK_TIMEOUT_MS),
      },
      (response) => {
        const status = response.statusCode ?? 0;
        if (status >= 200 && status < 300) {
          finish({ ok: true, httpStatus: status });
          response.destroy();
          return;
        }
        const chunks: Buffer[] = [];
        let byteLength = 0;
        const finishWithText = () => {
          const text = Buffer.concat(chunks).subarray(0, MAX_WEBHOOK_ERROR_BODY_BYTES).toString("utf8");
          finish({ ok: false, httpStatus: status, error: text.slice(0, 500) || response.statusMessage || "" });
        };
        response.on("data", (chunk: Buffer) => {
          chunks.push(chunk);
          byteLength += chunk.length;
          if (byteLength >= MAX_WEBHOOK_ERROR_BODY_BYTES) {
            finishWithText();
            response.destroy();
          }
        });
        response.on("end", finishWithText);
        response.on("close", finishWithText);
        response.on("error", finishWithText);
      },
    );
    request.on("error", (e: Error) => finish({ ok: false, httpStatus: 0, error: String(e?.message ?? e) }));
    request.end(body);
  });
}
