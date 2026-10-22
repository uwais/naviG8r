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

The legacy OTP provider remains available on web. Android uses Firebase by
default; enable it explicitly with
`--dart-define=ALLOW_LEGACY_OTP_FALLBACK=true` only when a fallback is needed.
