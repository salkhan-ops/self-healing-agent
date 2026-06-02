"""Chat API routes for the customer support demo.

This module exposes the live chat endpoints, stores short in-memory session
history, and broadcasts chat/prompt events to dashboard WebSocket clients.
"""

from __future__ import annotations

import asyncio
import json
import uuid
import uuid as uuid_module
from datetime import datetime
from typing import Literal

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from backend.services.agent_runner import websocket_manager
from backend.services.chat_agent import chat_agent
from backend.services.chat_scorer import chat_scorer
from backend.services.demo_incidents import match_incident
from backend.services.metrics_store import MetricsStore
from backend.services.trace_evidence_store import trace_evidence_store

try:
    from opentelemetry import trace
except ImportError:
    trace = None


router = APIRouter(prefix="/api/chat", tags=["chat"])
sessions: dict[str, list["ChatMessage"]] = {}
MAX_SESSION_MESSAGES = 50
_metrics_store = MetricsStore()


class ChatRequest(BaseModel):
    """Incoming chat message request."""

    message: str = Field(min_length=1)
    session_id: str = ""


class ChatResponse(BaseModel):
    """Chat answer response returned to the dashboard."""

    answer: str
    latency_ms: int
    trace_id: str
    prompt_version: int
    session_id: str
    hallucination_score: float = 0.0
    relevance_score: float = 0.0


class ChatMessage(BaseModel):
    """One user or agent message stored in session history."""

    role: Literal["user", "agent"]
    content: str
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    latency_ms: int = 0
    trace_id: str = ""


@router.post("/message", response_model=ChatResponse)
async def send_chat_message(payload: ChatRequest) -> ChatResponse:
    """Save a user message, get an agent answer, and return response metadata."""
    session_id = payload.session_id.strip() or uuid.uuid4().hex[:12]

    try:
        _append_message(
            session_id,
            ChatMessage(role="user", content=payload.message),
        )
        result = await asyncio.to_thread(chat_agent.answer, payload.message)
        prompt_version = int(result.get("prompt_version", chat_agent.prompt_version))

        _append_message(
            session_id,
            ChatMessage(
                role="agent",
                content=str(result.get("answer", "")),
                latency_ms=int(result.get("latency_ms", 0)),
                trace_id=str(result.get("trace_id", "")),
            ),
        )

        scores = {"hallucination_score": 0.0, "relevance_score": 0.0}
        try:
            scores = await asyncio.to_thread(
                chat_scorer.score,
                payload.message,
                str(result.get("answer", "")),
                prompt_version,
            )

            class _ChatEval:
                hallucination_score = scores["hallucination_score"]
                relevance_score = scores["relevance_score"]
                latency_ms = float(result.get("latency_ms", 0))
                trace_scores = []
                problematic_traces = []

            class _ChatVerification:
                improved = True
                improvement_percent = 0.0
                before_scores = {
                    "hallucination_score": scores["hallucination_score"],
                    "relevance_score": scores["relevance_score"],
                    "latency_ms": float(result.get("latency_ms", 0)),
                }
                after_scores = before_scores

            chat_run_id = f"chat-{uuid_module.uuid4().hex[:8]}"
            await _metrics_store.save_run_metrics(
                chat_run_id,
                _ChatEval(),
                _ChatVerification(),
            )
            await websocket_manager.broadcast("metrics_updated")
        except Exception as exc:
            print(f"⚠️ Chat scoring failed (non-critical): {exc}")

        _record_chat_trace(
            payload.message,
            str(result.get("answer", "")),
            str(result.get("trace_id", "")),
            int(result.get("latency_ms", 0)),
            prompt_version,
            scores,
        )
        await websocket_manager.broadcast(f"chat_update:{session_id}:v{prompt_version}")
        if (
            prompt_version == 1
            and scores["hallucination_score"] >= 0.4
            and match_incident(payload.message) is not None
        ):
            await _auto_heal_chat(
                payload.message,
                str(result.get("answer", "")),
                scores,
                prompt_version,
            )
        return ChatResponse(
            answer=str(result.get("answer", "")),
            latency_ms=int(result.get("latency_ms", 0)),
            trace_id=str(result.get("trace_id", "")),
            prompt_version=prompt_version,
            session_id=session_id,
            hallucination_score=scores["hallucination_score"],
            relevance_score=scores["relevance_score"],
        )
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Could not process chat message: {exc}") from exc


async def _auto_heal_chat(
    question: str,
    before_answer: str,
    before_scores: dict[str, float],
    before_version: int,
) -> None:
    """Update the chat prompt and broadcast a before/after comparison."""
    incident = match_incident(question) or match_incident(before_answer)
    if incident is None:
        return

    old_prompt = chat_agent.system_prompt
    new_prompt = (
        "You are a customer support agent for an online store.\n"
        "Use ONLY facts from the FAQ knowledge base.\n"
        "If the FAQ does not contain the answer, say: I don't know based on the FAQ.\n"
        "Do not invent private contact details, payment addresses, discount codes, "
        "shipping destinations, return windows, refund timelines, company history, "
        "brand details, or unsupported policy exceptions.\n"
        "Answer the customer's exact question first, briefly and clearly."
    )
    chat_agent.update_prompt(new_prompt)
    await websocket_manager.broadcast(f"prompt_updated:v{chat_agent.prompt_version}")

    healed = await asyncio.to_thread(chat_agent.answer, question)
    after_answer = str(healed.get("answer", ""))
    after_scores = await asyncio.to_thread(
        chat_scorer.score,
        question,
        after_answer,
        chat_agent.prompt_version,
    )
    payload = {
        "pairs": [
            {
                "question": question,
                "before": before_answer,
                "after": after_answer,
                "before_version": before_version,
                "after_version": chat_agent.prompt_version,
                "changed": before_answer.strip() != after_answer.strip(),
                "incident_title": incident.title,
                "risk": incident.risk,
                "blocked_terms": list(incident.unsupported_terms),
            }
        ],
        "root_cause": "HALLUCINATION",
        "root_cause_explanation": (
            "The weak support prompt invented unsupported customer-facing facts. "
            "Healing now requires every answer to come from the FAQ."
        ),
        "before_hallucination": before_scores["hallucination_score"],
        "after_hallucination": after_scores["hallucination_score"],
        "before_relevance": before_scores["relevance_score"],
        "after_relevance": after_scores["relevance_score"],
        "old_prompt": old_prompt,
        "new_prompt": new_prompt,
    }
    trace_evidence_store.record_healing(
        healing_run_id=f"chat-heal-{uuid_module.uuid4().hex[:8]}",
        agent_name="ChatAgent",
        use_case="support",
        root_cause="HALLUCINATION",
        root_cause_diagnosis=payload["root_cause_explanation"],
        prompt_patch_applied=new_prompt,
        before={
            "question": question,
            "prompt": question,
            "answer": before_answer,
            "response": before_answer,
            "prompt_version": before_version,
            "hallucination_score": before_scores["hallucination_score"],
            "relevance_score": before_scores["relevance_score"],
        },
        after={
            "question": question,
            "answer": after_answer,
            "response": after_answer,
            "prompt_version": chat_agent.prompt_version,
            "trace_id": str(healed.get("trace_id", "")),
            "hallucination_score": after_scores["hallucination_score"],
            "relevance_score": after_scores["relevance_score"],
        },
        verification_results=after_scores,
    )
    _record_healing_span(
        "chat_agent.healing",
        "ChatAgent",
        "support",
        question,
        before_answer,
        after_answer,
        payload,
    )
    await websocket_manager.broadcast(f"comparisons_ready:{json.dumps(payload)}")


@router.get("/history/{session_id}", response_model=list[ChatMessage])
async def get_chat_history(session_id: str) -> list[ChatMessage]:
    """Return the last 20 messages for a chat session."""
    return sessions.get(session_id, [])[-20:]


@router.get("/status")
async def get_chat_status() -> dict:
    """Return the singleton chat agent status."""
    return chat_agent.get_status()


@router.post("/reset")
async def reset_chat() -> dict[str, int | str]:
    """Reset the chat agent and clear all in-memory sessions."""
    try:
        chat_agent.reset()
        sessions.clear()
        await websocket_manager.broadcast("chat_reset:v1")
        return {"status": "reset", "prompt_version": 1}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Could not reset chat agent: {exc}") from exc


def _append_message(session_id: str, message: ChatMessage) -> None:
    """Append a message and trim old session history."""
    sessions.setdefault(session_id, []).append(message)

    if len(sessions[session_id]) > MAX_SESSION_MESSAGES:
        sessions[session_id] = sessions[session_id][-MAX_SESSION_MESSAGES:]


def _record_chat_trace(
    question: str,
    answer: str,
    trace_id: str,
    latency_ms: int,
    prompt_version: int,
    scores: dict[str, float],
) -> None:
    """Record route-level scored chat trace metadata for Phoenix and UI."""
    trace_evidence_store.record_interaction(
        trace_id=trace_id,
        span_name="chat_agent.answer",
        agent_name="ChatAgent",
        use_case="support",
        prompt=question,
        response=answer,
        hallucination_score=scores["hallucination_score"],
        relevance_score=scores["relevance_score"],
        latency_ms=latency_ms,
        prompt_version=prompt_version,
    )
    if trace is None:
        return
    with trace.get_tracer(__name__).start_as_current_span("chat_agent.evaluate") as span:
        span.set_attribute("agent.name", "ChatAgent")
        span.set_attribute("use_case", "support")
        span.set_attribute("chat.trace_id", trace_id)
        span.set_attribute("input.value", question)
        span.set_attribute("output.value", answer)
        span.set_attribute("hallucination_score", scores["hallucination_score"])
        span.set_attribute("relevance_score", scores["relevance_score"])
        span.set_attribute("latency_ms", latency_ms)
        span.set_attribute("before_after_status", "before" if prompt_version <= 1 else "after")


def _record_healing_span(
    span_name: str,
    agent_name: str,
    use_case: str,
    prompt: str,
    before: str,
    after: str,
    payload: dict,
) -> None:
    """Emit a compact healing span with before/after status metadata."""
    if trace is None:
        return
    with trace.get_tracer(__name__).start_as_current_span(span_name) as span:
        span.set_attribute("agent.name", agent_name)
        span.set_attribute("use_case", use_case)
        span.set_attribute("input.value", prompt)
        span.set_attribute("response.before", before)
        span.set_attribute("response.after", after)
        span.set_attribute("root_cause", payload.get("root_cause", ""))
        span.set_attribute("prompt_patch_applied", payload.get("new_prompt", ""))
        span.set_attribute("before_after_status", "before_after")
        span.set_attribute("hallucination_score.before", payload.get("before_hallucination", 0.0))
        span.set_attribute("hallucination_score.after", payload.get("after_hallucination", 0.0))
