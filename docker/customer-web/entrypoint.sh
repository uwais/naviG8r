#!/bin/sh
set -eu

: "${API_UPSTREAM:?API_UPSTREAM must be set}"
: "${MAPS_API_KEY:?MAPS_API_KEY must be set}"

envsubst '${API_UPSTREAM}' \
  < /etc/nginx/navi8r-nginx.conf.template \
  > /etc/nginx/conf.d/default.conf

# The existing Flutter HTML template contains __MAPS_API_KEY__.
# Inject the environment-specific key only at container startup so
# the same image can be promoted unchanged through Alpha/Beta/Prod.
sed -i "s|__MAPS_API_KEY__|${MAPS_API_KEY}|g" \
  /usr/share/nginx/html/index.html

printf '{"releaseSha":"%s"}\n' "${RELEASE_SHA:-unknown}" \
  > /usr/share/nginx/html/release.json

exec nginx -g 'daemon off;'
