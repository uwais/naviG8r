# Firebase phone authentication

The Android pilot uses Firebase Phone Auth to verify the phone number. The
Firebase ID token is exchanged at `POST /v1/auth/firebase/exchange`, where the
API verifies it with Firebase Admin and issues the existing NaviG8r session
token.

## API configuration

Set these variables in the API process:

```bash
export FIREBASE_PROJECT_ID="<firebase-project-id>"
export GOOGLE_APPLICATION_CREDENTIALS="/secure/path/to/firebase-admin-service-account.json"
```

`GOOGLE_APPLICATION_CREDENTIALS` must point to a Firebase Admin service-account
credential outside the repository. Do not commit that credential or place it
in the Android application.

## Firebase console setup

1. Enable **Authentication → Sign-in method → Phone**.
2. Add the SHA-1 and SHA-256 fingerprints for every Android signing
   certificate used by the build (debug, internal/release, and Play App
   Signing where applicable).
3. Keep the Android package name as `com.navig8r.pilot`.
4. Use the matching `google-services.json` for the Firebase project being
   built. The root file is the beta/non-production configuration; production
   uses the variant-specific file below.

The Android configurations are selected by the Google Services Gradle plugin:

```text
apps/driver_pilot/android/app/google-services.json              # beta/default
apps/driver_pilot/android/app/src/release/google-services.json # production
```

`flutter build apk --debug` and `flutter run` use the beta configuration.
`flutter build apk --release` uses the production configuration.

Keep the API and Firebase project paired. Debug builds default to the beta API
(`https://navig8r-api-beta.onrender.com`) and `navig8r-beta`; release builds
default to the production API (`https://navig8r.onrender.com`) and
`project-e8131904-7071-4f79-89c`. For a local API, override the API only with
the matching Firebase project in the bundled configuration, for example:

```bash
flutter run \
  --dart-define=API_BASE_URL=http://10.0.2.2:3000 \
  --dart-define=FIREBASE_PROJECT_ID=navig8r-beta
```

The app validates the initialized Firebase project at startup and refuses a
mixed project configuration. The API deployments must set the same
`FIREBASE_PROJECT_ID` and provide Google Application Default Credentials
through the deployment secret manager; Render does not receive the Android
`google-services.json` file.

Service-account credentials remain deployment secrets.

## Local checks

```bash
node --experimental-strip-types --test apps/api/src/firebaseAuth.test.ts
```

Web uses Firebase when runtime-config.js carries the four Firebase settings, and
the old server code otherwise; a production server refuses the old server code.
Android uses Firebase by default; enable the old server code explicitly with
`--dart-define=ALLOW_LEGACY_OTP_FALLBACK=true` only when a fallback is needed.

## Staff pages served by the API

`/ops`, `/ops/beta`, `/ops/v1`, `/ops/v2`, `/admin`, `/admin/v1`, `/admin/v2` and
`/workflow` sign in with Firebase phone auth in the browser, then call the same
`POST /v1/auth/firebase/exchange`. The browser script lives in
`apps/api/src/staffSignIn.ts` and loads one pinned Firebase JS SDK version from
`www.gstatic.com`.

Set these on the API service, next to `FIREBASE_PROJECT_ID`:

```bash
export FIREBASE_WEB_API_KEY="<web app apiKey from the Firebase console>"
export FIREBASE_WEB_APP_ID="<web app appId, 1:<number>:web:<hex>>"
```

Each value must match a strict pattern or the server ignores it. The old code
sign-in is allowed only when `NODE_ENV` is `test`, `development`, `alpha` or
`beta`, or is unset (local runs and tests). Any other value, `production` or a
misspelling of it, counts as production:

- `POST /v1/auth/otp/start` and `/v1/auth/otp/verify` answer `410`
  `otp_sign_in_retired` and never return a code or a session.
- Sessions made by the old code sign-in stop working; people sign in again
  with Firebase.
- If the two web settings are missing or invalid, the staff pages show
  "Staff sign-in is not set up on this server." and offer no way in.

Where the old code sign-in is allowed, staff pages keep it unless both web
settings are set on that server, in which case they use Firebase too.
