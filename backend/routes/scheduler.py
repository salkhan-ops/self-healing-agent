"""Schedule API routes for the dashboard backend.

These endpoints let the dashboard create, update, delete, and toggle scheduled
self-healing agent runs.
"""

from __future__ import annotations

from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from backend.database import Schedule, get_session
from backend.models import ScheduleResponse
from backend.services.scheduler_svc import scheduler_service


router = APIRouter(prefix="/api/schedules", tags=["schedules"])


class ScheduleRequest(BaseModel):
    """Request body for creating or updating a schedule."""

    name: str = Field(default="Default self-healing run", min_length=1)
    interval_minutes: int = Field(default=60, ge=1)
    enabled: bool = True


@router.get("", response_model=list[ScheduleResponse])
async def list_schedules(session: AsyncSession = Depends(get_session)) -> list[Schedule]:
    """Return all schedules, newest first."""
    try:
        result = await session.execute(select(Schedule).order_by(Schedule.id.desc()))
        return list(result.scalars().all())
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Could not load schedules: {exc}") from exc


@router.post("", response_model=ScheduleResponse)
async def create_schedule(
    payload: ScheduleRequest,
    session: AsyncSession = Depends(get_session),
) -> Schedule:
    """Create a new dashboard schedule."""
    schedule = Schedule(
        name=payload.name,
        interval_minutes=payload.interval_minutes,
        enabled=payload.enabled,
        next_run=_next_run(payload.interval_minutes, payload.enabled),
    )

    try:
        session.add(schedule)
        await session.commit()
        await session.refresh(schedule)
        scheduler_service.add_schedule(schedule)
        return schedule
    except Exception as exc:
        await session.rollback()
        raise HTTPException(status_code=500, detail=f"Could not create schedule: {exc}") from exc


@router.put("/{schedule_id}", response_model=ScheduleResponse)
async def update_schedule(
    schedule_id: int,
    payload: ScheduleRequest,
    session: AsyncSession = Depends(get_session),
) -> Schedule:
    """Update an existing schedule."""
    schedule = await session.get(Schedule, schedule_id)
    if schedule is None:
        raise HTTPException(status_code=404, detail="Schedule not found.")

    schedule.name = payload.name
    schedule.interval_minutes = payload.interval_minutes
    schedule.enabled = payload.enabled
    schedule.next_run = _next_run(payload.interval_minutes, payload.enabled)

    try:
        await session.commit()
        await session.refresh(schedule)
        scheduler_service.add_schedule(schedule)
        return schedule
    except Exception as exc:
        await session.rollback()
        raise HTTPException(status_code=500, detail=f"Could not update schedule: {exc}") from exc


@router.delete("/{schedule_id}")
async def delete_schedule(schedule_id: int, session: AsyncSession = Depends(get_session)) -> dict[str, bool]:
    """Delete one schedule."""
    schedule = await session.get(Schedule, schedule_id)
    if schedule is None:
        raise HTTPException(status_code=404, detail="Schedule not found.")

    try:
        await session.delete(schedule)
        await session.commit()
        scheduler_service.remove_schedule(schedule_id)
        return {"deleted": True}
    except Exception as exc:
        await session.rollback()
        raise HTTPException(status_code=500, detail=f"Could not delete schedule: {exc}") from exc


@router.post("/{schedule_id}/toggle", response_model=ScheduleResponse)
async def toggle_schedule(schedule_id: int, session: AsyncSession = Depends(get_session)) -> Schedule:
    """Enable or disable a schedule."""
    try:
        return await scheduler_service.toggle_schedule(schedule_id)
    except ValueError as exc:
        raise HTTPException(status_code=404, detail="Schedule not found.")
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Could not toggle schedule: {exc}") from exc


def _next_run(interval_minutes: int, enabled: bool) -> datetime | None:
    """Return the next run time for enabled schedules."""
    if not enabled:
        return None

    return datetime.utcnow() + timedelta(minutes=interval_minutes)
