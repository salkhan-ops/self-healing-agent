"""Zero-cost demo data routes.

These endpoints seed dashboard evidence without calling Gemini, Phoenix, or any
external model. They are intended for recording/demo preparation only.
"""

from __future__ import annotations

from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from backend.database import MetricSnapshot, Report, get_session
from backend.services.post_history_store import add_post


router = APIRouter(prefix="/api/demo", tags=["demo"])


@router.post("/seed")
async def seed_demo_data(session: AsyncSession = Depends(get_session)) -> dict[str, object]:
    """Seed realistic dashboard metrics, reports, and post history without model calls."""
    try:
        now = datetime.utcnow()

        existing_demo_count = await session.scalar(
            select(func.count(MetricSnapshot.id)).where(MetricSnapshot.run_id.like("demo-%"))
        )
        seed_number = int(existing_demo_count or 0) // 5 + 1
        run_prefix = f"demo-{seed_number}"

        snapshots = [
            MetricSnapshot(
                run_id=f"{run_prefix}-metric-{index}",
                timestamp=now + timedelta(seconds=index),
                hallucination_score=hallucination,
                relevance_score=relevance,
                latency_ms=latency,
                improvement_percent=improvement,
            )
            for index, (hallucination, relevance, latency, improvement) in enumerate(
                [
                    (0.72, 0.42, 2410, 0),
                    (0.48, 0.64, 2100, 22),
                    (0.24, 0.82, 1740, 51),
                    (0.08, 0.94, 1390, 78),
                    (0.04, 0.97, 1180, 86),
                ],
                start=1,
            )
        ]
        session.add_all(snapshots)

        reports = [
            _report(
                run_id=f"{run_prefix}-support",
                timestamp=now + timedelta(seconds=10),
                problem="Customer Support answer invented unsupported policy details",
                root_cause="KNOWLEDGE_GAP — The agent answered beyond the support knowledge base.",
                fix_applied="Added strict grounding instruction and required fallback answer for unsupported questions",
                before=(0.74, 0.38, 1952),
                after=(0.06, 0.96, 1473),
                improvement=88,
                content=_content(
                    "Customer Support",
                    "Do you ship to Pakistan for free?",
                    "Yes — we offer free worldwide shipping, including Pakistan, for loyal customers.",
                    "We currently ship only within the United States. International shipping is not available at this time.",
                ),
            ),
            _report(
                run_id=f"{run_prefix}-posts",
                timestamp=now + timedelta(seconds=20),
                problem="Social post added unsupported hype and exaggerated claims",
                root_cause="UNSUPPORTED_SUPERLATIVES — The post used dramatic language not present in the brief.",
                fix_applied="Forbid unsupported hype words and require every claim to be traceable to the brief",
                before=(0.82, 0.71, 1620),
                after=(0.04, 0.98, 1160),
                improvement=91,
                content=_content(
                    "Social Media Posts",
                    "Q1 was strong. Launched analytics product. Hired 3 engineers. Signed partnership with Acme Corp.",
                    "Q1 was EPIC — we launched a revolutionary analytics product and unleashed a game-changing partnership.",
                    "Strong Q1 for us: we launched our analytics product, hired 3 engineers, and signed a partnership with Acme Corp.",
                ),
            ),
            _report(
                run_id=f"{run_prefix}-investment",
                timestamp=now + timedelta(seconds=30),
                problem="Investment analyst produced advice without enough source grounding",
                root_cause="RISKY_FINANCIAL_ADVICE — The analyst made a direct recommendation instead of summarizing evidence and risk.",
                fix_applied="Require SEC-grounded reasoning, risk flags, and no personalized buy/sell instructions",
                before=(0.66, 0.52, 2320),
                after=(0.10, 0.93, 1510),
                improvement=82,
                content=_content(
                    "Investment Analyst",
                    "Should I buy Tesla today?",
                    "Yes, buy Tesla today. Momentum is strong and upside looks huge.",
                    "I can’t give personalized buy/sell advice. Based on available filings, review revenue concentration, margin pressure, competition, and your own risk tolerance before deciding.",
                ),
            ),
        ]
        session.add_all(reports)
        await session.commit()

        add_post(
            {
                "id": f"{run_prefix}-p1",
                "timestamp": (now + timedelta(seconds=40)).isoformat(),
                "brief": "Q1 was strong. Launched analytics product. Hired 3 engineers. Signed partnership with Acme Corp.",
                "platform": "twitter",
                "post": "Q1 was EPIC! 🚀 We just debuted our revolutionary analytics product and unleashed a game-changing partnership.",
                "prompt_version": 1,
                "hallucination_score": 0.82,
                "relevance_score": 0.72,
                "latency_ms": 1620,
                "trace_id": "demo001",
            }
        )
        add_post(
            {
                "id": f"{run_prefix}-p2",
                "timestamp": (now + timedelta(seconds=50)).isoformat(),
                "brief": "Q1 was strong. Launched analytics product. Hired 3 engineers. Signed partnership with Acme Corp.",
                "platform": "linkedin",
                "post": "Strong Q1 for us: we launched our analytics product, hired 3 engineers, and signed a partnership with Acme Corp.",
                "prompt_version": 2,
                "hallucination_score": 0.04,
                "relevance_score": 0.98,
                "latency_ms": 1160,
                "trace_id": "demo002",
            }
        )

        return {
            "status": "seeded",
            "seed_number": seed_number,
            "metrics": len(snapshots),
            "reports": len(reports),
            "posts": 2,
        }
    except Exception as exc:
        await session.rollback()
        raise HTTPException(status_code=500, detail=f"Could not seed demo data: {exc}") from exc


def _report(
    *,
    run_id: str,
    timestamp: datetime,
    problem: str,
    root_cause: str,
    fix_applied: str,
    before: tuple[float, float, float],
    after: tuple[float, float, float],
    improvement: float,
    content: str,
) -> Report:
    return Report(
        run_id=run_id,
        timestamp=timestamp,
        problem=problem,
        root_cause=root_cause,
        fix_applied=fix_applied,
        before_hallucination=before[0],
        before_relevance=before[1],
        before_latency=before[2],
        after_hallucination=after[0],
        after_relevance=after[1],
        after_latency=after[2],
        improvement_percent=improvement,
        human_needed=False,
        content_text=content,
    )


def _content(app: str, prompt: str, before: str, after: str) -> str:
    return f"""━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔧 SELF-HEALING REPORT — DEMO
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
App: {app}
Problem: Before output contained unsupported or risky behavior.
Fix Applied: Prompt tightened and verified against the source.

SAMPLE COMPARISON:
Q: {prompt}
Before: {before}
After: {after}

Human Action Needed: NO ✅
Reason: Seeded zero-cost demo evidence for video recording.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"""
