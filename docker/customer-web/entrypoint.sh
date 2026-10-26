#!/bin/sh
set -eu

: "${API_UPSTREAM:?API_UPSTREAM must be set}"
: "${MAPS_API_KEY:?MAPS_API_KEY must be set}"

newline='
'

# Settings are written into JavaScript and HTML, so each must match a strict pattern.
# Never print a value: the logs are shared.
check_setting() {
  case "$2" in
    *"$newline"*) ;;
    *) printf '%s' "$2" | grep -Eq "$3" && return 0 ;;
  esac
  echo "NaviG8r customer-web: $1 is not in the expected format. Fix it and redeploy." >&2
  exit 1
}

check_setting MAPS_API_KEY "$MAPS_API_KEY" '^[A-Za-z0-9_-]+$'

FIREBASE_PROJECT_ID="${FIREBASE_PROJECT_ID:-}"
FIREBASE_WEB_API_KEY="${FIREBASE_WEB_API_KEY:-}"
FIREBASE_WEB_APP_ID="${FIREBASE_WEB_APP_ID:-}"
FIREBASE_MESSAGING_SENDER_ID="${FIREBASE_MESSAGING_SENDER_ID:-}"
firebase_settings=""
firebase_settings_set=0

add_firebase_setting() {
  [ -n "$2" ] || return 0
  check_setting "$1" "$2" "$3"
  firebase_settings="${firebase_settings},
  $1: \"$2\""
  firebase_settings_set=$((firebase_settings_set + 1))
}

# Same patterns as apps/driver_pilot/lib/firebase_app.dart, which reads these values.
add_firebase_setting FIREBASE_PROJECT_ID "$FIREBASE_PROJECT_ID" \
  '^[a-z][a-z0-9-]{4,28}[a-z0-9]$'
add_firebase_setting FIREBASE_WEB_API_KEY "$FIREBASE_WEB_API_KEY" \
  '^AIza[0-9A-Za-z_-]{35}$'
add_firebase_setting FIREBASE_WEB_APP_ID "$FIREBASE_WEB_APP_ID" \
  '^[0-9]{1,3}:[0-9]{6,20}:web:[0-9a-f]{6,40}$'
add_firebase_setting FIREBASE_MESSAGING_SENDER_ID "$FIREBASE_MESSAGING_SENDER_ID" \
  '^[0-9]{6,20}$'

# Some but not all set would quietly leave the site on the old code sign-in.
if [ "$firebase_settings_set" -ne 0 ] && [ "$firebase_settings_set" -ne 4 ]; then
  echo "NaviG8r customer-web: set all four Firebase web settings or none." >&2
  exit 1
fi

envsubst '${API_UPSTREAM}' \
  < /etc/nginx/navi8r-nginx.conf.template \
  > /etc/nginx/conf.d/default.conf

# Google Maps JavaScript SDK
sed -i "s|__MAPS_API_KEY__|${MAPS_API_KEY}|g" \
  /usr/share/nginx/html/index.html

# Runtime configuration used by compiled Flutter Web code.
cat > /usr/share/nginx/html/runtime-config.js <<EOF
window.__NAVI8R_CONFIG__ = {
  MAPS_API_KEY: "${MAPS_API_KEY}"${firebase_settings}
};
EOF

printf '{"releaseSha":"%s"}\n' "${RELEASE_SHA:-unknown}" \
  > /usr/share/nginx/html/release.json

if [ "$firebase_settings_set" -eq 4 ]; then
  echo "NaviG8r customer-web: Firebase phone sign-in settings found."
else
  echo "NaviG8r customer-web: no Firebase web settings; the site uses the old code sign-in."
fi
echo "NaviG8r customer-web runtime configuration complete."
