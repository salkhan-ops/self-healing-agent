# Self-Healing AI Agent

This project is a working customer support AI agent that improves its own
system prompt after observing its answers. It answers questions from a local
FAQ, records traces to a local Arize Phoenix server, evaluates its own
performance, diagnoses root causes, rewrites its prompt, verifies the change,
and writes a plain English incident report.

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
│  TaskAgent          │ ───────────────────▶ │  Phoenix Local      │
│  Gemini answers     │                      │  localhost:6006     │
└─────────┬──────────┘                      └─────────┬──────────┘
          │                                           │
          ▼                                           ▼
┌────────────────────┐                      ┌────────────────────┐
│  Evaluator          │ ◀─────────────────── │  TraceReader        │
│  scores answers     │                      │  reads traces       │
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
PHOENIX_COLLECTOR_ENDPOINT=http://localhost:6006

GOOGLE_API_KEY=your_google_api_key

SLACK_WEBHOOK_URL=

HALLUCINATION_THRESHOLD=0.4
RELEVANCE_THRESHOLD=0.6
LATENCY_THRESHOLD_MS=3000
```

Secrets must stay in environment variables. Do not hardcode API keys.

## Run Phoenix Locally

Phoenix is local only for this project. Do not use external Phoenix cloud URLs.

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
4. Read recent traces.
5. Evaluate hallucination, relevance, and latency.
6. Analyze the root cause.
7. Rewrite its system prompt.
8. Verify the new prompt on the same questions.
9. Save a report in `reports/`.

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

For Phoenix tracing from inside Docker, make sure the container can reach the
host Phoenix server at `localhost:6006` or adjust networking for your platform.

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
├── config/
│   └── settings.py
├── data/
│   └── faq.txt
├── tests/
│   └── test_loop.py
├── deploy/
│   └── Dockerfile
└── README.md
```

## Notes

- Phoenix must point to `http://localhost:6006`.
- Gemini model: `gemini-2.0-flash-exp`.
- Reports are saved locally in `reports/`.
- Slack reporting is optional and only runs when `SLACK_WEBHOOK_URL` is set.
