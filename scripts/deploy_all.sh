#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LANDING_DIR="${LANDING_DIR:-/Users/salmankhan/StudioProjects/self-healing-agent-landing}"

GCP_PROJECT="${SELF_HEALING_GCP_PROJECT:-gen-lang-client-0880901302}"
SERVICE_NAME="${SELF_HEALING_SERVICE_NAME:-self-healing-agent}"
REGION="${SELF_HEALING_REGION:-us-central1}"
BACKEND_URL="${SELF_HEALING_BACKEND_URL:-https://self-healing-agent-65778886250.us-central1.run.app}"
PHOENIX_HOST="${PHOENIX_HOST:-https://phoenix-server-fwelzysgnq-uc.a.run.app}"
PHOENIX_COLLECTOR_ENDPOINT="${PHOENIX_COLLECTOR_ENDPOINT:-$PHOENIX_HOST/v1/traces}"
PAGES_COMMIT_MESSAGE="${PAGES_COMMIT_MESSAGE:-Update self-healing app}"
PUBLIC_DEMO_MODE="${PUBLIC_DEMO_MODE:-false}"
PUSH_PAGES=false

for arg in "$@"; do
  case "$arg" in
    --push-pages)
      PUSH_PAGES=true
      ;;
    --help|-h)
      cat <<EOF
Usage: ./scripts/deploy_all.sh [--push-pages]

Deploys the Cloud Run backend, health-checks it, then rebuilds the Flutter
frontend into the GitHub Pages repo.

Environment overrides:
  SELF_HEALING_GCP_PROJECT      default: $GCP_PROJECT
  SELF_HEALING_SERVICE_NAME     default: $SERVICE_NAME
  SELF_HEALING_REGION           default: $REGION
  SELF_HEALING_BACKEND_URL      default: $BACKEND_URL
  PHOENIX_HOST                  default: $PHOENIX_HOST
  LANDING_DIR                   default: $LANDING_DIR
  PUBLIC_DEMO_MODE              default: $PUBLIC_DEMO_MODE
  PAGES_COMMIT_MESSAGE          default: $PAGES_COMMIT_MESSAGE

Use --push-pages to git add/commit/push the rebuilt GitHub Pages repo.
EOF
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      exit 1
      ;;
  esac
done

if [[ ! -d "$LANDING_DIR/.git" ]]; then
  echo "Landing repo not found: $LANDING_DIR" >&2
  exit 1
fi

cd "$PROJECT_ROOT"

echo "Deploying backend to Cloud Run..."
gcloud run deploy "$SERVICE_NAME" \
  --project "$GCP_PROJECT" \
  --source . \
  --region "$REGION" \
  --port=8080 \
  --allow-unauthenticated \
  --clear-base-image \
  --memory=1Gi \
  --set-env-vars "PUBLIC_DEMO_MODE=$PUBLIC_DEMO_MODE,PUBLIC_DEMO_AGENT_RUN_LIMIT=3,PUBLIC_DEMO_HEALING_RUN_LIMIT=3,MAX_AGENT_ITERATIONS=2,MAX_LLM_RETRIES=1,AGENT_RUN_TIMEOUT_SECONDS=60,LLM_TIMEOUT_SECONDS=30,MAX_OUTPUT_TOKENS=1024,APP_ENV=production,PHOENIX_HOST=$PHOENIX_HOST,PHOENIX_COLLECTOR_ENDPOINT=$PHOENIX_COLLECTOR_ENDPOINT,PHOENIX_PROJECT_NAME=self-healing-agent,PHOENIX_MCP_PROJECT_IDENTIFIER=self-healing-agent" \
  --set-secrets GOOGLE_API_KEY=GOOGLE_API_KEY:latest

echo "Applying Cloud Run scaling settings..."
gcloud run services update "$SERVICE_NAME" \
  --project "$GCP_PROJECT" \
  --region "$REGION" \
  --min=0 \
  --max=2 \
  --cpu-throttling

echo "Checking backend health..."
curl -fsS "$BACKEND_URL/health"
printf '\n'

echo "Building and copying Flutter web frontend..."
PATH="/Users/salmankhan/flutter/bin:$PATH" \
  PUBLIC_DEMO_MODE="$PUBLIC_DEMO_MODE" \
  API_BASE_URL="$BACKEND_URL" \
  "$PROJECT_ROOT/scripts/deploy_flutter_web_to_pages.sh"

if [[ "$PUSH_PAGES" == true ]]; then
  echo "Committing and pushing GitHub Pages repo..."
  cd "$LANDING_DIR"
  git add .
  if git diff --cached --quiet; then
    echo "No frontend changes to commit."
  else
    git commit -m "$PAGES_COMMIT_MESSAGE"
    git push
  fi
else
  echo "Frontend copied but not pushed. Run with --push-pages to publish Pages."
fi

echo "Done."
echo "Backend: $BACKEND_URL"
echo "Pages repo: $LANDING_DIR"
