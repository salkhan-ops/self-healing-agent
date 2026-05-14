"""APScheduler service for dashboard-managed agent schedules.

SchedulerService loads schedules from SQLite, adds enabled jobs to
APScheduler, and lets routes enable, disable, or remove scheduled runs.
"""

from __future__ import annotations

from datetime import datetime, timedelta

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from sqlalchemy import select

from backend.database import AsyncSessionLocal, Schedule
from backend.services.agent_runner import agent_runner


class SchedulerService:
    """Manage APScheduler jobs for self-healing agent runs."""

    def __init__(self) -> None:
        self.scheduler = AsyncIOScheduler()

    async def start(self) -> None:
        """Start APScheduler and load enabled schedules from the database."""
        if not self.scheduler.running:
            self.scheduler.start()
        await self.load_schedules()

    async def shutdown(self) -> None:
        """Stop APScheduler without waiting for running jobs."""
        if self.scheduler.running:
            self.scheduler.shutdown(wait=False)

    async def load_schedules(self) -> None:
        """Load enabled schedules from the database on startup."""
        async with AsyncSessionLocal() as session:
            result = await session.execute(select(Schedule).where(Schedule.enabled.is_(True)))
            for schedule in result.scalars().all():
                self.add_schedule(schedule)

    def add_schedule(self, schedule: Schedule) -> None:
        """Add or replace one enabled schedule in APScheduler."""
        job_id = self._job_id(schedule.id)
        self.scheduler.remove_job(job_id) if self.scheduler.get_job(job_id) else None

        if schedule.enabled:
            self.scheduler.add_job(
                agent_runner.run_agent,
                trigger="interval",
                minutes=schedule.interval_minutes,
                id=job_id,
                next_run_time=schedule.next_run or datetime.utcnow() + timedelta(minutes=schedule.interval_minutes),
                replace_existing=True,
            )

    def remove_schedule(self, id: int) -> None:
        """Remove one schedule job from APScheduler."""
        job_id = self._job_id(id)
        if self.scheduler.get_job(job_id):
            self.scheduler.remove_job(job_id)

    async def toggle_schedule(self, id: int) -> Schedule:
        """Enable or disable a schedule in the database and scheduler."""
        async with AsyncSessionLocal() as session:
            schedule = await session.get(Schedule, id)
            if schedule is None:
                raise ValueError("Schedule not found.")

            schedule.enabled = not schedule.enabled
            schedule.next_run = (
                datetime.utcnow() + timedelta(minutes=schedule.interval_minutes)
                if schedule.enabled
                else None
            )
            await session.commit()
            await session.refresh(schedule)

            if schedule.enabled:
                self.add_schedule(schedule)
            else:
                self.remove_schedule(schedule.id)

            return schedule

    def _job_id(self, schedule_id: int) -> str:
        """Return a stable APScheduler job id for a schedule row."""
        return f"schedule-{schedule_id}"


scheduler_service = SchedulerService()
