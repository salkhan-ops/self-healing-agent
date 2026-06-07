"""Social media post generation API routes.

Exposes generate, status, reset, and history endpoints for the social media
posts use case.
"""

from __future__ import annotations

import asyncio
import uuid as uuid_module
from datetime import datetime
from typing import Literal

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from backend.services.agent_runner import websocket_manager
from backend.services.cost_controls import InMemoryDemoLimiter, demo_client_key
from backend.services.metrics_store import MetricsStore
from backend.services.post_agent import post_agent
from backend.services.post_healer import post_healer
from backend.services.post_history_store import add_post, clear_posts, list_posts
from backend.services.post_scorer import post_scorer
from backend.services.trace_evidence_store import trace_evidence_store
from config.settings import (
    AGENT_RUN_TIMEOUT_SECONDS,
    LLM_TIMEOUT_SECONDS,
    PUBLIC_DEMO_HEALING_RUN_LIMIT,
    PUBLIC_DEMO_MODE,
)

try:
    from opentelemetry import trace
except ImportError:
    trace = None

router = APIRouter(prefix="/api/posts", tags=["posts"])
_metrics_store = MetricsStore()
_healing_limiter = InMemoryDemoLimiter(
    name="post_healing",
    limit=PUBLIC_DEMO_HEALING_RUN_LIMIT,
)
_healing_lock = asyncio.Lock()
POST_SCORING_TIMEOUT_SECONDS = 12

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
        try:
            result = await asyncio.wait_for(
                asyncio.to_thread(
                    post_agent.generate,
                    payload.brief,
                    payload.platform,
                ),
                timeout=LLM_TIMEOUT_SECONDS,
            )
        except TimeoutError:
            print("⚠️ Post generation timed out, using grounded fallback post.")
            result = {
                "post": _fallback_post(payload.brief, payload.platform),
                "platform": payload.platform,
                "latency_ms": int(LLM_TIMEOUT_SECONDS * 1000),
                "trace_id": f"post-timeout-{uuid_module.uuid4().hex[:8]}",
                "prompt_version": post_agent.prompt_version,
            }
        post_text = str(result.get("post", ""))
        prompt_version = int(result.get("prompt_version", 1))
        try:
            scores = await asyncio.wait_for(
                asyncio.to_thread(
                    post_scorer.score,
                    payload.brief,
                    post_text,
                    prompt_version,
                ),
                timeout=POST_SCORING_TIMEOUT_SECONDS,
            )
        except TimeoutError:
            print("⚠️ Post scoring timed out, using rule-based score.")
            scores = post_scorer._score_with_rules(payload.brief, post_text)

        entry = {
            "id": uuid_module.uuid4().hex[:8],
            "timestamp": datetime.utcnow().isoformat() + "Z",
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
        trace_evidence_store.record_interaction(
            trace_id=entry["trace_id"],
            span_name="post_agent.generate",
            agent_name="PostAgent",
            use_case="post",
            prompt=payload.brief,
            response=post_text,
            hallucination_score=scores["hallucination_score"],
            relevance_score=scores["relevance_score"],
            latency_ms=entry["latency_ms"],
            prompt_version=prompt_version,
            metadata={"platform": payload.platform},
        )
        _record_post_evaluation_span(payload.brief, post_text, entry, scores)

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


def _fallback_post(brief: str, platform: str) -> str:
    """Return a concise grounded post when Gemini is slow or unavailable."""
    clean_brief = " ".join(brief.split())
    if platform == "twitter":
        return clean_brief[:260]
    if platform == "facebook":
        return (
            "Update from the team:\n\n"
            f"{clean_brief}\n\n"
            "We are keeping this update limited to the approved facts in the brief."
        )
    return (
        "Team update:\n\n"
        f"{clean_brief}\n\n"
        "This version stays grounded in the approved brief and avoids adding "
        "unverified metrics, customer claims, or growth language."
    )


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


@router.post("/heal")
async def heal_post_agent(request: Request) -> dict:
    """Run the dedicated post-agent healer without waiting for the full cross-agent loop."""
    client_key = demo_client_key(request)
    if PUBLIC_DEMO_MODE:
        allowed, remaining = _healing_limiter.check_and_increment(client_key)
        if not allowed:
            raise HTTPException(
                status_code=429,
                detail="Public demo healing limit reached. Social post healing has reached the public demo limit.",
            )
        print(f"💸 Public demo post healing allowed; remaining_for_client={remaining}")

    if _healing_lock.locked():
        raise HTTPException(
            status_code=409,
            detail="Social post healing is already running. Please wait for the current healing pass to finish.",
        )

    try:
        async with _healing_lock:
            healing = await asyncio.wait_for(
                asyncio.to_thread(post_healer.heal_recent_posts),
                timeout=AGENT_RUN_TIMEOUT_SECONDS,
            )
        if healing is None:
            if PUBLIC_DEMO_MODE:
                _healing_limiter.refund(client_key)
            return {
                "status": "no_change",
                "prompt_version": post_agent.prompt_version,
            }

        post_agent.update_prompt(healing.new_prompt)
        await websocket_manager.broadcast(f"post_prompt_updated:v{post_agent.prompt_version}")
        verification = healing.verification_traces[0] if healing.verification_traces else {}
        healing_run_id = f"post-heal-{uuid_module.uuid4().hex[:8]}"
        source = list_posts(limit=1)
        before = source[0] if source else {}
        trace_evidence_store.record_healing(
            healing_run_id=healing_run_id,
            agent_name="PostAgent",
            use_case="post",
            root_cause=healing.root_cause,
            root_cause_diagnosis=healing.root_cause_explanation,
            prompt_patch_applied=healing.new_prompt,
            before={
                "brief": before.get("brief", verification.get("brief", "")),
                "prompt": before.get("brief", verification.get("brief", "")),
                "post": before.get("post", ""),
                "response": before.get("post", ""),
                "prompt_version": before.get("prompt_version", post_agent.prompt_version - 1),
                "trace_id": before.get("trace_id", ""),
                "hallucination_score": healing.before_scores.get("hallucination_score", 0.0),
                "relevance_score": healing.before_scores.get("relevance_score", 0.0),
                "latency_ms": before.get("latency_ms", 0),
            },
            after={
                "brief": verification.get("brief", ""),
                "post": verification.get("post", ""),
                "response": verification.get("post", ""),
                "prompt_version": post_agent.prompt_version,
                "hallucination_score": verification.get("hallucination_score", 0.0),
                "relevance_score": verification.get("relevance_score", 0.0),
            },
            verification_results=healing.after_scores,
        )
        try:
            await _metrics_store.save_healing_report(
                run_id=healing_run_id,
                use_case="Social Media Posts",
                problem="Social post hallucination above threshold",
                root_cause=healing.root_cause_explanation or healing.root_cause,
                fix_applied="Updated the post prompt with learned grounding constraints.",
                before_scores={
                    **healing.before_scores,
                    "latency_ms": float(before.get("latency_ms", 0)),
                },
                after_scores={
                    **healing.after_scores,
                    "latency_ms": float(verification.get("latency_ms", 0)),
                },
                before_text=str(before.get("post", "")),
                after_text=str(verification.get("post", "")),
            )
            await websocket_manager.broadcast("reports_updated")
        except Exception as exc:
            print(f"⚠️ Post healing report save failed (non-critical): {exc}")
        _record_post_healing_span(healing_run_id, healing, verification)
        return {
            "status": "healed",
            "prompt_version": post_agent.prompt_version,
            "healing_run_id": healing_run_id,
            "root_cause": healing.root_cause,
            "root_cause_explanation": healing.root_cause_explanation,
            "old_prompt": healing.old_prompt,
            "new_prompt": healing.new_prompt,
            "before_scores": healing.before_scores,
            "after_scores": healing.after_scores,
            "verification_traces": healing.verification_traces,
            "preview": {
                "brief": verification.get("brief", ""),
                "platform": verification.get("platform", "linkedin"),
                "post": verification.get("post", ""),
                "prompt_version": post_agent.prompt_version,
                "hallucination_score": verification.get("hallucination_score", 0.0),
                "relevance_score": verification.get("relevance_score", 0.0),
            },
        }
    except TimeoutError as exc:
        print(f"⏱️ Post healing timed out after {AGENT_RUN_TIMEOUT_SECONDS}s")
        raise HTTPException(
            status_code=504,
            detail="Social post healing timed out. Please try again later.",
        ) from exc
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=f"Post healing failed: {exc}",
        ) from exc


def _record_post_evaluation_span(
    brief: str,
    post_text: str,
    entry: dict,
    scores: dict[str, float],
) -> None:
    """Emit a scored post span after route-level evaluation completes."""
    if trace is None:
        return
    with trace.get_tracer(__name__).start_as_current_span("post_agent.evaluate") as span:
        span.set_attribute("agent.name", "PostAgent")
        span.set_attribute("use_case", "post")
        span.set_attribute("post.trace_id", entry.get("trace_id", ""))
        span.set_attribute("post.platform", entry.get("platform", ""))
        span.set_attribute("input.value", brief)
        span.set_attribute("output.value", post_text)
        span.set_attribute("hallucination_score", scores["hallucination_score"])
        span.set_attribute("relevance_score", scores["relevance_score"])
        span.set_attribute("latency_ms", entry.get("latency_ms", 0))
        span.set_attribute(
            "before_after_status",
            "before" if int(entry.get("prompt_version", 1)) <= 1 else "after",
        )


def _record_post_healing_span(
    healing_run_id: str,
    healing,
    verification: dict,
) -> None:
    """Emit a post healing span with the root cause and patch."""
    if trace is None:
        return
    with trace.get_tracer(__name__).start_as_current_span("post_agent.healing") as span:
        span.set_attribute("agent.name", "PostAgent")
        span.set_attribute("use_case", "post")
        span.set_attribute("healing.run_id", healing_run_id)
        span.set_attribute("input.value", verification.get("brief", ""))
        span.set_attribute("output.value", verification.get("post", ""))
        span.set_attribute("root_cause", healing.root_cause)
        span.set_attribute("root_cause_diagnosis", healing.root_cause_explanation)
        span.set_attribute("prompt_patch_applied", healing.new_prompt)
        span.set_attribute("before_after_status", "before_after")
        span.set_attribute(
            "hallucination_score.before",
            healing.before_scores.get("hallucination_score", 0.0),
        )
        span.set_attribute(
            "hallucination_score.after",
            healing.after_scores.get("hallucination_score", 0.0),
        )
