#!/usr/bin/env bash
set -euo pipefail

SOURCE_IMAGE="${1:?source image required, e.g. ghcr.io/uwais/navig8r-api}"
DIGEST="${2:?digest required, e.g. sha256:...}"
TARGET_TAG="${3:?target tag required, e.g. beta}"

echo "Promoting ${SOURCE_IMAGE}@${DIGEST} -> ${SOURCE_IMAGE}:${TARGET_TAG}"

docker buildx imagetools create \
  --tag "${SOURCE_IMAGE}:${TARGET_TAG}" \
  "${SOURCE_IMAGE}@${DIGEST}"
