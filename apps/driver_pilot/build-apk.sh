#!/usr/bin/env bash
# Build a release APK with MAPS_API_KEY + API_BASE_URL baked in for Dart.
#
# Native Maps SDK tiles still come from android/local.properties → manifest.
# Geocoding / place search in Dart needs the same key via --dart-define.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

LOCAL_PROPS="$ROOT/android/local.properties"
MAPS_API_KEY="${MAPS_API_KEY:-}"
API_BASE_URL="${API_BASE_URL:-}"

if [[ -z "$MAPS_API_KEY" && -f "$LOCAL_PROPS" ]]; then
  MAPS_API_KEY="$(grep -E '^MAPS_API_KEY=' "$LOCAL_PROPS" | head -1 | cut -d= -f2- || true)"
fi

if [[ -z "$MAPS_API_KEY" ]]; then
  echo "error: MAPS_API_KEY is unset." >&2
  echo "  Add MAPS_API_KEY=... to android/local.properties (Android Maps SDK + this script)," >&2
  echo "  or export MAPS_API_KEY before running." >&2
  exit 1
fi

DART_DEFINES=(--dart-define="MAPS_API_KEY=$MAPS_API_KEY")
if [[ -n "$API_BASE_URL" ]]; then
  DART_DEFINES+=(--dart-define="API_BASE_URL=$API_BASE_URL")
fi

echo "Building release APK…"
echo "  MAPS_API_KEY=(set)"
if [[ -n "$API_BASE_URL" ]]; then
  echo "  API_BASE_URL=$API_BASE_URL"
else
  echo "  API_BASE_URL=(default from Dart — set API_BASE_URL for physical-device / production API)"
fi

flutter build apk --release "${DART_DEFINES[@]}"

echo "APK: $ROOT/build/app/outputs/flutter-apk/app-release.apk"
