"""Pydantic response models for the dashboard API.

These models describe the JSON returned by the FastAPI backend for metrics,
reports, schedules, and live agent status.
"""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field


class MetricPointResponse(BaseModel):
    """One metric point for dashboard charts."""

    id: int = 0
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    hallucination_score: float = 0.0
    relevance_score: float = 0.0
    latency_ms: float = 0.0
    improvement_percent: float = 0.0
    run_id: str = ""


class ReportResponse(BaseModel):
    """One saved self-healing incident report."""

    id: int = 0
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    run_id: str = ""
    problem: str = ""
    root_cause: str = ""
    fix_applied: str = ""
    before_hallucination: float = 0.0
    before_relevance: float = 0.0
    before_latency: float = 0.0
    after_hallucination: float = 0.0
    after_relevance: float = 0.0
    after_latency: float = 0.0
    improvement_percent: float = 0.0
    human_needed: bool = False
    content_text: str = ""


class ScheduleResponse(BaseModel):
    """Schedule configuration returned by the dashboard API."""

    id: int = 0
    name: str = "Default self-healing run"
    interval_minutes: int = 60
    enabled: bool = True
    last_run: datetime | None = None
    next_run: datetime | None = None
    run_count: int = 0


class AgentStatusResponse(BaseModel):
    """Current dashboard status for the self-healing agent."""

    status: Literal["idle", "running", "error"] = "idle"
    message: str = "Agent is idle."
    current_run_id: str | None = None
    last_run_at: datetime | None = None
    next_run_at: datetime | None = None
    latest_hallucination_score: float = 0.0
    latest_relevance_score: float = 0.0
    latest_latency_ms: float = 0.0
    latest_improvement_percent: float = 0.0
    human_needed: bool = False
