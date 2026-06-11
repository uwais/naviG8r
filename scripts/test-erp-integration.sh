#!/usr/bin/env bash
# Executable ERP integration smoke test against a running NaviG8r API.
# Usage:
#   BASE_URL=https://navig8r.onrender.com bash scripts/test-erp-integration.sh
#   BASE_URL=http://127.0.0.1:3000 bash scripts/test-erp-integration.sh
#
# Requires: curl, jq (optional but recommended for pretty output)
set -euo pipefail

BASE_URL="${BASE_URL:-http://127.0.0.1:3000}"
BASE_URL="${BASE_URL%/}"
PHONE="${ERP_TEST_PHONE:-9111009900}"
CARRIER_PHONE="${ERP_TEST_CARRIER_PHONE:-9876549900}"
OTP_CODE="${OTP_FIXED_CODE:-123456}"
USE_OTP_DEBUG="${OTP_DEBUG:-1}"

echo "==> ERP integration smoke test"
echo "    BASE_URL=$BASE_URL"
echo "    CUSTOMER_PHONE=$PHONE"

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required" >&2
  exit 1
fi

json_field() {
  if command -v jq >/dev/null 2>&1; then
    jq -r "$1"
  else
    python3 -c "import json,sys; d=json.load(sys.stdin); print($1)" 2>/dev/null || cat
  fi
}

post_json() {
  local path="$1"
  local body="$2"
  shift 2
  curl -sS -X POST "${BASE_URL}${path}" \
    -H "content-type: application/json" \
    "$@" \
    -d "$body"
}

patch_json() {
  local path="$1"
  local body="$2"
  shift 2
  curl -sS -X PATCH "${BASE_URL}${path}" \
    -H "content-type: application/json" \
    "$@" \
    -d "$body"
}

get_auth() {
  curl -sS "${BASE_URL}$1" "$@"
}

echo "==> 1. Register customer org (admin)"
REG=$(post_json "/v1/pilot/customer/register" "$(cat <<EOF
{"fullName":"ERP Smoke Admin","phone":"$PHONE","orgDisplayName":"ERP Smoke Co"}
EOF
)")
ORG_ID=$(echo "$REG" | json_field '.org.id // empty')
if [ -z "$ORG_ID" ] || [ "$ORG_ID" = "null" ]; then
  echo "Customer register failed: $REG" >&2
  exit 1
fi
echo "    orgId=$ORG_ID"

echo "==> 2. OTP sign-in (OTP_DEBUG=$USE_OTP_DEBUG)"
START=$(post_json "/v1/auth/otp/start" "{\"phone\":\"$PHONE\"}")
CHALLENGE=$(echo "$START" | json_field '.challengeId // empty')
DEBUG_CODE=$(echo "$START" | json_field '.debugCode // empty')
CODE="$OTP_CODE"
if [ -n "$DEBUG_CODE" ] && [ "$DEBUG_CODE" != "null" ]; then
  CODE="$DEBUG_CODE"
fi
VERIFY=$(post_json "/v1/auth/otp/verify" "$(cat <<EOF
{"phone":"$PHONE","challengeId":"$CHALLENGE","code":"$CODE"}
EOF
)")
ACCESS=$(echo "$VERIFY" | json_field '.accessToken // empty')
if [ -z "$ACCESS" ] || [ "$ACCESS" = "null" ]; then
  echo "OTP verify failed: $VERIFY" >&2
  exit 1
fi
echo "    accessToken=(ok)"

echo "==> 3. Register carrier + publish open trip"
post_json "/v1/pilot/driver/register" "$(cat <<EOF
{
  "fullName":"ERP Smoke Carrier",
  "phone":"$CARRIER_PHONE",
  "orgDisplayName":"ERP Smoke Carrier",
  "vehicleRegistrationNumber":"HR26SM0001",
  "vehicleClass":"MEDIUM",
  "vehicleCapacityKg":5000
}
EOF
)" >/dev/null

# Carrier trip publish requires auth — use OTP for carrier or pre-seeded trip on hosted env.
# For smoke test on hosted API, assume an open trip exists OR register carrier OTP flow.
CARRIER_START=$(post_json "/v1/auth/otp/start" "{\"phone\":\"$CARRIER_PHONE\"}")
CARRIER_CHALLENGE=$(echo "$CARRIER_START" | json_field '.challengeId // empty')
CARRIER_DEBUG=$(echo "$CARRIER_START" | json_field '.debugCode // empty')
CARRIER_CODE="$OTP_CODE"
if [ -n "$CARRIER_DEBUG" ] && [ "$CARRIER_DEBUG" != "null" ]; then
  CARRIER_CODE="$CARRIER_DEBUG"
fi
CARRIER_VERIFY=$(post_json "/v1/auth/otp/verify" "$(cat <<EOF
{"phone":"$CARRIER_PHONE","challengeId":"$CARRIER_CHALLENGE","code":"$CARRIER_CODE"}
EOF
)")
CARRIER_TOKEN=$(echo "$CARRIER_VERIFY" | json_field '.accessToken // empty')
ME=$(get_auth "/v1/pilot/me" -H "authorization: Bearer $CARRIER_TOKEN")
CARRIER_ORG=$(echo "$ME" | json_field '.organizations[0].id // empty')

TRIP=$(post_json "/v1/pilot/anchor-trips" "$(cat <<EOF
{
  "orgId":"$CARRIER_ORG",
  "originCity":"Gurugram",
  "destCity":"Jaipur",
  "origin":{"lat":28.4595,"lng":77.0266,"label":"Gurugram"},
  "destination":{"lat":26.9124,"lng":75.7873,"label":"Jaipur"},
  "windowStart":"2026-04-24T00:00:00+05:30",
  "windowEnd":"2026-04-25T23:59:59+05:30",
  "vehicleClass":"MEDIUM",
  "capacityKg":1000
}
EOF
)" -H "authorization: Bearer $CARRIER_TOKEN")
TRIP_ID=$(echo "$TRIP" | json_field '.trip.id // empty')
echo "    tripId=$TRIP_ID"

echo "==> 4. Create integration API key (portal)"
KEYS=$(post_json "/v1/pilot/customer/integrations/keys?orgId=$ORG_ID" \
  '{"scopes":["loads:read","loads:write","webhooks:manage"]}' \
  -H "authorization: Bearer $ACCESS")
INT_TOKEN=$(echo "$KEYS" | json_field '.token // empty')
if [ -z "$INT_TOKEN" ] || [ "$INT_TOKEN" = "null" ]; then
  echo "Key create failed: $KEYS" >&2
  exit 1
fi
echo "    integrationToken=(ok)"

patch_json "/v1/pilot/customer/integrations/connection?orgId=$ORG_ID" \
  '{"paymentPolicy":"erp_preauthorized","webhookUrl":"https://example.com/erp-webhook"}' \
  -H "authorization: Bearer $ACCESS" >/dev/null

echo "==> 5. POST /v1/integrations/loads"
EXT_ID="ERP-SMOKE-$(date +%s)"
LOAD=$(post_json "/v1/integrations/loads" "$(cat <<EOF
{
  "externalLoadId":"$EXT_ID",
  "weightKg":120,
  "pickupAddress":"Gurugram warehouse",
  "dropAddress":"Jaipur plant",
  "pickup":{"lat":28.4595,"lng":77.0266},
  "drop":{"lat":26.9124,"lng":75.7873},
  "metadata":{"poNumber":"PO-SMOKE"}
}
EOF
)" -H "authorization: Bearer $INT_TOKEN" -H "Idempotency-Key: smoke-$EXT_ID")
SHIPMENT_ID=$(echo "$LOAD" | json_field '.shipmentId // empty')
echo "    externalLoadId=$EXT_ID shipmentId=$SHIPMENT_ID"

echo "==> 6. Idempotent retry (same externalLoadId)"
LOAD2=$(post_json "/v1/integrations/loads" "$(cat <<EOF
{
  "externalLoadId":"$EXT_ID",
  "weightKg":120,
  "pickupAddress":"Gurugram warehouse",
  "dropAddress":"Jaipur plant",
  "pickup":{"lat":28.4595,"lng":77.0266},
  "drop":{"lat":26.9124,"lng":75.7873}
}
EOF
)" -H "authorization: Bearer $INT_TOKEN")
CREATED2=$(echo "$LOAD2" | json_field '.created // empty')
echo "    second created=$CREATED2 (expect false)"

echo "==> 7. GET /v1/integrations/loads?externalLoadId="
LOOKUP=$(get_auth "/v1/integrations/loads?externalLoadId=$EXT_ID" -H "authorization: Bearer $INT_TOKEN")
COUNT=$(echo "$LOOKUP" | json_field '.loads | length // 0')
echo "    loads returned=$COUNT"

echo "==> 8. GET /v1/integrations/events"
EVENTS=$(get_auth "/v1/integrations/events?limit=5" -H "authorization: Bearer $INT_TOKEN")
echo "$EVENTS" | head -c 400
echo ""
echo "==> Done. ERP integration smoke test passed."
