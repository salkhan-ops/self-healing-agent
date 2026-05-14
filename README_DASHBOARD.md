# Self-Healing Agent Dashboard

This dashboard adds a FastAPI backend, Flutter web UI, live WebSocket output,
schedules, reports, metrics, and an embeddable mini widget for the
Self-Healing AI Agent.

## 1. Start Phoenix

Phoenix runs locally:

```bash
source venv/bin/activate
python -m phoenix.server.main serve
```

Open:

```text
http://localhost:6006
```

Create an API key in `Settings -> API Keys -> Create`, then put it in `.env`:

```text
PHOENIX_API_KEY=your_local_key
PHOENIX_COLLECTOR_ENDPOINT=http://localhost:6006
```

## 2. Start Backend

Install backend dependencies once:

```bash
source venv/bin/activate
pip install -r backend/requirements_backend.txt
```

Run:

```bash
chmod +x backend/start.sh
./backend/start.sh
```

Backend URL:

```text
http://localhost:8000
```

Health check:

```text
http://localhost:8000/health
```

## 3. Start Flutter Dashboard

Run:

```bash
cd dashboard
flutter pub get
chmod +x run.sh
./run.sh
```

Dashboard URL:

```text
http://localhost:3000
```

## 4. API Endpoints

Metrics:

```text
GET /api/metrics/latest
GET /api/metrics/range?period=hour|day|week|month|year
GET /api/metrics/summary
```

Reports:

```text
GET /api/reports
GET /api/reports/{id}
GET /api/reports/{id}/export?format=pdf|csv
```

Schedules:

```text
GET /api/schedules
POST /api/schedules
PUT /api/schedules/{id}
DELETE /api/schedules/{id}
POST /api/schedules/{id}/toggle
```

Agent:

```text
POST /api/agent/run
GET /api/agent/status
WS /ws
```

FAQ:

```text
GET /api/faq
PUT /api/faq
```

Embed:

```text
GET /embed/widget
```

## 5. Embed Widget

Use an iframe in any app:

```html
<iframe
  src="http://localhost:8000/embed/widget"
  width="360"
  height="240"
  style="border:0;border-radius:12px;overflow:hidden"
  title="Self-Healing Agent Health"
></iframe>
```

The widget shows the current health score and latest report summary. It is
designed to work as a small status card inside other tools or admin consoles.
