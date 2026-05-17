# 🔧 Self-Healing AI Agent

> **"They wake up in the morning, see this in Slack, and their AI already fixed itself overnight."**

[![Live Demo](https://img.shields.io/badge/Live%20Demo-Cloud%20Run-4285F4?style=for-the-badge&logo=google-cloud)](https://self-healing-agent-274002881656.us-central1.run.app/)
[![License](https://img.shields.io/badge/License-Apache%202.0-green?style=for-the-badge)](LICENSE)
[![Built for](https://img.shields.io/badge/Built%20for-Google%20Cloud%20Rapid%20Agent%20Hackathon-orange?style=for-the-badge)](https://rapid-agent.devpost.com/)
[![Powered by](https://img.shields.io/badge/Powered%20by-Gemini%202.5%20Flash-blue?style=for-the-badge)](https://ai.google.dev/)

---

## 🌐 Live Demo

**[https://self-healing-agent-274002881656.us-central1.run.app/](https://self-healing-agent-274002881656.us-central1.run.app/)**

No setup required. Open in any browser. All three use cases are live.

---

## 🎯 The Problem

AI agents fail silently in production.

A customer support bot starts making up refund policies. A LinkedIn post generator invents revenue figures that never existed. An investment analyst cites a P/E ratio it fabricated. Nobody notices until a customer complains, a post goes viral for the wrong reason, or a regulator asks questions.

Most teams only find out when the damage is done.

---

## 💡 The Solution

**Self-Healing Agent** monitors your AI in production, detects failures automatically, rewrites the broken prompt, verifies the fix works, and sends you a report — all without human intervention.

```
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
| You need an engineer on call | Report says "Human Needed: NO ✅" |

---

## 🚀 Three Live Use Cases

### 💬 Customer Support
An FAQ-grounded support agent that catches itself hallucinating and stops.

**Before healing (Prompt v1):**
> "I believe we may ship to Pakistan for free on qualifying orders."
> *(Invented — not in the FAQ)*

**After healing (Prompt v2):**
> "We currently ship only within the United States."
> *(Grounded — directly from FAQ)*

---

### 📱 Social Media Post Safety
A post generator that learns to stop inventing metrics before they go live.

**Before healing (Prompt v1):**
> "We crushed Q1 with 340% revenue growth! 🚀 Our revolutionary platform is disrupting the industry."
> *(340% invented — not in the brief)*

**After healing (Prompt v2):**
> "Q1 was a strong quarter. We launched our new product and welcomed three new engineers."
> *(Every word from the brief)*

---

### 📈 Investment Research
An SEC-grounded analyst that refuses to cite financial figures it cannot verify.

Before healing it invents P/E ratios. After healing it says:
> "I cannot confirm that figure without a verified SEC source."

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Flutter Web Dashboard                        │
│  Dashboard │ Charts │ Reports │ Scheduler │ Agent Control        │
│  Customer Support │ Social Media Posts │ Investment Analyst      │
└──────────────────────────┬──────────────────────────────────────┘
                           │ REST + WebSocket
┌──────────────────────────▼──────────────────────────────────────┐
│                      FastAPI Backend                             │
│  /api/agent  /api/chat  /api/posts  /api/investment             │
│  /api/metrics  /api/reports  /api/schedules  /ws                │
└───────────┬────────────────────────────┬────────────────────────┘
            │                            │
┌───────────▼──────────┐    ┌────────────▼──────────────────────┐
│   Self-Healing Loop   │    │         Child Agents               │
│                       │    │                                    │
│  TaskAgent            │    │  ChatAgent (Customer Support)      │
│      ↓                │    │  PostAgent (Social Media)          │
│  TraceReader ←── MCP ─┼────┼──→ Arize Phoenix                  │
│      ↓                │    │  InvestmentAgent (SEC Research)    │
│  Evaluator            │    │                                    │
│      ↓                │    └────────────────────────────────────┘
│  RootCauseAnalyzer    │
│      ↓                │    ┌────────────────────────────────────┐
│  PromptImprover ──────┼───▶│  Gemini 2.5 Flash                  │
│      ↓                │    │  (answer / judge / rewrite)        │
│  Verifier             │    └────────────────────────────────────┘
│      ↓                │
│  Reporter ────────────┼───▶  Slack + SQLite + reports/
└───────────────────────┘
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full interactive Mermaid diagram.

---

## 🔗 Partner Integration — Arize Phoenix + MCP

This project uses the **official Arize Phoenix MCP server** as its observability superpower.

Every agent interaction is traced to Phoenix via OpenTelemetry. The self-healing loop then reads its own traces back at runtime using the Phoenix MCP server — giving the agent the ability to inspect its own behavior and improve without human review.

```python
# The agent reads its own traces via Phoenix MCP
result = subprocess.run([
    "npx", "@arizeai/phoenix-mcp@latest",
    "--baseUrl", PHOENIX_HOST
], ...)
```

This is the core of the Arize track requirement: **an agent that uses Phoenix MCP to query its own traces and self-improve at runtime.**

---

## 🧠 The Self-Healing Loop (7 Steps)

```
Step 1  ANSWER    Agent answers 10 questions → traces sent to Phoenix
Step 2  FETCH     Agent reads own traces via Phoenix MCP server
Step 3  EVALUATE  Gemini scores each answer: hallucination + relevance
Step 4  DIAGNOSE  Root cause identified: GUESSING / HALLUCINATION / IRRELEVANT
Step 5  REWRITE   Gemini rewrites the system prompt to fix the root cause
Step 6  VERIFY    Same questions run again → scores compared before/after
Step 7  REPORT    Incident report saved + Slack notification sent
```

All 7 steps happen automatically. No human required.

---

## 📊 Dashboard Features

- **Live health score** (0–100) updated after every agent interaction
- **Real-time charts** — hallucination, relevance, latency over hour/day/week/month/year
- **Incident reports** — before/after comparison with root cause and fix description
- **Scheduler** — run healing loops on a recurring schedule
- **Agent Control** — trigger runs manually, watch live output stream
- **Healing Journey Dialog** — animated step-by-step visualization of the healing process
- **FAQ Editor** — edit the knowledge base from the dashboard
- **Embeddable Widget** — paste one `<iframe>` tag into any app

---

## 🛠️ Tech Stack

| Layer | Technology |
|---|---|
| Frontend | Flutter Web, Dart, Provider, go_router, fl_chart |
| Backend API | Python, FastAPI, Uvicorn, WebSockets |
| Agent / AI | Gemini 2.5 Flash via google-generativeai |
| Observability | Arize Phoenix, OpenTelemetry, Phoenix MCP server |
| External Data | SEC EDGAR APIs (for investment use case) |
| Persistence | SQLite, SQLAlchemy async |
| Scheduling | APScheduler |
| Deployment | Google Cloud Run, Docker |

---

## ⚡ Quick Start

### Prerequisites
- Python 3.12
- Node.js / npm (for Phoenix MCP)
- Flutter (for dashboard UI)
- Google API key from [aistudio.google.com](https://aistudio.google.com)

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
GOOGLE_API_KEY=your_google_api_key_here
PHOENIX_API_KEY=your_local_phoenix_key
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

Open [http://localhost:6006](http://localhost:6006) → Settings → API Keys → Create → paste key into `.env`

### 4. Run the agent (standalone)

```bash
python agent/main.py
```

Watch the 7-step healing loop run in your terminal.

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

Open [http://localhost:3000](http://localhost:3000)

---

## 🐳 Docker

```bash
docker build -f deploy/Dockerfile -t self-healing-agent .
docker run --env-file .env self-healing-agent
```

---

## ☁️ Deploy to Google Cloud Run

```bash
gcloud run deploy self-healing-agent \
  --source . \
  --region us-central1 \
  --allow-unauthenticated \
  --set-env-vars GOOGLE_API_KEY=your_key \
  --set-env-vars HALLUCINATION_THRESHOLD=0.4 \
  --set-env-vars RELEVANCE_THRESHOLD=0.6 \
  --set-env-vars LATENCY_THRESHOLD_MS=3000
```

Build Flutter for production first:

```bash
cd dashboard
flutter build web --release \
  --dart-define=API_BASE_URL=https://your-cloud-run-url \
  --dart-define=WS_URL=wss://your-cloud-run-url/ws
```

---

## 🧩 Embed in Any App

Drop this into any HTML page or admin console:

```html
<iframe
  src="https://self-healing-agent-274002881656.us-central1.run.app/embed/widget"
  width="360"
  height="240"
  style="border:0;border-radius:12px;overflow:hidden"
  title="Self-Healing Agent Health">
</iframe>
```

Shows live health score and latest incident report. Updates automatically.

---

## 🧪 Tests

```bash
pytest
```

All tests pass without Phoenix or Gemini keys configured — components fall back gracefully to local rules.

---

## 📁 Project Structure

```
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

## 📄 Sample Healing Report

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔧 SELF-HEALING REPORT — 2026-05-17 03:47:00
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
App: Customer Support Agent
Problem: Hallucination rate above threshold (0.72)
Root Cause: GUESSING — Agent filling knowledge gaps
            with invented details not in the FAQ
Fix Applied: Added strict grounding instruction.
             Required fallback for unsupported questions.

BEFORE:
  Hallucination: 0.72
  Relevance:     0.31
  Latency:       2046ms

AFTER:
  Hallucination: 0.04  (-94%)  ✅
  Relevance:     0.87  (+181%) ✅
  Latency:       1.9s          ✅

Improvement: +89%
Human Action Needed: NO ✅
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## 🏆 Built For

**Google Cloud Rapid Agent Hackathon** — Arize Track

- ✅ Powered by Gemini 2.5 Flash
- ✅ Deployed on Google Cloud Run
- ✅ Arize Phoenix MCP integration
- ✅ Multi-step autonomous agent loop
- ✅ Moves beyond chat — plans, acts, verifies, reports
- ✅ Three real-world use cases

---

## 📜 License

Apache 2.0 — see [LICENSE](LICENSE)

---

*Built by Salman Khan · May 2026*