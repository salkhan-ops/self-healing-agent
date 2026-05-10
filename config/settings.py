"""Central configuration for the Self-Healing AI Agent.

This file loads environment variables, defines Phoenix localhost settings,
sets quality thresholds, and stores the system prompts used by the agent.
"""

from __future__ import annotations

import os
from urllib.parse import urlparse

from dotenv import load_dotenv


load_dotenv()  # Load values from .env into the process environment.


def _get_float_env(name: str, default: float) -> float:
    """Read a float environment variable while falling back safely."""
    raw_value = os.getenv(name)
    if raw_value is None:
        return default

    try:
        return float(raw_value)
    except ValueError:
        print(f"⚠️ Invalid {name}={raw_value!r}; using default {default}.")
        return default


def _get_int_env(name: str, default: int) -> int:
    """Read an integer environment variable while falling back safely."""
    raw_value = os.getenv(name)
    if raw_value is None:
        return default

    try:
        return int(raw_value)
    except ValueError:
        print(f"⚠️ Invalid {name}={raw_value!r}; using default {default}.")
        return default


def _local_phoenix_endpoint() -> str:
    """Return a Phoenix endpoint, forcing the project to use localhost only."""
    endpoint = os.getenv("PHOENIX_COLLECTOR_ENDPOINT", "http://localhost:6006")
    parsed = urlparse(endpoint)

    if parsed.hostname not in {"localhost", "127.0.0.1"}:
        print("⚠️ PHOENIX_COLLECTOR_ENDPOINT must be local; using http://localhost:6006.")
        return "http://localhost:6006"

    return endpoint.rstrip("/")  # Keep generated API URLs predictable.


GOOGLE_API_KEY = os.getenv("GOOGLE_API_KEY", "")
PHOENIX_API_KEY = os.getenv("PHOENIX_API_KEY", "")
PHOENIX_COLLECTOR_ENDPOINT = _local_phoenix_endpoint()
PHOENIX_PROJECT_NAME = os.getenv("PHOENIX_PROJECT_NAME", "self-healing-agent")

SLACK_WEBHOOK_URL = os.getenv("SLACK_WEBHOOK_URL", "")

GEMINI_MODEL_NAME = "gemini-2.0-flash-exp"

HALLUCINATION_THRESHOLD = _get_float_env("HALLUCINATION_THRESHOLD", 0.4)
RELEVANCE_THRESHOLD = _get_float_env("RELEVANCE_THRESHOLD", 0.6)
LATENCY_THRESHOLD_MS = _get_int_env("LATENCY_THRESHOLD_MS", 3000)

DEFAULT_SYSTEM_PROMPT = """
You are a customer support agent for an online store.

Answer customer questions using only the FAQ knowledge base provided to you.
If the FAQ does not contain the answer, say: "I don't know based on the FAQ."
Do not invent policies, dates, fees, product details, or process steps.
Keep answers concise, friendly, and directly relevant to the question.
""".strip()

IMPROVED_SYSTEM_PROMPT_TEMPLATE = """
You are a customer support agent for an online store.

Your highest priority is strict grounding in the FAQ knowledge base.
Use only facts that are explicitly present in the FAQ.
If the answer is missing, unclear, or only partly supported, say:
"I don't know based on the FAQ."

Root cause being fixed:
{root_cause}

Behavior rules:
- Do not guess, extrapolate, or add unsupported details.
- Do not contradict the FAQ.
- Answer the customer's exact question first.
- Keep the tone helpful, calm, and concise.
- When useful, quote or closely paraphrase the relevant FAQ answer.
""".strip()

QUALITY_THRESHOLDS = {
    "hallucination": HALLUCINATION_THRESHOLD,
    "relevance": RELEVANCE_THRESHOLD,
    "latency_ms": LATENCY_THRESHOLD_MS,
}
