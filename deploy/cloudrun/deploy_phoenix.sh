#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${1:-${PROJECT_ID:-}}"
REGION="${2:-${REGION:-us-central1}}"

if [[ -n "$PROJECT_ID" ]]; then
  gcloud config set project "$PROJECT_ID"
fi

gcloud run deploy phoenix-server \
  --image arizephoenix/phoenix:latest \
  --region "$REGION" \
  --allow-unauthenticated \
  --port 6006 \
  --memory 2Gi \
  --cpu 1 \
  --min-instances 1 \
  --set-env-vars PHOENIX_PORT=6006

PHOENIX_URL="$(gcloud run services describe phoenix-server \
  --region "$REGION" \
  --format='value(status.url)')"

printf '\nPhoenix service URL: %s\n' "$PHOENIX_URL"
printf 'PHOENIX_HOST=%s\n' "$PHOENIX_URL"
printf 'PHOENIX_COLLECTOR_ENDPOINT=%s/v1/traces\n' "$PHOENIX_URL"
