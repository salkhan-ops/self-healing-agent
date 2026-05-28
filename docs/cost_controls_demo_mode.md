# Public demo cost controls

This project is split for low-cost public judging:

- **GitHub Pages serves the Flutter frontend**: `https://salkhan-ops.github.io/self-healing-agent-landing/`
- **Cloud Run serves backend APIs only**: `https://self-healing-agent-274002881656.us-central1.run.app`

Do not replace backend/API URLs with the GitHub Pages URL. GitHub Pages is frontend-only.

## Cloud Run settings

Recommended public-demo service settings:

- min instances: `0`
- max instances: `2`
- CPU throttling: enabled

Recommended update command:

```bash
gcloud run services update self-healing-agent \
  --region us-central1 \
  --min=0 \
  --max=2 \
  --cpu-throttling
```

## Recommended demo environment variables

```bash
PUBLIC_DEMO_MODE=true
PUBLIC_DEMO_AGENT_RUN_LIMIT=2
PUBLIC_DEMO_HEALING_RUN_LIMIT=2
MAX_AGENT_ITERATIONS=2
MAX_LLM_RETRIES=1
AGENT_RUN_TIMEOUT_SECONDS=60
LLM_TIMEOUT_SECONDS=30
MAX_OUTPUT_TOKENS=1024
```

Use existing production values when running privately. For public judging, keep `PUBLIC_DEMO_MODE=true` so judges see targeted healing flows without starting the full expensive loop.

## What demo mode protects

In `PUBLIC_DEMO_MODE=true`:

- Full Agent Control endpoints are disabled:
  - `POST /api/agent/run`
  - `POST /api/agent/stop`
- Dedicated social post healing remains available, but is limited by `PUBLIC_DEMO_HEALING_RUN_LIMIT`.
- The background scheduler is disabled at startup to avoid surprise background runs.
- Gemini calls use bounded output tokens, request timeouts, and limited retries.
- Long full-agent runs use `AGENT_RUN_TIMEOUT_SECONDS` and `MAX_AGENT_ITERATIONS`.

## Best-effort limits

The lightweight demo limiter is in-memory and keyed by session header when present, otherwise by client IP/user-agent. Because Cloud Run can run up to 2 instances, these counters are **best-effort per instance**, not a global quota. They are guardrails against accidental spend, not billing enforcement.

## Credits and Gemini cost

Google Cloud credits may cover eligible Google Cloud costs, but this app should still prevent accidental spend. Gemini cost coverage depends on the billing/credit type, so the project should not assume unlimited Gemini usage.

## Judge experience

Judges should use targeted healing flows, especially social post healing. They should not need the full multi-agent run loop in the public demo.
