# Deploy the Flutter web UI to GitHub Pages

GitHub Pages hosts only the static Flutter web build output from `dashboard/build/web`.
Phoenix and FastAPI stay on Google Cloud; they are not copied into the landing repo.

## Deploy

```bash
cd /Users/salmankhan/StudioProjects/self-healing-agent
API_BASE_URL="YOUR_CLOUD_BACKEND_URL_HERE" ./scripts/deploy_flutter_web_to_pages.sh
cd /Users/salmankhan/StudioProjects/self-healing-agent-landing
git status
git add .
git commit -m "Deploy Flutter web UI"
git push
```

The deployment script:

- builds the Flutter app from `dashboard/`
- passes `API_BASE_URL` at build time with `--dart-define`
- uses the GitHub Pages subpath base href `/self-healing-agent-landing/`
- syncs only the static `build/web` output into the landing repo
- preserves the landing repo `.git` directory
- recreates `.nojekyll`
- never commits or pushes automatically

## Local development

If `API_BASE_URL` is omitted, the Flutter app keeps using `http://localhost:8000`.
For cloud deployments, pass an HTTPS URL so the GitHub Pages site does not make mixed-content requests from HTTPS to HTTP.

## Backend CORS

FastAPI CORS allows the GitHub Pages origin:

```text
https://salkhan-ops.github.io
```

This repo does not contain Phoenix application source or Phoenix CORS configuration; it only contains Phoenix deployment/configuration references. If Phoenix later serves browser-facing endpoints directly, add the same GitHub Pages origin in the Phoenix service's own CORS configuration there.
