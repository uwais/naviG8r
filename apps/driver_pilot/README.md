## `driver_pilot` (Flutter — Android Option A)

One Flutter binary serving three personas — driver, carrier and customer. `kIsWeb` picks the
shell at startup: the Android APK opens at `/driver`, the web build at `/customer`.

This was once a minimal pilot UI over four endpoints. It is not any more: as of 2026-09-15 the
app calls at least 27 distinct `/v1/*` paths, so this file no longer lists them. 27 is the count of distinct literal path prefixes the grep below returns; interpolated ids truncate the match, so `"/v1/pilot/anchor-trips/` alone stands for four routes. The app also calls routes outside `/v1` that the grep does not see, including `/health`, `/anchor-trips`, `/shipments`, `/shipments/quote` and `/shipments/book`. The API reference is
[`../../docs/pilot-api.md`](../../docs/pilot-api.md); to see what this app actually calls, run
`grep -ohE '"/v1/[a-zA-Z0-9/_-]+' lib/*.dart | sort -u`.

### Bootstrap (requires Flutter SDK)

```bash
cd apps/driver_pilot
chmod +x bootstrap.sh
./bootstrap.sh
```

### Docs
See `../../docs/android-option-a-apk-pilot.md`.
