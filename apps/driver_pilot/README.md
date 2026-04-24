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

### Docs
See `../../docs/android-option-a-apk-pilot.md`.
