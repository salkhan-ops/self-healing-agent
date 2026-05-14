"""Async SQLite database models for the dashboard backend.

This module defines the dashboard database connection, async SQLAlchemy
session factory, and the three tables used by the Self-Healing AI Agent UI.
"""

from __future__ import annotations

from datetime import datetime
from pathlib import Path
from typing import AsyncGenerator

from sqlalchemy import Boolean, DateTime, Float, Integer, String, Text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


BACKEND_DIR = Path(__file__).resolve().parent
DATABASE_PATH = BACKEND_DIR.parent / "data" / "dashboard.db"
DATABASE_URL = f"sqlite+aiosqlite:///{DATABASE_PATH}"


class Base(DeclarativeBase):
    """Base class for all dashboard database tables."""


class MetricSnapshot(Base):
    """Point-in-time agent quality metrics for charts and status cards."""

    __tablename__ = "metric_snapshots"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    timestamp: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, index=True)
    hallucination_score: Mapped[float] = mapped_column(Float, default=0.0)
    relevance_score: Mapped[float] = mapped_column(Float, default=0.0)
    latency_ms: Mapped[float] = mapped_column(Float, default=0.0)
    improvement_percent: Mapped[float] = mapped_column(Float, default=0.0)
    run_id: Mapped[str] = mapped_column(String(120), index=True)


class Report(Base):
    """Saved self-healing report data for incident review screens."""

    __tablename__ = "reports"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    timestamp: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, index=True)
    run_id: Mapped[str] = mapped_column(String(120), index=True)
    problem: Mapped[str] = mapped_column(Text, default="")
    root_cause: Mapped[str] = mapped_column(Text, default="")
    fix_applied: Mapped[str] = mapped_column(Text, default="")
    before_hallucination: Mapped[float] = mapped_column(Float, default=0.0)
    before_relevance: Mapped[float] = mapped_column(Float, default=0.0)
    before_latency: Mapped[float] = mapped_column(Float, default=0.0)
    after_hallucination: Mapped[float] = mapped_column(Float, default=0.0)
    after_relevance: Mapped[float] = mapped_column(Float, default=0.0)
    after_latency: Mapped[float] = mapped_column(Float, default=0.0)
    improvement_percent: Mapped[float] = mapped_column(Float, default=0.0)
    human_needed: Mapped[bool] = mapped_column(Boolean, default=False)
    content_text: Mapped[str] = mapped_column(Text, default="")


class Schedule(Base):
    """Dashboard schedule configuration for automatic agent runs."""

    __tablename__ = "schedules"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    name: Mapped[str] = mapped_column(String(120), default="Default self-healing run")
    interval_minutes: Mapped[int] = mapped_column(Integer, default=60)
    enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    last_run: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    next_run: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    run_count: Mapped[int] = mapped_column(Integer, default=0)


engine = create_async_engine(DATABASE_URL, echo=False, future=True)
AsyncSessionLocal = async_sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)


async def init_db() -> None:
    """Create dashboard tables if they do not already exist."""
    DATABASE_PATH.parent.mkdir(parents=True, exist_ok=True)
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)


async def get_session() -> AsyncGenerator[AsyncSession, None]:
    """Yield an async database session for FastAPI dependencies."""
    async with AsyncSessionLocal() as session:
        yield session
