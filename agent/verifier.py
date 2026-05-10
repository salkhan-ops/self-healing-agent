"""Verification step for the self-healing loop.

The Verifier reruns the same questions after a prompt change, scores the new
answers, and reports whether the agent improved.
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field
from typing import Any, Iterable

from agent.evaluator import EvaluationResult, Evaluator


@dataclass
class VerificationResult:
    """Structured before-and-after comparison for a prompt improvement."""

    improved: bool
    before_scores: dict[str, float]
    after_scores: dict[str, float]
    delta_scores: dict[str, float]
    improvement_percent: float
    traces: list[dict[str, Any]] = field(default_factory=list)
    evaluation: EvaluationResult | None = None


class Verifier:
    """Run verification questions and compare scores before and after."""

    def __init__(self, evaluator: Evaluator | None = None) -> None:
        self.evaluator = evaluator or Evaluator()

    def verify(
        self,
        questions: Iterable[str],
        old_scores: EvaluationResult | dict[str, Any],
        agent: Any,
    ) -> VerificationResult:
        """Run the same questions with the updated agent and compare quality scores."""
        verification_traces = []

        for question in questions:
            started_at = time.perf_counter()
            try:
                answer = agent.answer(question)
            except Exception as exc:
                print(f"⚠️ Verification answer failed for {question!r}: {exc}")
                answer = "I don't know based on the FAQ."

            latency_ms = int((time.perf_counter() - started_at) * 1000)
            verification_traces.append(
                {
                    "question": question,
                    "answer": answer,
                    "latency_ms": latency_ms,
                }
            )

        after_evaluation = self.evaluator.score_traces(verification_traces)
        before = self._scores_to_dict(old_scores)
        after = self._scores_to_dict(after_evaluation)
        deltas = self._delta_scores(before, after)
        improvement_percent = self._overall_improvement_percent(before, after)

        return VerificationResult(
            improved=improvement_percent > 0,
            before_scores=before,
            after_scores=after,
            delta_scores=deltas,
            improvement_percent=improvement_percent,
            traces=verification_traces,
            evaluation=after_evaluation,
        )

    def _scores_to_dict(self, scores: EvaluationResult | dict[str, Any]) -> dict[str, float]:
        """Normalize score dataclasses and dictionaries to simple float dictionaries."""
        if isinstance(scores, EvaluationResult):
            return {
                "hallucination_score": float(scores.hallucination_score),
                "relevance_score": float(scores.relevance_score),
                "latency_ms": float(scores.latency_ms),
            }

        return {
            "hallucination_score": self._number(scores.get("hallucination_score"), 0.0),
            "relevance_score": self._number(scores.get("relevance_score"), 0.0),
            "latency_ms": self._number(scores.get("latency_ms"), 0.0),
        }

    def _delta_scores(self, before: dict[str, float], after: dict[str, float]) -> dict[str, float]:
        """Calculate raw before-to-after score deltas."""
        return {
            "hallucination_score": after["hallucination_score"] - before["hallucination_score"],
            "relevance_score": after["relevance_score"] - before["relevance_score"],
            "latency_ms": after["latency_ms"] - before["latency_ms"],
        }

    def _overall_improvement_percent(
        self,
        before: dict[str, float],
        after: dict[str, float],
    ) -> float:
        """Calculate average quality improvement across the three key metrics."""
        hallucination_improvement = self._percent_drop(
            before["hallucination_score"],
            after["hallucination_score"],
        )
        relevance_improvement = self._percent_gain(
            before["relevance_score"],
            after["relevance_score"],
        )
        latency_improvement = self._percent_drop(before["latency_ms"], after["latency_ms"])

        return (hallucination_improvement + relevance_improvement + latency_improvement) / 3

    def _percent_drop(self, before: float, after: float) -> float:
        """Return positive percent when a lower-after metric improved."""
        if before <= 0:
            return 0.0 if after <= before else -100.0

        return ((before - after) / before) * 100

    def _percent_gain(self, before: float, after: float) -> float:
        """Return positive percent when a higher-after metric improved."""
        if before <= 0:
            return 100.0 if after > before else 0.0

        return ((after - before) / before) * 100

    def _number(self, value: Any, default: float) -> float:
        """Convert a value to float with a safe default."""
        if value in (None, ""):
            return default

        try:
            return float(value)
        except (TypeError, ValueError):
            return default
