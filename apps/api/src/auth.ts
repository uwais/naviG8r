import crypto from "node:crypto";
import type { AuthSession, OtpChallenge, User } from "./types.ts";
import type { Store } from "./store.ts";
import { isActiveEntity } from "./softDelete.ts";

function nowUtcMs(): number {
  return Date.now();
}

function id(prefix: string): string {
  return `${prefix}_${Math.random().toString(16).slice(2)}_${Date.now().toString(16)}`;
}

function b64urlEncode(buf: Buffer): string {
  return buf
    .toString("base64")
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

function b64urlDecode(s: string): Buffer {
  const pad = 4 - (s.length % 4 || 4);
  const b64 = (s + "=".repeat(pad === 4 ? 0 : pad))
    .replaceAll("-", "+")
    .replaceAll("_", "/");
  return Buffer.from(b64, "base64");
}

function getAuthSecret(): string {
  const s = process.env.AUTH_SECRET;
  if (!s || s.length < 16) {
    throw new Error("AUTH_SECRET_missing_or_too_short");
  }
  return s;
}

type TokenPayloadV1 = {
  v: 1;
  sid: string;
  uid: string;
  exp: number;
};

function signPayload(payload: TokenPayloadV1): string {
  const payloadJson = JSON.stringify(payload);
  const payloadB64 = b64urlEncode(Buffer.from(payloadJson, "utf8"));
  const mac = crypto
    .createHmac("sha256", getAuthSecret())
    .update(payloadB64)
    .digest();
  const sigB64 = b64urlEncode(mac);
  return `${payloadB64}.${sigB64}`;
}

function verifyToken(token: string): TokenPayloadV1 {
  const [payloadB64, sigB64] = String(token).split(".");
  if (!payloadB64 || !sigB64) throw new Error("invalid_token");
  const expected = b64urlEncode(
    crypto.createHmac("sha256", getAuthSecret()).update(payloadB64).digest(),
  );
  const a = b64urlDecode(sigB64);
  const b = b64urlDecode(expected);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b))
    throw new Error("invalid_token");
  const payload = JSON.parse(
    b64urlDecode(payloadB64).toString("utf8"),
  ) as TokenPayloadV1;
  if (payload?.v !== 1 || !payload.sid || !payload.uid || !payload.exp)
    throw new Error("invalid_token");
  if (payload.exp <= nowUtcMs()) throw new Error("token_expired");
  return payload;
}

function normalizeInPhone(phone: string): string {
  const p = String(phone ?? "").trim();
  if (!p) throw new Error("invalid_phone");
  const digits = p.replace(/[^\d]/g, "");
  if (digits.length === 12 && digits.startsWith("91")) return digits.slice(-10);
  if (digits.length === 10) return digits;
  throw new Error("invalid_phone");
}

function findUserByPhone(store: Store, phone: string): User | null {
  const p = normalizeInPhone(phone);
  return [...store.users.values()].find((u) => u.phone === p) ?? null;
}

function randomOtp6(): string {
  const n = crypto.randomInt(0, 1_000_000);
  return String(n).padStart(6, "0");
}

export type OtpDependencies = {
  readonly ttlMs: number;
  readonly resendCooldownMs: number;
  readonly phoneStartLimit: number;
  readonly phoneStartWindowMs: number;
  readonly ipStartLimit: number;
  readonly ipStartWindowMs: number;
  readonly trustProxy: boolean;
  readonly debug: boolean;
  readonly now: () => number;
  readonly generateCode: () => string;
  consumeIpStart: (ip: string) => number;
};

export class OtpRateLimitError extends Error {
  readonly retryAfterMs: number;
  constructor(retryAfterMs: number) {
    super("otp_rate_limited");
    this.name = "OtpRateLimitError";
    this.retryAfterMs = retryAfterMs;
  }
}

const MAX_DATE_MS = 8_640_000_000_000_000;

function otpDeadline(now: number, ttlMs: number): number {
  const deadline = now + ttlMs;
  if (
    !Number.isSafeInteger(now) ||
    !Number.isSafeInteger(deadline) ||
    deadline <= now ||
    Math.abs(deadline) > MAX_DATE_MS
  ) {
    throw new Error("OTP_TTL_MS_invalid");
  }
  return deadline;
}

/** One validated configuration per application; clock and generator are injectable in tests. */
export function createOtpDependencies(
  options: {
    env?: NodeJS.ProcessEnv;
    now?: () => number;
    generateCode?: () => string;
  } = {},
): OtpDependencies {
  const env = options.env ?? process.env;
  const raw = env.OTP_TTL_MS;
  const ttlMs = raw === undefined ? 600_000 : Number(raw);
  if (
    !Number.isSafeInteger(ttlMs) ||
    ttlMs <= 0 ||
    (raw !== undefined && raw.trim() === "")
  ) {
    throw new Error("OTP_TTL_MS_invalid");
  }
  const configNumber = (name: string, fallback: number): number => {
    const value = env[name];
    const parsed = value === undefined ? fallback : Number(value);
    if (!Number.isSafeInteger(parsed) || parsed <= 0 || (value !== undefined && value.trim() === "")) {
      throw new Error(`${name}_invalid`);
    }
    return parsed;
  };
  const resendCooldownMs = configNumber("OTP_RESEND_COOLDOWN_MS", 30_000);
  const phoneStartLimit = configNumber("OTP_PHONE_START_LIMIT", 5);
  const phoneStartWindowMs = configNumber("OTP_PHONE_START_WINDOW_MS", 3_600_000);
  const ipStartLimit = configNumber("OTP_IP_START_LIMIT", 30);
  const ipStartWindowMs = configNumber("OTP_IP_START_WINDOW_MS", 600_000);
  const now = options.now ?? nowUtcMs;
  otpDeadline(now(), ttlMs);
  const ipStarts = new Map<string, number[]>();
  const consumeIpStart = (ip: string): number => {
    const instant = now();
    const prior = ipStarts.get(ip) ?? [];
    const recent = prior.filter((at) => at > instant - ipStartWindowMs);
    if (recent.length >= ipStartLimit) {
      ipStarts.set(ip, recent);
      throw new OtpRateLimitError(Math.max(1, recent[0]! + ipStartWindowMs - instant));
    }
    recent.push(instant);
    ipStarts.delete(ip);
    ipStarts.set(ip, recent);
    // Keep attacker-controlled IP cardinality bounded. Oldest keys are evicted first.
    while (ipStarts.size > 10_000) ipStarts.delete(ipStarts.keys().next().value!);
    return Math.max(0, recent[0]! + ipStartWindowMs - instant);
  };
  return Object.freeze({
    ttlMs,
    resendCooldownMs,
    phoneStartLimit,
    phoneStartWindowMs,
    ipStartLimit,
    ipStartWindowMs,
    trustProxy: env.OTP_TRUST_PROXY === "1",
    debug: env.OTP_DEBUG === "1",
    now,
    generateCode: options.generateCode ?? randomOtp6,
    consumeIpStart,
  });
}

/** Debug response delivery only; an external delivery adapter can replace this later. */
function debugOtpDelivery(
  code: string,
  enabled: boolean,
): { debugCode?: string } {
  return enabled ? { debugCode: code } : {};
}

/** Returns an unexpired in-cooldown challenge without mutating OTP state. */
export function pilotOtpCooldownReuse(
  store: Store,
  params: { phone: string },
  otp = createOtpDependencies(),
): { challengeId: string; expiresAtUtcMs: number; retryAfterMs: number; debugCode?: string } | null {
  const user = findUserByPhone(store, params.phone);
  if (!user) throw new Error("user_not_found");
  if (!isActiveEntity(user)) throw new Error("account_inactive");
  const now = otp.now();
  const pending = [...store.otpChallenges.values()].find((challenge) =>
    challenge.phone === user.phone && challenge.status === "PENDING" && challenge.expiresAtUtcMs > now,
  );
  if (!pending || pending.createdAtUtcMs + otp.resendCooldownMs <= now) return null;
  return {
    challengeId: pending.id,
    expiresAtUtcMs: pending.expiresAtUtcMs,
    retryAfterMs: pending.createdAtUtcMs + otp.resendCooldownMs - now,
    ...debugOtpDelivery(pending.code, otp.debug),
  };
}

export function pilotOtpStart(
  store: Store,
  params: { phone: string },
  otp = createOtpDependencies(),
): {
  challengeId: string;
  expiresAtUtcMs: number;
  retryAfterMs: number;
  /** Only returned when the server enables OTP_DEBUG=1. */
  debugCode?: string;
} {
  const user = findUserByPhone(store, params.phone);
  if (!user) throw new Error("user_not_found");
  if (!isActiveEntity(user)) throw new Error("account_inactive");

  const now = otp.now();
  const reusable = pilotOtpCooldownReuse(store, params, otp);
  if (reusable) return reusable;
  const recent = [...store.otpChallenges.values()].filter((challenge) =>
    challenge.phone === user.phone && challenge.createdAtUtcMs > now - otp.phoneStartWindowMs,
  ).sort((a, b) => a.createdAtUtcMs - b.createdAtUtcMs);
  if (recent.length >= otp.phoneStartLimit) {
    throw new OtpRateLimitError(Math.max(1, recent[0]!.createdAtUtcMs + otp.phoneStartWindowMs - now));
  }
  const expiresAtUtcMs = otpDeadline(now, otp.ttlMs);
  const code = otp.generateCode();
  if (!/^\d{6}$/.test(code)) throw new Error("otp_generator_invalid");
  const delivery = debugOtpDelivery(code, otp.debug);

  const ch: OtpChallenge = {
    id: id("otp"),
    phone: user.phone,
    code,
    status: "PENDING",
    expiresAtUtcMs,
    createdAtUtcMs: now,
  };
  for (const previous of store.otpChallenges.values()) {
    if (previous.phone === user.phone && previous.status === "PENDING") {
      store.otpChallenges.set(previous.id, {
        ...previous,
        status: "SUPERSEDED",
      });
    }
  }
  store.otpChallenges.set(ch.id, ch);

  // Retain recent issuance history for the configured phone window and any live challenge.
  for (const [challengeId, challenge] of store.otpChallenges) {
    if (challenge.phone === user.phone && challenge.status !== "PENDING" &&
        challenge.createdAtUtcMs <= now - otp.phoneStartWindowMs) {
      store.otpChallenges.delete(challengeId);
    }
  }

  const out: {
    challengeId: string;
    expiresAtUtcMs: number;
    retryAfterMs: number;
    debugCode?: string;
  } = {
    challengeId: ch.id,
    expiresAtUtcMs: ch.expiresAtUtcMs,
    retryAfterMs: otp.resendCooldownMs,
    ...delivery,
  };
  return out;
}

export function pilotOtpVerify(
  store: Store,
  params: { phone: string; challengeId: string; code: string },
  otp = createOtpDependencies(),
): {
  user: User;
  accessToken: string;
  session: AuthSession;
} {
  const user = findUserByPhone(store, params.phone);
  if (!user) throw new Error("user_not_found");
  if (!isActiveEntity(user)) throw new Error("account_inactive");

  const ch = store.otpChallenges.get(String(params.challengeId ?? ""));
  if (!ch) throw new Error("otp_challenge_not_found");
  if (ch.phone !== user.phone) throw new Error("otp_challenge_mismatch");
  if (ch.status !== "PENDING") throw new Error("otp_challenge_invalid");
  const now = otp.now();
  if (ch.expiresAtUtcMs <= now) {
    store.otpChallenges.set(ch.id, { ...ch, status: "EXPIRED" });
    throw new Error("otp_expired");
  }
  if (String(params.code ?? "") !== ch.code) throw new Error("otp_incorrect");

  const sessionTtlMs = Number(
    process.env.SESSION_TTL_MS ?? `${30 * 24 * 60 * 60 * 1000}`,
  );
  const session: AuthSession = {
    id: id("ses"),
    userId: user.id,
    createdAtUtcMs: now,
    expiresAtUtcMs: now + sessionTtlMs,
    revokedAtUtcMs: null,
  };
  const token = signPayload({
    v: 1,
    sid: session.id,
    uid: user.id,
    exp: session.expiresAtUtcMs,
  });
  store.otpChallenges.set(ch.id, { ...ch, status: "CONSUMED" });
  store.authSessions.set(session.id, session);
  return { user, accessToken: token, session };
}

export function verifyBearer(
  store: Store,
  token: string | null,
): { userId: string; sessionId: string } {
  if (!token) throw new Error("unauthorized");
  const payload = verifyToken(token);
  const s = store.authSessions.get(payload.sid);
  if (!s) throw new Error("unauthorized");
  if (s.revokedAtUtcMs) throw new Error("unauthorized");
  if (s.expiresAtUtcMs <= nowUtcMs()) throw new Error("unauthorized");
  if (s.userId !== payload.uid) throw new Error("unauthorized");
  const user = store.users.get(s.userId);
  if (!user || !isActiveEntity(user)) throw new Error("unauthorized");
  return { userId: s.userId, sessionId: s.id };
}
