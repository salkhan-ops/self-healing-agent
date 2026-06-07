"""Database persistence helpers for dashboard metrics and reports.

MetricsStore converts self-healing run objects into dashboard database rows
and calculates health metrics for the FastAPI backend.
"""

from __future__ import annotations

import re
from datetime import datetime, timedelta
from typing import Any, Literal

from sqlalchemy import func, select

from backend.database import AsyncSessionLocal, MetricSnapshot, Report


PeriodName = Literal["hour", "day", "week", "month", "year"]


class MetricsStore:
    """Save and read dashboard metrics for self-healing agent runs."""

    async def save_run_metrics(self, run_id: str, evaluation: Any, verification: Any) -> MetricSnapshot:
        """Save one metric snapshot using EvaluationResult and VerificationResult values."""
        snapshot = MetricSnapshot(
            run_id=run_id,
            timestamp=datetime.utcnow(),
            hallucination_score=float(getattr(evaluation, "hallucination_score", 0.0)),
            relevance_score=float(getattr(evaluation, "relevance_score", 0.0)),
            latency_ms=float(getattr(evaluation, "latency_ms", 0.0)),
            improvement_percent=float(getattr(verification, "improvement_percent", 0.0)),
        )

        async with AsyncSessionLocal() as session:
            try:
                session.add(snapshot)
                await session.commit()
                await session.refresh(snapshot)
                return snapshot
            except Exception:
                await session.rollback()
                raise

    async def save_report(self, run_id: str, report_obj: Any) -> Report:
        """Save a Reporter.Report object to the dashboard reports table."""
        content = str(getattr(report_obj, "content", ""))
        parsed = self._parse_report_content(content)
        report = Report(
            run_id=run_id,
            timestamp=self._parse_timestamp(getattr(report_obj, "timestamp", "")),
            problem=parsed["problem"],
            root_cause=parsed["root_cause"],
            fix_applied=parsed["fix_applied"],
            before_hallucination=parsed["before_hallucination"],
            before_relevance=parsed["before_relevance"],
            before_latency=parsed["before_latency"],
            after_hallucination=parsed["after_hallucination"],
            after_relevance=parsed["after_relevance"],
            after_latency=parsed["after_latency"],
            improvement_percent=parsed["improvement_percent"],
            human_needed=parsed["human_needed"],
            content_text=content,
        )

        async with AsyncSessionLocal() as session:
            try:
                session.add(report)
                await session.commit()
                await session.refresh(report)
                return report
            except Exception:
                await session.rollback()
                raise

    async def save_healing_report(
        self,
        *,
        run_id: str,
        use_case: str,
        problem: str,
        root_cause: str,
        fix_applied: str,
        before_scores: dict[str, Any],
        after_scores: dict[str, Any],
        before_text: str = "",
        after_text: str = "",
        human_needed: bool = False,
    ) -> Report:
        """Save a report row for targeted use-case healing flows."""
        before_hallucination = float(before_scores.get("hallucination_score", 0.0))
        after_hallucination = float(after_scores.get("hallucination_score", 0.0))
        before_relevance = float(before_scores.get("relevance_score", 0.0))
        after_relevance = float(after_scores.get("relevance_score", 0.0))
        before_latency = float(before_scores.get("latency_ms", 0.0))
        after_latency = float(after_scores.get("latency_ms", 0.0))
        improvement_percent = (
            0.0
            if before_hallucination <= 0
            else ((before_hallucination - after_hallucination) / before_hallucination) * 100
        )
        timestamp = datetime.utcnow()
        content = self._format_healing_report_content(
            timestamp=timestamp,
            use_case=use_case,
            problem=problem,
            root_cause=root_cause,
            fix_applied=fix_applied,
            before_scores={
                "hallucination_score": before_hallucination,
                "relevance_score": before_relevance,
                "latency_ms": before_latency,
            },
            after_scores={
                "hallucination_score": after_hallucination,
                "relevance_score": after_relevance,
                "latency_ms": after_latency,
            },
            improvement_percent=improvement_percent,
            human_needed=human_needed,
            before_text=before_text,
            after_text=after_text,
        )
        report = Report(
            run_id=run_id,
            timestamp=timestamp,
            problem=problem,
            root_cause=root_cause,
            fix_applied=fix_applied,
            before_hallucination=before_hallucination,
            before_relevance=before_relevance,
            before_latency=before_latency,
            after_hallucination=after_hallucination,
            after_relevance=after_relevance,
            after_latency=after_latency,
            improvement_percent=improvement_percent,
            human_needed=human_needed,
            content_text=content,
        )

        async with AsyncSessionLocal() as session:
            try:
                session.add(report)
                await session.commit()
                await session.refresh(report)
                return report
            except Exception:
                await session.rollback()
                raise

    async def get_metrics_for_period(self, period: PeriodName) -> list[MetricSnapshot]:
        """Return metric snapshots inside a named time period."""
        since = datetime.utcnow() - self._period_delta(period)
        async with AsyncSessionLocal() as session:
            result = await session.execute(
                select(MetricSnapshot)
                .where(MetricSnapshot.timestamp >= since)
                .order_by(MetricSnapshot.timestamp.asc())
            )
            return list(result.scalars().all())

    async def calculate_health_score(self) -> float:
        """Calculate the latest overall health score from 0 to 100."""
        async with AsyncSessionLocal() as session:
            result = await session.execute(select(MetricSnapshot).order_by(MetricSnapshot.timestamp.desc()).limit(1))
            latest = result.scalar_one_or_none()

            if latest is None:
                return 0.0

            raw_score = 100 - (latest.hallucination_score * 100) + (latest.relevance_score * 100) / 2
            return max(0.0, min(100.0, raw_score))

    async def average_for_period(self, period: PeriodName) -> dict[str, float]:
        """Return average metric values for a named time period."""
        since = datetime.utcnow() - self._period_delta(period)
        async with AsyncSessionLocal() as session:
            result = await session.execute(
                select(
                    func.avg(MetricSnapshot.hallucination_score),
                    func.avg(MetricSnapshot.relevance_score),
                    func.avg(MetricSnapshot.latency_ms),
                    func.avg(MetricSnapshot.improvement_percent),
                ).where(MetricSnapshot.timestamp >= since)
            )
            row = result.one()
            return {
                "hallucination_score": float(row[0] or 0.0),
                "relevance_score": float(row[1] or 0.0),
                "latency_ms": float(row[2] or 0.0),
                "improvement_percent": float(row[3] or 0.0),
            }

    def _period_delta(self, period: PeriodName) -> timedelta:
        """Convert a period name to a timedelta."""
        periods = {
            "hour": timedelta(hours=1),
            "day": timedelta(days=1),
            "week": timedelta(weeks=1),
            "month": timedelta(days=30),
            "year": timedelta(days=365),
        }
        return periods[period]

    def _parse_report_content(self, content: str) -> dict[str, Any]:
        """Extract dashboard report fields from plain English report text."""
        return {
            "problem": self._line_after("Problem:", content),
            "root_cause": self._line_after("Root Cause:", content),
            "fix_applied": self._line_after("Fix Applied:", content),
            "before_hallucination": self._number_after(r"BEFORE:\s+Hallucination:\s+([0-9.]+)", content),
            "before_relevance": self._number_after(r"BEFORE:.*?Relevance:\s+([0-9.]+)", content),
            "before_latency": self._number_after(r"BEFORE:.*?Latency:\s+([0-9.]+)ms", content),
            "after_hallucination": self._number_after(r"AFTER:\s+Hallucination:\s+([0-9.]+)", content),
            "after_relevance": self._number_after(r"AFTER:.*?Relevance:\s+([0-9.]+)", content),
            "after_latency": self._number_after(r"AFTER:.*?Latency:\s+([0-9.]+)ms", content),
            "improvement_percent": self._number_after(r"Improvement:\s+([+-]?[0-9.]+)%", content),
            "human_needed": "Human Action Needed: YES" in content,
        }

    def _line_after(self, label: str, content: str) -> str:
        """Return the text after a report label on the same line."""
        for line in content.splitlines():
            if line.startswith(label):
                return line.removeprefix(label).strip()
        return ""

    def _number_after(self, pattern: str, content: str) -> float:
        """Return a matched number from report text."""
        match = re.search(pattern, content, flags=re.DOTALL)
        if not match:
            return 0.0
        try:
            return float(match.group(1))
        except ValueError:
            return 0.0

    def _parse_timestamp(self, timestamp: str) -> datetime:
        """Convert report timestamp text to datetime."""
        try:
            return datetime.strptime(timestamp, "%Y-%m-%d %H:%M:%S")
        except (TypeError, ValueError):
            return datetime.utcnow()

    def _format_healing_report_content(
        self,
        *,
        timestamp: datetime,
        use_case: str,
        problem: str,
        root_cause: str,
        fix_applied: str,
        before_scores: dict[str, float],
        after_scores: dict[str, float],
        improvement_percent: float,
        human_needed: bool,
        before_text: str,
        after_text: str,
    ) -> str:
        """Build readable report text for targeted healing incidents."""
        return f"""
Self-Healing Incident Report
Generated: {timestamp.strftime("%Y-%m-%d %H:%M:%S")}
Use Case: {use_case}

Problem: {problem}
Root Cause: {root_cause}
Fix Applied: {fix_applied}

BEFORE:
  Hallucination: {before_scores["hallucination_score"]:.2f}
  Relevance: {before_scores["relevance_score"]:.2f}
  Latency: {before_scores["latency_ms"]:.0f}ms

AFTER:
  Hallucination: {after_scores["hallucination_score"]:.2f}
  Relevance: {after_scores["relevance_score"]:.2f}
  Latency: {after_scores["latency_ms"]:.0f}ms

Improvement: {improvement_percent:+.0f}%
Human Action Needed: {"YES" if human_needed else "NO"}

Before Output:
{before_text}

After Output:
{after_text}
""".strip()
