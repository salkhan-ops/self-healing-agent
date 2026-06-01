"""Evaluate agent traces for hallucination, relevance, and latency.

The Evaluator scores each question and answer pair with Gemini when possible,
then falls back to simple local scoring so the self-healing loop can keep
running during local development.
"""

from __future__ import annotations

import json
import re
import warnings
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

try:
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", FutureWarning)
        import google.generativeai as genai
except ImportError as exc:
    raise ImportError(
        "google-generativeai is required. Fix with: pip install google-generativeai"
    ) from exc

from config.settings import (
    GEMINI_MODEL_NAME,
    GOOGLE_API_KEY,
    HALLUCINATION_THRESHOLD,
    LATENCY_THRESHOLD_MS,
    RELEVANCE_THRESHOLD,
    USE_GEMINI_META,
)
from config.llm import llm_generate_content
from agent.usage import usage_tracker
from backend.services.demo_incidents import contains_unsupported_demo_claim


@dataclass
class EvaluationResult:
    """Structured evaluation output for a batch of traces."""

    hallucination_score: float
    relevance_score: float
    latency_ms: float
    trace_scores: list[dict[str, Any]] = field(default_factory=list)
    problematic_traces: list[dict[str, Any]] = field(default_factory=list)


class Evaluator:
    """Score support-agent traces for quality problems."""

    def __init__(self, faq_path: str | Path = "data/faq.txt") -> None:
        self.faq_path = Path(faq_path)
        self.faq_text = self._load_faq_text()
        self.model = self._build_model()

    def score_traces(self, traces: list[dict[str, Any]]) -> EvaluationResult:
        """Score every trace and return average batch metrics."""
        try:
            trace_scores = self._score_batch_with_gemini(traces)
        except Exception as exc:
            print(f"⚠️ Gemini evaluation failed; using local scoring. Error: {exc}")
            trace_scores = [{**trace, **self._score_locally(trace)} for trace in traces]

        problematic = self.find_problematic_traces(
            trace_scores,
            {
                "hallucination": HALLUCINATION_THRESHOLD,
                "relevance": RELEVANCE_THRESHOLD,
                "latency_ms": LATENCY_THRESHOLD_MS,
            },
        )

        return EvaluationResult(
            hallucination_score=self._average("hallucination_score", trace_scores),
            relevance_score=self._average("relevance_score", trace_scores),
            latency_ms=self._average("latency_ms", trace_scores),
            trace_scores=trace_scores,
            problematic_traces=problematic,
        )

    def find_problematic_traces(
        self,
        traces: list[dict[str, Any]],
        thresholds: dict[str, float],
    ) -> list[dict[str, Any]]:
        """Return traces that exceed hallucination/latency thresholds or miss relevance."""
        problematic = []
        hallucination_limit = thresholds.get("hallucination", HALLUCINATION_THRESHOLD)
        relevance_limit = thresholds.get("relevance", RELEVANCE_THRESHOLD)
        latency_limit = thresholds.get("latency_ms", LATENCY_THRESHOLD_MS)

        for trace in traces:
            hallucination_score = self._number(trace.get("hallucination_score"), 0.0)
            relevance_score = self._number(trace.get("relevance_score"), 1.0)
            latency_ms = self._number(trace.get("latency_ms"), 0.0)

            is_problematic = (
                hallucination_score > hallucination_limit
                or relevance_score < relevance_limit
                or latency_ms > latency_limit
            )

            if is_problematic:
                problematic.append(trace)

        return problematic

    def _build_model(self):
        """Create the Gemini model used for scoring when an API key is available."""
        if not GOOGLE_API_KEY:
            print("⚠️ GOOGLE_API_KEY is missing; Evaluator will use local scoring.")
            return None

        if not USE_GEMINI_META:
            print("⚠️ Gemini meta-analysis disabled; Evaluator will use local scoring.")
            return None

        try:
            genai.configure(api_key=GOOGLE_API_KEY)
            return genai.GenerativeModel(model_name=GEMINI_MODEL_NAME)
        except Exception as exc:
            print(f"⚠️ Could not initialize Gemini evaluator: {exc}")
            return None

    def _score_batch_with_gemini(self, traces: list[dict[str, Any]]) -> list[dict[str, Any]]:
        """Score a whole batch in one Gemini call, or locally when disabled."""
        if self.model is None:
            return [{**trace, **self._score_locally(trace)} for trace in traces]

        compact_traces = [
            {
                "question": trace.get("question") or trace.get("input.value") or "",
                "answer": trace.get("answer") or trace.get("output.value") or "",
            }
            for trace in traces
        ]
        prompt = f"""
You are evaluating customer support answers against an FAQ.

FAQ:
{self.faq_text}

Traces:
{json.dumps(compact_traces, indent=2)}

Return only a JSON array with one object per trace, in the same order:
[{{"hallucination_score": 0.0, "relevance_score": 1.0}}]

Hallucination score means unsupported or false content, from 0.0 to 1.0.
Relevance score means how directly the answer addresses the question, from 0.0 to 1.0.
""".strip()
        response = llm_generate_content(self.model, prompt, label="evaluator.score_batch")
        usage_tracker.record(response)
        parsed = self._parse_json(getattr(response, "text", ""))
        if not isinstance(parsed, list) or len(parsed) != len(traces):
            raise ValueError("Gemini returned an unexpected batch evaluation shape.")

        scored_traces = []
        for trace, raw_scores in zip(traces, parsed):
            raw_scores = raw_scores if isinstance(raw_scores, dict) else {}
            scored_traces.append(
                {
                    **trace,
                    "hallucination_score": self._clamp(raw_scores.get("hallucination_score", 0.0)),
                    "relevance_score": self._clamp(raw_scores.get("relevance_score", 0.0)),
                    "latency_ms": self._number(trace.get("latency_ms"), 0.0),
                }
            )
        return scored_traces

    def _score_locally(self, trace: dict[str, Any]) -> dict[str, float]:
        """Produce simple deterministic scores without making a network call."""
        question = str(trace.get("question") or trace.get("input.value") or "")
        answer = str(trace.get("answer") or trace.get("output.value") or "")
        faq_answers = self._faq_answers()
        answer_words = self._words(answer)
        question_words = self._words(question)

        if not answer.strip():
            relevance_score = 0.0
            hallucination_score = 1.0
        elif contains_unsupported_demo_claim(answer):
            relevance_score = 0.2
            hallucination_score = 0.92
        elif "i don't know based on the faq" in answer.lower():
            relevance_score = 0.7
            hallucination_score = 0.0
        else:
            faq_words = set().union(*(self._words(faq_answer) for faq_answer in faq_answers))
            unsupported_words = answer_words.difference(faq_words).difference(question_words)
            overlap = len(answer_words.intersection(faq_words))
            hallucination_score = self._clamp(len(unsupported_words) / max(len(answer_words), 1))
            relevance_score = self._clamp(overlap / max(len(question_words), 1))

        return {
            "hallucination_score": hallucination_score,
            "relevance_score": relevance_score,
            "latency_ms": self._number(trace.get("latency_ms"), 0.0),
        }

    def _load_faq_text(self) -> str:
        """Load the FAQ text used as ground truth for evaluation."""
        try:
            return self.faq_path.read_text(encoding="utf-8")
        except OSError as exc:
            print(f"⚠️ Could not load FAQ for evaluation: {exc}")
            return ""

    def _faq_answers(self) -> list[str]:
        """Extract answer lines from the FAQ file."""
        return [
            line.removeprefix("A: ").strip()
            for line in self.faq_text.splitlines()
            if line.startswith("A: ")
        ]

    def _parse_json(self, text: str) -> Any:
        """Parse Gemini JSON even if it is wrapped in a Markdown code block."""
        cleaned = text.strip()
        cleaned = re.sub(r"^```(?:json)?", "", cleaned).strip()
        cleaned = re.sub(r"```$", "", cleaned).strip()

        try:
            return json.loads(cleaned)
        except json.JSONDecodeError:
            match = re.search(r"(\[.*\]|\{.*\})", cleaned, flags=re.DOTALL)
            if not match:
                return {}
            try:
                return json.loads(match.group(0))
            except json.JSONDecodeError:
                return {}

    def _words(self, text: str) -> set[str]:
        """Return lowercase word tokens for simple overlap scoring."""
        return set(re.findall(r"[a-z0-9']+", text.lower()))

    def _average(self, field_name: str, traces: list[dict[str, Any]]) -> float:
        """Average a numeric field, returning 0.0 when no values exist."""
        values = [self._number(trace.get(field_name), None) for trace in traces]
        numbers = [value for value in values if value is not None]

        if not numbers:
            return 0.0

        return sum(numbers) / len(numbers)

    def _number(self, value: Any, default: float | None) -> float | None:
        """Convert values to floats with a caller-selected fallback."""
        if value in (None, ""):
            return default

        try:
            return float(value)
        except (TypeError, ValueError):
            return default

    def _clamp(self, value: Any) -> float:
        """Clamp a numeric score into the required 0.0 to 1.0 range."""
        number = self._number(value, 0.0) or 0.0
        return max(0.0, min(1.0, number))
