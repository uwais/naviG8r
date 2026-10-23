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

3) Google Maps key (required for Publish map search / reverse-geocode):

Add to `android/local.properties` (gitignored):

```properties
MAPS_API_KEY=your_android_restricted_key
```

Enable **Maps SDK for Android** + **Geocoding API** on that key (package `com.navig8r.pilot` + SHA-1).

The key is used in **two** places:

| Path | Purpose |
|------|---------|
| `android/local.properties` → Gradle manifest placeholder | Native map **tiles** |
| `--dart-define=MAPS_API_KEY=…` at build/run | Dart **geocoding** / address look-up |

If you only set `local.properties`, map tiles can still render but Publish shows:
`Set MAPS_API_KEY (--dart-define) for look up` / SnackBar about `--dart-define`.

4) Build APK (preferred — passes dart-define from `local.properties`):

```bash
cd apps/driver_pilot
# Optional: point physical devices at your API
export API_BASE_URL=https://your-api.example.com
chmod +x build-apk.sh
./build-apk.sh
```

Or manually:

```bash
cd apps/driver_pilot
flutter build apk --release \
  --dart-define=MAPS_API_KEY="$(grep '^MAPS_API_KEY=' android/local.properties | cut -d= -f2-)" \
  --dart-define=API_BASE_URL=https://your-api.example.com
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

### Live GPS on customer view (not caused by MAPS_API_KEY)

Publishing a load alone does **not** enable customer live tracking. Missing GPS after publish is almost always the trip lifecycle / driver session, not the geocoding snackbar.

Customer `isLive` is true only when **all** of these hold (see `docs/pilot-api.md`):

1. Customer booking is **`BOOKED`** (carrier accepted).
2. Carrier tapped **Start load** → trip status **`IN_PROGRESS`**.
3. Driver keeps the **active trip** screen open (app posts GPS ~every 30s from that screen).
4. Last ping is fresher than ~15 minutes.

Leaving the active-trip screen (or killing the app) stops pings; customer UI then shows “waiting for driver GPS” or stale signal.

You can still publish with pin drag if geocoding is broken; lane pins and live GPS are independent of address look-up.

### Android location permission

The app declares `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION` only — **not** `ACCESS_BACKGROUND_LOCATION`.

- Grant **“While using the app”** (or “Allow only while using”). That is enough for the current pilot.
- **“Allow all the time”** is **not** required and is unused (no background location service).
- GPS is sampled while the driver is on the active-trip map screen; it does not continue as a background “always” tracker.

### Notes / pitfalls
- **Cleartext HTTP** is enabled for pilot demos via `network_security_config.xml`. Move to **HTTPS** before a broad external pilot.
- If Gradle is Kotlin DSL (`build.gradle.kts`) on your Flutter version, release signing injection may need manual steps (see Flutter docs). The Python injector supports the common **Groovy** `android/app/build.gradle` template.
- Rebuild the APK after adding `MAPS_API_KEY` / `--dart-define` — a previously installed APK will not pick up a new dart-define until reinstalled.

---

## Apr 30, 2026 — Roadmap (Android pilot)

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
- [x] **Session UX**: show “logged in as …” from `GET /v1/pilot/me`, plus **logout** (clear token).
- [x] **Trips UX**: pull-to-refresh, and a **trip detail** view (copy trip id, show raw JSON).
- [x] **Publish UX**: on success, show a snackbar and optionally **jump to Trips**.

### Next (medium-term: customer flow UI)
- [x] Create a small **customer pilot UI** (implemented as a mode inside the same app):
  - [x] Customer register (`POST /v1/pilot/customer/register`)
  - [x] Browse open trips (`GET /anchor-trips`)
  - [x] Quote + book (`POST /shipments/quote`, `POST /shipments/book`)
  - [x] Track shipment + simulate POD/refund (`GET /shipments`, `GET /shipments/:id`, `POST /shipments/:id/pod`, `POST /shipments/:id/fail-refund`)

### Hardening (before broad external pilot)
- [ ] Replace debug OTP (`OTP_DEBUG`) with real SMS + rate limits.
- [ ] Token/session revocation + device binding.
- [ ] Observability + per-env config (dev vs pilot vs production).
