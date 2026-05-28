"""Agent control API routes for the dashboard backend.

These endpoints trigger a self-healing run through AgentRunner and expose the
current runner status to the dashboard.
"""

from __future__ import annotations

import uuid

from fastapi import APIRouter, BackgroundTasks

from backend.services.agent_runner import agent_runner
from config.settings import PUBLIC_DEMO_AGENT_RUN_LIMIT, PUBLIC_DEMO_MODE


router = APIRouter(prefix="/api/agent", tags=["agent"])
_public_demo_runs_started = 0


@router.post("/run")
async def run_agent_now(background_tasks: BackgroundTasks) -> dict[str, str]:
    """Trigger the self-healing agent now and return immediately."""
    global _public_demo_runs_started

    if PUBLIC_DEMO_MODE:
        print("🛑 Public demo blocked full agent run.")
        return {
            "run_id": "",
            "status": "disabled",
            "message": "Full agent run is disabled in public demo mode.",
        }

    if agent_runner.status == "running":
        return {"run_id": agent_runner.current_run_id or "", "status": "already_running"}

    run_id = str(uuid.uuid4())
    background_tasks.add_task(agent_runner.run_agent, run_id)
    return {"run_id": run_id, "status": "started"}


@router.post("/stop")
async def stop_agent_now() -> dict[str, object]:
    """Ask the self-healing agent to stop at the next safe checkpoint."""
    if PUBLIC_DEMO_MODE:
        print("🛑 Public demo blocked full agent stop endpoint.")
        return {
            "run_id": "",
            "status": "disabled",
            "message": "Full agent stop is disabled in public demo mode.",
        }

    return await agent_runner.request_stop()


@router.get("/status")
async def get_agent_status() -> dict[str, object]:
    """Return the current AgentRunner status."""
    status = agent_runner.get_status()
    status["public_demo_mode"] = PUBLIC_DEMO_MODE
    status["public_demo_agent_runs_remaining"] = (
        0
        if PUBLIC_DEMO_MODE
        else max(0, PUBLIC_DEMO_AGENT_RUN_LIMIT - _public_demo_runs_started)
    )
    return status
