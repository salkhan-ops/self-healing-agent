"""Phoenix trace visibility endpoints for hackathon judging."""

from __future__ import annotations

import asyncio
from typing import Any

from fastapi import APIRouter, Query

from agent.trace_reader import TraceReader
from backend.services.trace_evidence_store import trace_evidence_store
from config.settings import PHOENIX_HOST, PHOENIX_PROJECT_NAME

router = APIRouter(prefix="/api/phoenix", tags=["phoenix"])


@router.get("/traces")
async def get_phoenix_traces(
    limit: int = Query(default=30, ge=1, le=80),
    refresh: bool = Query(default=True),
) -> dict[str, Any]:
    """Return recent app trace evidence plus Phoenix MCP retrieval status."""
    phoenix_rows: list[dict[str, Any]] = []
    if refresh:
        phoenix_rows = await asyncio.to_thread(TraceReader().get_recent_traces, limit)

    return {
        "project_name": PHOENIX_PROJECT_NAME,
        "phoenix_host": PHOENIX_HOST,
        "mcp": trace_evidence_store.mcp_status(),
        "traces": _merge_phoenix_rows(
            trace_evidence_store.list_traces(limit=limit),
            phoenix_rows,
            limit,
        ),
        "timeline": _demo_timeline(trace_evidence_store.timeline(limit=20)),
    }


@router.get("/demo")
async def get_phoenix_demo() -> dict[str, Any]:
    """Return the judge-facing Phoenix MCP demo state."""
    return {
        "title": "Phoenix MCP Trace Retrieval",
        "project_name": PHOENIX_PROJECT_NAME,
        "phoenix_host": PHOENIX_HOST,
        "mcp": trace_evidence_store.mcp_status(),
        "timeline": _demo_timeline(trace_evidence_store.timeline(limit=20)),
    }


def _merge_phoenix_rows(
    evidence: list[dict[str, Any]],
    phoenix_rows: list[dict[str, Any]],
    limit: int,
) -> list[dict[str, Any]]:
    """Append normalized Phoenix MCP rows when they are not already represented."""
    seen = {str(item.get("trace_id", "")) for item in evidence if item.get("trace_id")}
    merged = list(evidence)
    for row in phoenix_rows:
        trace_id = str(row.get("trace_id", ""))
        if trace_id and trace_id in seen:
            continue
        merged.append(
            {
                "timestamp": str(
                    row.get("timestamp")
                    or row.get("start_time")
                    or row.get("start_time.iso")
                    or ""
                ),
                "trace_id": trace_id,
                "span_name": str(row.get("name") or row.get("span_name") or ""),
                "span_count": int(_float(row.get("span_count")) or 1),
                "agent_name": str(row.get("agent.name") or row.get("agent_name") or "Phoenix"),
                "use_case": str(row.get("use_case") or row.get("attributes.use_case") or "unknown"),
                "status": "captured",
                "prompt": str(row.get("question") or row.get("input.value") or ""),
                "response": str(row.get("answer") or row.get("output.value") or ""),
                "hallucination_score": _float(row.get("hallucination_score")),
                "relevance_score": _float(row.get("relevance_score")),
                "latency_ms": int(_float(row.get("latency_ms"))),
                "prompt_version": int(_float(row.get("prompt_version")) or 0),
                "healing_run_id": str(row.get("healing.run_id") or ""),
                "before_after_status": str(row.get("before_after_status") or "captured"),
                "root_cause": str(row.get("root_cause") or ""),
                "root_cause_diagnosis": str(row.get("root_cause_diagnosis") or ""),
                "prompt_patch_applied": str(row.get("prompt_patch_applied") or ""),
                "verification_results": {},
                "final_healed_response": str(row.get("response.after") or ""),
                "metadata": {"source": "Phoenix MCP"},
            }
        )
        if trace_id:
            seen.add(trace_id)
    return merged[:limit]


def _demo_timeline(items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Return timeline items or a stable not-yet-run scaffold."""
    if items:
        return items
    return [
        {
            "timestamp": "",
            "step": step,
            "status": "waiting",
            "trace_id": "",
            "span_name": "",
            "healing_run_id": "",
            "details": "Run Agent Control or a targeted healing flow to populate this step.",
        }
        for step in [
            "Step 1: Agent Response",
            "Step 2: Trace Captured",
            "Step 3: Phoenix Trace Retrieved",
            "Step 4: Failure Diagnosed",
            "Step 5: Prompt Rewritten",
            "Step 6: Verification Run",
            "Step 7: Report Generated",
        ]
    ]


def _float(value: Any) -> float:
    try:
        return float(value or 0.0)
    except (TypeError, ValueError):
        return 0.0
