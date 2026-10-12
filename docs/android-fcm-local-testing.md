# Test Android FCM notifications against a local API

This guide uses a separate local FILE store and a Firebase development project. It does not use production data or credentials. A push is created only for a new notification after device registration; registering does not backfill old notifications.

## 1. Configure a Firebase development app

In Firebase Console, create or select a **development-only** project, register an Android app with package ID `com.navig8r.pilot`, and enable Firebase Cloud Messaging. Copy the Android app's `apiKey`, `appId`, `messagingSenderId`, and `projectId`; these are client configuration values, not the server credential.

Create a development service-account credential with permission to send FCM messages. Keep its JSON outside the repository. The API reads it from `FCM_SERVICE_ACCOUNT_JSON`; do not put it in Flutter `--dart-define`, commit it, or use a production service account.

## 2. Start an isolated local API

From the repository root, choose the computer's Wi-Fi IPv4 address (for example `192.168.1.24`) and allow inbound TCP port 3000 through its firewall. Create a new local store path and start the API in the same terminal:

```bash
mkdir -p apps/api/data
export AUTH_SECRET="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"
export OTP_DEBUG=1
export DATA_FILE=apps/api/data/fcm-dev-store.json
export PUSH_DEVICE_REGISTRATION_ENABLED=1
export PUSH_ENQUEUE_ENABLED=1
export PUSH_SENDER_ENABLED=1
export PUSH_ENVIRONMENT=DEVELOPMENT
export PUSH_TOKEN_ENCRYPTION_KEY="$(openssl rand -base64 32)"
export FCM_SERVICE_ACCOUNT_JSON="$(cat /path/outside/repository/firebase-dev-service-account.json)"
node --experimental-strip-types apps/api/src/index.ts
```

This runs single-process FILE persistence for local testing. The API binds to `0.0.0.0:3000`; from the Android device's browser, verify `http://<LAN-IP>:3000/health` returns `{"ok":true,...}`. The phone and computer both need internet access so the phone can reach FCM and the API can call Google.

Keep these enabled flags and credentials in that terminal only. To stop sending, stop the API or set `PUSH_SENDER_ENABLED=0` and restart it. Use a fresh local store for clean scenarios.

## 3. Build and install a debug APK

Use Flutter 3.22.3, the repository's CI baseline (`flutter --version` should report that version). From `apps/driver_pilot`, replace `<LAN-IP>` and the four Firebase values with the development project settings:

```bash
flutter pub get
flutter build apk --debug \
  --dart-define=API_BASE_URL=http://<LAN-IP>:3000 \
  --dart-define=FIREBASE_API_KEY=<firebase-api-key> \
  --dart-define=FIREBASE_APP_ID=<firebase-app-id> \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=<sender-id> \
  --dart-define=FIREBASE_PROJECT_ID=<firebase-project-id>
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

If an earlier debug APK was installed before the AndroidX Window compatibility
fix, uninstall it once before installing the rebuilt APK:

```bash
adb uninstall com.navig8r.pilot
adb install build/app/outputs/flutter-apk/app-debug.apk
```

The uninstall is needed because Android cannot update an installation signed
with a different key or carrying the incompatible earlier native dependency.

USB debugging must be enabled and `adb devices` must list the phone. Alternatively copy the generated APK to the phone and install it. The debug manifest permits cleartext HTTP for the LAN API; the release manifest does not enable cleartext traffic. Keep Firebase values out of committed source and do not use the debug APK for production.

## 4. Enable alerts and generate a new shipment event

1. Open the app and register or sign in as a local shipper or carrier. With an empty FILE store, create local test accounts and a shipment using the existing app flows; no production backup is needed.
2. Open **Notifications** and choose **Enable alerts on this device**. Allow Android notifications. On Android 12 the app still requires this explicit opt-in; Android 13 and later also show the system permission prompt.
3. Keep the API running and confirm the FCM registration succeeds. The app stores only the installation ID and notification consent locally; the API encrypts the FCM token in the local Store.
4. Create a new shipment notification after registration, such as booking a load or accepting/starting a trip with the other shipment actor. A pre-existing notification will not send a push.
5. With the app in the foreground, confirm a generic “Shipment update” appears in Android's notification tray. Send another event for the same shipment; it should replace that shipment's tray item. An event for another shipment should have a separate item.
6. Tap the notification. The app should call the authenticated notification-open resolver and open the authorized shipment conversation. The payload itself must not decide the shipment route.
7. Repeat with the app backgrounded and then terminated. On Android 13+, also test deny permission, enable it later in Android Settings, return to the app, and verify the app refreshes registration. Sign out and confirm the visible app notifications are cleared.

## Troubleshooting

- If **Enable alerts** is unavailable, the APK was built without the Firebase `--dart-define` values. Rebuild with the development Firebase app values.
- If registration does not succeed, check that all three push flags are `1`, `PUSH_TOKEN_ENCRYPTION_KEY` decodes to 32 bytes, API base URL points to the LAN IP, and the user has a current SHIPPER or CARRIER membership.
- If the API responds with FCM auth errors, verify the service-account project matches `FIREBASE_PROJECT_ID` and that the credential can send FCM messages.
- If the phone cannot open `/health`, verify both devices are on the same Wi-Fi, use the computer's LAN IP rather than `localhost`, bind/firewall port 3000, and ensure router client isolation is off.
- FCM is best-effort. Force-stopping the app from Android Settings can prevent background delivery until the user opens it again. The in-app notification inbox remains authoritative.
