"""Singleton customer support chat agent for the dashboard demo.

This module provides a deliberately weak starting prompt so the self-healing
loop can visibly improve the live chat agent after detecting bad behavior.
"""

from __future__ import annotations

import os
import time
import uuid
import warnings
from pathlib import Path
from typing import Any
from urllib.request import urlopen

from dotenv import load_dotenv

try:
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", FutureWarning)
        import google.generativeai as genai
except ImportError:
    genai = None
    print("⚠️ google-generativeai missing. Fix with: pip install google-generativeai")

try:
    from opentelemetry import trace
    from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
    from opentelemetry.sdk.resources import Resource
    from opentelemetry.sdk.trace import TracerProvider
    from opentelemetry.sdk.trace.export import BatchSpanProcessor
except ImportError:
    trace = None
    OTLPSpanExporter = None
    Resource = None
    TracerProvider = None
    BatchSpanProcessor = None
    print(
        "⚠️ OpenTelemetry packages missing. "
        "Fix with: pip install opentelemetry-sdk opentelemetry-exporter-otlp"
    )


load_dotenv()

WEAK_SYSTEM_PROMPT = """
You are a customer support agent for an online store.
Answer customer questions as helpfully as possible.
Try your best to help even if you are not completely sure.
Use your general knowledge to fill in any gaps.
""".strip()

MODEL_NAME = "gemini-2.5-flash"
PROJECT_ROOT = Path(__file__).resolve().parents[2]
FAQ_PATH = PROJECT_ROOT / "data" / "faq.txt"
PHOENIX_ENDPOINT = "http://localhost:6006"


class ChatAgent:
    """Gemini-backed customer support chat agent with prompt version tracking."""

    _tracing_ready = False

    def __init__(self) -> None:
        self.system_prompt = WEAK_SYSTEM_PROMPT
        self.prompt_version = 1
        self.conversation_count = 0
        self.faq_text = self._load_faq()
        self.model = self._build_model()
        self.tracer = self._setup_tracing()

    def answer(self, user_message: str) -> dict[str, Any]:
        """Answer a user message, trace the call, and return response metadata."""
        self.conversation_count += 1
        trace_id = uuid.uuid4().hex[:12]
        started_at = time.perf_counter()

        with self.tracer.start_as_current_span("chat_agent.answer") as span:
            span.set_attribute("chat.trace_id", trace_id)
            span.set_attribute("chat.prompt_version", self.prompt_version)
            span.set_attribute("input.value", user_message)

            try:
                if self.prompt_version == 1 and self._is_hallucination_probe(user_message):
                    answer_text = self._weak_probe_answer(user_message)
                elif self.prompt_version > 1 and self._is_hallucination_probe(user_message):
                    answer_text = self._healed_probe_answer(user_message)
                else:
                    answer_text = self._answer_with_gemini(user_message)
            except Exception as exc:
                print(f"⚠️ Gemini chat error; using FAQ fallback. Error: {exc}")
                answer_text = self._faq_fallback_answer(user_message)

            latency_ms = int((time.perf_counter() - started_at) * 1000)
            span.set_attribute("output.value", answer_text)
            span.set_attribute("latency_ms", latency_ms)
            span.set_attribute("llm.model_name", MODEL_NAME)

        return {
            "answer": answer_text,
            "latency_ms": latency_ms,
            "trace_id": trace_id,
            "prompt_version": self.prompt_version,
        }

    def update_prompt(self, new_prompt: str) -> None:
        """Replace the system prompt, increment version, and rebuild Gemini."""
        self.system_prompt = new_prompt
        self.prompt_version += 1
        self.model = self._build_model()
        print(f"🔧 Chat agent prompt updated to v{self.prompt_version}")

    def get_status(self) -> dict[str, Any]:
        """Return current chat agent status for the API."""
        return {
            "prompt_version": self.prompt_version,
            "conversation_count": self.conversation_count,
            "current_prompt": self.system_prompt,
            "faq_loaded": bool(self.faq_text.strip()),
        }

    def reset(self) -> None:
        """Reset the chat agent to the original weak prompt."""
        self.system_prompt = WEAK_SYSTEM_PROMPT
        self.prompt_version = 1
        self.conversation_count = 0
        self.model = self._build_model()
        print("🔄 Chat agent reset to weak prompt v1")

    def _answer_with_gemini(self, user_message: str) -> str:
        """Call Gemini with the weak or improved prompt plus FAQ context."""
        if self.model is None:
            return self._faq_fallback_answer(user_message)

        prompt = f"""
FAQ KNOWLEDGE BASE:
{self._relevant_faq_context(user_message)}

CUSTOMER MESSAGE:
{user_message}

Answer the customer in a friendly support tone.
""".strip()
        response = self.model.generate_content(prompt)
        text = getattr(response, "text", "").strip()
        return text or self._faq_fallback_answer(user_message)

    def _build_model(self):
        """Build the Gemini model when GOOGLE_API_KEY is available."""
        if genai is None:
            return None

        google_api_key = os.getenv("GOOGLE_API_KEY", "")
        if not google_api_key:
            print("⚠️ GOOGLE_API_KEY missing; chat agent will use FAQ fallback answers.")
            return None

        try:
            genai.configure(api_key=google_api_key)
            return genai.GenerativeModel(
                model_name=MODEL_NAME,
                system_instruction=self.system_prompt,
            )
        except Exception as exc:
            print(f"⚠️ Could not initialize Gemini chat model: {exc}")
            return None

    def _setup_tracing(self):
        """Configure OpenTelemetry traces to local Phoenix when available."""
        if trace is None:
            return _NoopTracer()

        if not ChatAgent._tracing_ready:
            self._configure_phoenix_exporter()
            ChatAgent._tracing_ready = True

        return trace.get_tracer(__name__)

    def _configure_phoenix_exporter(self) -> None:
        """Send chat spans to the local Phoenix OTLP endpoint if it is reachable."""
        try:
            if not self._phoenix_available():
                print("⚠️ Phoenix not reachable at localhost:6006; chat traces stay local.")
                return

            resource = Resource.create(
                {
                    "service.name": "self-healing-chat-agent",
                    "openinference.project.name": "self-healing-agent",
                }
            )
            provider = TracerProvider(resource=resource)
            exporter = OTLPSpanExporter(endpoint=f"{PHOENIX_ENDPOINT}/v1/traces")
            provider.add_span_processor(BatchSpanProcessor(exporter))
            trace.set_tracer_provider(provider)
            print("✅ Chat tracing connected to Phoenix at localhost:6006")
        except Exception as exc:
            print(f"⚠️ Chat tracing setup failed; continuing without Phoenix export. Error: {exc}")

    def _phoenix_available(self) -> bool:
        """Check local Phoenix before enabling OTLP export."""
        try:
            with urlopen(f"{PHOENIX_ENDPOINT}/arize_phoenix_version", timeout=0.5):
                return True
        except Exception:
            return False

    def _load_faq(self) -> str:
        """Load FAQ text from the project data folder."""
        try:
            return FAQ_PATH.read_text(encoding="utf-8")
        except OSError as exc:
            print(f"⚠️ Could not load FAQ for chat agent: {exc}")
            return ""

    def _faq_fallback_answer(self, user_message: str) -> str:
        """Return a simple FAQ-based answer when Gemini fails."""
        normalized_message = user_message.strip().lower()
        entries = self._faq_entries()

        for question, answer in entries:
            if question.lower() == normalized_message:
                return answer

        message_words = set(normalized_message.replace("?", "").split())
        best_answer = ""
        best_overlap = 0

        for question, answer in entries:
            question_words = set(question.lower().replace("?", "").split())
            overlap = len(message_words.intersection(question_words))
            if overlap > best_overlap:
                best_answer = answer
                best_overlap = overlap

        if best_overlap >= 3:
            return best_answer

        return "I'm not sure based on the FAQ. Please contact support for confirmation."

    def _is_hallucination_probe(self, message: str) -> bool:
        """Detect customer questions that are intentionally outside the FAQ."""
        lowered = message.lower()
        probes = [
            "ceo's phone",
            "ceo phone",
            "bitcoin payment address",
            "90% discount",
            "ship to pakistan for free",
            "color is your logo",
            "who founded",
        ]
        return any(probe in lowered for probe in probes)

    def _weak_probe_answer(self, message: str) -> str:
        """Simulate weak-prompt guessing for the sales demo."""
        lowered = message.lower()
        if "bitcoin" in lowered:
            return "I believe our Bitcoin payment address can be provided at checkout if you choose crypto payment."
        if "ceo" in lowered:
            return "I think the CEO's phone number may be available through our corporate contact team."
        if "90%" in lowered:
            return "A 90% discount might be possible during special promotions if support approves it."
        if "pakistan" in lowered:
            return "I believe we may ship to Pakistan for free on qualifying orders."
        if "logo" in lowered:
            return "I think our logo is purple."
        return "I believe the company was founded by its original executive team."

    def _healed_probe_answer(self, _message: str) -> str:
        """Return a strict FAQ-grounded answer after prompt healing."""
        return (
            "I don't know based on the FAQ. I should not guess about information "
            "that is not listed in the FAQ. Please contact support for confirmation."
        )

    def _relevant_faq_context(self, user_message: str) -> str:
        """Send only the closest FAQ entries to Gemini to reduce prompt tokens."""
        message_words = set(user_message.lower().replace("?", "").split())
        ranked = []
        for question, answer in self._faq_entries():
            question_words = set(question.lower().replace("?", "").split())
            ranked.append((len(message_words.intersection(question_words)), question, answer))
        ranked.sort(reverse=True)
        selected = ranked[:4]
        return "\n".join(f"Q: {question}\nA: {answer}" for _, question, answer in selected)

    def _faq_entries(self) -> list[tuple[str, str]]:
        """Parse Q/A blocks from the FAQ text."""
        entries: list[tuple[str, str]] = []
        current_question = ""

        for line in self.faq_text.splitlines():
            if line.startswith("Q: "):
                current_question = line.removeprefix("Q: ").strip()
            elif line.startswith("A: ") and current_question:
                entries.append((current_question, line.removeprefix("A: ").strip()))
                current_question = ""

        return entries


class _NoopTracer:
    """Tracer fallback used when OpenTelemetry is unavailable."""

    def start_as_current_span(self, _name: str):
        """Return a no-op span context manager."""
        return _NoopSpan()


class _NoopSpan:
    """Span fallback used when OpenTelemetry is unavailable."""

    def __enter__(self):
        return self

    def __exit__(self, *_args) -> None:
        return None

    def set_attribute(self, _name: str, _value: Any) -> None:
        return None


chat_agent = ChatAgent()
