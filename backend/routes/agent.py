"""Agent control API routes for the dashboard backend.

These endpoints trigger a self-healing run through AgentRunner and expose the
current runner status to the dashboard.
"""

from __future__ import annotations

import uuid

from fastapi import APIRouter, BackgroundTasks, Request

from backend.services.cost_controls import InMemoryDemoLimiter, demo_client_key
from backend.services.agent_runner import agent_runner
from config.settings import PUBLIC_DEMO_AGENT_RUN_LIMIT, PUBLIC_DEMO_MODE


router = APIRouter(prefix="/api/agent", tags=["agent"])
_public_demo_limiter = InMemoryDemoLimiter(
    name="full_agent_loop",
    limit=PUBLIC_DEMO_AGENT_RUN_LIMIT,
)


@router.post("/run")
async def run_agent_now(request: Request, background_tasks: BackgroundTasks) -> dict[str, str]:
    """Trigger the self-healing agent now and return immediately."""
    if agent_runner.status == "running":
        return {"run_id": agent_runner.current_run_id or "", "status": "already_running"}

    if PUBLIC_DEMO_MODE:
        allowed, remaining = _public_demo_limiter.check_and_increment(demo_client_key(request))
        if not allowed:
            return {
                "run_id": "",
                "status": "disabled",
                "message": f"Public demo allows {PUBLIC_DEMO_AGENT_RUN_LIMIT} full Agent Control runs per browser.",
            }
        print(f"💸 Public demo full agent run allowed; remaining_for_client={remaining}")

    run_id = str(uuid.uuid4())
    background_tasks.add_task(agent_runner.run_agent, run_id)
    return {"run_id": run_id, "status": "started"}


@router.post("/stop")
async def stop_agent_now() -> dict[str, object]:
    """Ask the self-healing agent to stop at the next safe checkpoint."""
    return await agent_runner.request_stop()


@router.get("/status")
async def get_agent_status(request: Request) -> dict[str, object]:
    """Return the current AgentRunner status."""
    status = agent_runner.get_status()
    status["public_demo_mode"] = PUBLIC_DEMO_MODE
    key = demo_client_key(request)
    used = _public_demo_limiter.counts[key]
    status["public_demo_agent_runs_remaining"] = max(0, PUBLIC_DEMO_AGENT_RUN_LIMIT - used)
    return status
