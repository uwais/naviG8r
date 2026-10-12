import { createSign } from "node:crypto";

export type FcmDeliveryMessage = {
  token: string;
  notificationId: string;
  presentationKey: string;
  ttlMs: number;
};

export type FcmSendResult =
  | { kind: "accepted"; providerMessageId: string }
  | { kind: "invalid_token"; errorCode: "UNREGISTERED" }
  | { kind: "transient"; errorCode: string; retryAfterMs?: number; quota: boolean }
  | { kind: "permanent"; errorCode: string };

export interface FcmSender {
  send(message: FcmDeliveryMessage): Promise<FcmSendResult>;
}

type ServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
  token_uri?: string;
};

type Fetcher = typeof fetch;
const REQUEST_TIMEOUT_MS = 10_000;
const TOKEN_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";

class FcmAuthRequestError extends Error {
  readonly retryable: boolean;
  readonly retryAfterMs?: number;
  constructor(message: string, retryable: boolean, retryAfterMs?: number) {
    super(message);
    this.retryable = retryable;
    this.retryAfterMs = retryAfterMs;
  }
}

export class HttpV1FcmSender implements FcmSender {
  private cachedToken: { value: string; expiresAtUtcMs: number } | null = null;
  private tokenRequest: Promise<string> | null = null;
  private readonly fetcher: Fetcher;

  constructor(fetcher: Fetcher = fetch) {
    this.fetcher = fetcher;
  }

  async send(message: FcmDeliveryMessage): Promise<FcmSendResult> {
    if (!Number.isSafeInteger(message.ttlMs) || message.ttlMs < 1000) return { kind: "permanent", errorCode: "INTENT_EXPIRED" };
    let account: ServiceAccount;
    try { account = this.readServiceAccount(); }
    catch { return { kind: "permanent", errorCode: "FCM_CREDENTIALS_UNAVAILABLE" }; }
    let token: string;
    try { token = await this.getAccessToken(account); }
    catch (error) {
      if (error instanceof FcmAuthRequestError && error.retryable) {
        return { kind: "transient", errorCode: "FCM_AUTH_UNAVAILABLE", retryAfterMs: error.retryAfterMs, quota: false };
      }
      return { kind: "permanent", errorCode: "FCM_CREDENTIALS_UNAVAILABLE" };
    }

    const ttlSeconds = Math.max(1, Math.floor(message.ttlMs / 1000));
    const body = {
      message: {
        token: message.token,
        notification: {
          title: "Shipment update",
          body: "There is an update for a shipment.",
        },
        data: {
          schemaVersion: "1",
          notificationId: message.notificationId,
          presentationKey: message.presentationKey,
        },
        android: {
          priority: "HIGH",
          ttl: `${ttlSeconds}s`,
          notification: {
            channel_id: "shipment_updates",
            tag: message.presentationKey,
            visibility: "PRIVATE",
          },
        },
      },
    };

    let response: Response;
    try {
      response = await this.fetcher(`https://fcm.googleapis.com/v1/projects/${encodeURIComponent(account.project_id)}/messages:send`, {
        method: "POST",
        redirect: "error",
        headers: {
          authorization: `Bearer ${token}`,
          "content-type": "application/json",
        },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
      });
    } catch (error) {
      const timedOut = error instanceof Error && error.name === "TimeoutError";
      return { kind: "transient", errorCode: timedOut ? "FCM_TIMEOUT" : "FCM_NETWORK_ERROR", quota: false };
    }

    const result = await response.json().catch(() => null) as {
      name?: string;
      error?: { status?: string; details?: Array<{ errorCode?: string }> };
    } | null;
    if (response.ok && typeof result?.name === "string") return { kind: "accepted", providerMessageId: result.name };

    const status = result?.error?.status ?? `HTTP_${response.status}`;
    const details = result?.error?.details ?? [];
    const providerCode = details.find(detail => typeof detail.errorCode === "string")?.errorCode;
    if (providerCode === "UNREGISTERED") return { kind: "invalid_token", errorCode: "UNREGISTERED" };
    if (response.status === 429 || status === "QUOTA_EXCEEDED") {
      return { kind: "transient", errorCode: "FCM_QUOTA_EXCEEDED", retryAfterMs: retryAfterMs(response.headers.get("retry-after")), quota: true };
    }
    if (response.status >= 500 || status === "UNAVAILABLE" || status === "INTERNAL") {
      return { kind: "transient", errorCode: "FCM_SERVER_UNAVAILABLE", retryAfterMs: retryAfterMs(response.headers.get("retry-after")), quota: false };
    }
    return { kind: "permanent", errorCode: `FCM_${safeCode(status)}` };
  }

  private readServiceAccount(): ServiceAccount {
    const raw = process.env.FCM_SERVICE_ACCOUNT_JSON;
    if (!raw) throw new Error("fcm_credentials_missing");
    const account = JSON.parse(raw) as ServiceAccount;
    if (!account.project_id || !account.client_email || !account.private_key) throw new Error("fcm_credentials_invalid");
    const tokenUri = account.token_uri ?? "https://oauth2.googleapis.com/token";
    if (tokenUri !== "https://oauth2.googleapis.com/token") throw new Error("fcm_token_uri_not_allowed");
    return { ...account, token_uri: tokenUri };
  }

  private async getAccessToken(account: ServiceAccount): Promise<string> {
    const now = Date.now();
    if (this.cachedToken && this.cachedToken.expiresAtUtcMs > now + 60_000) return this.cachedToken.value;
    if (this.tokenRequest) return this.tokenRequest;
    this.tokenRequest = this.exchangeJwt(account).finally(() => { this.tokenRequest = null; });
    return this.tokenRequest;
  }

  private async exchangeJwt(account: ServiceAccount): Promise<string> {
    const nowSeconds = Math.floor(Date.now() / 1000);
    const tokenUri = account.token_uri!;
    const header = base64UrlJson({ alg: "RS256", typ: "JWT" });
    const claim = base64UrlJson({
      iss: account.client_email,
      scope: TOKEN_SCOPE,
      aud: tokenUri,
      iat: nowSeconds,
      exp: nowSeconds + 3600,
    });
    const unsigned = `${header}.${claim}`;
    const signature = createSign("RSA-SHA256").update(unsigned).sign(account.private_key, "base64url");
    const assertion = `${unsigned}.${signature}`;
    let response: Response;
    try {
      response = await this.fetcher(tokenUri, {
        method: "POST",
        redirect: "error",
        headers: { "content-type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
        signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
      });
    } catch {
      throw new FcmAuthRequestError("fcm_oauth_network_error", true);
    }
    const result = await response.json().catch(() => null) as { access_token?: string; expires_in?: number } | null;
    if (!response.ok || !result?.access_token) {
      const transient = response.status === 429 || response.status >= 500;
      if (transient) throw new FcmAuthRequestError("fcm_oauth_exchange_failed", true, retryAfterMs(response.headers.get("retry-after")));
      throw new FcmAuthRequestError("fcm_oauth_exchange_failed", false);
    }
    const expiresInSeconds = Math.max(60, Math.min(3600, Number(result.expires_in ?? 3600)));
    this.cachedToken = { value: result.access_token, expiresAtUtcMs: Date.now() + expiresInSeconds * 1000 };
    return result.access_token;
  }
}

function base64UrlJson(value: unknown): string {
  return Buffer.from(JSON.stringify(value)).toString("base64url");
}

function retryAfterMs(value: string | null): number | undefined {
  if (!value) return undefined;
  const seconds = Number(value);
  if (Number.isFinite(seconds) && seconds >= 0) return Math.ceil(seconds * 1000);
  const date = Date.parse(value);
  return Number.isFinite(date) ? Math.max(0, date - Date.now()) : undefined;
}

function safeCode(value: string): string {
  return value.replace(/[^A-Za-z0-9_-]/g, "_").slice(0, 48);
}
