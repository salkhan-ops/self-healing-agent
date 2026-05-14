"""Metric API routes for the dashboard backend.

These endpoints return recent metric snapshots, time-window summaries, and a
simple health score for the Self-Healing AI Agent dashboard.
"""

from __future__ import annotations

from datetime import datetime, timedelta
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from backend.database import MetricSnapshot, get_session
from backend.models import MetricPointResponse


router = APIRouter(prefix="/api/metrics", tags=["metrics"])


@router.get("/latest", response_model=list[MetricPointResponse])
async def get_latest_metrics(session: AsyncSession = Depends(get_session)) -> list[MetricSnapshot]:
    """Return the last 10 metric snapshots, newest first."""
    try:
        statement = select(MetricSnapshot).order_by(MetricSnapshot.timestamp.desc()).limit(10)
        result = await session.execute(statement)
        return list(result.scalars().all())
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Could not load latest metrics: {exc}") from exc


@router.get("/range")
async def get_metrics_range(
    period: Literal["hour", "day", "week", "month", "year"] = Query("day"),
    session: AsyncSession = Depends(get_session),
) -> dict[str, object]:
    """Return metric points and averages for a requested time period."""
    since = datetime.utcnow() - _period_delta(period)

    try:
        points_statement = (
            select(MetricSnapshot)
            .where(MetricSnapshot.timestamp >= since)
            .order_by(MetricSnapshot.timestamp.asc())
        )
        points_result = await session.execute(points_statement)
        points = list(points_result.scalars().all())

        averages_statement = select(
            func.avg(MetricSnapshot.hallucination_score),
            func.avg(MetricSnapshot.relevance_score),
            func.avg(MetricSnapshot.latency_ms),
            func.avg(MetricSnapshot.improvement_percent),
        ).where(MetricSnapshot.timestamp >= since)
        averages = (await session.execute(averages_statement)).one()

        return {
            "period": period,
            "since": since,
            "count": len(points),
            "averages": {
                "hallucination_score": float(averages[0] or 0.0),
                "relevance_score": float(averages[1] or 0.0),
                "latency_ms": float(averages[2] or 0.0),
                "improvement_percent": float(averages[3] or 0.0),
            },
            "points": [MetricPointResponse.model_validate(point, from_attributes=True) for point in points],
        }
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Could not load metric range: {exc}") from exc


@router.get("/summary")
async def get_metrics_summary(session: AsyncSession = Depends(get_session)) -> dict[str, float | int]:
    """Return an overall health score from the latest metric snapshot."""
    try:
        statement = select(MetricSnapshot).order_by(MetricSnapshot.timestamp.desc()).limit(1)
        result = await session.execute(statement)
        latest = result.scalar_one_or_none()

        if latest is None:
            return {
                "health_score": 0.0,
                "hallucination_score": 0.0,
                "relevance_score": 0.0,
                "latency_ms": 0.0,
                "improvement_percent": 0.0,
                "snapshot_count": 0,
            }

        count = await session.scalar(select(func.count(MetricSnapshot.id)))
        raw_health = 100 - (latest.hallucination_score * 100) + (latest.relevance_score * 100) / 2
        health_score = max(0.0, min(100.0, raw_health))

        return {
            "health_score": health_score,
            "hallucination_score": latest.hallucination_score,
            "relevance_score": latest.relevance_score,
            "latency_ms": latest.latency_ms,
            "improvement_percent": latest.improvement_percent,
            "snapshot_count": int(count or 0),
        }
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Could not calculate metric summary: {exc}") from exc


def _period_delta(period: str) -> timedelta:
    """Map dashboard period names to UTC time windows."""
    periods = {
        "hour": timedelta(hours=1),
        "day": timedelta(days=1),
        "week": timedelta(weeks=1),
        "month": timedelta(days=30),
        "year": timedelta(days=365),
    }
    return periods[period]
