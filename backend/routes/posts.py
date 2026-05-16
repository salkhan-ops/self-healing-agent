"""Social media post generation API routes.

Exposes generate, status, reset, and history endpoints for the social media
posts use case.
"""

from __future__ import annotations

import asyncio
import uuid as uuid_module
from datetime import datetime
from typing import Literal

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from backend.services.agent_runner import websocket_manager
from backend.services.metrics_store import MetricsStore
from backend.services.post_agent import post_agent
from backend.services.post_history_store import add_post, clear_posts, list_posts
from backend.services.post_scorer import post_scorer

router = APIRouter(prefix="/api/posts", tags=["posts"])
_metrics_store = MetricsStore()

class PostRequest(BaseModel):
    brief: str = Field(min_length=1)
    platform: Literal["linkedin", "twitter", "facebook"] = "linkedin"


class PostResponse(BaseModel):
    post: str
    platform: str
    latency_ms: int
    trace_id: str
    prompt_version: int
    hallucination_score: float
    relevance_score: float


@router.post("/generate", response_model=PostResponse)
async def generate_post(payload: PostRequest) -> PostResponse:
    """Generate a social media post from a raw brief."""
    try:
        result = await asyncio.to_thread(
            post_agent.generate,
            payload.brief,
            payload.platform,
        )
        post_text = str(result.get("post", ""))
        prompt_version = int(result.get("prompt_version", 1))
        scores = await asyncio.to_thread(
            post_scorer.score,
            payload.brief,
            post_text,
            prompt_version,
        )

        entry = {
            "id": uuid_module.uuid4().hex[:8],
            "timestamp": datetime.utcnow().isoformat(),
            "brief": payload.brief,
            "platform": payload.platform,
            "post": post_text,
            "prompt_version": prompt_version,
            "hallucination_score": scores["hallucination_score"],
            "relevance_score": scores["relevance_score"],
            "latency_ms": int(result.get("latency_ms", 0)),
            "trace_id": str(result.get("trace_id", "")),
        }
        add_post(entry)

        class _Eval:
            hallucination_score = scores["hallucination_score"]
            relevance_score = scores["relevance_score"]
            latency_ms = float(result.get("latency_ms", 0))
            trace_scores = []
            problematic_traces = []

        class _Verify:
            improved = True
            improvement_percent = 0.0
            before_scores = {
                "hallucination_score": scores["hallucination_score"],
                "relevance_score": scores["relevance_score"],
                "latency_ms": float(result.get("latency_ms", 0)),
            }
            after_scores = before_scores

        run_id = f"post-{entry['id']}"
        await _metrics_store.save_run_metrics(run_id, _Eval(), _Verify())
        await websocket_manager.broadcast("metrics_updated")

        return PostResponse(
            post=post_text,
            platform=payload.platform,
            latency_ms=int(result.get("latency_ms", 0)),
            trace_id=str(result.get("trace_id", "")),
            prompt_version=prompt_version,
            hallucination_score=scores["hallucination_score"],
            relevance_score=scores["relevance_score"],
        )
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=f"Post generation failed: {exc}",
        ) from exc


@router.get("/history")
async def get_post_history() -> list[dict]:
    """Return the last 20 generated posts."""
    return list_posts(limit=20)


@router.get("/status")
async def get_post_status() -> dict:
    """Return current post agent status."""
    return post_agent.get_status()


@router.post("/reset")
async def reset_post_agent() -> dict:
    """Reset post agent to weak prompt."""
    try:
        post_agent.reset()
        clear_posts()
        await websocket_manager.broadcast("post_reset:v1")
        return {"status": "reset", "prompt_version": 1}
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=f"Reset failed: {exc}",
        ) from exc
