#!/usr/bin/env bash
set -euo pipefail

URL="${1:?URL required}"
EXPECTED="${2:?expected release SHA required}"
LABEL="${3:-service}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-900}"
SLEEP_SECONDS="${SLEEP_SECONDS:-30}"

start="$(date +%s)"

echo "Waiting for ${LABEL}: ${URL} to report release ${EXPECTED}"

while true; do
  body="$(curl -fsSL --max-time 15 "${URL}" 2>/dev/null || true)"

  if [[ "${body}" == *"${EXPECTED}"* ]]; then
    echo "${LABEL} is serving ${EXPECTED}"
    exit 0
  fi

  now="$(date +%s)"
  if (( now - start >= TIMEOUT_SECONDS )); then
    echo "Timed out waiting for ${LABEL}" >&2
    echo "Last response: ${body}" >&2
    exit 1
  fi

  sleep "${SLEEP_SECONDS}"
done
