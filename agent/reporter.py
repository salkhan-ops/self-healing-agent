"""Incident reporting for the self-healing agent.

The Reporter writes a plain English self-healing report to disk and can send
the same report to Slack when a webhook URL is configured.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any

try:
    import requests
except ImportError as exc:
    raise ImportError("requests is required. Fix with: pip install requests") from exc

from config.settings import SLACK_WEBHOOK_URL


@dataclass
class Report:
    """Structured report object returned after generating an incident report."""

    timestamp: str
    content: str
    file_path: str
    sent_to_slack: bool = False


class Reporter:
    """Generate, save, and optionally send self-healing incident reports."""

    def __init__(self, reports_dir: str | Path = "reports") -> None:
        self.reports_dir = Path(reports_dir)

    def generate(
        self,
        evaluation: Any,
        root_cause: Any,
        verification: Any,
        old_prompt: str,
        new_prompt: str,
        comparisons: list[dict[str, Any]] | None = None,
    ) -> Report:
        """Create and save a plain English incident report."""
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        filename_timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.reports_dir.mkdir(parents=True, exist_ok=True)
        file_path = self.reports_dir / f"report_{filename_timestamp}.txt"

        content = self._build_report_content(
            timestamp,
            evaluation,
            root_cause,
            verification,
            old_prompt,
            new_prompt,
            comparisons or [],
        )

        try:
            file_path.write_text(content, encoding="utf-8")
        except OSError as exc:
            print(f"⚠️ Could not save report to {file_path}: {exc}")

        return Report(timestamp=timestamp, content=content, file_path=str(file_path))

    def send_to_slack(self, report: Report) -> bool:
        """Send a report to Slack when SLACK_WEBHOOK_URL is configured."""
        if not SLACK_WEBHOOK_URL:
            return False

        try:
            response = requests.post(
                SLACK_WEBHOOK_URL,
                json={"text": report.content},
                timeout=10,
            )
            response.raise_for_status()
            report.sent_to_slack = True
            return True
        except requests.RequestException as exc:
            print(f"⚠️ Could not send report to Slack: {exc}")
            return False

    def _build_report_content(
        self,
        timestamp: str,
        evaluation: Any,
        root_cause: Any,
        verification: Any,
        old_prompt: str,
        new_prompt: str,
        comparisons: list[dict[str, Any]],
    ) -> str:
        """Assemble the incident report in the required format."""
        before = self._evaluation_scores(evaluation)
        after = self._verification_after_scores(verification)
        delta_percent = self._delta_percent_scores(before, after)
        category = self._root_cause_category(root_cause)
        explanation = self._root_cause_explanation(root_cause)
        human_action_needed = self._human_action_needed(verification)
        reason = self._human_action_reason(human_action_needed, verification)
        fix_applied = self._describe_prompt_change(old_prompt, new_prompt)
        problem = self._describe_problem(before)

        comparison_section = self._comparison_section(comparisons)

        return f"""━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔧 SELF-HEALING REPORT — {timestamp}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
App: Customer Support Agent
Problem: {problem}
Root Cause: {category} — {explanation}
Fix Applied: {fix_applied}

BEFORE:
  Hallucination: {before["hallucination_score"]:.2f}
  Relevance: {before["relevance_score"]:.2f}
  Latency: {before["latency_ms"]:.0f}ms

AFTER:
  Hallucination: {after["hallucination_score"]:.2f} ({delta_percent["hallucination_score"]:+.0f}%)
  Relevance: {after["relevance_score"]:.2f} ({delta_percent["relevance_score"]:+.0f}%)
  Latency: {after["latency_ms"]:.0f}ms ({delta_percent["latency_ms"]:+.0f}%)

Improvement: {self._number(getattr(verification, "improvement_percent", 0.0), 0.0):+.0f}%
Human Action Needed: {human_action_needed}
Reason: {reason}
{comparison_section}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"""

    def _comparison_section(self, comparisons: list[dict[str, Any]]) -> str:
        """Render a compact before/after sample section for report review."""
        if not comparisons:
            return ""

        lines = ["", "SAMPLE COMPARISONS:"]
        for index, pair in enumerate(comparisons[:3], start=1):
            question = str(pair.get("question", "")).strip()
            before = str(pair.get("before", "")).strip()
            after = str(pair.get("after", "")).strip()
            lines.extend(
                [
                    f"{index}. Q: {question}",
                    f"   Before: {before}",
                    f"   After: {after}",
                ]
            )
        return "\n".join(lines)

    def _evaluation_scores(self, evaluation: Any) -> dict[str, float]:
        """Normalize EvaluationResult-like values into a score dictionary."""
        return {
            "hallucination_score": self._number(getattr(evaluation, "hallucination_score", 0.0), 0.0),
            "relevance_score": self._number(getattr(evaluation, "relevance_score", 0.0), 0.0),
            "latency_ms": self._number(getattr(evaluation, "latency_ms", 0.0), 0.0),
        }

    def _verification_after_scores(self, verification: Any) -> dict[str, float]:
        """Read after scores from a VerificationResult-like object."""
        scores = getattr(verification, "after_scores", {}) or {}
        return {
            "hallucination_score": self._number(scores.get("hallucination_score"), 0.0),
            "relevance_score": self._number(scores.get("relevance_score"), 0.0),
            "latency_ms": self._number(scores.get("latency_ms"), 0.0),
        }

    def _delta_percent_scores(
        self,
        before: dict[str, float],
        after: dict[str, float],
    ) -> dict[str, float]:
        """Calculate report-friendly percent deltas for each metric."""
        return {
            "hallucination_score": self._percent_drop(
                before["hallucination_score"],
                after["hallucination_score"],
            ),
            "relevance_score": self._percent_gain(
                before["relevance_score"],
                after["relevance_score"],
            ),
            "latency_ms": self._percent_drop(before["latency_ms"], after["latency_ms"]),
        }

    def _describe_problem(self, before: dict[str, float]) -> str:
        """Create a short problem statement from before scores."""
        if before["hallucination_score"] > 0.4:
            return f"Hallucination rate above threshold ({before['hallucination_score']:.2f})"

        if before["relevance_score"] < 0.6:
            return f"Relevance below threshold ({before['relevance_score']:.2f})"

        if before["latency_ms"] > 3000:
            return f"Latency above threshold ({before['latency_ms']:.0f}ms)"

        return "Self-evaluation found room for prompt improvement"

    def _describe_prompt_change(self, old_prompt: str, new_prompt: str) -> str:
        """Summarize the prompt change in plain English."""
        old_lower = old_prompt.lower()
        new_lower = new_prompt.lower()

        if "i don't know based on the faq" in new_lower and "i don't know based on the faq" not in old_lower:
            return "Added strict grounding instruction and required fallback answer for unsupported questions"

        if "do not guess" in new_lower or "verify" in new_lower:
            return "Strengthened instructions to avoid guessing and verify answers against the FAQ"

        return "Rewrote the system prompt to better address the detected root cause"

    def _human_action_needed(self, verification: Any) -> str:
        """Return YES when automated healing did not improve the agent."""
        improved = bool(getattr(verification, "improved", False))
        return "NO ✅" if improved else "YES"

    def _human_action_reason(self, human_action_needed: str, verification: Any) -> str:
        """Explain why human review is or is not needed."""
        if human_action_needed.startswith("NO"):
            return "Automated prompt change improved the measured scores."

        improvement = self._number(getattr(verification, "improvement_percent", 0.0), 0.0)
        return f"Automated prompt change did not improve scores enough ({improvement:+.0f}%)."

    def _root_cause_category(self, root_cause: Any) -> str:
        """Read root cause category from a dataclass, dictionary, or string."""
        if hasattr(root_cause, "category"):
            return str(root_cause.category)

        if isinstance(root_cause, dict):
            return str(root_cause.get("category", "UNKNOWN"))

        return str(root_cause or "UNKNOWN")

    def _root_cause_explanation(self, root_cause: Any) -> str:
        """Read root cause explanation from a dataclass, dictionary, or string."""
        if hasattr(root_cause, "explanation"):
            return str(root_cause.explanation)

        if isinstance(root_cause, dict):
            return str(root_cause.get("explanation", "No explanation provided."))

        return "No explanation provided."

    def _percent_drop(self, before: float, after: float) -> float:
        """Return positive percent when a lower value is better."""
        if before <= 0:
            return 0.0 if after <= before else -100.0

        return ((before - after) / before) * 100

    def _percent_gain(self, before: float, after: float) -> float:
        """Return positive percent when a higher value is better."""
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
