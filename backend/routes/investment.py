"""Investment analyst API routes for SEC-grounded company research.

These endpoints provide chat-like analyst responses, SEC context lookup,
answer evaluation, and in-memory session history for the investment agent.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any, Literal

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from backend.services.agent_runner import websocket_manager
from backend.services.investment_agent import investment_agent


router = APIRouter(prefix="/api/investment", tags=["investment"])
sessions: dict[str, list["InvestmentMessage"]] = {}
MAX_SESSION_MESSAGES = 50


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
    await websocket_manager.broadcast("investment_reset:v1")
    return {"status": "reset", "prompt_version": 1}


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
