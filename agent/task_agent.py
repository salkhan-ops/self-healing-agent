"""Customer support task agent with Gemini answering and Phoenix tracing.

The TaskAgent loads a local FAQ, answers questions with Gemini 2.0 Flash,
and records each interaction as an OpenTelemetry trace for local Phoenix.
"""

from __future__ import annotations

import time
import warnings
from pathlib import Path
from typing import Iterable

try:
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", FutureWarning)
        import google.generativeai as genai
except ImportError as exc:
    raise ImportError(
        "google-generativeai is required. Fix with: pip install google-generativeai"
    ) from exc

try:
    from openinference.instrumentation.google_genai import GoogleGenAIInstrumentor
except ImportError:
    GoogleGenAIInstrumentor = None

try:
    from opentelemetry import trace
except ImportError:
    trace = None

from config.phoenix_tracing import configure_phoenix_tracing
from config.settings import (
    DEFAULT_SYSTEM_PROMPT,
    GEMINI_MODEL_NAME,
    GOOGLE_API_KEY,
    PHOENIX_PROJECT_NAME,
    USE_GEMINI_ANSWERS,
)
from config.llm import llm_generate_content
from agent.usage import usage_tracker


class TaskAgent:
    """Answer customer questions from the FAQ and trace every interaction."""

    _tracing_ready = False

    def __init__(
        self,
        faq_path: str | Path = "data/faq.txt",
        system_prompt: str = DEFAULT_SYSTEM_PROMPT,
    ) -> None:
        self.faq_path = Path(faq_path)
        self.system_prompt = system_prompt
        self.faq_text = self._load_faq_text()
        self.model = self._build_model()
        self.tracer = self._setup_tracing()

    def answer(self, question: str) -> str:
        """Return one answer string for a customer question."""
        started_at = time.perf_counter()
        span_name = "customer_support.answer"

        with self.tracer.start_as_current_span(span_name) as span:
            span.set_attribute("input.value", question)
            span.set_attribute("phoenix.project.name", PHOENIX_PROJECT_NAME)

            try:
                answer = self._answer_with_gemini(question)
            except Exception as exc:
                print(f"⚠️ Gemini answer failed; using FAQ fallback. Error: {exc}")
                answer = self._answer_from_faq(question)

            latency_ms = int((time.perf_counter() - started_at) * 1000)
            span.set_attribute("output.value", answer)
            span.set_attribute("latency_ms", latency_ms)
            span.set_attribute("llm.model_name", GEMINI_MODEL_NAME)

        return answer

    def set_system_prompt(self, prompt: str) -> None:
        """Update the active system prompt and rebuild the Gemini model."""
        self.system_prompt = prompt
        self.model = self._build_model()

    def run_batch(self, questions: Iterable[str]) -> list[str]:
        """Answer a batch of questions in order."""
        return [self.answer(question) for question in questions]

    def _build_model(self):
        """Create a Gemini model, or return None when local config is incomplete."""
        if not GOOGLE_API_KEY:
            print("⚠️ GOOGLE_API_KEY is missing; TaskAgent will use FAQ fallback answers.")
            return None

        if not USE_GEMINI_ANSWERS:
            print("⚠️ Gemini answers disabled; TaskAgent will use FAQ fallback answers.")
            return None

        try:
            genai.configure(api_key=GOOGLE_API_KEY)
            return genai.GenerativeModel(
                model_name=GEMINI_MODEL_NAME,
                system_instruction=self.system_prompt,
            )
        except Exception as exc:
            print(f"⚠️ Could not initialize Gemini model: {exc}")
            return None

    def _setup_tracing(self):
        """Configure OpenTelemetry export to Phoenix and return a tracer."""
        if trace is None:
            print(
                "⚠️ OpenTelemetry packages are missing. "
                "Fix with: pip install opentelemetry-sdk opentelemetry-exporter-otlp"
            )
            return _NoopTracer()

        if not TaskAgent._tracing_ready:
            configure_phoenix_tracing("TaskAgent")
            self._instrument_google_genai()
            TaskAgent._tracing_ready = True

        return trace.get_tracer(__name__)

    def _instrument_google_genai(self) -> None:
        """Enable OpenInference instrumentation when the package is available."""
        if GoogleGenAIInstrumentor is None:
            print(
                "⚠️ OpenInference Google GenAI instrumentation missing. "
                "Fix with: pip install openinference-instrumentation-google-genai"
            )
            return

        try:
            GoogleGenAIInstrumentor().instrument()
        except Exception as exc:
            print(f"⚠️ OpenInference instrumentation failed; manual traces still run. Error: {exc}")

    def _answer_with_gemini(self, question: str) -> str:
        """Ask Gemini to answer using the configured prompt and FAQ."""
        if self.model is None:
            return self._answer_from_faq(question)

        prompt = f"""
FAQ KNOWLEDGE BASE:
{self.faq_text}

CUSTOMER QUESTION:
{question}

Answer using only the FAQ knowledge base.
""".strip()
        response = llm_generate_content(self.model, prompt, label="task_agent.answer")
        usage_tracker.record(response)
        text = getattr(response, "text", "").strip()

        if not text:
            return "I don't know based on the FAQ."

        return text

    def _load_faq_text(self) -> str:
        """Load the FAQ text, returning an empty string if the file is unavailable."""
        try:
            return self.faq_path.read_text(encoding="utf-8")
        except OSError as exc:
            print(f"⚠️ Could not load FAQ from {self.faq_path}: {exc}")
            return ""

    def _answer_from_faq(self, question: str) -> str:
        """Use a simple local FAQ lookup when Gemini is unavailable."""
        normalized_question = question.strip().lower()
        entries = self._faq_entries()

        for faq_question, faq_answer in entries:
            if faq_question.lower() == normalized_question:
                return faq_answer

        question_words = set(normalized_question.replace("?", "").split())
        best_answer = ""
        best_overlap = 0

        for faq_question, faq_answer in entries:
            faq_words = set(faq_question.lower().replace("?", "").split())
            overlap = len(question_words.intersection(faq_words))
            if overlap > best_overlap:
                best_answer = faq_answer
                best_overlap = overlap

        if best_overlap >= 3:
            return best_answer

        return "I don't know based on the FAQ."

    def _faq_entries(self) -> list[tuple[str, str]]:
        """Parse Q/A blocks from the local FAQ file."""
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
    """Tiny tracer fallback used when OpenTelemetry is unavailable."""

    def start_as_current_span(self, _name: str):
        """Return a context manager with a no-op span."""
        return _NoopSpan()


class _NoopSpan:
    """Tiny span fallback used when OpenTelemetry is unavailable."""

    def __enter__(self):
        return self

    def __exit__(self, *_args) -> None:
        return None

    def set_attribute(self, _name: str, _value: object) -> None:
        return None
