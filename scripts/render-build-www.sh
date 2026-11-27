#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../apps/www"
npm install
# Optional build-time env (Render Dashboard / image runtime preferred):
#   FORMSPREE_FORM_ID / VITE_FORMSPREE_FORM_ID — Formspree form id
#   VITE_TURNSTILE_SITE_KEY — contact + Explore Turnstile
npm run build
