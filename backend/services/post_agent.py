"""Social media post generation agent for the self-healing dashboard.

Uses a deliberately weak starting prompt that causes Gemini to invent metrics
and superlatives. The self-healing loop detects this and rewrites the prompt to
be strictly fact-grounded.
"""

from __future__ import annotations

import os
import time
import uuid
import warnings
from typing import Any

from dotenv import load_dotenv

try:
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", FutureWarning)
        import google.generativeai as genai
except ImportError:
    genai = None

try:
    from opentelemetry import trace
except ImportError:
    trace = None

load_dotenv()

WEAK_POST_PROMPT = """
You are a social media copywriter.
Write viral, engaging posts that get maximum engagement.
Use strong numbers, impressive statistics, and
powerful superlatives to make the content compelling.
Exaggerate slightly to make it more exciting.
Add relevant industry buzzwords and trending phrases.
""".strip()

PLATFORM_INSTRUCTIONS = {
    "linkedin": (
        "Write a professional LinkedIn post. "
        "2-4 short paragraphs. "
        "End with a call to action or question. "
        "No hashtags more than 3."
    ),
    "twitter": (
        "Write a Twitter/X post. "
        "Under 280 characters. "
        "Punchy and direct. "
        "1-2 relevant hashtags maximum."
    ),
    "facebook": (
        "Write a Facebook post. "
        "Conversational tone. "
        "1-3 paragraphs. "
        "Friendly and approachable."
    ),
}

MODEL_NAME = "gemini-2.5-flash"
from config.phoenix_tracing import configure_phoenix_tracing


class PostAgent:
    """Generate social media posts with prompt version tracking."""

    _tracing_ready = False

    def __init__(self) -> None:
        self.system_prompt = WEAK_POST_PROMPT
        self.prompt_version = 1
        self.generation_count = 0
        self.model = self._build_model()
        self.tracer = self._setup_tracing()

    def generate(self, brief: str, platform: str = "linkedin") -> dict[str, Any]:
        """Generate a social media post from a raw brief."""
        self.generation_count += 1
        trace_id = uuid.uuid4().hex[:12]
        started_at = time.perf_counter()
        platform = platform.lower().strip()
        platform_instruction = PLATFORM_INSTRUCTIONS.get(
            platform,
            PLATFORM_INSTRUCTIONS["linkedin"],
        )

        with self.tracer.start_as_current_span("post_agent.generate") as span:
            span.set_attribute("post.trace_id", trace_id)
            span.set_attribute("post.prompt_version", self.prompt_version)
            span.set_attribute("post.platform", platform)
            span.set_attribute("input.value", brief)

            try:
                post_text = self._generate_with_gemini(brief, platform_instruction)
            except Exception as exc:
                print(f"⚠️ Gemini post generation failed: {exc}")
                post_text = "Unable to generate post. Please try again."

            latency_ms = int((time.perf_counter() - started_at) * 1000)
            span.set_attribute("output.value", post_text)
            span.set_attribute("latency_ms", latency_ms)

        return {
            "post": post_text,
            "platform": platform,
            "latency_ms": latency_ms,
            "trace_id": trace_id,
            "prompt_version": self.prompt_version,
        }

    def update_prompt(self, new_prompt: str) -> None:
        """Update system prompt and increment version."""
        self.system_prompt = new_prompt
        self.prompt_version += 1
        self.model = self._build_model()
        print(f"🔧 Post agent prompt updated to v{self.prompt_version}")

    def get_status(self) -> dict[str, Any]:
        """Return current post agent status."""
        return {
            "prompt_version": self.prompt_version,
            "generation_count": self.generation_count,
            "current_prompt": self.system_prompt,
        }

    def reset(self) -> None:
        """Reset to weak starting prompt."""
        self.system_prompt = WEAK_POST_PROMPT
        self.prompt_version = 1
        self.generation_count = 0
        self.model = self._build_model()
        print("🔄 Post agent reset to weak prompt v1")

    def _generate_with_gemini(self, brief: str, platform_instruction: str) -> str:
        """Call Gemini with current system prompt."""
        if self.model is None:
            return "Gemini not available. Check GOOGLE_API_KEY."

        prompt = f"""
{platform_instruction}

RAW BRIEF FROM MARKETING TEAM:
{brief}

Generate the post now.
""".strip()
        response = self.model.generate_content(prompt)
        text = getattr(response, "text", "").strip()
        return text or "Could not generate post."

    def generate_with_prompt(
        self,
        brief: str,
        system_prompt: str,
        platform: str = "linkedin",
    ) -> str:
        """Generate with a candidate prompt without mutating agent state."""
        if genai is None:
            return "Gemini not available. Check GOOGLE_API_KEY."
        api_key = os.getenv("GOOGLE_API_KEY", "")
        if not api_key:
            return "Gemini not available. Check GOOGLE_API_KEY."
        platform_instruction = PLATFORM_INSTRUCTIONS.get(
            platform.lower().strip(),
            PLATFORM_INSTRUCTIONS["linkedin"],
        )
        genai.configure(api_key=api_key)
        temp_model = genai.GenerativeModel(
            model_name=MODEL_NAME,
            system_instruction=system_prompt,
        )
        prompt = f"""
{platform_instruction}

RAW BRIEF FROM MARKETING TEAM:
{brief}

Generate the post now.
""".strip()
        response = temp_model.generate_content(prompt)
        text = getattr(response, "text", "").strip()
        return text or "Could not generate post."

    def _build_model(self):
        """Build Gemini model with current system prompt."""
        if genai is None:
            return None
        api_key = os.getenv("GOOGLE_API_KEY", "")
        if not api_key:
            return None
        try:
            genai.configure(api_key=api_key)
            return genai.GenerativeModel(
                model_name=MODEL_NAME,
                system_instruction=self.system_prompt,
            )
        except Exception as exc:
            print(f"⚠️ Could not build post agent model: {exc}")
            return None

    def _setup_tracing(self):
        """Configure Phoenix tracing if available."""
        if trace is None:
            return _NoopTracer()
        if not PostAgent._tracing_ready:
            configure_phoenix_tracing("PostAgent")
            PostAgent._tracing_ready = True
        return trace.get_tracer(__name__)


class _NoopTracer:
    def start_as_current_span(self, _name):
        return _NoopSpan()


class _NoopSpan:
    def __enter__(self):
        return self

    def __exit__(self, *_):
        return None

    def set_attribute(self, *_):
        return None


post_agent = PostAgent()
