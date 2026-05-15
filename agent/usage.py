"""Tiny in-process Gemini usage and cost tracker."""

from __future__ import annotations

from dataclasses import dataclass


MODEL_PRICING_PER_MILLION = {
    "gemini-2.5-flash": {"input": 0.30, "output": 2.50},
    "gemini-2.5-flash-lite": {"input": 0.10, "output": 0.40},
}


@dataclass
class UsageTotals:
    requests: int = 0
    input_tokens: int = 0
    output_tokens: int = 0
    thinking_tokens: int = 0


class UsageTracker:
    """Collect token usage from Gemini responses during one process run."""

    def __init__(self) -> None:
        self.totals = UsageTotals()

    def record(self, response: object) -> None:
        """Read Gemini usage metadata when it is present."""
        metadata = getattr(response, "usage_metadata", None)
        if metadata is None:
            return

        self.totals.requests += 1
        self.totals.input_tokens += int(getattr(metadata, "prompt_token_count", 0) or 0)
        self.totals.output_tokens += int(getattr(metadata, "candidates_token_count", 0) or 0)
        self.totals.thinking_tokens += int(getattr(metadata, "thoughts_token_count", 0) or 0)

    def estimated_cost_usd(self, model_name: str) -> float:
        """Estimate text-token cost for the configured model."""
        pricing = MODEL_PRICING_PER_MILLION.get(model_name)
        if pricing is None:
            return 0.0

        billed_output_tokens = self.totals.output_tokens + self.totals.thinking_tokens
        return (
            self.totals.input_tokens * pricing["input"]
            + billed_output_tokens * pricing["output"]
        ) / 1_000_000


usage_tracker = UsageTracker()
