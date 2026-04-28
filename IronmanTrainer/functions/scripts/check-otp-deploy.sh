#!/usr/bin/env bash
# Post-deploy smoke for the requestOTP Cloud Function.
#
# Hits the deployed endpoint with ?dryRun=true and asserts that
# smtp_configured is true. This catches the regression where a deploy
# uploads code but not the SMTP_EMAIL/SMTP_PASSWORD env vars — the bug
# we hit on 2026-04-27 where users got "Code sent" but no email ever
# arrived.
#
# Usage:  bash functions/scripts/check-otp-deploy.sh
# Or:     (cd functions && npm run check-otp-deploy)
#
# Exits non-zero on failure so it can gate a deploy script.

set -euo pipefail

URL="${OTP_URL:-https://us-central1-brents-trainer.cloudfunctions.net/requestOTP}"

echo "Probing $URL?dryRun=true ..."
RESPONSE=$(curl -sS -w "\n%{http_code}" "$URL?dryRun=true")
BODY=$(echo "$RESPONSE" | sed '$d')
CODE=$(echo "$RESPONSE" | tail -n1)

echo "HTTP $CODE"
echo "$BODY"

if [ "$CODE" != "200" ]; then
  echo "FAIL: dry-run probe returned non-200 status"
  exit 1
fi

if echo "$BODY" | grep -q '"smtp_configured":true'; then
  echo "OK: SMTP creds present on deployed instance"
else
  echo "FAIL: smtp_configured is not true on deployed instance — redeploy with functions/.env populated"
  exit 1
fi
