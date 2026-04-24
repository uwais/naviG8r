#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter not found on PATH. Install Flutter SDK, then re-run:"
  echo "  cd \"$ROOT\" && ./bootstrap.sh"
  exit 1
fi

if [[ ! -d android ]]; then
  echo "Generating Android platform files (flutter create)..."
  flutter create . --project-name driver_pilot --org com.logisticsmvp --platforms=android
fi

flutter pub get

echo "Patching Android pilot wiring (cleartext + optional release signing)..."
python3 tool/inject_android_pilot_wiring.py

echo "Done."
echo "Next:"
echo "  - Debug on emulator: flutter run -d emulator"
echo "  - Release APK: copy key.properties.example → android/key.properties + keystore, then:"
echo "      flutter build apk --release"
