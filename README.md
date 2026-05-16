# Self-Healing AI Agent

This project is a working self-healing AI system with three demo agents:

- a customer-support assistant grounded in a local FAQ,
- a social-media post generator that learns to stop inventing metrics, and
- an SEC-grounded investment research assistant.

Each agent records traces to a local Arize Phoenix server. The core healing
loop reads recent traces through the official Phoenix MCP server, evaluates
quality, diagnoses failures, rewrites prompts, verifies the change, and saves a
plain-English incident report. A FastAPI backend and Flutter dashboard expose
live runs, metrics, reports, schedules, chat flows, post generation, and
investment analysis.

Built for: **Google Cloud Rapid Agent Hackathon**

## Why This Matters

Support agents often fail quietly. They may guess when a policy is missing,
answer the wrong question, or slowly drift away from the source of truth.
Most teams only notice after a customer complains.

This project demonstrates a practical self-healing loop:

- Observe every answer.
- Score answer quality.
- Detect repeated failure patterns.
- Improve the prompt automatically.
- Verify the fix before declaring success.
- Produce a report a human can review.

## Architecture

```text
┌────────────────────┐
│  data/faq.txt       │
│  Local FAQ          │
└─────────┬──────────┘
          │
          ▼
┌────────────────────┐        traces        ┌────────────────────┐
│  Agents             │ ───────────────────▶ │  Phoenix Local      │
│  support/posts/SEC  │                      │  localhost:6006     │
└─────────┬──────────┘                      └─────────┬──────────┘
          │                                           │
          ▼                                           ▼
┌────────────────────┐                      ┌────────────────────┐
│  Evaluator          │ ◀─────────────────── │  TraceReader        │
│  scores answers     │                      │  Phoenix MCP client  │
└─────────┬──────────┘                      └────────────────────┘
          │
          ▼
┌────────────────────┐
│  RootCauseAnalyzer  │
│  finds why          │
└─────────┬──────────┘
          │
          ▼
┌────────────────────┐
│  PromptImprover     │
│  rewrites prompt    │
└─────────┬──────────┘
          │
          ▼
┌────────────────────┐
│  Verifier           │
│  reruns questions   │
└─────────┬──────────┘
          │
          ▼
┌────────────────────┐
│  Reporter           │
│  saves report       │
└────────────────────┘
```

## Prerequisites

- Python 3.12
- Node.js/npm available on `PATH` so `npx` can launch `@arizeai/phoenix-mcp`
- Flutter if you want to run the dashboard UI

## Setup

1. Create and activate a Python 3.12 virtual environment:

```bash
python3.12 -m venv venv
source venv/bin/activate
```

2. Install dependencies:

```bash
pip install -r requirements.txt
```

3. Create your `.env` file:

```bash
cp .env.example .env
```

4. Fill in `.env`:

```text
PHOENIX_API_KEY=your_local_phoenix_key
PHOENIX_HOST=http://localhost:6006
PHOENIX_COLLECTOR_ENDPOINT=http://localhost:6006/v1/traces

GOOGLE_API_KEY=your_google_api_key
AGENT_MODE=cheap
GEMINI_MODEL_NAME=gemini-2.5-flash-lite

SLACK_WEBHOOK_URL=

HALLUCINATION_THRESHOLD=0.4
RELEVANCE_THRESHOLD=0.6
LATENCY_THRESHOLD_MS=3000

SEC_USER_AGENT=SelfHealingAgent/1.0 your_email@example.com
```

Secrets must stay in environment variables. Do not hardcode API keys.

`AGENT_MODE` options:

- `cheap`: Gemini answers + local self-evaluation/improvement
- `full`: Gemini answers + Gemini self-evaluation/improvement
- `local`: no Gemini calls

## Run Phoenix Locally

Phoenix defaults to local development at `http://localhost:6006`, but both the
host and collector endpoint are environment-driven so Cloud Run can point at a
self-hosted Phoenix service. The app exports traces over OpenTelemetry and reads
them back through Phoenix MCP during the healing loop.

Start Phoenix:

```bash
python -m phoenix.server.main serve
```

Open the dashboard:

```text
http://localhost:6006
```

Create a local API key:

```text
Settings → API Keys → Create
```

Put that key in `.env` as `PHOENIX_API_KEY`.

## Run The Agent

From the project root:

```bash
python agent/main.py
```

The agent will:

1. Load `data/faq.txt`.
2. Answer 10 FAQ questions.
3. Send traces to local Phoenix when available.
4. Read recent traces through the official Phoenix MCP server.
5. Evaluate hallucination, relevance, and latency.
6. Analyze the root cause.
7. Rewrite its system prompt.
8. Verify the new prompt on the same questions.
9. Save a report in `reports/`.

If Phoenix is offline, the agent continues with local in-memory traces so local
development still works.

## Run The Dashboard

The dashboard stack has three moving parts:

```text
Phoenix      http://localhost:6006
FastAPI API  http://localhost:8000
Flutter UI   http://localhost:3000
```

Start the backend:

```bash
source venv/bin/activate
pip install -r backend/requirements_backend.txt
uvicorn backend.main:app --reload --port 8000
```

Start the Flutter dashboard in another terminal:

```bash
cd dashboard
flutter pub get
./run.sh
```

The UI includes:

- Dashboard, charts, reports, scheduler, and agent controls
- Customer-support chat with before/after healing views
- Social-media post generation
- SEC-grounded investment analysis
- Phoenix connection status and live WebSocket progress

See `README_DASHBOARD.md` for endpoint details and the embeddable widget.

## Sample Output

```text
🚀 Self-Healing Agent Starting...
📚 Loading FAQ knowledge base... (20 Q&As loaded)
🔌 Connecting to Phoenix at http://localhost:6006... ✅

─────────────────────────────────────
ROUND 1 — Answering 10 Questions
─────────────────────────────────────
Q1: What is your return policy? → Answered ✅
Q2: How do I start a return? → Answered ✅
...
All traces sent to Phoenix ✅

─────────────────────────────────────
SELF-EVALUATION (Reading own traces)
─────────────────────────────────────
📊 Fetching traces from Phoenix...
Traces retrieved: 10
Hallucination Score: 0.42 ⚠️  (threshold: 0.40)
Relevance Score:    0.55 ⚠️  (threshold: 0.60)
Avg Latency:        1.2s  ✅

─────────────────────────────────────
ROOT CAUSE ANALYSIS
─────────────────────────────────────
🔍 Analyzing 3 problematic traces...
Root Cause: Agent is guessing when information is not in the FAQ.

─────────────────────────────────────
SELF-IMPROVEMENT
─────────────────────────────────────
✏️  Rewriting system prompt...
Old prompt saved ✅
New prompt applied ✅

─────────────────────────────────────
ROUND 2 — Verifying Improvement
─────────────────────────────────────
Q1: What is your return policy? → Answered ✅
...

─────────────────────────────────────
RESULTS
─────────────────────────────────────
Hallucination: 0.42 → 0.08  ✅ (+81%)
Relevance:     0.55 → 0.79  ✅ (+44%)
Latency:       1.2s → 1.1s  ✅

─────────────────────────────────────
📄 INCIDENT REPORT GENERATED
─────────────────────────────────────
🔧 SELF-HEALING REPORT — 2026-05-10 20:30:00
Problem: Hallucination rate above threshold (0.42)
Root Cause: GUESSING — Prompt allowed guessing
Fix Applied: Added strict grounding instruction and required fallback answer
Human Action Needed: NO ✅
Report saved to: reports/report_20260510_203000.txt
```

## Run Tests

```bash
pytest
```

The tests are designed to pass locally even before Phoenix or Gemini keys are
configured. In that case, components use graceful local fallbacks.

## Docker

Build:

```bash
docker build -f deploy/Dockerfile -t self-healing-agent .
```

Run:

```bash
docker run --env-file .env self-healing-agent
```

For Phoenix tracing from inside Docker or Cloud Run, set `PHOENIX_HOST` and
`PHOENIX_COLLECTOR_ENDPOINT` to a reachable Phoenix service and make sure
Node/npm are available if the container also needs to execute the MCP trace-read
path.

## Project Structure

```text
self-healing-agent/
├── agent/
│   ├── main.py
│   ├── task_agent.py
│   ├── trace_reader.py
│   ├── evaluator.py
│   ├── analyzer.py
│   ├── improver.py
│   ├── verifier.py
│   └── reporter.py
├── backend/
│   ├── main.py
│   ├── routes/
│   └── services/
├── config/
│   └── settings.py
├── dashboard/
│   └── lib/
├── data/
│   └── faq.txt
├── tests/
│   ├── test_loop.py
│   ├── test_investment_agent.py
│   └── test_sec_client.py
├── deploy/
│   └── Dockerfile
└── README.md
```

## Notes

- Local Phoenix defaults to `http://localhost:6006`; cloud deployments should
  use a reachable self-hosted Phoenix URL instead.
- The core FAQ loop uses `GEMINI_MODEL_NAME` from `.env` (default:
  `gemini-2.5-flash-lite`).
- The dashboard post and investment agents currently use `gemini-2.5-flash`.
- Reports are saved locally in `reports/`.
- Slack reporting is optional and only runs when `SLACK_WEBHOOK_URL` is set.
