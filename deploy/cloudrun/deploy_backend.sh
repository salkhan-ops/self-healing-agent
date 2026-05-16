#!/usr/bin/env bash
set -euo pipefail

REGION="${REGION:-us-central1}"
SERVICE_NAME="${SERVICE_NAME:-self-healing-agent-backend}"
PHOENIX_HOST="${PHOENIX_HOST:-}"

if [[ -z "$PHOENIX_HOST" ]]; then
  echo "PHOENIX_HOST is required."
  echo "Example:"
  echo "  PHOENIX_HOST=https://phoenix-server-xxxxx.run.app ./deploy/cloudrun/deploy_backend.sh"
  exit 1
fi

if ! gcloud secrets describe GOOGLE_API_KEY >/dev/null 2>&1; then
  echo "Missing Secret Manager secret: GOOGLE_API_KEY"
  echo 'Create it with:'
  echo '  printf "YOUR_KEY" | gcloud secrets create GOOGLE_API_KEY --data-file=-'
  exit 1
fi

gcloud run deploy "$SERVICE_NAME" \
  --source . \
  --region "$REGION" \
  --allow-unauthenticated \
  --memory 2Gi \
  --cpu 1 \
  --timeout 900 \
  --set-env-vars "APP_ENV=production,PHOENIX_HOST=$PHOENIX_HOST,PHOENIX_COLLECTOR_ENDPOINT=$PHOENIX_HOST/v1/traces,PHOENIX_PROJECT_NAME=self-healing-agent,GEMINI_MODEL_NAME=gemini-2.5-flash,SEC_USER_AGENT=SelfHealingAgent/1.0 your_email@example.com" \
  --set-secrets GOOGLE_API_KEY=GOOGLE_API_KEY:latest

BACKEND_URL="$(gcloud run services describe "$SERVICE_NAME" \
  --region "$REGION" \
  --format='value(status.url)')"

printf '\nBackend service URL: %s\n' "$BACKEND_URL"
printf 'Health test: curl %s/health\n' "$BACKEND_URL"
printf 'Flutter API base: %s\n' "$BACKEND_URL"
