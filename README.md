## logistics-mvp

Backend-first MVP skeleton for:
- Carrier-published anchor trips
- Instant booking (payment captured at booking; mocked)
- POD triggers payout scheduling
- Payout rule: **POD IST date + 7 calendar days (00:00 IST)**, then **next weekly batch cutoff**
- Weekly cutoff configured as **Wednesday 18:00 IST**
- Pilot API resources for Flutter: see `docs/pilot-api.md`

### Run API (Node 22+)

```bash
cd logistics-mvp
export AUTH_SECRET="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"
# Optional (local dev only): echo OTP codes in API responses
export OTP_DEBUG=1
node --experimental-strip-types apps/api/src/index.ts
```

API listens on `http://localhost:3000`.

Notes:
- `AUTH_SECRET` is **required** (min 16 chars). Without it, the API exits on startup.
- For quick local testing, `OTP_DEBUG=1` makes `/v1/auth/otp/start` return `debugCode` (see `docs/pilot-api.md`).
- When `NODE_ENV=production`, unauthenticated **demo/admin** JSON and HTML (`/admin`, `/v1/users`, `/carriers`, legacy `POST /anchor-trips`, ledger/payout toys, etc.) return **403** unless you set `ENABLE_LEGACY_DEMO_SURFACE=1`. **Public marketplace** routes used by the customer pilot (`GET /anchor-trips`, quote/book, etc.) stay enabled.
- **Customer shipments** (`GET /shipments`, `GET /shipments/:id`, POD, fail-refund) require `Authorization: Bearer <token>` from `POST /v1/auth/otp/*`. You see shipments tagged to your **CUSTOMER** org (`customerOrgId` / name match when booking logged in), **or** anonymous bookings where you passed **`customerPhone`** on `POST /shipments/book` and it matches your account phone after OTP. Book while logged in as a customer user sets `customerOrgId` on the shipment.

### Run tests

```bash
cd logistics-mvp
node --experimental-strip-types --test "packages/**/src/**/*.test.ts" "apps/**/src/**/*.test.ts"
```

### Key files
- `packages/core/src/payoutSchedule.ts`: IST + T+7 + weekly cutoff computation
- `apps/api/src/services.ts`: publish trip, book, POD->ledger, run payout batch
- `apps/api/src/httpServer.ts`: minimal REST API
- `docs/pilot-api.md`: pilot `/v1/pilot/*` resources for Driver-first onboarding
- `apps/driver_pilot/`: minimal Flutter Driver pilot app (Android APK Option A)
- `docs/android-option-a-apk-pilot.md`: build/install signed APK + emulator demo steps
- `docs/DEPLOY.md`: GitHub push + notes on external hosting (Vercel vs API)
- `docs/RENDER.md`: deploy the Node API to Render (Docker + disk + env vars)

