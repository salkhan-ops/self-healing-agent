"""Small Gemini cost-control helpers shared by demo agents.

The helpers here intentionally avoid logging prompts, user content, or API
keys. They only report call labels and timing so public-demo spend is visible
without leaking content.
"""

from __future__ import annotations

import time
from typing import Any

from config.settings import LLM_TIMEOUT_SECONDS, MAX_LLM_RETRIES, MAX_OUTPUT_TOKENS


def llm_generate_content(model: Any, prompt: str, *, label: str) -> Any:
    """Call a Gemini model with bounded output, timeout, and limited retries."""
    attempts = max(1, MAX_LLM_RETRIES + 1)
    last_error: Exception | None = None

    for attempt in range(1, attempts + 1):
        started = time.perf_counter()
        print(f"💸 LLM call started: {label} attempt={attempt}/{attempts}")
        try:
            response = model.generate_content(
                prompt,
                generation_config={"max_output_tokens": MAX_OUTPUT_TOKENS},
                request_options={"timeout": LLM_TIMEOUT_SECONDS},
            )
            elapsed_ms = int((time.perf_counter() - started) * 1000)
            print(f"💸 LLM call finished: {label} latency_ms={elapsed_ms}")
            return response
        except Exception as exc:
            last_error = exc
            elapsed_ms = int((time.perf_counter() - started) * 1000)
            print(f"⚠️ LLM call failed: {label} attempt={attempt}/{attempts} latency_ms={elapsed_ms}")

    raise last_error or RuntimeError(f"LLM call failed: {label}")
