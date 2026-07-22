# Self-Healing AI Agent

> **"They wake up in the morning, see this in Slack, and their AI already fixed itself overnight."**

[![License](https://img.shields.io/badge/License-Apache%202.0-green?style=for-the-badge)](LICENSE)
[![Built for](https://img.shields.io/badge/Built%20for-Google%20Cloud%20Rapid%20Agent%20Hackathon-orange?style=for-the-badge)](https://rapid-agent.devpost.com/)

> **Archived:** This was a hackathon submission for the Google Cloud Rapid Agent Hackathon. The public Cloud Run/Phoenix services and Gemini credentials have been shut down. The code remains here as a portfolio/reference project and defaults to local, no-LLM fallback mode.

---

## Archive Status

The live backend is intentionally offline. Local runs default to:

```text
DISABLE_LLM_CALLS=true
PUBLIC_DEMO_MODE=true
AGENT_MODE=local
```

With these defaults, the app uses local fallback behavior and does not call the Gemini API. Re-enabling live LLM behavior requires explicitly setting `DISABLE_LLM_CALLS=false` and providing a new API key.

---

## 📚 Table of Contents

- [The Problem](#-the-problem)
- [The Solution](#-the-solution)
- [What Makes It Different](#-what-makes-it-different)
- [Three Live Use Cases](#-three-live-use-cases)
- [Architecture](#️-architecture)
- [Partner Integration — Arize Phoenix + MCP](#-partner-integration--arize-phoenix--mcp)
- [The Self-Healing Loop](#-the-self-healing-loop-7-steps)
- [Dashboard Features](#-dashboard-features)
- [Cost Controls for Public Demo](#-cost-controls-for-public-demo)
- [Tech Stack](#️-tech-stack)
- [Quick Start](#-quick-start)
- [Docker](#-docker)
- [Deployment](#️-deploy-backend-to-google-cloud-run)
- [Embed in Any App](#-embed-in-any-app)
- [Sample Healing Report](#-sample-healing-report)
- [Tests](#-tests)
- [Project Structure](#-project-structure)
- [Built For](#-built-for)
- [License](#-license)

---

## 🎯 The Problem

AI agents fail silently in production.

A customer support bot starts making up refund policies. A LinkedIn post generator invents revenue figures that never existed. An investment analyst cites a P/E ratio it fabricated.

Nobody notices until a customer complains, a post goes viral for the wrong reason, or a regulator asks questions.

Most teams only find out when the damage is already done.

---

## 💡 The Solution

**Self-Healing Agent** monitors your AI in production, detects failures automatically, rewrites the broken prompt, verifies that the fix works, and sends you a report — all without human intervention.

```text
AI makes mistake → Phoenix records it → Agent reads its own traces
→ Detects hallucination → Rewrites its own prompt
→ Verifies improvement → Sends Slack report
→ You wake up. It already fixed itself.
```

---

## ✨ What Makes It Different

| Traditional Monitoring | Self-Healing Agent |
|---|---|
| Alerts you when something breaks | Fixes it before you wake up |
| Human reviews traces manually | Agent reads its own traces via MCP |
| Prompt updates require a deploy | Prompt updates happen at runtime |
| One dashboard per tool | One loop works for any AI agent |
| You need an engineer on call | Report says **Human Needed: NO ✅** |

---

## 🚀 Three Live Use Cases

### 💬 Customer Support

An FAQ-grounded support agent that catches itself hallucinating and learns to stop.

**Before healing — Prompt v1:**

```text
"I believe we may ship to Pakistan for free on qualifying orders."
```

Invented answer — not present in the FAQ.

**After healing — Prompt v2:**

```text
"We currently ship only within the United States."
```

Grounded answer — directly supported by the FAQ.

---

### 📱 Social Media Post Safety

A post generator that learns to stop inventing metrics before they go live.

**Before healing — Prompt v1:**

```text
"We crushed Q1 with 340% revenue growth! 🚀 Our revolutionary
platform is disrupting the industry."
```

The `340%` claim was invented and did not appear in the brief.

**After healing — Prompt v2:**

```text
"Q1 was a strong quarter. We launched our new product and
welcomed three new engineers."
```

Every claim is grounded in the original brief.

---

### 📈 Investment Research

An SEC-grounded analyst that refuses to cite financial figures it cannot verify.

Before healing, the agent invents P/E ratios. After healing, it responds safely:

```text
"I cannot confirm that figure without a verified SEC source."
```

---

## 🏗️ Architecture

```text
┌─────────────────────────────────────────────────────────────────┐
│         Flutter Web Dashboard (GitHub Pages — static)            │
│  Dashboard │ Phoenix Traces │ Reports │ Resources │ Scheduler    │
│  Customer Support │ Social Media Posts │ Investment Analyst      │
└──────────────────────────┬──────────────────────────────────────┘
                           │ REST + WebSocket
┌──────────────────────────▼──────────────────────────────────────┐
│              FastAPI Backend (Google Cloud Run)                  │
│  /api/agent  /api/chat  /api/posts  /api/investment              │
│  /api/metrics  /api/reports  /api/schedules  /ws                 │
└───────────┬────────────────────────────┬────────────────────────┘
            │                            │
┌───────────▼──────────┐    ┌────────────▼──────────────────────┐
│   Self-Healing Loop   │    │         Child Agents               │
│                       │    │                                    │
│  TaskAgent            │    │  ChatAgent (Customer Support)      │
│      ↓                │    │  PostAgent (Social Media)          │
│  TraceReader ←── MCP ─┼────┼──→ Arize Phoenix                   │
│      ↓                │    │  InvestmentAgent (SEC Research)    │
│  Evaluator            │    │                                    │
│      ↓                │    └────────────────────────────────────┘
│  RootCauseAnalyzer    │
│      ↓                │    ┌────────────────────────────────────┐
│  PromptImprover ──────┼───▶│  Gemini 2.5 Flash                  │
│      ↓                │    │  answer / judge / rewrite          │
│  Verifier             │    └────────────────────────────────────┘
│      ↓                │
│  Reporter ────────────┼───▶  Slack + SQLite + reports/
└───────────────────────┘
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full interactive Mermaid diagram.

---

## 🔗 Partner Integration — Arize Phoenix + MCP

The Arize Phoenix MCP server is not just used for dashboards. It is the mechanism that makes self-healing possible.

Every agent interaction is traced to Phoenix via OpenTelemetry. The healing loop then reads those traces back at runtime using the official Phoenix MCP server, giving the agent the ability to query its own past behavior as a tool.

```python
# The agent reads its own traces via Phoenix MCP
result = subprocess.run([
    "npx", "@arizeai/phoenix-mcp@latest",
    "--baseUrl", PHOENIX_HOST
], input=json.dumps({
    "tool": "list-traces",
    "params": {
        "project_name": "self-healing-agent",
        "limit": 10
    }
}), capture_output=True, text=True, timeout=30)
```

This moves the project beyond a monitoring dashboard into genuine autonomous self-improvement. The agent is not just observed — it uses its own observations to change its behavior at runtime.

---

## 🧠 The Self-Healing Loop — 7 Steps

```text
Step 1  ANSWER    Agent answers 10 questions → traces sent to Phoenix
Step 2  FETCH     Agent reads own traces via Phoenix MCP server
Step 3  EVALUATE  Gemini scores each answer: hallucination + relevance
Step 4  DIAGNOSE  Root cause: GUESSING / HALLUCINATION / IRRELEVANT
Step 5  REWRITE   Gemini rewrites the system prompt to fix root cause
Step 6  VERIFY    Same questions run again → scores compared before/after
Step 7  REPORT    Incident report saved + Slack notification sent
```

All seven steps happen automatically. No human is required.

---

## 📊 Dashboard Features

- **Live health score** from 0–100, updated after every agent interaction
- **Real-time charts** for hallucination, relevance, and latency across hour/day/week/month/year views
- **Incident reports** with before/after comparison, root cause, and fix description
- **Phoenix Traces** page showing trace IDs, span names, scores, MCP retrieval status, and the trace-to-healing timeline
- **Resources** section with five judge-facing articles on self-healing architecture, Phoenix trace retrieval, and the support, social, and investment use cases
- **Scheduler** for recurring healing loops
- **Agent Control** to trigger runs manually and watch the live output stream
- **Healing Journey Dialog** with an animated step-by-step visualization of the healing process
- **FAQ Editor** for updating the support knowledge base directly from the dashboard
- **Embeddable Widget** that works with one `<iframe>` tag in any app

---

## Cost Controls

This project was built with public-demo safeguards. The current archived default is stronger: live LLM calls are disabled unless explicitly re-enabled.

### 1. Static Flutter UI on GitHub Pages

The Flutter web dashboard can be deployed as static files to GitHub Pages. The original public backend has been shut down.

### 2. Backend-only Cloud Run Deployments

The Cloud Run upload is restricted with `.gcloudignore`, so local Flutter build artifacts, macOS project files, virtual environments, reports, and generated caches are excluded from backend deploys. Deployment scripts now require `ALLOW_ARCHIVED_DEPLOY=true` to avoid accidental restores.

Backend upload dropped to approximately `90KB / 65 files`. This keeps deployments fast and prevents large local files from being uploaded accidentally.

### 3. Public Demo Mode

The backend supports a configurable public demo mode:

```bash
PUBLIC_DEMO_MODE=true
PUBLIC_DEMO_AGENT_RUN_LIMIT=2
```

In public demo mode:

- The full multi-agent healing loop is limited to two runs per browser/session
- Backend in-memory limits provide a second safety net for public usage
- Social media post healing remains available through the targeted flow, with `PUBLIC_DEMO_HEALING_RUN_LIMIT` capping prompt-healing attempts
- The UI shows clear restriction messages instead of silently hiding the product

### 4. Cost-Aware Learning Loop

The healing path uses a cheap-first strategy before spending on LLM calls:

- **Policy memory / learned rules:** recurring failures create reusable rules such as “do not use unsupported superlatives” or “do not give buy/sell advice.”
- **Cached failure patterns:** repeated post or investment failures reuse the previous prompt patch instead of diagnosing and rewriting from scratch.
- **Cheap judge first:** deterministic scorers catch obvious pass/fail cases before calling Gemini as judge.
- **Prompt patches:** known failures append a small learned constraint instead of asking Gemini to rewrite the entire system prompt.
- **Retry rules:** if a learned post constraint is already present but hallucination remains high, the healer can append a stronger override instead of reporting that no regeneration is needed.
- **Batch repair:** one healing pass learns from recent failures and verifies a small focused sample, so one repair can improve future examples.

Unsupported hype phrases such as `EPIC`, `revolutionary`, `UNLEASHED`, and `MONUMENTAL` are caught by cheaper rule-based calibration before falling back to LLM judging. This reduces Gemini API calls for straightforward hallucination signals.

### 5. Navigation and UX Stability

- Dark mode is the default
- A visible `Healing…` state prevents duplicate clicks
- Clear cache and clear history controls are separated so judges can reset state cleanly without triggering new API calls

---

## 🛠️ Tech Stack

| Layer | Technology |
|---|---|
| Frontend | Flutter Web, Dart, Provider, go_router, fl_chart |
| Backend API | Python, FastAPI, Uvicorn, WebSockets |
| Agent / AI | Gemini 2.5 Flash via google-generativeai |
| Observability | Arize Phoenix, OpenTelemetry, Phoenix MCP server |
| External Data | SEC EDGAR APIs for the investment use case |
| Persistence | SQLite, SQLAlchemy async |
| Scheduling | APScheduler |
| Deployment | Google Cloud Run backend, GitHub Pages frontend |

---

## ⚡ Quick Start

### Prerequisites

- Python 3.12
- Node.js / npm for Phoenix MCP
- Flutter for the dashboard UI
- Optional Phoenix local server for trace viewing

### 1. Clone and install

```bash
git clone https://github.com/salkhan-ops/self-healing-agent.git
cd self-healing-agent
python3.12 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### 2. Configure environment

```bash
cp .env.example .env
```

Edit `.env`:

```env
DISABLE_LLM_CALLS=true
PUBLIC_DEMO_MODE=true
AGENT_MODE=local
GOOGLE_API_KEY=
PHOENIX_API_KEY=
PHOENIX_HOST=http://localhost:6006
PHOENIX_COLLECTOR_ENDPOINT=http://localhost:6006/v1/traces
HALLUCINATION_THRESHOLD=0.4
RELEVANCE_THRESHOLD=0.6
LATENCY_THRESHOLD_MS=3000
```

### 3. Start Phoenix

```bash
python -m phoenix.server.main serve
```

Open [http://localhost:6006](http://localhost:6006), then go to **Settings → API Keys → Create** and paste the key into `.env`.

### 4. Run the agent standalone

```bash
python agent/main.py
```

Watch the seven-step healing loop run in your terminal.

### 5. Run the full dashboard

```bash
# Terminal 1 — Phoenix
source venv/bin/activate
python -m phoenix.server.main serve

# Terminal 2 — FastAPI backend
source venv/bin/activate
uvicorn backend.main:app --reload --port 8000

# Terminal 3 — Flutter dashboard
cd dashboard
flutter pub get
flutter run -d chrome --web-port 3000 \
  --dart-define=API_BASE_URL=http://localhost:8000 \
  --dart-define=WS_URL=ws://localhost:8000/ws
```

Open [http://localhost:3000](http://localhost:3000).

---

## 🐳 Docker

```bash
docker build -f deploy/Dockerfile -t self-healing-agent .
docker run --env-file .env self-healing-agent
```

---

## Deployment

The production Cloud Run and Phoenix services have been shut down. Deployment scripts are intentionally guarded and will exit unless `ALLOW_ARCHIVED_DEPLOY=true` is set.

### Build Flutter Locally

```bash
cd dashboard
flutter build web --release \
  --dart-define=API_BASE_URL=http://localhost:8000 \
  --dart-define=PUBLIC_DEMO_MODE=true
```

---

## 🧩 Embed in Any App

The original live embed endpoint is offline with the rest of the backend. The widget code remains in the repo for reference.

---

## 📄 Sample Healing Report

```text
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔧 SELF-HEALING REPORT — 2026-05-17 03:47:00
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
App: Social Media Post Agent
Problem: Hallucination rate above threshold (1.00)
Root Cause: GUESSING — Agent inventing metrics
            and superlatives not present in the brief
Fix Applied: Added strict fact-grounding instruction.
             Required fallback for unsupported claims.

BEFORE:
  Hallucination: 1.00
  Relevance:     0.31
  Latency:       2046ms

AFTER:
  Hallucination: 0.00  (-100%) ✅
  Relevance:     0.87  (+181%) ✅
  Latency:       1.9s          ✅

Improvement: +94%
Human Action Needed: NO ✅
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## 🧪 Tests

```bash
pytest
```

All tests pass without Phoenix or Gemini keys configured. Components fall back gracefully to local rules.

---

## 📁 Project Structure

```text
self-healing-agent/
├── agent/                  ← Core self-healing loop
│   ├── main.py             ← Entry point
│   ├── task_agent.py       ← Gemini agent with Phoenix tracing
│   ├── trace_reader.py     ← Phoenix MCP client
│   ├── evaluator.py        ← LLM-as-judge scoring
│   ├── analyzer.py         ← Root cause classification
│   ├── improver.py         ← Prompt rewriting
│   ├── verifier.py         ← Before/after verification
│   └── reporter.py         ← Incident report generation
├── backend/                ← FastAPI backend
│   ├── main.py             ← App + routes + WebSocket
│   ├── routes/             ← REST endpoints
│   └── services/           ← Agent singletons + DB
├── dashboard/              ← Flutter web UI
│   └── lib/
│       ├── screens/        ← 7 screens
│       ├── widgets/        ← Healing journey dialog + components
│       └── providers/      ← State management
├── config/                 ← Settings + Phoenix config
├── data/
│   ├── faq.txt             ← Support knowledge base
│   └── sec_cache/          ← SEC EDGAR local cache
├── deploy/                 ← Dockerfile + Cloud Run scripts
├── tests/                  ← Pytest suite
├── ARCHITECTURE.md         ← Full system diagram
├── LICENSE                 ← Apache 2.0
└── README.md
```

---

## 🏆 Built For

**Google Cloud Rapid Agent Hackathon — Arize Track**

- Built with Gemini 2.5 Flash during the hackathon
- Originally deployed on Google Cloud Run
- ✅ Arize Phoenix MCP integration
- ✅ Multi-step autonomous agent loop
- ✅ Moves beyond chat — plans, acts, verifies, and reports
- ✅ Three real-world use cases
- ✅ Cost-controlled public demo with GitHub Pages frontend
- ✅ Apache 2.0 open source license

---

## 📜 License

Apache 2.0 — see [LICENSE](LICENSE).

---

*Built by Salman Khan · May 2026*
