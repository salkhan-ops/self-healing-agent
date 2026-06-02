"""In-memory Phoenix trace evidence for dashboard demos.

Phoenix remains the source of exported OpenTelemetry traces. This store keeps
the app-side trace metadata and healing evidence easy to show in the dashboard,
including cases where Phoenix or MCP is temporarily unavailable.
"""

from __future__ import annotations

from collections import deque
from datetime import datetime
from threading import Lock
from time import perf_counter
from typing import Any

from config.settings import PHOENIX_HOST, PHOENIX_PROJECT_NAME


class TraceEvidenceStore:
    """Collect recent trace and healing evidence for judge-facing UI."""

    def __init__(self, max_items: int = 80) -> None:
        self._items: deque[dict[str, Any]] = deque(maxlen=max_items)
        self._timeline: deque[dict[str, Any]] = deque(maxlen=max_items)
        self._lock = Lock()
        self._mcp_status: dict[str, Any] = {
            "label": "Phoenix MCP Trace Retrieval",
            "status": "not_run",
            "project_name": PHOENIX_PROJECT_NAME,
            "phoenix_host": PHOENIX_HOST,
            "traces_fetched": 0,
            "retrieval_time_ms": 0,
            "last_error": "",
            "timestamp": "",
        }

    def record_interaction(
        self,
        *,
        trace_id: str,
        span_name: str,
        agent_name: str,
        use_case: str,
        prompt: str,
        response: str,
        hallucination_score: float = 0.0,
        relevance_score: float = 0.0,
        latency_ms: int = 0,
        prompt_version: int = 1,
        status: str | None = None,
        metadata: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Record one AI output and its evaluation metadata."""
        item = {
            "timestamp": self._now(),
            "trace_id": trace_id,
            "span_name": span_name,
            "span_count": 1,
            "agent_name": agent_name,
            "use_case": use_case,
            "status": status or self._status_from_scores(hallucination_score),
            "prompt": prompt,
            "response": response,
            "hallucination_score": float(hallucination_score),
            "relevance_score": float(relevance_score),
            "latency_ms": int(latency_ms),
            "prompt_version": int(prompt_version),
            "healing_run_id": "",
            "before_after_status": "before" if prompt_version <= 1 else "after",
            "root_cause": "",
            "root_cause_diagnosis": "",
            "prompt_patch_applied": "",
            "verification_results": {},
            "final_healed_response": "",
            "metadata": metadata or {},
        }
        with self._lock:
            self._items.appendleft(item)
        return item

    def record_healing(
        self,
        *,
        healing_run_id: str,
        agent_name: str,
        use_case: str,
        root_cause: str,
        root_cause_diagnosis: str,
        prompt_patch_applied: str,
        before: dict[str, Any],
        after: dict[str, Any],
        verification_results: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Record before/after evidence for one healing action."""
        item = {
            "timestamp": self._now(),
            "trace_id": str(after.get("trace_id") or before.get("trace_id") or healing_run_id),
            "span_name": f"{use_case}.healing",
            "span_count": 2,
            "agent_name": agent_name,
            "use_case": use_case,
            "status": "healed",
            "prompt": str(before.get("prompt") or before.get("brief") or before.get("question") or ""),
            "response": str(before.get("response") or before.get("answer") or before.get("post") or ""),
            "hallucination_score": float(before.get("hallucination_score", 0.0) or 0.0),
            "relevance_score": float(before.get("relevance_score", 0.0) or 0.0),
            "latency_ms": int(before.get("latency_ms", 0) or 0),
            "prompt_version": int(before.get("prompt_version", 1) or 1),
            "healing_run_id": healing_run_id,
            "before_after_status": "before_after",
            "root_cause": root_cause,
            "root_cause_diagnosis": root_cause_diagnosis,
            "prompt_patch_applied": prompt_patch_applied,
            "verification_results": verification_results or {},
            "final_healed_response": str(
                after.get("response") or after.get("answer") or after.get("post") or ""
            ),
            "comparison": {
                "before": before,
                "after": after,
            },
            "metadata": {},
        }
        with self._lock:
            self._items.appendleft(item)
        return item

    def record_timeline_step(
        self,
        *,
        step: str,
        status: str,
        trace_id: str = "",
        span_name: str = "",
        healing_run_id: str = "",
        details: str = "",
        timestamp: str | None = None,
    ) -> dict[str, Any]:
        """Record one hackathon demo timeline step."""
        item = {
            "timestamp": timestamp or self._now(),
            "step": step,
            "status": status,
            "trace_id": trace_id,
            "span_name": span_name,
            "healing_run_id": healing_run_id,
            "details": details,
        }
        with self._lock:
            self._timeline.appendleft(item)
        return item

    def set_mcp_status(
        self,
        *,
        status: str,
        traces_fetched: int,
        retrieval_time_ms: int,
        last_error: str = "",
    ) -> None:
        """Update visible Phoenix MCP retrieval status."""
        with self._lock:
            self._mcp_status = {
                "label": "Phoenix MCP Trace Retrieval",
                "status": status,
                "project_name": PHOENIX_PROJECT_NAME,
                "phoenix_host": PHOENIX_HOST,
                "traces_fetched": traces_fetched,
                "retrieval_time_ms": retrieval_time_ms,
                "last_error": last_error,
                "timestamp": self._now(),
            }

    def list_traces(self, limit: int = 30) -> list[dict[str, Any]]:
        """Return newest trace evidence entries."""
        with self._lock:
            return list(self._items)[:limit]

    def timeline(self, limit: int = 20) -> list[dict[str, Any]]:
        """Return newest timeline steps in chronological display order."""
        with self._lock:
            items = list(self._timeline)[:limit]
        return list(reversed(items))

    def mcp_status(self) -> dict[str, Any]:
        """Return current Phoenix MCP status."""
        with self._lock:
            return dict(self._mcp_status)

    def timed_mcp(self):
        """Return a perf-counter start marker for retrieval timing."""
        return perf_counter()

    def elapsed_ms(self, started: float) -> int:
        """Convert a perf-counter start marker to milliseconds."""
        return int((perf_counter() - started) * 1000)

    def _status_from_scores(self, hallucination_score: float) -> str:
        if hallucination_score > 0.4:
            return "failed"
        return "healthy"

    def _now(self) -> str:
        return datetime.utcnow().isoformat()


trace_evidence_store = TraceEvidenceStore()
