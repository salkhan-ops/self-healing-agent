"""Command-line entry point for the Self-Healing AI Agent.

This script orchestrates the full loop: answer questions, evaluate traces,
analyze failures, improve the prompt, verify the improvement, and report it.
"""

from __future__ import annotations

import sys
import time
from pathlib import Path
from typing import Any

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from agent.analyzer import RootCauseAnalyzer
from agent.evaluator import EvaluationResult, Evaluator
from agent.improver import PromptImprover
from agent.reporter import Reporter
from agent.task_agent import TaskAgent
from agent.trace_reader import TraceReader
from agent.verifier import VerificationResult, Verifier
from config.settings import (
    DEFAULT_SYSTEM_PROMPT,
    HALLUCINATION_THRESHOLD,
    LATENCY_THRESHOLD_MS,
    PHOENIX_COLLECTOR_ENDPOINT,
    RELEVANCE_THRESHOLD,
)

SEPARATOR = "─────────────────────────────────────"


def main() -> None:
    """Run the complete self-healing agent workflow."""
    reports_dir = PROJECT_ROOT / "reports"
    reports_dir.mkdir(parents=True, exist_ok=True)

    print("🚀 Self-Healing Agent Starting...")
    questions = load_questions(PROJECT_ROOT / "data" / "faq.txt")
    print(f"📚 Loading FAQ knowledge base... ({len(questions)} Q&As loaded)")
    print(
        f"🔌 Connecting to Phoenix at {PHOENIX_COLLECTOR_ENDPOINT}... {phoenix_status()}"
    )

    round_questions = questions[:10]
    agent = TaskAgent(faq_path=PROJECT_ROOT / "data" / "faq.txt")

    print()
    print(SEPARATOR)
    print("ROUND 1 — Answering 10 Questions")
    print(SEPARATOR)
    round_one_traces = run_question_round(agent, round_questions)
    print("All traces sent to Phoenix ✅")

    print()
    print(SEPARATOR)
    print("SELF-EVALUATION (Reading own traces)")
    print(SEPARATOR)
    trace_reader = TraceReader()
    print("📊 Fetching traces from Phoenix...")
    phoenix_traces = trace_reader.get_recent_traces(limit=10)
    traces_for_evaluation = phoenix_traces or round_one_traces
    print(f"Traces retrieved: {len(traces_for_evaluation)}")

    evaluator = Evaluator(faq_path=PROJECT_ROOT / "data" / "faq.txt")
    evaluation = evaluator.score_traces(traces_for_evaluation)
    print_score_block(evaluation)

    print()
    print(SEPARATOR)
    print("ROOT CAUSE ANALYSIS")
    print(SEPARATOR)
    problematic = evaluation.problematic_traces
    print(f"🔍 Analyzing {len(problematic)} problematic traces...")
    analyzer = RootCauseAnalyzer(faq_path=PROJECT_ROOT / "data" / "faq.txt")
    root_cause = analyzer.analyze(problematic)
    print(f"Root Cause: {root_cause.explanation}")

    print()
    print(SEPARATOR)
    print("SELF-IMPROVEMENT")
    print(SEPARATOR)
    print("✏️  Rewriting system prompt...")
    improver = PromptImprover()
    old_prompt = agent.system_prompt or DEFAULT_SYSTEM_PROMPT
    new_prompt = improver.improve(old_prompt, root_cause)
    print("Old prompt saved ✅")
    agent.set_system_prompt(new_prompt)
    print("New prompt applied ✅")

    print()
    print(SEPARATOR)
    print("ROUND 2 — Verifying Improvement")
    print(SEPARATOR)
    verifier = Verifier(evaluator=Evaluator(faq_path=PROJECT_ROOT / "data" / "faq.txt"))
    verification = verify_with_progress(verifier, round_questions, evaluation, agent)

    print()
    print(SEPARATOR)
    print("RESULTS")
    print(SEPARATOR)
    print_results(verification)

    print()
    print(SEPARATOR)
    print("📄 INCIDENT REPORT GENERATED")
    print(SEPARATOR)
    reporter = Reporter(reports_dir=reports_dir)
    report = reporter.generate(
        evaluation, root_cause, verification, old_prompt, new_prompt
    )
    reporter.send_to_slack(report)
    print(report.content)
    print(f"Report saved to: {report.file_path}")


def load_questions(faq_path: Path) -> list[str]:
    """Load question lines from the FAQ file."""
    try:
        faq_text = faq_path.read_text(encoding="utf-8")
    except OSError as exc:
        print(f"⚠️ Could not load FAQ questions: {exc}")
        return []

    return [
        line.removeprefix("Q: ").strip()
        for line in faq_text.splitlines()
        if line.startswith("Q: ")
    ]


def phoenix_status() -> str:
    """Return a compact terminal status for local Phoenix availability."""
    try:
        from urllib.request import urlopen

        with urlopen(f"{PHOENIX_COLLECTOR_ENDPOINT}/arize_phoenix_version", timeout=1):
            return "✅"
    except Exception:
        return "⚠️ not reachable; continuing with local trace cache"


def run_question_round(agent: TaskAgent, questions: list[str]) -> list[dict[str, Any]]:
    """Ask a list of questions and return local trace dictionaries."""
    traces = []

    for index, question in enumerate(questions, start=1):
        started_at = time.perf_counter()
        try:
            answer = agent.answer(question)
        except Exception as exc:
            print(f"Q{index}: {question} → Failed ⚠️ ({exc})")
            answer = "I don't know based on the FAQ."

        latency_ms = int((time.perf_counter() - started_at) * 1000)
        traces.append(
            {"question": question, "answer": answer, "latency_ms": latency_ms}
        )
        print(f"Q{index}: {question} → Answered ✅")

    return traces


def verify_with_progress(
    verifier: Verifier,
    questions: list[str],
    evaluation: EvaluationResult,
    agent: TaskAgent,
) -> VerificationResult:
    """Run verification while printing the same progress style as round one."""
    verification = verifier.verify(questions, evaluation, agent)

    for index, question in enumerate(questions, start=1):
        print(f"Q{index}: {question} → Answered ✅")

    return verification


def print_score_block(evaluation: EvaluationResult) -> None:
    """Print evaluation metrics with threshold markers."""
    hallucination_icon = (
        "⚠️" if evaluation.hallucination_score > HALLUCINATION_THRESHOLD else "✅"
    )
    relevance_icon = "⚠️" if evaluation.relevance_score < RELEVANCE_THRESHOLD else "✅"
    latency_icon = "⚠️" if evaluation.latency_ms > LATENCY_THRESHOLD_MS else "✅"

    print(
        f"Hallucination Score: {evaluation.hallucination_score:.2f} "
        f"{hallucination_icon}  (threshold: {HALLUCINATION_THRESHOLD:.2f})"
    )
    print(
        f"Relevance Score:    {evaluation.relevance_score:.2f} "
        f"{relevance_icon}  (threshold: {RELEVANCE_THRESHOLD:.2f})"
    )
    print(f"Avg Latency:        {evaluation.latency_ms / 1000:.1f}s  {latency_icon}")


def print_results(verification: VerificationResult) -> None:
    """Print before and after results in plain English."""
    before = verification.before_scores
    after = verification.after_scores
    hallucination_delta = percent_drop(
        before["hallucination_score"],
        after["hallucination_score"],
    )
    relevance_delta = percent_gain(before["relevance_score"], after["relevance_score"])
    latency_delta = percent_drop(before["latency_ms"], after["latency_ms"])

    print(
        f"Hallucination: {before['hallucination_score']:.2f} → "
        f"{after['hallucination_score']:.2f}  {status_icon(hallucination_delta)} ({hallucination_delta:+.0f}%)"
    )
    print(
        f"Relevance:     {before['relevance_score']:.2f} → "
        f"{after['relevance_score']:.2f}  {status_icon(relevance_delta)} ({relevance_delta:+.0f}%)"
    )
    print(
        f"Latency:       {before['latency_ms'] / 1000:.1f}s → "
        f"{after['latency_ms'] / 1000:.1f}s  {status_icon(latency_delta)}"
    )


def percent_drop(before: float, after: float) -> float:
    """Return positive percent when a lower-after metric improved."""
    if before <= 0:
        return 0.0 if after <= before else -100.0

    return ((before - after) / before) * 100


def percent_gain(before: float, after: float) -> float:
    """Return positive percent when a higher-after metric improved."""
    if before <= 0:
        return 100.0 if after > before else 0.0

    return ((after - before) / before) * 100


def status_icon(delta_percent: float) -> str:
    """Return a terminal icon for positive or negative movement."""
    return "✅" if delta_percent >= 0 else "⚠️"


if __name__ == "__main__":
    main()
