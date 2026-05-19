#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_DIR="$PROJECT_ROOT/dashboard"
LANDING_DIR="/Users/salmankhan/StudioProjects/self-healing-agent-landing"
BASE_HREF="/self-healing-agent-landing/"

if [[ ! -f "$FLUTTER_DIR/pubspec.yaml" || ! -d "$FLUTTER_DIR/lib" || ! -d "$FLUTTER_DIR/web" ]]; then
  echo "Flutter app not found at expected path: $FLUTTER_DIR" >&2
  exit 1
fi

if [[ ! -d "$LANDING_DIR/.git" ]]; then
  echo "Landing repo not found or missing .git directory: $LANDING_DIR" >&2
  exit 1
fi

if [[ -z "${API_BASE_URL:-}" || "$API_BASE_URL" == "YOUR_CLOUD_BACKEND_URL_HERE" ]]; then
  echo 'Set API_BASE_URL to your HTTPS Cloud backend URL before deploying.' >&2
  echo 'Example:' >&2
  echo '  API_BASE_URL="https://your-backend.example.run.app" ./scripts/deploy_flutter_web_to_pages.sh' >&2
  exit 1
fi

if [[ "$API_BASE_URL" != https://* ]]; then
  echo "API_BASE_URL must use https:// for GitHub Pages production builds: $API_BASE_URL" >&2
  exit 1
fi

cd "$FLUTTER_DIR"
flutter clean
flutter pub get

BUILD_ARGS=(
  --release \
  --base-href "$BASE_HREF" \
  --dart-define=API_BASE_URL="$API_BASE_URL"
)

if [[ "${PUBLIC_DEMO_MODE:-false}" == "true" || "${PUBLIC_DEMO_MODE:-false}" == "1" ]]; then
  BUILD_ARGS+=(--dart-define=PUBLIC_DEMO_MODE=true)
fi

flutter build web "${BUILD_ARGS[@]}"

mkdir -p "$LANDING_DIR"
rsync -a --delete --exclude '.git/' "$FLUTTER_DIR/build/web/" "$LANDING_DIR/"
touch "$LANDING_DIR/.nojekyll"

echo "Flutter web build copied to $LANDING_DIR"
echo "No git commit or push was performed."
