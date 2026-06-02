"""Investment analyst API routes for SEC-grounded company research.

These endpoints provide chat-like analyst responses, SEC context lookup,
answer evaluation, and in-memory session history for the investment agent.
"""

from __future__ import annotations

import asyncio
import uuid
from datetime import datetime
from typing import Any, Literal

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from backend.services.agent_runner import websocket_manager
from backend.services.investment_agent import investment_agent
from backend.services.investment_healer import investment_healer
from backend.services.investment_history_store import (
    add_investment_entry,
    clear_investment_entries,
)
from backend.services.trace_evidence_store import trace_evidence_store
from config.settings import AGENT_RUN_TIMEOUT_SECONDS


router = APIRouter(prefix="/api/investment", tags=["investment"])
sessions: dict[str, list["InvestmentMessage"]] = {}
MAX_SESSION_MESSAGES = 50
_healing_lock = asyncio.Lock()


class InvestmentRequest(BaseModel):
    """Request body for investment research chat."""

    message: str = Field(min_length=1)
    ticker: str = ""
    session_id: str = ""


class InvestmentResponse(BaseModel):
    """Investment research response payload."""

    answer: str
    ticker: str
    latency_ms: int
    trace_id: str
    prompt_version: int
    session_id: str
    sources: list[str]
    risk_flags: list[str]
    hallucination_score: float = 0.0
    relevance_score: float = 0.0
    quality_score: float = 0.0
    sec_context: dict[str, Any]


class InvestmentMessage(BaseModel):
    """One investment conversation message."""

    role: Literal["user", "agent"]
    content: str
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    latency_ms: int = 0
    trace_id: str = ""
    ticker: str = ""


class EvaluationRequest(BaseModel):
    """Request body for evaluating an investment answer."""

    question: str
    answer: str
    ticker: str = ""


@router.post("/message", response_model=InvestmentResponse)
async def send_investment_message(payload: InvestmentRequest) -> InvestmentResponse:
    """Answer an investment question and store the conversation session."""
    session_id = payload.session_id.strip() or uuid.uuid4().hex[:12]
    try:
        _append(session_id, InvestmentMessage(role="user", content=payload.message, ticker=payload.ticker))
        result = investment_agent.answer(payload.message, payload.ticker or None)
        prompt_version = int(result.get("prompt_version", investment_agent.prompt_version))
        _append(
            session_id,
            InvestmentMessage(
                role="agent",
                content=str(result.get("answer", "")),
                latency_ms=int(result.get("latency_ms", 0)),
                trace_id=str(result.get("trace_id", "")),
                ticker=str(result.get("ticker", "")),
            ),
        )
        evaluation = investment_agent.evaluate_answer(
            payload.message,
            str(result.get("answer", "")),
            str(result.get("ticker", "")),
        )
        add_investment_entry(
            {
                "question": payload.message,
                "ticker": str(result.get("ticker", "")),
                "answer": str(result.get("answer", "")),
                "prompt_version": prompt_version,
                "risk_flags": evaluation["risk_flags"],
                "hallucination_score": evaluation["hallucination_score"],
                "relevance_score": evaluation["relevance_score"],
                "quality_score": evaluation["quality_score"],
                "sec_context": result.get("sec_context", {}),
            }
        )
        trace_evidence_store.record_interaction(
            trace_id=str(result.get("trace_id", "")),
            span_name="investment_agent.answer",
            agent_name="InvestmentAgent",
            use_case="investment",
            prompt=payload.message,
            response=str(result.get("answer", "")),
            hallucination_score=evaluation["hallucination_score"],
            relevance_score=evaluation["relevance_score"],
            latency_ms=int(result.get("latency_ms", 0)),
            prompt_version=prompt_version,
            metadata={
                "ticker": str(result.get("ticker", "")),
                "risk_flags": evaluation["risk_flags"],
                "quality_score": evaluation["quality_score"],
            },
        )
        await websocket_manager.broadcast(f"investment_update:{session_id}:v{prompt_version}")
        return InvestmentResponse(session_id=session_id, **result)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Could not process investment message: {exc}") from exc


@router.get("/status")
async def get_investment_status() -> dict[str, Any]:
    """Return investment agent status."""
    return investment_agent.get_status()


@router.get("/history/{session_id}", response_model=list[InvestmentMessage])
async def get_investment_history(session_id: str) -> list[InvestmentMessage]:
    """Return last 20 messages for a session."""
    return sessions.get(session_id, [])[-20:]


@router.post("/reset")
async def reset_investment() -> dict[str, int | str]:
    """Reset investment agent and clear sessions."""
    investment_agent.reset()
    sessions.clear()
    clear_investment_entries()
    await websocket_manager.broadcast("investment_reset:v1")
    return {"status": "reset", "prompt_version": 1}


@router.post("/heal")
async def heal_investment() -> dict[str, Any]:
    """Run the dedicated investment healer and update the live analyst prompt."""
    if _healing_lock.locked():
        raise HTTPException(
            status_code=409,
            detail="Investment healing is already running.",
        )

    try:
        async with _healing_lock:
            healing = await asyncio.wait_for(
                asyncio.to_thread(investment_healer.heal_recent_answers),
                timeout=AGENT_RUN_TIMEOUT_SECONDS,
            )
        if healing is None:
            return {
                "status": "no_change",
                "prompt_version": investment_agent.prompt_version,
            }

        investment_agent.update_prompt(healing.new_prompt)
        await websocket_manager.broadcast(
            f"investment_prompt_updated:v{investment_agent.prompt_version}"
        )
        verification = healing.verification_traces[0] if healing.verification_traces else {}
        trace_evidence_store.record_healing(
            healing_run_id=f"investment-heal-{uuid.uuid4().hex[:8]}",
            agent_name="InvestmentAgent",
            use_case="investment",
            root_cause=healing.root_cause,
            root_cause_diagnosis=healing.root_cause_explanation,
            prompt_patch_applied=healing.new_prompt,
            before={
                "question": verification.get("question", ""),
                "answer": "",
                "prompt_version": investment_agent.prompt_version - 1,
                "hallucination_score": 0.0,
                "relevance_score": 0.0,
            },
            after={
                "question": verification.get("question", ""),
                "answer": verification.get("answer", ""),
                "prompt_version": investment_agent.prompt_version,
                "hallucination_score": 0.0,
                "relevance_score": 0.0,
            },
            verification_results=healing.after_scores,
        )
        return {
            "status": "healed",
            "prompt_version": investment_agent.prompt_version,
            "root_cause": healing.root_cause,
        }
    except TimeoutError as exc:
        raise HTTPException(
            status_code=504,
            detail="Investment healing timed out. Please try again later.",
        ) from exc
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=f"Investment healing failed: {exc}",
        ) from exc


@router.get("/tickers")
async def get_tickers() -> dict[str, Any]:
    """Return cached SEC ticker mapping when available."""
    mapping = investment_agent.sec_client._get_ticker_mapping()
    return {"count": len(mapping), "tickers": mapping}


@router.get("/sec/{ticker}")
async def get_sec_context(ticker: str) -> dict[str, Any]:
    """Return SEC research context for a ticker."""
    context = investment_agent.sec_client.build_research_context(ticker)
    if not context.get("cik"):
        raise HTTPException(status_code=404, detail="Ticker not found or SEC data unavailable.")
    return context


@router.post("/evaluate")
async def evaluate_investment_answer(payload: EvaluationRequest) -> dict[str, Any]:
    """Evaluate answer safety and grounding."""
    return investment_agent.evaluate_answer(payload.question, payload.answer, payload.ticker)


def _append(session_id: str, message: InvestmentMessage) -> None:
    """Append and trim session history."""
    sessions.setdefault(session_id, []).append(message)
    if len(sessions[session_id]) > MAX_SESSION_MESSAGES:
        sessions[session_id] = sessions[session_id][-MAX_SESSION_MESSAGES:]
