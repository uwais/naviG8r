#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../apps/www"
npm install
# Optional build-time env (Render Dashboard):
#   VITE_TURNSTILE_SITE_KEY — contact + Explore Turnstile (skips FormSubmit captcha)
npm run build
