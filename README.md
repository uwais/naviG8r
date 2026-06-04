## logistics-mvp

Backend-first MVP skeleton for:
- Carrier-published anchor trips
- Instant booking with **payments**: default **`MOCK`** treats freight as captured at booking; set **`PAYMENT_PROVIDER=RAZORPAY`** for **Razorpay test mode** with **authorize at checkout, capture at POD** (see `docs/pilot-api.md`).
- POD triggers payout scheduling
- Payout rule: **POD IST date + 7 calendar days (00:00 IST)**, then **next weekly batch cutoff**
- Weekly cutoff configured as **Wednesday 18:00 IST**
- Pilot API resources for Flutter: see `docs/pilot-api.md`
- Roadmap checklist: see `ROADMAP.md`

### API dependencies (install once)

```bash
cd logistics-mvp/apps/api
npm install
```

This installs Prisma client, the Razorpay SDK, and runs `prisma generate` via `postinstall`.

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
- **Freight estimator** (distance + ₹5/kg when coords exist): override defaults with `FREIGHT_PAISE_PER_KM_SMALL`, `FREIGHT_PAISE_PER_KM_MEDIUM`, `FREIGHT_PAISE_PER_KM_LARGE`, and optional `FREIGHT_MIN_GROSS_PAISE` (see `docs/pilot-api.md`).
- When `NODE_ENV=production`, unauthenticated **demo/admin** JSON and HTML (`/admin`, `/v1/users`, `/carriers`, legacy `POST /anchor-trips`, ledger/payout toys, etc.) return **403** unless you set `ENABLE_LEGACY_DEMO_SURFACE=1`. **Public marketplace** routes used by the customer pilot (`GET /anchor-trips`, quote/book, etc.) stay enabled.
- **Customer shipments** (`GET /shipments`, `GET /shipments/:id`, POD, fail-refund) require `Authorization: Bearer <token>` from `POST /v1/auth/otp/*`. You see shipments tagged to your **CUSTOMER** org (`customerOrgId` / name match when booking logged in), **or** anonymous bookings where you passed **`customerPhone`** on `POST /shipments/book` and it matches your account phone after OTP. Book while logged in as a customer user sets `customerOrgId` on the shipment.
- **Persistence** (see `apps/api/prisma/schema.prisma`):
  - Default **`PERSISTENCE` unset or not `DB`**: in-memory store + **`DATA_FILE`** (path to JSON snapshot; persists on writes).
  - **`PERSISTENCE=DB`**: Postgres via Prisma (`DATABASE_URL` required). Bootstrap schema: `cd apps/api && npx prisma db push`. No importer from legacy `store.json` is wired yet (greenfield pilots only).
- **Razorpay (test)** — set `PAYMENT_PROVIDER=RAZORPAY`, `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET`, and register webhook URL **`POST /v1/payments/razorpay/webhook`** (raw JSON body; header `x-razorpay-signature`). **`GET /health`** reports `persistence` and `paymentProvider`.
- **Carrier payouts** (`PAYOUTS_MODE`) — controls how `POST /payout-batches/run` settles carrier earnings. This is **independent** of `PAYMENT_PROVIDER`: `PAYMENT_PROVIDER` governs charging the **customer**, while `PAYOUTS_MODE` governs paying the **carrier**.
  - **Unset / `BOOKKEEPING` (default):** the payout batch is **bookkeeping only** — eligible ledger lines flip `ACCRUED → PAID` and a per-carrier transfer record is written, but **no money actually leaves the account**. Use this for the pilot until real disbursement is needed. Carrier payout setup (`POST /v1/pilot/carrier/payout-setup`) just records intent (`kycStatus=SUBMITTED`); the optional `accountNumber` is accepted but not used.
  - **`RAZORPAYX`:** the batch creates a **real RazorpayX payout per carrier** (reuses the `RAZORPAY_KEY_ID`/`RAZORPAY_KEY_SECRET` test keys). Requires **`RAZORPAYX_ACCOUNT_NUMBER`** (your RazorpayX source account); optional **`RAZORPAYX_PAYOUT_MODE`** = `IMPS` (default) | `NEFT` | `RTGS` | `UPI`. Payout setup now provisions a RazorpayX contact + bank fund account (so `accountNumber` becomes required), and carriers without a fund account are **skipped** (their lines stay `ACCRUED` to retry once setup completes); transfers that error are marked `FAILED` and retried on the next run.
  - **Role-gated:** `POST /payout-batches/run`, `GET /payout-batches`, and `GET /carriers/:id/ledger` require an **Ops Admin/Agent** bearer token in both modes.

### Flutter customer checkout (Razorpay)

The driver pilot app’s customer book flow opens **Razorpay Flutter** checkout when `POST /shipments/book` returns **`razorpayKeyId`** and payment status **`CREATED`**. Successful payment completes **authorization**; the server learns state from **webhooks** (`payment.authorized` / `payment.failed`). **Capture** runs on **POD** (`POST /shipments/:id/pod`). Configure the same Razorpay key id on the device as returned by the API.

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

