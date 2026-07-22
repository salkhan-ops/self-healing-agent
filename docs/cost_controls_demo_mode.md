# Archived cost controls

This project was originally split for low-cost public judging:

- GitHub Pages served the Flutter frontend.
- Cloud Run served backend APIs.
- Public demo mode limited agent loops and disabled background scheduling.

The hackathon deployment is now shut down. The archived default is:

```bash
DISABLE_LLM_CALLS=true
PUBLIC_DEMO_MODE=true
AGENT_MODE=local
```

With these settings:

- Gemini calls are disabled process-wide.
- The scheduler is disabled at startup.
- Agent responses use local fallback behavior.
- Deployment scripts refuse to run unless `ALLOW_ARCHIVED_DEPLOY=true` is set.

Re-enabling the original live demo requires intentionally creating new
credentials, setting `DISABLE_LLM_CALLS=false`, and redeploying Cloud Run.
