"""Phoenix trace reader for the Self-Healing AI Agent.

This module connects to the local Phoenix server, retrieves recent traces,
and extracts score and latency fields for self-evaluation.
"""

from __future__ import annotations

import os
from typing import Any
from urllib.request import urlopen

from config.settings import PHOENIX_COLLECTOR_ENDPOINT, PHOENIX_PROJECT_NAME


class TraceReader:
    """Read recent agent traces from local Phoenix."""

    def __init__(
        self,
        endpoint: str = PHOENIX_COLLECTOR_ENDPOINT,
        project_name: str = PHOENIX_PROJECT_NAME,
    ) -> None:
        self.endpoint = endpoint.rstrip("/")
        self.project_name = project_name
        self.client = None

    def get_recent_traces(self, limit: int = 10) -> list[dict[str, Any]]:
        """Fetch recent traces from Phoenix and return them as plain dictionaries."""
        if not self._is_local_endpoint():
            print("⚠️ Phoenix endpoint must be localhost; refusing to read remote traces.")
            return []

        if not self._phoenix_is_available():
            print(f"⚠️ Phoenix is not reachable at {self.endpoint}. Start it with:")
            print("   python -m phoenix.server.main serve")
            return []

        client = self._get_client()
        if client is None:
            return []

        try:
            spans = client.query_spans(project_name=self.project_name)
            dataframe = self._first_dataframe(spans)
            if dataframe is None or dataframe.empty:
                return []

            dataframe = self._sort_dataframe(dataframe)
            recent = dataframe.tail(limit)
            return [self._normalize_trace(row) for row in recent.to_dict("records")]
        except Exception as exc:
            print(f"⚠️ Could not fetch traces from Phoenix: {exc}")
            return []

    def get_trace_scores(self, traces: list[dict[str, Any]]) -> dict[str, Any]:
        """Return per-trace score fields plus average hallucination, relevance, and latency."""
        per_trace_scores = []

        for trace in traces:
            hallucination_score = self._number_or_none(
                trace.get("hallucination_score")
                or trace.get("eval.hallucination_score")
                or trace.get("attributes.hallucination_score")
            )
            relevance_score = self._number_or_none(
                trace.get("relevance_score")
                or trace.get("eval.relevance_score")
                or trace.get("attributes.relevance_score")
            )
            latency_ms = self._number_or_none(
                trace.get("latency_ms")
                or trace.get("attributes.latency_ms")
                or trace.get("duration_ms")
            )

            per_trace_scores.append(
                {
                    "trace_id": trace.get("trace_id"),
                    "span_id": trace.get("span_id"),
                    "question": trace.get("question"),
                    "answer": trace.get("answer"),
                    "hallucination_score": hallucination_score,
                    "relevance_score": relevance_score,
                    "latency_ms": latency_ms,
                }
            )

        return {
            "hallucination_score": self._average("hallucination_score", per_trace_scores),
            "relevance_score": self._average("relevance_score", per_trace_scores),
            "latency_ms": self._average("latency_ms", per_trace_scores),
            "traces": per_trace_scores,
        }

    def _get_client(self):
        """Create a Phoenix client, supporting both current and older import paths."""
        if self.client is not None:
            return self.client

        os.environ.setdefault("PHOENIX_WORKING_DIR", "/tmp/phoenix")
        os.environ["PHOENIX_COLLECTOR_ENDPOINT"] = self.endpoint
        os.environ["PHOENIX_PROJECT_NAME"] = self.project_name

        try:
            try:
                from phoenix.client import Client
            except ImportError:
                from phoenix.session.client import Client

            self.client = Client(endpoint=self.endpoint, use_active_session_if_available=False)
            return self.client
        except ModuleNotFoundError as exc:
            missing_package = exc.name or "missing dependency"
            print(f"⚠️ Phoenix client dependency missing: {missing_package}.")
            print(f"   Fix with: pip install {missing_package}")
            return None
        except ImportError as exc:
            print(f"⚠️ Could not import Phoenix client: {exc}")
            print("   Fix with: pip install arize-phoenix")
            return None
        except Exception as exc:
            print(f"⚠️ Could not create Phoenix client: {exc}")
            return None

    def _is_local_endpoint(self) -> bool:
        """Confirm the configured endpoint is the required local Phoenix server."""
        return self.endpoint.startswith("http://localhost:6006") or self.endpoint.startswith(
            "http://127.0.0.1:6006"
        )

    def _phoenix_is_available(self) -> bool:
        """Check the Phoenix server before calling the Python client."""
        try:
            with urlopen(f"{self.endpoint}/arize_phoenix_version", timeout=1):
                return True
        except Exception:
            return False

    def _first_dataframe(self, spans: Any) -> Any:
        """Phoenix may return one DataFrame, a list of DataFrames, or None."""
        if spans is None:
            return None

        if isinstance(spans, list):
            return spans[0] if spans else None

        return spans

    def _sort_dataframe(self, dataframe: Any) -> Any:
        """Sort traces by timestamp when Phoenix includes a timestamp column."""
        for column in ("start_time", "start_time.iso", "timestamp"):
            if column in dataframe.columns:
                return dataframe.sort_values(column)

        return dataframe

    def _normalize_trace(self, row: dict[str, Any]) -> dict[str, Any]:
        """Convert Phoenix span rows into stable trace dictionaries."""
        return {
            **row,
            "trace_id": self._first_value(row, "context.trace_id", "trace_id"),
            "span_id": self._first_value(row, "context.span_id", "span_id"),
            "question": self._first_value(row, "input.value", "attributes.input.value"),
            "answer": self._first_value(row, "output.value", "attributes.output.value"),
            "latency_ms": self._first_value(row, "latency_ms", "attributes.latency_ms", "duration_ms"),
            "hallucination_score": self._first_value(
                row,
                "hallucination_score",
                "eval.hallucination_score",
                "attributes.hallucination_score",
            ),
            "relevance_score": self._first_value(
                row,
                "relevance_score",
                "eval.relevance_score",
                "attributes.relevance_score",
            ),
        }

    def _first_value(self, row: dict[str, Any], *keys: str) -> Any:
        """Return the first non-empty value from a row for several possible Phoenix columns."""
        for key in keys:
            value = row.get(key)
            if value not in (None, ""):
                return value

        return None

    def _number_or_none(self, value: Any) -> float | None:
        """Convert numeric values safely while preserving unknown scores as None."""
        if value in (None, ""):
            return None

        try:
            return float(value)
        except (TypeError, ValueError):
            return None

    def _average(self, field: str, traces: list[dict[str, Any]]) -> float | None:
        """Average one numeric field, ignoring traces where that field is missing."""
        values = [trace[field] for trace in traces if trace.get(field) is not None]
        if not values:
            return None

        return sum(values) / len(values)
