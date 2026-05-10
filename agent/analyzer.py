"""Root cause analysis for problematic support-agent traces.

The RootCauseAnalyzer reviews bad answers and identifies why they failed so
the prompt improver can apply a focused self-healing change.
"""

from __future__ import annotations

import json
import re
import warnings
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Literal

try:
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", FutureWarning)
        import google.generativeai as genai
except ImportError as exc:
    raise ImportError(
        "google-generativeai is required. Fix with: pip install google-generativeai"
    ) from exc

from config.settings import GEMINI_MODEL_NAME, GOOGLE_API_KEY


RootCauseCategory = Literal["GUESSING", "IRRELEVANT", "INCOMPLETE", "HALLUCINATION"]


@dataclass
class RootCause:
    """Structured explanation of why the agent's answers were problematic."""

    category: RootCauseCategory
    explanation: str


class RootCauseAnalyzer:
    """Identify the main failure mode across problematic traces."""

    VALID_CATEGORIES = {"GUESSING", "IRRELEVANT", "INCOMPLETE", "HALLUCINATION"}

    def __init__(self, faq_path: str | Path = "data/faq.txt") -> None:
        self.faq_path = Path(faq_path)
        self.faq_text = self._load_faq_text()
        self.model = self._build_model()

    def analyze(self, problematic_traces: list[dict[str, Any]]) -> RootCause:
        """Return the most likely root cause for a list of problematic traces."""
        if not problematic_traces:
            return RootCause(
                category="INCOMPLETE",
                explanation="No problematic traces were found, so no concrete failure pattern is available.",
            )

        try:
            return self._analyze_with_gemini(problematic_traces)
        except Exception as exc:
            print(f"⚠️ Gemini root-cause analysis failed; using local analysis. Error: {exc}")
            return self._analyze_locally(problematic_traces)

    def _build_model(self):
        """Create the Gemini model used for root cause analysis."""
        if not GOOGLE_API_KEY:
            print("⚠️ GOOGLE_API_KEY is missing; RootCauseAnalyzer will use local analysis.")
            return None

        try:
            genai.configure(api_key=GOOGLE_API_KEY)
            return genai.GenerativeModel(model_name=GEMINI_MODEL_NAME)
        except Exception as exc:
            print(f"⚠️ Could not initialize Gemini analyzer: {exc}")
            return None

    def _analyze_with_gemini(self, problematic_traces: list[dict[str, Any]]) -> RootCause:
        """Ask Gemini to classify the dominant failure mode."""
        if self.model is None:
            return self._analyze_locally(problematic_traces)

        prompt = f"""
You are diagnosing why a customer support AI gave bad answers.

FAQ:
{self.faq_text}

Problematic traces:
{json.dumps(problematic_traces, indent=2, default=str)}

Choose exactly one category:
- GUESSING: agent made up info not in FAQ
- IRRELEVANT: answer did not address the question
- INCOMPLETE: answer was too vague
- HALLUCINATION: answer contradicted the FAQ

Return only JSON:
{{"category": "GUESSING", "explanation": "Short plain English explanation."}}
""".strip()
        response = self.model.generate_content(prompt)
        parsed = self._parse_json(getattr(response, "text", ""))
        category = self._clean_category(parsed.get("category"))
        explanation = str(parsed.get("explanation") or "").strip()

        if not explanation:
            explanation = self._fallback_explanation(category)

        return RootCause(category=category, explanation=explanation)

    def _analyze_locally(self, problematic_traces: list[dict[str, Any]]) -> RootCause:
        """Classify traces with simple deterministic rules."""
        category_counts = {category: 0 for category in self.VALID_CATEGORIES}

        for trace in problematic_traces:
            answer = str(trace.get("answer") or trace.get("output.value") or "")
            hallucination_score = self._number(trace.get("hallucination_score"), 0.0)
            relevance_score = self._number(trace.get("relevance_score"), 1.0)

            if self._contradicts_faq(answer):
                category_counts["HALLUCINATION"] += 1
            elif hallucination_score > 0.4:
                category_counts["GUESSING"] += 1
            elif relevance_score < 0.6:
                category_counts["IRRELEVANT"] += 1
            elif len(answer.split()) < 8:
                category_counts["INCOMPLETE"] += 1
            else:
                category_counts["GUESSING"] += 1

        category = max(category_counts, key=category_counts.get)
        return RootCause(category=category, explanation=self._fallback_explanation(category))

    def _contradicts_faq(self, answer: str) -> bool:
        """Detect a few obvious contradictions against the local FAQ."""
        lowered = answer.lower()
        contradiction_pairs = [
            ("international", "ship only within the united states"),
            ("exchange", "do not process direct exchanges"),
            ("free return", "return shipping fee is deducted"),
        ]

        for answer_claim, faq_fact in contradiction_pairs:
            if answer_claim in lowered and faq_fact in self.faq_text.lower():
                return True

        return False

    def _fallback_explanation(self, category: str) -> str:
        """Return a plain English explanation for a category."""
        explanations = {
            "GUESSING": "Agent is adding details that are not clearly supported by the FAQ.",
            "IRRELEVANT": "Agent is not directly answering the customer's question.",
            "INCOMPLETE": "Agent is giving answers that are too vague or missing useful detail.",
            "HALLUCINATION": "Agent is contradicting the FAQ or presenting unsupported claims as facts.",
        }
        return explanations.get(category, explanations["GUESSING"])

    def _clean_category(self, raw_category: Any) -> RootCauseCategory:
        """Normalize Gemini output into one of the allowed categories."""
        category = str(raw_category or "GUESSING").strip().upper()

        if category not in self.VALID_CATEGORIES:
            return "GUESSING"

        return category  # type: ignore[return-value]

    def _parse_json(self, text: str) -> dict[str, Any]:
        """Parse JSON even when Gemini wraps it in Markdown fences."""
        cleaned = text.strip()
        cleaned = re.sub(r"^```(?:json)?", "", cleaned).strip()
        cleaned = re.sub(r"```$", "", cleaned).strip()

        try:
            return json.loads(cleaned)
        except json.JSONDecodeError:
            match = re.search(r"\{.*\}", cleaned, flags=re.DOTALL)
            if not match:
                return {}
            try:
                return json.loads(match.group(0))
            except json.JSONDecodeError:
                return {}

    def _load_faq_text(self) -> str:
        """Load the FAQ text used as the source of truth."""
        try:
            return self.faq_path.read_text(encoding="utf-8")
        except OSError as exc:
            print(f"⚠️ Could not load FAQ for analysis: {exc}")
            return ""

    def _number(self, value: Any, default: float) -> float:
        """Convert a value to float with a safe default."""
        if value in (None, ""):
            return default

        try:
            return float(value)
        except (TypeError, ValueError):
            return default
