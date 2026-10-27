import type { Store } from "./store.ts";
import type { User } from "./types.ts";

export const DEFAULT_COUNTRY_CODE = "+91";
export const SUPPORTED_COUNTRY_CODES = ["+91", "+1"] as const;
export type SupportedCountryCode = (typeof SUPPORTED_COUNTRY_CODES)[number];

export type PhoneIdentity = {
  countryCode: SupportedCountryCode;
  phone: string;
  e164: string;
  key: string;
};

function countryCodeOrDefault(raw: unknown): SupportedCountryCode {
  const value = String(raw ?? "").trim();
  if (!value) return DEFAULT_COUNTRY_CODE;
  const normalized = value.startsWith("+") ? value : `+${value}`;
  if ((SUPPORTED_COUNTRY_CODES as readonly string[]).includes(normalized)) {
    return normalized as SupportedCountryCode;
  }
  throw new Error("invalid_country_code");
}

/** Parse a supported phone into a country code plus national digits. */
export function normalizePhone(rawPhone: unknown, rawCountryCode?: unknown): PhoneIdentity {
  const raw = String(rawPhone ?? "").trim();
  if (!raw) throw new Error("invalid_phone");
  const digits = raw.replace(/[^\d]/g, "");
  if (!digits) throw new Error("invalid_phone");

  let countryCode = countryCodeOrDefault(rawCountryCode);
  let national = digits;
  const hasInternationalPrefix = raw.startsWith("+") || digits.length > 10;

  if (hasInternationalPrefix) {
    if (digits.length === 12 && digits.startsWith("91")) {
      if (rawCountryCode != null && countryCode !== "+91") throw new Error("phone_country_mismatch");
      countryCode = "+91";
      national = digits.slice(2);
    } else if (digits.length === 11 && digits.startsWith("1")) {
      if (rawCountryCode != null && countryCode !== "+1") throw new Error("phone_country_mismatch");
      countryCode = "+1";
      national = digits.slice(1);
    } else if (digits.length !== 10) {
      throw new Error("invalid_phone");
    } else if (raw.startsWith("+")) {
      throw new Error("invalid_phone");
    }
  }

  if (national.length !== 10) throw new Error("invalid_phone");
  return {
    countryCode,
    phone: national,
    e164: `${countryCode}${national}`,
    key: `${countryCode}:${national}`,
  };
}

export function phoneIdentityForUser(user: Pick<User, "phone" | "countryCode">): PhoneIdentity {
  return normalizePhone(user.phone, user.countryCode);
}

export function phoneKeyForUser(user: Pick<User, "phone" | "countryCode">): string {
  return phoneIdentityForUser(user).key;
}

export function findUserByPhone(
  store: Store,
  rawPhone: unknown,
  rawCountryCode?: unknown,
): User | null {
  const identity = normalizePhone(rawPhone, rawCountryCode);
  return [...store.users.values()].find((user) => phoneKeyForUser(user) === identity.key) ?? null;
}

/** Legacy rows without countryCode are India rows. */
export function storedCountryCode(raw: unknown): SupportedCountryCode {
  return countryCodeOrDefault(raw);
}
