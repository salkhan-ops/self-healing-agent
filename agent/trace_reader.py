"""Phoenix trace reader for the Self-Healing AI Agent.

This module connects to Phoenix, retrieves recent traces,
and extracts score and latency fields for self-evaluation.
"""

from __future__ import annotations

import os
import json
from typing import Any
from urllib.request import urlopen

import anyio
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

from config.settings import PHOENIX_HOST, PHOENIX_PROJECT_NAME


class TraceReader:
    """Read recent agent traces from Phoenix through MCP."""

    def __init__(
        self,
        endpoint: str = PHOENIX_HOST,
        project_name: str = PHOENIX_PROJECT_NAME,
    ) -> None:
        self.endpoint = endpoint.rstrip("/")
        self.project_name = project_name
        self.client = None

    def get_recent_traces(self, limit: int = 10) -> list[dict[str, Any]]:
        """Read recent traces through Phoenix's official MCP server."""
        if not self._phoenix_is_available():
            return []

        try:
            response = self.query_phoenix_via_mcp(
                "list-traces",
                params={"project_name": self.project_name, "limit": limit},
            )
        except Exception as exc:
            print(f"⚠️ Could not read Phoenix traces via MCP: {exc}")
            return []

        traces = self._extract_mcp_traces(response)
        return [self._normalize_trace(trace) for trace in traces]

    def query_phoenix_via_mcp(
        self,
        query: str,
        params: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """
        Query Phoenix traces via the official MCP server.

        This keeps the self-healing loop on the required MCP integration path
        for the Arize track while still failing closed when local Phoenix or
        the Node package is unavailable.
        """
        return anyio.run(
            self._query_phoenix_via_mcp_async,
            query,
            params
            or {
                "project_name": self.project_name,
                "limit": 10,
            },
        )

    async def _query_phoenix_via_mcp_async(
        self,
        query: str,
        params: dict[str, Any],
    ) -> dict[str, Any]:
        """Open a real MCP stdio session and call one Phoenix tool."""
        server = StdioServerParameters(
            command="npx",
            args=[
                "-y",
                "@arizeai/phoenix-mcp@latest",
                "--baseUrl",
                self.endpoint,
            ],
            env=os.environ.copy(),
        )
        async with stdio_client(server) as (read_stream, write_stream):
            async with ClientSession(read_stream, write_stream) as session:
                await session.initialize()
                result = await session.call_tool(query, params)

        if result.isError:
            raise RuntimeError(self._mcp_content_to_text(result.content) or query)

        if result.structuredContent:
            return result.structuredContent

        return self._mcp_content_to_json(result.content)

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
            "hallucination_score": self._average(
                "hallucination_score", per_trace_scores
            ),
            "relevance_score": self._average("relevance_score", per_trace_scores),
            "latency_ms": self._average("latency_ms", per_trace_scores),
            "traces": per_trace_scores,
        }

    def _get_client(self):
        """Create a Phoenix client, supporting both current and older import paths."""
        if self.client is not None:
            return self.client

        os.environ.setdefault("PHOENIX_WORKING_DIR", "/tmp/phoenix")
        os.environ["PHOENIX_HOST"] = self.endpoint
        os.environ["PHOENIX_PROJECT_NAME"] = self.project_name

        try:
            try:
                from phoenix.client import Client
            except ImportError:
                from phoenix.session.client import Client

            self.client = Client(base_url=self.endpoint)
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

    def _phoenix_is_available(self) -> bool:
        """Check the Phoenix server before calling MCP."""
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
            "latency_ms": self._first_value(
                row, "latency_ms", "attributes.latency_ms", "duration_ms"
            ),
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

    def _extract_mcp_traces(self, response: dict[str, Any]) -> list[dict[str, Any]]:
        """Accept the common MCP response envelopes and return raw trace rows."""
        candidates = (
            response.get("traces"),
            response.get("data"),
            response.get("result"),
            response.get("content"),
        )

        for candidate in candidates:
            traces = self._coerce_trace_list(candidate)
            if traces:
                return traces

        return []

    def _coerce_trace_list(self, value: Any) -> list[dict[str, Any]]:
        """Normalize nested MCP content into a list of trace dictionaries."""
        if isinstance(value, list):
            if all(isinstance(item, dict) for item in value):
                return value

            for item in value:
                traces = self._coerce_trace_list(item)
                if traces:
                    return traces

        if isinstance(value, dict):
            for key in ("traces", "data", "items", "result"):
                traces = self._coerce_trace_list(value.get(key))
                if traces:
                    return traces

        if isinstance(value, str):
            try:
                return self._coerce_trace_list(json.loads(value))
            except json.JSONDecodeError:
                return []

        return []

    def _mcp_content_to_json(self, content: list[Any]) -> dict[str, Any]:
        """Parse JSON text content returned by MCP tools."""
        text = self._mcp_content_to_text(content)
        if not text:
            return {}

        try:
            parsed = json.loads(text)
        except json.JSONDecodeError:
            return {"content": text}

        return parsed if isinstance(parsed, dict) else {"content": parsed}

    def _mcp_content_to_text(self, content: list[Any]) -> str:
        """Join text-bearing MCP content blocks into one string."""
        return "\n".join(
            item.text for item in content if getattr(item, "type", None) == "text"
        ).strip()

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
