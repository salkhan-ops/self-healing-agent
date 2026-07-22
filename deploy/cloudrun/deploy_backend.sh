#!/usr/bin/env bash
set -euo pipefail

if [[ "${ALLOW_ARCHIVED_DEPLOY:-false}" != "true" ]]; then
  echo "This project is archived and Cloud Run/Gemini deployment is disabled." >&2
  echo "Set ALLOW_ARCHIVED_DEPLOY=true only if you intentionally want to restore it." >&2
  exit 1
fi

REGION="${REGION:-us-central1}"
SERVICE_NAME="${SERVICE_NAME:-self-healing-agent-backend}"
PHOENIX_HOST="${PHOENIX_HOST:-}"

if [[ -z "$PHOENIX_HOST" ]]; then
  echo "PHOENIX_HOST is required."
  echo "Example:"
  echo "  PHOENIX_HOST=http://localhost:6006 ./deploy/cloudrun/deploy_backend.sh"
  exit 1
fi

gcloud run deploy "$SERVICE_NAME" \
  --source . \
  --region "$REGION" \
  --allow-unauthenticated \
  --memory 2Gi \
  --cpu 1 \
  --timeout 900 \
  --set-env-vars "DISABLE_LLM_CALLS=true,PUBLIC_DEMO_MODE=true,APP_ENV=production,PHOENIX_HOST=$PHOENIX_HOST,PHOENIX_COLLECTOR_ENDPOINT=$PHOENIX_HOST/v1/traces,PHOENIX_PROJECT_NAME=self-healing-agent,GEMINI_MODEL_NAME=gemini-2.5-flash,SEC_USER_AGENT=SelfHealingAgent/1.0 archived"

BACKEND_URL="$(gcloud run services describe "$SERVICE_NAME" \
  --region "$REGION" \
  --format='value(status.url)')"

printf '\nBackend service URL: %s\n' "$BACKEND_URL"
printf 'Health test: curl %s/health\n' "$BACKEND_URL"
printf 'Flutter API base: %s\n' "$BACKEND_URL"
