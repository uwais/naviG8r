## Android pilot — Option A (signed release APK sideload)

This repo includes a minimal Flutter app at `apps/driver_pilot/` that talks to the Node API (`apps/api`).

### Prereqs
- Flutter SDK installed (`flutter doctor`)
- Android SDK + emulator **or** physical phone with USB debugging
- API running and reachable from the device/emulator

### API URLs
- **Android emulator → API on your PC**: `http://10.0.2.2:3000` (already default in `lib/main.dart`)
- **Physical Android → API on your PC (same Wi‑Fi)**: `http://<PC_LAN_IP>:3000` (change constant in `lib/main.dart`)

### Start the API (required)
From repo root:

```bash
export AUTH_SECRET="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"
export OTP_DEBUG=1
node --experimental-strip-types apps/api/src/index.ts
```

### One-time: generate Android platform + deps

```bash
cd apps/driver_pilot
chmod +x bootstrap.sh
./bootstrap.sh
```

### Demo on Android emulator (fastest: debug run)

1) Start an emulator from Android Studio **or**:

```bash
flutter emulators
flutter emulators --launch <emulator_id>
```

2) Run the app:

```bash
cd apps/driver_pilot
flutter run
```

3) In the app:
- **Retry health** should show `{ok: true}` if API is reachable.
- **Register** → **Login** (OTP start/verify) → **Publish** (paste `orgId` from register JSON).

### Option A: build a signed **release** APK (sideload)

1) Create a keystore (once):

```bash
cd apps/driver_pilot
keytool -genkeypair -v -keystore driver_pilot-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

2) Create `android/key.properties` (do not commit secrets):

```bash
cp key.properties.example android/key.properties
# edit passwords + paths
```

3) Build APK:

```bash
cd apps/driver_pilot
flutter build apk --release
```

Output:
- `build/app/outputs/flutter-apk/app-release.apk`

### Install APK onto emulator

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

### Install APK onto a physical phone (pilot)
- Send `app-release.apk` (Drive/email).
- On phone: allow install from source → open APK.

### Notes / pitfalls
- **Cleartext HTTP** is enabled for pilot demos via `network_security_config.xml`. Move to **HTTPS** before a broad external pilot.
- If Gradle is Kotlin DSL (`build.gradle.kts`) on your Flutter version, release signing injection may need manual steps (see Flutter docs). The Python injector supports the common **Groovy** `android/app/build.gradle` template.

---

## Roadmap (Android pilot)

### Current scope
- **Driver pilot app**: `apps/driver_pilot/` (Android APK).
- **API**: `apps/api/` (Node) + `docs/pilot-api.md` for contracts.
- There is **no customer UI** in this repo yet (customer endpoints exist server-side; see `docs/pilot-api.md` and marketplace routes in `apps/api/src/httpServer.ts`).

### What’s done (Android)
- [x] **Build + run on emulator/device** (Gradle / Java / NDK alignment).
- [x] **Home + navigation shell** (bottom tabs).
- [x] **Driver register** (`POST /v1/pilot/driver/register`) with phone normalization.
- [x] **OTP login** (`/v1/auth/otp/start` + `/v1/auth/otp/verify`) with clearer error output.
- [x] **Publish anchor trip** (`POST /v1/pilot/anchor-trips`) with org helper (`GET /v1/pilot/me`) and IST window helper.
- [x] **List my trips** (`GET /v1/pilot/anchor-trips`) + Trips tab (requires API deployed with that route).

### Next (near-term: improve driver pilot UX)
- [ ] **Session UX**: show “logged in as …” from `GET /v1/pilot/me`, plus **logout** (clear token).
- [ ] **Trips UX**: pull-to-refresh, and a **trip detail** view (copy trip id, show raw JSON).
- [ ] **Publish UX**: on success, show a snackbar and optionally **jump to Trips**.

### Next (medium-term: customer flow UI)
- [ ] Create a small **customer pilot UI** (separate Flutter app or a mode inside the same app):
  - Customer register (`POST /v1/pilot/customer/register`)
  - Browse open trips + quote + book (`/shipments/quote`, `/shipments/book`)
  - Track shipment + simulate POD (`/shipments/:id/pod`)

### Hardening (before broad external pilot)
- [ ] Replace debug OTP (`OTP_DEBUG`) with real SMS + rate limits.
- [ ] Token/session revocation + device binding.
- [ ] Observability + per-env config (dev vs pilot vs production).
