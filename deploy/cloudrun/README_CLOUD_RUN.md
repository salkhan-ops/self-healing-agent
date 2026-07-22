# Archived Cloud Run Deployment Guide

The hackathon Cloud Run and Phoenix services have been shut down. Scripts in
this directory now refuse to deploy unless `ALLOW_ARCHIVED_DEPLOY=true` is set.
The archived default is no-LLM local fallback mode.

This guide deploys a self-hosted Phoenix server plus the FastAPI backend. It does **not** use Phoenix Cloud.

## A. Prerequisites

```bash
gcloud auth login
gcloud config set project PROJECT_ID
gcloud services enable run.googleapis.com artifactregistry.googleapis.com cloudbuild.googleapis.com secretmanager.googleapis.com
```

## B. Deploy Phoenix

```bash
chmod +x deploy/cloudrun/deploy_phoenix.sh
./deploy/cloudrun/deploy_phoenix.sh
```

## C. Copy the Phoenix URL

The script prints:

```text
PHOENIX_HOST=http://localhost:6006
PHOENIX_COLLECTOR_ENDPOINT=http://localhost:6006/v1/traces
```

## D. Create the Gemini secret

```bash
printf "YOUR_GOOGLE_API_KEY" | gcloud secrets create GOOGLE_API_KEY --data-file=-
```

## E. Deploy the backend

```bash
chmod +x deploy/cloudrun/deploy_backend.sh
PHOENIX_HOST=http://localhost:6006 ./deploy/cloudrun/deploy_backend.sh
```

## F. Test the backend

```bash
curl https://BACKEND_URL/health
```

## G. Update Flutter for production

```bash
flutter build web \
  --dart-define=API_BASE_URL=https://BACKEND_URL \
  --dart-define=WS_URL=wss://BACKEND_URL/ws
```

## H. Verify the full flow

- Send a customer chat message.
- Send an investment analyst message.
- Open the Phoenix Cloud Run URL.
- Confirm traces appear.

## I. Persistence warning

This simple Phoenix Cloud Run deployment uses container storage, so traces may be lost across restarts. For persistent Phoenix:

- Create Cloud SQL PostgreSQL.
- Set `PHOENIX_SQL_DATABASE_URL`.
- Deploy `phoenix-server` with `--add-cloudsql-instances`.

Those production persistence steps are intentionally documented here but not automated by the hackathon scripts.
