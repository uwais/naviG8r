#!/bin/sh
set -eu

# The Vite app reads these values from window.__NAVI8R_CONFIG__.
# Keep environment-specific settings outside the image.
cat > /usr/share/nginx/html/runtime-config.js <<EOF
window.__NAVI8R_CONFIG__ = {
  TURNSTILE_SITE_KEY: "${VITE_TURNSTILE_SITE_KEY:-}",
  PORTAL_URL: "${PORTAL_URL:-}"
};
EOF

printf '{"releaseSha":"%s"}\n' "${RELEASE_SHA:-unknown}" \
  > /usr/share/nginx/html/release.json

exec nginx -g 'daemon off;'
