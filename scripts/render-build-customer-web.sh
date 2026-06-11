#!/usr/bin/env bash
# Render Static Site build — installs Flutter SDK then builds customer web.
set -euo pipefail

API_BASE_URL="${API_BASE_URL:-https://navig8r.onrender.com}"
MAPS_API_KEY="${MAPS_API_KEY:-}"
FLUTTER_VERSION="${FLUTTER_VERSION:-3.22.3}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/apps/driver_pilot"
SDK_DIR="${RENDER_PROJECT_ROOT:-$ROOT}/.render/flutter"

echo "==> NaviG8r customer web build"
echo "    API_BASE_URL=$API_BASE_URL"
echo "    FLUTTER_VERSION=$FLUTTER_VERSION"
echo "    APP_DIR=$APP_DIR"
if [ -n "$MAPS_API_KEY" ]; then
  echo "    MAPS_API_KEY=(set)"
else
  echo "    MAPS_API_KEY=(unset — web maps will be blank)"
fi

if [ ! -x "$SDK_DIR/bin/flutter" ]; then
  echo "==> Installing Flutter SDK to $SDK_DIR"
  rm -rf "$SDK_DIR"
  git clone https://github.com/flutter/flutter.git -b "$FLUTTER_VERSION" --depth 1 "$SDK_DIR"
fi

export PATH="$SDK_DIR/bin:$PATH"
export FLUTTER_SUPPRESS_ANALYTICS=true
export CI=true

flutter config --no-analytics --enable-web
flutter --version
flutter precache --web

bash "$ROOT/scripts/inject-maps-api-key.sh"

cd "$APP_DIR"
flutter pub get

DART_DEFINES=(--dart-define="API_BASE_URL=$API_BASE_URL")
if [ -n "$MAPS_API_KEY" ]; then
  DART_DEFINES+=(--dart-define="MAPS_API_KEY=$MAPS_API_KEY")
fi
flutter build web --release "${DART_DEFINES[@]}"

echo "==> Build output: $APP_DIR/build/web"
ls -la "$APP_DIR/build/web" | head -20
