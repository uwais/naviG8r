#!/bin/sh
set -eu

: "${API_UPSTREAM:?API_UPSTREAM must be set}"
: "${MAPS_API_KEY:?MAPS_API_KEY must be set}"

envsubst '${API_UPSTREAM}' \
  < /etc/nginx/navi8r-nginx.conf.template \
  > /etc/nginx/conf.d/default.conf

sed -i "s|__MAPS_API_KEY__|${MAPS_API_KEY}|g" \
  /usr/share/nginx/html/index.html

printf '{"releaseSha":"%s"}\n' "${RELEASE_SHA:-unknown}" \
  > /usr/share/nginx/html/release.json

echo "NaviG8r customer-web runtime configuration complete."