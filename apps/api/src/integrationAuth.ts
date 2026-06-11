import crypto from "node:crypto";
import type { IntegrationApiKey, IntegrationApiScope } from "./types.ts";
import type { Store } from "./store.ts";

function nowUtcMs(): number {
  return Date.now();
}

function getAuthSecret(): string {
  const s = process.env.AUTH_SECRET;
  if (!s || s.length < 16) throw new Error("AUTH_SECRET_missing_or_too_short");
  return s;
}

export function hashIntegrationSecret(secret: string): string {
  return crypto.createHash("sha256").update(`${secret}:${getAuthSecret()}`).digest("hex");
}

export function generateApiKeyMaterial(): { keyId: string; secret: string; token: string } {
  const keyId = crypto.randomBytes(8).toString("hex");
  const secret = crypto.randomBytes(24).toString("base64url");
  const token = `nvg8r_${keyId}_${secret}`;
  return { keyId, secret, token };
}

export function parseIntegrationBearer(token: string): { keyId: string; secret: string } | null {
  const m = /^nvg8r_([a-f0-9]+)_([A-Za-z0-9_-]+)$/.exec(String(token).trim());
  if (!m) return null;
  return { keyId: m[1]!, secret: m[2]! };
}

export type IntegrationAuthContext = {
  orgId: string;
  connectionId: string;
  keyId: string;
  scopes: IntegrationApiScope[];
};

function findActiveKey(store: Store, keyId: string, secret: string): IntegrationApiKey | null {
  const hash = hashIntegrationSecret(secret);
  for (const k of store.integrationApiKeys.values()) {
    if (k.keyId !== keyId || k.status !== "ACTIVE") continue;
    if (k.secretHash !== hash) continue;
    if (k.expiresAtUtcMs != null && k.expiresAtUtcMs <= nowUtcMs()) continue;
    return k;
  }
  return null;
}

export function resolveIntegrationAuth(
  store: Store,
  params: { bearerToken?: string | null; apiKey?: string | null; apiSecret?: string | null },
): IntegrationAuthContext {
  let keyId: string | null = params.apiKey?.trim() || null;
  let secret: string | null = params.apiSecret?.trim() || null;

  if (params.bearerToken) {
    const parsed = parseIntegrationBearer(params.bearerToken);
    if (parsed) {
      keyId = parsed.keyId;
      secret = parsed.secret;
    }
  }

  if (!keyId || !secret) throw new Error("integration_unauthorized");

  const key = findActiveKey(store, keyId, secret);
  if (!key) throw new Error("integration_unauthorized");

  const conn = store.integrationConnections.get(key.connectionId);
  if (!conn || conn.status !== "ACTIVE") throw new Error("integration_connection_inactive");

  const org = store.organizations.get(key.orgId);
  if (!org || org.kind !== "CUSTOMER") throw new Error("integration_org_invalid");

  key.lastUsedAtUtcMs = nowUtcMs();
  store.integrationApiKeys.set(key.id, key);

  return {
    orgId: key.orgId,
    connectionId: key.connectionId,
    keyId: key.keyId,
    scopes: key.scopes,
  };
}

export function assertIntegrationScope(ctx: IntegrationAuthContext, scope: IntegrationApiScope): void {
  if (!ctx.scopes.includes(scope)) throw new Error("integration_forbidden");
}

export function signWebhookPayload(secret: string, body: string): string {
  return crypto.createHmac("sha256", secret).update(body).digest("hex");
}

export function verifyWebhookSignature(secret: string, body: string, signature: string | null | undefined): boolean {
  if (!signature) return false;
  const expected = signWebhookPayload(secret, body);
  const a = Buffer.from(expected, "utf8");
  const b = Buffer.from(String(signature).trim(), "utf8");
  if (a.length !== b.length) return false;
  return crypto.timingSafeEqual(a, b);
}
