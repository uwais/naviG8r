import crypto from "node:crypto";

export type FirebaseTokenClaims = {
  uid: string;
  phone_number?: string;
  aud?: string;
  iss?: string;
  exp?: number;
  firebase?: { sign_in_provider?: string };
};

export type FirebaseTokenVerifier = (token: string) => Promise<FirebaseTokenClaims>;

export type VerifiedFirebasePhoneToken = {
  claims: FirebaseTokenClaims;
  /** Non-reversible key used to make retries of one verified token idempotent. */
  exchangeKey: string;
};

let verifierOverride: FirebaseTokenVerifier | undefined;

/** Test-only dependency injection for Firebase verification. */
export function setFirebaseTokenVerifierForTests(verifier?: FirebaseTokenVerifier): void {
  verifierOverride = verifier;
}

async function firebaseVerifier(): Promise<FirebaseTokenVerifier> {
  if (verifierOverride) return verifierOverride;
  const projectId = process.env.FIREBASE_PROJECT_ID?.trim();
  if (!projectId) throw new Error("firebase_auth_not_configured");
  const { getApps, initializeApp } = await import("firebase-admin/app");
  const { getAuth } = await import("firebase-admin/auth");
  const app = getApps()[0] ?? initializeApp({ projectId });
  const auth = getAuth(app);
  return (token) => auth.verifyIdToken(token, true) as Promise<FirebaseTokenClaims>;
}

function nowUtcMs(): number {
  return Date.now();
}

/** Verify and validate a Firebase phone-auth ID token before it enters the store queue. */
export async function verifyFirebasePhoneToken(token: string): Promise<VerifiedFirebasePhoneToken> {
  if (!token || token.length > 10000) throw new Error("firebase_token_invalid");
  let claims: FirebaseTokenClaims;
  try {
    claims = await (await firebaseVerifier())(token);
  } catch {
    throw new Error("firebase_token_invalid");
  }
  const projectId = process.env.FIREBASE_PROJECT_ID?.trim();
  if (projectId && claims.aud !== projectId) throw new Error("firebase_token_invalid");
  if (projectId && claims.iss !== `https://securetoken.google.com/${projectId}`) {
    throw new Error("firebase_token_invalid");
  }
  if (claims.exp !== undefined && claims.exp * 1000 <= nowUtcMs()) throw new Error("firebase_token_invalid");
  if (!claims.uid || claims.firebase?.sign_in_provider !== "phone" || !claims.phone_number) {
    throw new Error("firebase_phone_provider_required");
  }
  return {
    claims,
    exchangeKey: crypto.createHash("sha256").update(token).digest("hex"),
  };
}
