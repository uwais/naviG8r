import crypto from "node:crypto";
import type { AuthSession, OtpChallenge, User } from "./types.ts";
import type { Store } from "./store.ts";

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
  const b64 = (s + "=".repeat(pad === 4 ? 0 : pad)).replaceAll("-", "+").replaceAll("_", "/");
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
  const mac = crypto.createHmac("sha256", getAuthSecret()).update(payloadB64).digest();
  const sigB64 = b64urlEncode(mac);
  return `${payloadB64}.${sigB64}`;
}

function verifyToken(token: string): TokenPayloadV1 {
  const [payloadB64, sigB64] = String(token).split(".");
  if (!payloadB64 || !sigB64) throw new Error("invalid_token");
  const expected = b64urlEncode(
    crypto.createHmac("sha256", getAuthSecret()).update(payloadB64).digest()
  );
  const a = b64urlDecode(sigB64);
  const b = b64urlDecode(expected);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) throw new Error("invalid_token");
  const payload = JSON.parse(b64urlDecode(payloadB64).toString("utf8")) as TokenPayloadV1;
  if (payload?.v !== 1 || !payload.sid || !payload.uid || !payload.exp) throw new Error("invalid_token");
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

export function pilotOtpStart(store: Store, params: { phone: string }): {
  challengeId: string;
  expiresAtUtcMs: number;
  /** Only returned when OTP_DEBUG=1 (never in production pilots). */
  debugCode?: string;
} {
  const user = findUserByPhone(store, params.phone);
  if (!user) throw new Error("user_not_found");

  const now = nowUtcMs();
  const ttlMs = Number(process.env.OTP_TTL_MS ?? `${10 * 60 * 1000}`);
  const code =
    process.env.OTP_DEBUG === "1"
      ? String(process.env.OTP_FIXED_CODE ?? "123456").padStart(6, "0").slice(-6)
      : randomOtp6();

  const ch: OtpChallenge = {
    id: id("otp"),
    phone: user.phone,
    code,
    status: "PENDING",
    expiresAtUtcMs: now + ttlMs,
    createdAtUtcMs: now,
  };
  store.otpChallenges.set(ch.id, ch);

  const out: { challengeId: string; expiresAtUtcMs: number; debugCode?: string } = {
    challengeId: ch.id,
    expiresAtUtcMs: ch.expiresAtUtcMs,
  };
  if (process.env.OTP_DEBUG === "1") out.debugCode = code;
  return out;
}

export function pilotOtpVerify(store: Store, params: { phone: string; challengeId: string; code: string }): {
  user: User;
  accessToken: string;
  session: AuthSession;
} {
  const user = findUserByPhone(store, params.phone);
  if (!user) throw new Error("user_not_found");

  const ch = store.otpChallenges.get(String(params.challengeId ?? ""));
  if (!ch) throw new Error("otp_challenge_not_found");
  if (ch.phone !== user.phone) throw new Error("otp_challenge_mismatch");
  if (ch.status !== "PENDING") throw new Error("otp_challenge_invalid");
  const now = nowUtcMs();
  if (ch.expiresAtUtcMs <= now) {
    store.otpChallenges.set(ch.id, { ...ch, status: "EXPIRED" });
    throw new Error("otp_expired");
  }
  if (String(params.code ?? "") !== ch.code) throw new Error("otp_incorrect");

  store.otpChallenges.set(ch.id, { ...ch, status: "CONSUMED" });

  const sessionTtlMs = Number(process.env.SESSION_TTL_MS ?? `${30 * 24 * 60 * 60 * 1000}`);
  const session: AuthSession = {
    id: id("ses"),
    userId: user.id,
    createdAtUtcMs: now,
    expiresAtUtcMs: now + sessionTtlMs,
    revokedAtUtcMs: null,
  };
  store.authSessions.set(session.id, session);

  const token = signPayload({ v: 1, sid: session.id, uid: user.id, exp: session.expiresAtUtcMs });
  return { user, accessToken: token, session };
}

export function verifyBearer(store: Store, token: string | null): { userId: string; sessionId: string } {
  if (!token) throw new Error("unauthorized");
  const payload = verifyToken(token);
  const s = store.authSessions.get(payload.sid);
  if (!s) throw new Error("unauthorized");
  if (s.revokedAtUtcMs) throw new Error("unauthorized");
  if (s.expiresAtUtcMs <= nowUtcMs()) throw new Error("unauthorized");
  if (s.userId !== payload.uid) throw new Error("unauthorized");
  return { userId: s.userId, sessionId: s.id };
}
