## `driver_pilot` (Flutter — Android Option A)

Minimal pilot UI for:
- `GET /health`
- `POST /v1/pilot/driver/register`
- `POST /v1/auth/otp/start` + `POST /v1/auth/otp/verify`
- `POST /v1/pilot/anchor-trips` (Bearer)

### Bootstrap (requires Flutter SDK)

```bash
cd apps/driver_pilot
chmod +x bootstrap.sh
./bootstrap.sh
```

### Maps + release APK

1. Set `MAPS_API_KEY=…` in `android/local.properties` (native map tiles).
2. Pass the same key to Dart geocoding via `--dart-define` (or use `./build-apk.sh`).

Without `--dart-define`, Publish shows “Set MAPS_API_KEY (--dart-define) for look up” even if tiles still render.

Live customer GPS requires **Start load** (`IN_PROGRESS`) + driver on the active-trip screen with **While using the app** location — not “Allow all the time”. See `../../docs/android-option-a-apk-pilot.md`.

### Docs
See `../../docs/android-option-a-apk-pilot.md`.
