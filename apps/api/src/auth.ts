import crypto from "node:crypto";
import type { AuthSession, OtpChallenge, User } from "./types.ts";
import type { Store } from "./store.ts";
import { isActiveEntity } from "./softDelete.ts";
import { verifyFirebasePhoneToken, type FirebaseTokenClaims, type VerifiedFirebasePhoneToken } from "./providers/firebasePhoneAuth.ts";
export { setFirebaseTokenVerifierForTests } from "./providers/firebasePhoneAuth.ts";
export type { FirebaseTokenClaims, FirebaseTokenVerifier } from "./providers/firebasePhoneAuth.ts";

function nowUtcMs(): number {
  return Date.now();
}

const DEFAULT_SESSION_TTL_MS = 30 * 24 * 60 * 60 * 1000;
const MAX_SESSION_TTL_MS = DEFAULT_SESSION_TTL_MS;
const MAX_ACTIVE_FIREBASE_SESSIONS_PER_USER = 5;

function sessionTtlMs(): number {
  const raw = process.env.SESSION_TTL_MS;
  const value = raw === undefined ? DEFAULT_SESSION_TTL_MS : Number(raw);
  if (!Number.isSafeInteger(value) || value <= 0 || value > MAX_SESSION_TTL_MS || (raw !== undefined && raw.trim() === "")) {
    throw new Error("SESSION_TTL_MS_invalid");
  }
  return value;
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

export type FirebasePhoneExchange = {
  user: User; accessToken: string; session: AuthSession;
};

type FirebasePhoneExchangeState = FirebasePhoneExchange & { stateChanged: boolean };

/**
 * Exchanges claims that have already been verified by Firebase. Keep this synchronous so the
 * HTTP layer can perform the network verification before entering the serialized store queue.
 */
export function firebasePhoneExchangeVerified(
  store: Store,
  claims: FirebaseTokenClaims,
  exchangeKey: string,
): FirebasePhoneExchangeState {
  if (!claims.uid || !claims.phone_number || claims.firebase?.sign_in_provider !== "phone") {
    throw new Error("firebase_phone_provider_required");
  }
  const phone = normalizeInPhone(claims.phone_number);
  const mapped = store.firebaseIdentities.get(claims.uid);
  const user = mapped ? store.users.get(mapped.userId) : findUserByPhone(store, phone);
  if (!user) throw new Error("user_not_found");
  if (!isActiveEntity(user)) throw new Error("account_inactive");
  if (user.phone !== phone) throw new Error("firebase_identity_conflict");
  const existingPhoneOwner = findUserByPhone(store, phone);
  if (existingPhoneOwner && existingPhoneOwner.id !== user.id) throw new Error("firebase_identity_conflict");
  let stateChanged = false;
  if (!mapped) {
    store.firebaseIdentities.set(claims.uid, { uid: claims.uid, userId: user.id, createdAtUtcMs: Date.now() });
    stateChanged = true;
  }
  const now = nowUtcMs();
  if (!exchangeKey) throw new Error("firebase_exchange_key_required");
  for (const [sessionId, candidate] of store.authSessions) {
    if (candidate.userId === user.id &&
        candidate.authProvider === "firebase" &&
        (candidate.revokedAtUtcMs != null || candidate.expiresAtUtcMs <= now)) {
      store.authSessions.delete(sessionId);
      stateChanged = true;
    }
  }
  let session = [...store.authSessions.values()]
    .find((candidate) => candidate.userId === user.id &&
      candidate.authProvider === "firebase" &&
      candidate.providerSessionKey === exchangeKey &&
      candidate.revokedAtUtcMs == null &&
      candidate.expiresAtUtcMs > now);
  if (!session) {
    const activeFirebaseSessions = [...store.authSessions.values()]
      .filter((candidate) => candidate.userId === user.id &&
        candidate.authProvider === "firebase" &&
        candidate.revokedAtUtcMs == null &&
        candidate.expiresAtUtcMs > now)
      .sort((a, b) => a.createdAtUtcMs - b.createdAtUtcMs);
    while (activeFirebaseSessions.length >= MAX_ACTIVE_FIREBASE_SESSIONS_PER_USER) {
      const oldest = activeFirebaseSessions.shift();
      if (!oldest) break;
      store.authSessions.delete(oldest.id);
      stateChanged = true;
    }
    const created: AuthSession = {
      id: id("ses"),
      userId: user.id,
      createdAtUtcMs: now,
      expiresAtUtcMs: now + sessionTtlMs(),
      revokedAtUtcMs: null,
      authProvider: "firebase",
      providerSessionKey: exchangeKey,
    };
    store.authSessions.set(created.id, created);
    stateChanged = true;
    session = created;
  }
  return { user, session, accessToken: signPayload({ v: 1, sid: session.id, uid: user.id, exp: session.expiresAtUtcMs }), stateChanged };
}

export async function firebasePhoneExchange(store: Store, token: string): Promise<FirebasePhoneExchange> {
  const verified: VerifiedFirebasePhoneToken = await verifyFirebasePhoneToken(token);
  const { stateChanged: _stateChanged, ...out } = firebasePhoneExchangeVerified(store, verified.claims, verified.exchangeKey);
  return out;
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
  /** False in production, where nothing sends the code by SMS; people sign in with Firebase there. */
  readonly serverCodeSignInAllowed: boolean;
  readonly now: () => number;
  readonly generateCode: () => string;
  consumeIpStart: (ip: string) => number;
  consumeIpVerify: (ip: string) => number;
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
  // Start and verify are counted separately, with the same limit and window.
  const ipRequestCounter = () => {
    const requestsByIp = new Map<string, number[]>();
    return (ip: string): number => {
      const instant = now();
      const prior = requestsByIp.get(ip) ?? [];
      const recent = prior.filter((at) => at > instant - ipStartWindowMs);
      if (recent.length >= ipStartLimit) {
        requestsByIp.set(ip, recent);
        throw new OtpRateLimitError(Math.max(1, recent[0]! + ipStartWindowMs - instant));
      }
      recent.push(instant);
      requestsByIp.delete(ip);
      requestsByIp.set(ip, recent);
      // Keep attacker-controlled IP cardinality bounded. Oldest keys are evicted first.
      while (requestsByIp.size > 10_000) requestsByIp.delete(requestsByIp.keys().next().value!);
      return Math.max(0, recent[0]! + ipStartWindowMs - instant);
    };
  };
  const consumeIpStart = ipRequestCounter();
  const consumeIpVerify = ipRequestCounter();
  return Object.freeze({
    ttlMs,
    resendCooldownMs,
    phoneStartLimit,
    phoneStartWindowMs,
    ipStartLimit,
    ipStartWindowMs,
    trustProxy: env.OTP_TRUST_PROXY === "1",
    debug: env.OTP_DEBUG === "1",
    serverCodeSignInAllowed: serverCodeSignInAllowed(env),
    now,
    generateCode: options.generateCode ?? randomOtp6,
    consumeIpStart,
    consumeIpVerify,
  });
}

/** Debug response delivery only; an external delivery adapter can replace this later. */
function debugOtpDelivery(
  code: string,
  enabled: boolean,
): { debugCode?: string } {
  return enabled ? { debugCode: code } : {};
}

// Any other value, a misspelt "production" included, is treated as production.
const SERVER_CODE_SIGN_IN_ENVIRONMENTS = ["test", "development", "alpha", "beta"];

/** Unset counts as a local run: tests and local servers leave NODE_ENV unset, and the API image sets production. */
export function serverCodeSignInAllowed(env: NodeJS.ProcessEnv = process.env): boolean {
  return env.NODE_ENV === undefined || SERVER_CODE_SIGN_IN_ENVIRONMENTS.includes(env.NODE_ENV);
}

function assertServerCodeSignInAllowed(otp: OtpDependencies): void {
  if (!otp.serverCodeSignInAllowed) throw new Error("otp_sign_in_retired");
}

/** Returns an unexpired in-cooldown challenge without mutating OTP state. */
export function pilotOtpCooldownReuse(
  store: Store,
  params: { phone: string },
  otp = createOtpDependencies(),
): { challengeId: string; expiresAtUtcMs: number; retryAfterMs: number; debugCode?: string } | null {
  assertServerCodeSignInAllowed(otp);
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
  assertServerCodeSignInAllowed(otp);
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

const MAX_WRONG_CODES_PER_CHALLENGE = 5;

export function pilotOtpVerify(
  store: Store,
  params: { phone: string; challengeId: string; code: string },
  otp = createOtpDependencies(),
): {
  user: User;
  accessToken: string;
  session: AuthSession;
} {
  assertServerCodeSignInAllowed(otp);
  const user = findUserByPhone(store, params.phone);
  if (!user) throw new Error("user_not_found");
  if (!isActiveEntity(user)) throw new Error("account_inactive");

  const ch = store.otpChallenges.get(String(params.challengeId ?? ""));
  if (!ch) throw new Error("otp_challenge_not_found");
  if (ch.phone !== user.phone) throw new Error("otp_challenge_mismatch");
  if (ch.status === "FAILED") throw new Error("otp_too_many_wrong_codes");
  if (ch.status !== "PENDING") throw new Error("otp_challenge_invalid");
  const now = otp.now();
  if (ch.expiresAtUtcMs <= now) {
    store.otpChallenges.set(ch.id, { ...ch, status: "EXPIRED" });
    throw new Error("otp_expired");
  }
  if (String(params.code ?? "") !== ch.code) {
    const wrongCodeCount = (ch.wrongCodeCount ?? 0) + 1;
    if (wrongCodeCount >= MAX_WRONG_CODES_PER_CHALLENGE) {
      store.otpChallenges.set(ch.id, { ...ch, wrongCodeCount, status: "FAILED" });
      throw new Error("otp_too_many_wrong_codes");
    }
    store.otpChallenges.set(ch.id, { ...ch, wrongCodeCount });
    throw new Error("otp_incorrect");
  }

  const sessionTtl = sessionTtlMs();
  const session: AuthSession = {
    id: id("ses"),
    userId: user.id,
    createdAtUtcMs: now,
    expiresAtUtcMs: now + sessionTtl,
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
  // Only Firebase sessions carry authProvider; the rest came from the server code and end where it is retired.
  if (s.authProvider !== "firebase" && !serverCodeSignInAllowed()) throw new Error("unauthorized");
  const user = store.users.get(s.userId);
  if (!user || !isActiveEntity(user)) throw new Error("unauthorized");
  return { userId: s.userId, sessionId: s.id };
}
