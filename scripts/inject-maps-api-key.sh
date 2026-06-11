#!/usr/bin/env bash
# Injects MAPS_API_KEY into apps/driver_pilot/web/index.html for Google Maps on Flutter web.
# Idempotent: resets from index.template.html then substitutes the placeholder.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${APP_DIR:-$ROOT/apps/driver_pilot}"
TEMPLATE="$APP_DIR/web/index.template.html"
INDEX="$APP_DIR/web/index.html"
PLACEHOLDER="__MAPS_API_KEY__"

# Load local key file when MAPS_API_KEY is not in the environment.
ENV_FILE="$APP_DIR/.env.maps"
if [ -z "${MAPS_API_KEY:-}" ] && [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  set -a
  source "$ENV_FILE"
  set +a
fi
if [ -z "${MAPS_API_KEY:-}" ] && [ -f "$APP_DIR/android/local.properties" ]; then
  MAPS_API_KEY="$(grep -E '^MAPS_API_KEY=' "$APP_DIR/android/local.properties" | head -1 | cut -d= -f2- || true)"
fi

if [ ! -f "$TEMPLATE" ]; then
  echo "inject-maps-api-key: missing template $TEMPLATE" >&2
  exit 1
fi

cp "$TEMPLATE" "$INDEX"

if [ -z "${MAPS_API_KEY:-}" ]; then
  echo "inject-maps-api-key: MAPS_API_KEY unset — web map tiles will be blank (tracking still works)."
  sed -i.bak '/BEGIN MAPS_API_SCRIPT/,/END MAPS_API_SCRIPT/d' "$INDEX" && rm -f "$INDEX.bak"
  exit 0
fi

if [[ "$MAPS_API_KEY" == *"$PLACEHOLDER"* ]]; then
  echo "inject-maps-api-key: MAPS_API_KEY looks like the placeholder; refusing to inject." >&2
  exit 1
fi

# Escape sed replacement (key is alphanumeric but be safe for & and /).
ESCAPED_KEY="$(printf '%s' "$MAPS_API_KEY" | sed 's/[&/\]/\\&/g')"
sed -i.bak "s/${PLACEHOLDER}/${ESCAPED_KEY}/g" "$INDEX" && rm -f "$INDEX.bak"
echo "inject-maps-api-key: injected Maps JavaScript API key into $INDEX"
