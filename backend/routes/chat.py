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
