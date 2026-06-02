"""Thread-safe self-healing agent runner for the dashboard backend.

AgentRunner wraps the existing agent modules, broadcasts progress to connected
WebSocket clients, and stores run metrics and reports after each run.
"""

from __future__ import annotations

import asyncio
import json
import uuid
from datetime import datetime
from pathlib import Path
from typing import Any

from fastapi import WebSocket

from agent.analyzer import RootCauseAnalyzer
from agent.evaluator import Evaluator
from agent.improver import PromptImprover
from agent.reporter import Reporter
from agent.task_agent import TaskAgent
from agent.trace_reader import TraceReader
from agent.verifier import Verifier
from config.settings import (
    AGENT_RUN_TIMEOUT_SECONDS,
    DEFAULT_SYSTEM_PROMPT,
    MAX_AGENT_ITERATIONS,
    PUBLIC_DEMO_MODE,
)
from backend.services.demo_incidents import demo_questions, match_incident
from backend.services.metrics_store import MetricsStore
from backend.services.trace_evidence_store import trace_evidence_store


PROJECT_ROOT = Path(__file__).resolve().parents[2]


class AgentStopRequested(Exception):
    """Raised when the dashboard asks the running agent to stop."""


class WebSocketManager:
    """Track WebSocket clients and broadcast text messages."""

    def __init__(self) -> None:
        self.active_connections: set[WebSocket] = set()

    async def connect(self, websocket: WebSocket) -> None:
        """Accept and register a WebSocket connection."""
        await websocket.accept()
        self.active_connections.add(websocket)

    def disconnect(self, websocket: WebSocket) -> None:
        """Remove a WebSocket connection."""
        self.active_connections.discard(websocket)

    async def broadcast(self, message: str) -> None:
        """Send a message to all connected WebSocket clients."""
        stale_connections = []
        for websocket in self.active_connections:
            try:
                await websocket.send_text(message)
            except Exception:
                stale_connections.append(websocket)

        for websocket in stale_connections:
            self.disconnect(websocket)


class AgentRunner:
    """Run the self-healing agent with one-at-a-time concurrency control."""

    def __init__(
        self,
        metrics_store: MetricsStore | None = None,
        websocket_manager: WebSocketManager | None = None,
    ) -> None:
        self.metrics_store = metrics_store or MetricsStore()
        self.websocket_manager = websocket_manager or WebSocketManager()
        self.lock = asyncio.Lock()
        self.status = "idle"
        self.last_run: datetime | None = None
        self.next_run: datetime | None = None
        self.last_error: str | None = None
        self.current_run_id: str | None = None
        self.loop: asyncio.AbstractEventLoop | None = None
        self.stop_requested = False

    async def run_agent(self, run_id: str | None = None) -> dict[str, Any]:
        """Run the full agent loop and save metrics for the dashboard."""
        if self.lock.locked():
            return {"run_id": self.current_run_id, "status": "already_running"}

        async with self.lock:
            run_id = run_id or str(uuid.uuid4())
            self.loop = asyncio.get_running_loop()
            self.current_run_id = run_id
            self.status = "running"
            self.last_error = None
            self.stop_requested = False

            try:
                await self._broadcast(f"run:{run_id}:started")
                result = await asyncio.wait_for(
                    asyncio.to_thread(self._run_agent_sync, run_id),
                    timeout=AGENT_RUN_TIMEOUT_SECONDS,
                )
                if result.get("status") == "stopped":
                    self.status = "idle"
                    await self._broadcast(f"run:{run_id}:stopped")
                    return {"run_id": run_id, "status": "stopped"}
                await self.metrics_store.save_run_metrics(run_id, result["evaluation"], result["verification"])
                await self.metrics_store.save_report(run_id, result["report"])
                await self._broadcast(f"run:{run_id}:completed")
                self.status = "idle"
                self.last_run = datetime.utcnow()
                return {"run_id": run_id, "status": "completed"}
            except AgentStopRequested:
                self.status = "idle"
                self.last_error = None
                await self._broadcast(f"run:{run_id}:stopped")
                return {"run_id": run_id, "status": "stopped"}
            except TimeoutError:
                self.stop_requested = True
                self.status = "error"
                self.last_error = f"Agent run timed out after {AGENT_RUN_TIMEOUT_SECONDS}s"
                print(f"⏱️ Agent run timed out: run_id={run_id} timeout_s={AGENT_RUN_TIMEOUT_SECONDS}")
                await self._broadcast(f"run:{run_id}:error:{self.last_error}")
                return {"run_id": run_id, "status": "error", "error": self.last_error}
            except Exception as exc:
                self.status = "error"
                self.last_error = str(exc)
                await self._broadcast(f"run:{run_id}:error:{exc}")
                return {"run_id": run_id, "status": "error", "error": str(exc)}
            finally:
                self.current_run_id = None
                self.stop_requested = False

    async def request_stop(self) -> dict[str, Any]:
        """Request the active self-healing run to stop at the next checkpoint."""
        if self.status == "stopping":
            return {"run_id": self.current_run_id or "", "status": "stopping"}

        if self.status != "running" or not self.lock.locked():
            self.status = "idle"
            self.current_run_id = None
            self.stop_requested = False
            return {"run_id": "", "status": "idle"}

        self.stop_requested = True
        self.status = "stopping"
        await self._broadcast(f"run:{self.current_run_id}:stop_requested")
        return {"run_id": self.current_run_id or "", "status": "stopping"}

    def get_status(self) -> dict[str, Any]:
        """Return current runner status for the API."""
        return {
            "status": self.status,
            "running": self.status in {"running", "stopping"},
            "last_run": self.last_run,
            "next_run": self.next_run,
            "current_run_id": self.current_run_id,
            "last_error": self.last_error,
        }

    def _run_agent_sync(self, run_id: str) -> dict[str, Any]:
        """Execute the existing self-healing loop with reusable agent classes."""
        faq_path = PROJECT_ROOT / "data" / "faq.txt"
        if PUBLIC_DEMO_MODE:
            questions = demo_questions()[: max(1, MAX_AGENT_ITERATIONS)]
            from backend.services.chat_agent import WEAK_SYSTEM_PROMPT

            agent = TaskAgent(faq_path=faq_path, system_prompt=WEAK_SYSTEM_PROMPT)
        else:
            questions = self._load_questions(faq_path)[: max(1, MAX_AGENT_ITERATIONS)]
            agent = TaskAgent(faq_path=faq_path)

        self._check_stop()
        self._broadcast_from_thread(f"run:{run_id}:round_1_started")
        round_one_traces = self._answer_questions(agent, questions)
        first_trace = round_one_traces[0] if round_one_traces else {}
        trace_evidence_store.record_timeline_step(
            step="Step 1: Agent Response",
            status="completed",
            trace_id=str(first_trace.get("trace_id", "")),
            span_name="customer_support.answer",
            healing_run_id=run_id,
            details=f"Answered {len(round_one_traces)} support prompt(s).",
        )
        trace_evidence_store.record_timeline_step(
            step="Step 2: Trace Captured",
            status="completed",
            trace_id=str(first_trace.get("trace_id", "")),
            span_name="customer_support.answer",
            healing_run_id=run_id,
            details="OpenTelemetry spans exported to Phoenix when reachable.",
        )

        self._check_stop()
        trace_reader = TraceReader()
        phoenix_traces = trace_reader.get_recent_traces(limit=10)
        traces_for_evaluation = phoenix_traces or round_one_traces
        mcp_status = trace_evidence_store.mcp_status()
        trace_evidence_store.record_timeline_step(
            step="Step 3: Phoenix Trace Retrieved",
            status=mcp_status.get("status", "failed"),
            trace_id=str((phoenix_traces[0] if phoenix_traces else first_trace).get("trace_id", "")),
            span_name=str((phoenix_traces[0] if phoenix_traces else {}).get("name", "Phoenix MCP list-traces")),
            healing_run_id=run_id,
            details=(
                f"Phoenix MCP Trace Retrieval fetched {mcp_status.get('traces_fetched', 0)} "
                f"trace(s) in {mcp_status.get('retrieval_time_ms', 0)}ms."
            ),
        )

        self._check_stop()
        evaluator = Evaluator(faq_path=faq_path)
        evaluation = evaluator.score_traces(traces_for_evaluation)
        self._broadcast_from_thread(f"run:{run_id}:evaluated")

        self._check_stop()
        analyzer = RootCauseAnalyzer(faq_path=faq_path)
        root_cause = analyzer.analyze(evaluation.problematic_traces)
        self._broadcast_from_thread(f"run:{run_id}:analyzed:{root_cause.category}")
        trace_evidence_store.record_timeline_step(
            step="Step 4: Failure Diagnosed",
            status="completed",
            trace_id=str(first_trace.get("trace_id", "")),
            span_name="root_cause.analyze",
            healing_run_id=run_id,
            details=f"{root_cause.category}: {root_cause.explanation}",
        )

        self._check_stop()
        improver = PromptImprover()
        old_prompt = agent.system_prompt or DEFAULT_SYSTEM_PROMPT
        new_prompt = improver.improve(old_prompt, root_cause)
        agent.set_system_prompt(new_prompt)
        from backend.services.chat_agent import chat_agent

        chat_agent.update_prompt(new_prompt)
        self._broadcast_from_thread(f"prompt_updated:v{chat_agent.prompt_version}")
        try:
            from backend.services.post_agent import post_agent
            from backend.services.post_healer import post_healer

            post_healing = post_healer.heal_recent_posts()
            if post_healing is not None:
                post_agent.update_prompt(post_healing.new_prompt)
                self._broadcast_from_thread(
                    f"post_prompt_updated:v{post_agent.prompt_version}"
                )
        except Exception as exc:
            print(f"Could not update post agent: {exc}")
        try:
            from backend.services.investment_agent import investment_agent
            from backend.services.investment_healer import investment_healer

            investment_healing = investment_healer.heal_recent_answers()
            if investment_healing is not None:
                investment_agent.update_prompt(investment_healing.new_prompt)
                self._broadcast_from_thread(
                    f"investment_prompt_updated:v{investment_agent.prompt_version}"
                )
        except Exception as exc:
            print(f"Could not update investment agent: {exc}")
        self._broadcast_from_thread(f"run:{run_id}:prompt_updated")
        trace_evidence_store.record_timeline_step(
            step="Step 5: Prompt Rewritten",
            status="completed",
            trace_id=str(first_trace.get("trace_id", "")),
            span_name="prompt_improver.improve",
            healing_run_id=run_id,
            details=f"Prompt updated from v{chat_agent.prompt_version - 1} to v{chat_agent.prompt_version}.",
        )

        self._check_stop()
        verifier = Verifier(evaluator=Evaluator(faq_path=faq_path))
        verification = verifier.verify(questions, evaluation, agent)
        self._broadcast_from_thread(f"run:{run_id}:verified")
        trace_evidence_store.record_timeline_step(
            step="Step 6: Verification Run",
            status="completed" if verification.improved else "failed",
            trace_id=str((verification.traces[0] if verification.traces else first_trace).get("trace_id", "")),
            span_name="verifier.verify",
            healing_run_id=run_id,
            details=(
                f"Hallucination {evaluation.hallucination_score:.2f} -> "
                f"{verification.after_scores.get('hallucination_score', 0.0):.2f}."
            ),
        )

        self._check_stop()
        old_version = chat_agent.prompt_version - 1
        new_version = chat_agent.prompt_version
        pairs = self._build_comparison_pairs(
            questions,
            round_one_traces,
            verification.traces if verification.traces else [],
            old_version,
            new_version,
        )
        if pairs:
            payload = {
                "pairs": pairs,
                "root_cause": root_cause.category,
                "root_cause_explanation": root_cause.explanation,
                "before_hallucination": evaluation.hallucination_score,
                "after_hallucination": verification.after_scores.get(
                    "hallucination_score", 0.0
                ),
                "before_relevance": evaluation.relevance_score,
                "after_relevance": verification.after_scores.get("relevance_score", 0.0),
                "old_prompt": old_prompt,
                "new_prompt": new_prompt,
            }
            self._broadcast_from_thread(
                f"comparisons_ready:{json.dumps(payload)}"
            )

        self._check_stop()
        reporter = Reporter(reports_dir=PROJECT_ROOT / "reports")
        report = reporter.generate(
            evaluation,
            root_cause,
            verification,
            old_prompt,
            new_prompt,
            comparisons=pairs,
        )
        reporter.send_to_slack(report)
        trace_evidence_store.record_timeline_step(
            step="Step 7: Report Generated",
            status="completed",
            trace_id=str(first_trace.get("trace_id", "")),
            span_name="reporter.generate",
            healing_run_id=run_id,
            details=f"Report {report.path.name if getattr(report, 'path', None) else run_id} generated.",
        )
        return {"evaluation": evaluation, "verification": verification, "report": report}

    def _answer_questions(self, agent: TaskAgent, questions: list[str]) -> list[dict[str, Any]]:
        """Answer questions and return local trace dictionaries."""
        traces = []
        for question in questions:
            self._check_stop()
            started = datetime.utcnow()
            answer = agent.answer(question)
            latency_ms = (datetime.utcnow() - started).total_seconds() * 1000
            trace_id = uuid.uuid4().hex[:12]
            traces.append(
                {
                    "trace_id": trace_id,
                    "question": question,
                    "answer": answer,
                    "latency_ms": latency_ms,
                }
            )
            trace_evidence_store.record_interaction(
                trace_id=trace_id,
                span_name="customer_support.answer",
                agent_name="TaskAgent",
                use_case="support",
                prompt=question,
                response=answer,
                latency_ms=int(latency_ms),
                prompt_version=1,
                status="captured",
            )
        return traces

    def _build_comparison_pairs(
        self,
        questions: list[str],
        round_one_traces: list[dict],
        verification_traces: list[dict],
        old_version: int,
        new_version: int,
    ) -> list[dict]:
        """
        Pair before/after answers for questions where
        the answer actually changed after healing.
        Return at most 3 pairs, prioritising changed answers.
        """
        pairs = []
        before_map = {
            t["question"]: t["answer"]
            for t in round_one_traces
            if "question" in t and "answer" in t
        }
        after_map = {
            t["question"]: t["answer"]
            for t in verification_traces
            if "question" in t and "answer" in t
        }
        for question in questions:
            before = before_map.get(question, "")
            after = after_map.get(question, "")
            if before and after:
                incident = match_incident(question) or match_incident(before)
                pairs.append(
                    {
                        "question": question,
                        "before": before,
                        "after": after,
                        "before_version": old_version,
                        "after_version": new_version,
                        "changed": before.strip() != after.strip(),
                        "incident_title": incident.title if incident else "",
                        "risk": incident.risk if incident else "",
                        "blocked_terms": list(incident.unsupported_terms)
                        if incident
                        else [],
                    }
                )
        pairs.sort(key=lambda p: not p["changed"])
        return pairs[:3]

    def _check_stop(self) -> None:
        """Stop cleanly when the dashboard has requested cancellation."""
        if self.stop_requested:
            raise AgentStopRequested()

    def _load_questions(self, faq_path: Path) -> list[str]:
        """Load question lines from the local FAQ file."""
        try:
            return [
                line.removeprefix("Q: ").strip()
                for line in faq_path.read_text(encoding="utf-8").splitlines()
                if line.startswith("Q: ")
            ]
        except OSError:
            return []

    async def _broadcast(self, message: str) -> None:
        """Broadcast a message from async code."""
        await self.websocket_manager.broadcast(message)

    def _broadcast_from_thread(self, message: str) -> None:
        """Safely broadcast progress from the worker thread."""
        if self.loop is None:
            return

        asyncio.run_coroutine_threadsafe(self.websocket_manager.broadcast(message), self.loop)


websocket_manager = WebSocketManager()
agent_runner = AgentRunner(websocket_manager=websocket_manager)
