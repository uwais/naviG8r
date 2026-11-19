/** How the staff pages served by this API sign people in, and the one browser script that does it with Firebase. */

import { serverCodeSignInAllowed } from "./auth.ts";
import { DEFAULT_COUNTRY_CODE, SUPPORTED_COUNTRY_CODES, type SupportedCountryCode } from "./phone.ts";

/** One pinned release, so every page load gets the same Firebase code; the policy below allows only this path. */
export const FIREBASE_JS_SDK_VERSION = "10.12.2";
const sdk = `https://www.gstatic.com/firebasejs/${FIREBASE_JS_SDK_VERSION}`;

export type FirebaseWebSettings = { projectId: string; apiKey: string; appId: string };

export type StaffSignIn =
  | { kind: "firebase"; settings: FirebaseWebSettings }
  | { kind: "server-code" }
  | { kind: "not-set-up" };

// Each value goes into a page, so anything outside the shape Firebase issues is refused rather than escaped.
const projectIdPattern = /^[a-z][a-z0-9-]{4,28}[a-z0-9]$/;
const webApiKeyPattern = /^AIza[0-9A-Za-z_-]{35}$/;
const webAppIdPattern = /^1:[0-9]{1,20}:web:[0-9a-f]{1,40}$/;

/** Only test and pre-release settings fall back to the server code, which has no SMS sender in production. */
export function staffSignInFromEnv(env: NodeJS.ProcessEnv = process.env): StaffSignIn {
  const settings = {
    projectId: env.FIREBASE_PROJECT_ID?.trim() ?? "",
    apiKey: env.FIREBASE_WEB_API_KEY?.trim() ?? "",
    appId: env.FIREBASE_WEB_APP_ID?.trim() ?? "",
  };
  if (projectIdPattern.test(settings.projectId) && webApiKeyPattern.test(settings.apiKey) && webAppIdPattern.test(settings.appId)) {
    return { kind: "firebase", settings };
  }
  return serverCodeSignInAllowed(env) ? { kind: "server-code" } : { kind: "not-set-up" };
}

export const staffSignInNotSetUpMarkup = '<p role="alert">Staff sign-in is not set up on this server.</p>';

const countryNames: Record<SupportedCountryCode, string> = { "+91": "India", "+1": "United States" };

/** The choices for each staff page's country box, from the server's own list, with India picked first. */
export const staffCountryOptions = SUPPORTED_COUNTRY_CODES.map((code) =>
  `<option value="${code}"${code === DEFAULT_COUNTRY_CODE ? " selected" : ""}>${countryNames[code]} (${code})</option>`).join("");

/**
 * Browser code: phoneForSignIn(typed number, chosen country code) gives { countryCode, phone, e164 }, or
 * { error, words } with the server's error code. It follows normalizePhone in phone.ts rule for rule, so the
 * page refuses exactly what the server would; staffSignIn.test.ts checks the two agree.
 */
export const phoneForSignInScript = `
const staffCountryNames = ${JSON.stringify(Object.fromEntries(SUPPORTED_COUNTRY_CODES.map((code) => [code, countryNames[code]])))};
function phoneForSignIn(raw, countryCode) {
  const name = staffCountryNames[countryCode];
  if (!name) return { error: 'invalid_country_code', words: 'Choose a country.' };
  const text = String(raw == null ? '' : raw).trim();
  const digits = text.replace(/[^0-9]/g, '');
  if (!digits) return { error: 'invalid_phone', words: 'Enter your phone number.' };
  const wrongLength = { error: 'invalid_phone', words: name + ' phone numbers have 10 digits. Check the number.' };
  let code = countryCode, national = digits;
  if (text.startsWith('+') || digits.length > 10) {
    if (digits.length === 12 && digits.startsWith('91')) { code = '+91'; national = digits.slice(2); }
    else if (digits.length === 11 && digits.startsWith('1')) { code = '+1'; national = digits.slice(1); }
    else return wrongLength;
    if (code !== countryCode) return { error: 'phone_country_mismatch', words: 'This number starts with ' + code + '. Choose ' + staffCountryNames[code] + ' as the country.' };
  }
  if (national.length !== 10) return wrongLength;
  return { countryCode: code, phone: national, e164: code + national };
}
`;

/** The page's own country box, phone and code fields and buttons, which the Firebase script takes over. */
export type SignInElementIds = { country: string; phone: string; send: string; code: string; verify: string };

/** Sources the Firebase phone sign-in needs in a page's content security policy, and no others. */
export const firebaseSignInPolicySources = {
  script: [`${sdk}/`, "https://www.google.com/recaptcha/", "https://www.gstatic.com/recaptcha/"],
  connect: ["https://identitytoolkit.googleapis.com", "https://securetoken.googleapis.com"],
  frame: ["https://www.google.com/recaptcha/", "https://recaptcha.google.com/recaptcha/"],
};

/**
 * Sends the code with Firebase, trades the Firebase ID token for a NaviG8r session, then hands the session
 * to the page through the navig8r-staff-signed-in event so the page keeps it exactly as before.
 */
export function firebaseSignInScript(settings: FirebaseWebSettings, ids: SignInElementIds): string {
  const firebaseConfig = JSON.stringify({
    apiKey: settings.apiKey,
    authDomain: `${settings.projectId}.firebaseapp.com`,
    projectId: settings.projectId,
    appId: settings.appId,
  });
  return `
import { initializeApp } from "${sdk}/firebase-app.js";
import { initializeAuth, inMemoryPersistence, RecaptchaVerifier, signInWithPhoneNumber } from "${sdk}/firebase-auth.js";
const ids = ${JSON.stringify(ids)};
const field = name => document.getElementById(ids[name]);
// Kept in memory only: the page holds the NaviG8r session, so Firebase stores nothing in the browser.
const auth = initializeAuth(initializeApp(${firebaseConfig}), { persistence: inMemoryPersistence });
const say = words => { document.getElementById('staff-sign-in-message').textContent = words; };
const firebaseWords = {
  'auth/invalid-phone-number': 'Enter a 10-digit phone number.',
  'auth/too-many-requests': 'Too many tries. Wait a few minutes and try again.',
  'auth/quota-exceeded': 'Too many tries. Wait a few minutes and try again.',
  'auth/invalid-verification-code': 'That code is wrong. Check it and try again.',
  'auth/code-expired': 'That code has expired. Send a new code.',
  'auth/captcha-check-failed': 'The check did not work. Reload the page and try again.',
  'auth/network-request-failed': 'No connection. Check your internet and try again.',
  'auth/unauthorized-domain': 'Phone sign-in is not set up for this site. Ask a teammate with ADMIN.',
};
const exchangeWords = {
  user_not_found: 'This phone number has no NaviG8r account.',
  account_inactive: 'This account is turned off.',
  firebase_identity_conflict: 'This phone number cannot sign in here. Ask a teammate with ADMIN.',
  firebase_exchange_rate_limited: 'Too many tries. Wait a few minutes and try again.',
  firebase_token_invalid: 'Sign-in did not work. Send a new code.',
};
let verifier = null, confirmation = null;
${phoneForSignInScript}
const startOver = () => { confirmation = null; field('code').value = ''; };
field('phone').addEventListener('input', startOver);
field('country').addEventListener('change', startOver);
field('send').addEventListener('click', async event => {
  event.preventDefault();
  const phone = phoneForSignIn(field('phone').value, field('country').value);
  if (phone.error) return say(phone.words);
  field('send').disabled = true;
  say('Sending the code...');
  try {
    verifier = verifier || new RecaptchaVerifier(auth, 'staff-recaptcha', { size: 'invisible' });
    confirmation = await signInWithPhoneNumber(auth, phone.e164, verifier);
    say('Code sent. Enter it to sign in.');
    field('code').focus();
  } catch (error) {
    confirmation = null;
    if (verifier) verifier.clear();
    verifier = null;
    // clear() leaves the old widget in its element, so the next verifier gets a fresh one to draw in.
    document.getElementById('staff-recaptcha').replaceWith(Object.assign(document.createElement('div'), { id: 'staff-recaptcha' }));
    say(firebaseWords[error && error.code] || 'Could not send the code. Try again.');
  } finally {
    field('send').disabled = false;
  }
});
field('verify').addEventListener('click', async event => {
  event.preventDefault();
  if (!confirmation) return say('Send a code first.');
  field('verify').disabled = true;
  say('Signing in...');
  try {
    const credential = await confirmation.confirm(field('code').value.trim());
    const idToken = await credential.user.getIdToken();
    await auth.signOut();
    const response = await fetch('/v1/auth/firebase/exchange', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ idToken }) });
    const out = await response.json().catch(() => ({}));
    if (!response.ok || typeof out.accessToken !== 'string') return say(exchangeWords[out.error] || 'Could not sign in. Try again.');
    confirmation = null;
    say('');
    document.dispatchEvent(new CustomEvent('navig8r-staff-signed-in', { detail: out.accessToken }));
  } catch (error) {
    say(firebaseWords[error && error.code] || 'Could not sign in. Try again.');
  } finally {
    field('verify').disabled = false;
  }
});
`;
}

/** The reCAPTCHA spot, the message line and the script, placed inside the page's sign-in section. */
export function firebaseSignInMarkup(settings: FirebaseWebSettings, ids: SignInElementIds): string {
  return `<div id="staff-recaptcha"></div><p id="staff-sign-in-message" role="status"></p><script type="module">${firebaseSignInScript(settings, ids)}</script>`;
}
