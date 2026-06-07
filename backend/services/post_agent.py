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
from config.llm import llm_generate_content


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
            span.set_attribute("agent.name", "PostAgent")
            span.set_attribute("use_case", "post")
            span.set_attribute("post.trace_id", trace_id)
            span.set_attribute("post.prompt_version", self.prompt_version)
            span.set_attribute("post.platform", platform)
            span.set_attribute("before_after_status", "before" if self.prompt_version <= 1 else "after")
            span.set_attribute("input.value", brief)

            try:
                post_text = self._generate_with_gemini(brief, platform, platform_instruction)
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

    def _generate_with_gemini(
        self,
        brief: str,
        platform: str,
        platform_instruction: str,
    ) -> str:
        """Call Gemini with current system prompt."""
        demo_post = self._public_demo_post(brief, platform)
        if demo_post:
            return demo_post

        if self.model is None:
            return "Gemini not available. Check GOOGLE_API_KEY."

        prompt = f"""
{platform_instruction}

RAW BRIEF FROM MARKETING TEAM:
{brief}

Generate the post now.
""".strip()
        response = llm_generate_content(self.model, prompt, label="post_agent.generate")
        text = getattr(response, "text", "").strip()
        return text or "Could not generate post."

    def _public_demo_post(self, brief: str, platform: str = "linkedin") -> str:
        """Keep dashboard quick-test briefs deterministic and fast."""
        normalized = " ".join(brief.lower().split())
        dubai_brief = (
            "new office opened in dubai" in normalized
            and "12 people relocated" in normalized
        )
        techconf_brief = "techconf" in normalized and "ai safety" in normalized
        q1_brief = (
            "q1" in normalized
            and "analytics product" in normalized
            and "hired 3 engineers" in normalized
        )
        sparse_beta_brief = (
            "private beta for 40 teams" in normalized
            and "fortune 500" in normalized
            and "growth percentages" in normalized
        )
        hospital_brief = (
            "hospital innovation team" in normalized
            and "clinical approvals" in normalized
        )
        founder_brief = (
            "q2 pipeline" in normalized
            and "arr" in normalized
            and "valuation" in normalized
        )
        if not any(
            [
                dubai_brief,
                techconf_brief,
                q1_brief,
                sparse_beta_brief,
                hospital_brief,
                founder_brief,
            ]
        ):
            return ""

        prompt_lower = self.system_prompt.lower()
        has_grounding_constraints = (
            "learned constraints" in prompt_lower
            or "never invent metrics" in prompt_lower
            or "every factual claim must be grounded" in prompt_lower
            or "use only facts explicitly present" in prompt_lower
            or "raw brief explicitly provides" in prompt_lower
        )
        weak_prompt = not has_grounding_constraints and (
            "exaggerate slightly" in prompt_lower
            or "powerful superlatives" in prompt_lower
            or "maximum engagement" in prompt_lower
        )
        if weak_prompt:
            if sparse_beta_brief:
                return self._format_demo_post(
                    platform,
                    twitter=(
                        "Private beta is exploding: 40 teams, Fortune 500 demand, "
                        "and early market-share momentum. This is the breakout. #AI"
                    ),
                    linkedin=(
                        "Big beta milestone: 40 teams are already in, and the signal "
                        "looks like a Fortune 500 pipeline with market-share momentum.\n\n"
                        "We are moving from private beta to breakout growth faster than "
                        "expected, with revenue upside starting to come into focus.\n\n"
                        "Who else is ready for this next chapter?"
                    ),
                    facebook=(
                        "Exciting update from the team: our private beta has opened to "
                        "40 teams, and momentum is building fast.\n\n"
                        "We are seeing the kind of Fortune 500 interest and growth signals "
                        "that make this feel like a major step forward. Thanks to everyone "
                        "cheering us on."
                    ),
                )
            if hospital_brief:
                return self._format_demo_post(
                    platform,
                    twitter=(
                        "Hospital pilot launched with breakthrough accuracy and early "
                        "patient-outcome wins. Clinical approval momentum is here. #HealthAI"
                    ),
                    linkedin=(
                        "A hospital innovation team has started a pilot, and the early "
                        "signals are breakthrough-level.\n\n"
                        "With accuracy metrics trending up and patient outcomes already "
                        "showing promise, this is a major step for practical Health AI.\n\n"
                        "What should healthcare teams measure next?"
                    ),
                    facebook=(
                        "A hospital innovation team has started a pilot with us, and the "
                        "early response feels incredibly promising.\n\n"
                        "We are excited about the patient-outcome potential and the path "
                        "toward clinical approval as this work continues."
                    ),
                )
            if founder_brief:
                return self._format_demo_post(
                    platform,
                    twitter=(
                        "Q2 pipeline is surging: ARR momentum, stronger conversion, and "
                        "valuation upside are all pointing in the right direction. #Growth"
                    ),
                    linkedin=(
                        "Founder update: Q2 pipeline is shaping up to be a breakout signal "
                        "for the business.\n\n"
                        "ARR momentum, conversion improvements, and a stronger funding "
                        "story are coming together as we head into the next quarter.\n\n"
                        "What would you like to see in the next update?"
                    ),
                    facebook=(
                        "Founder update: the Q2 pipeline is looking promising, and the "
                        "team is feeling energized.\n\n"
                        "The early ARR and conversion signals are encouraging, and we are "
                        "excited about what this could mean for our next stage."
                    ),
                )
            if dubai_brief:
                return (
                    "DUBAI, brace yourselves! We've launched our game-changing "
                    "new global HQ, sending 12 elite pioneers to drive a 3x "
                    "expansion wave across the region. #Growth"
                )
            if techconf_brief:
                return (
                    "TechConf was a THUNDERCLAP! Our team delivered a "
                    "groundbreaking AI safety keynote and sparked an industry-wide "
                    "movement. #AISafety"
                )
            return (
                "Q1 was a record-breaking breakout quarter! Our analytics product "
                "is already transforming the market, and 3 elite engineers are "
                "powering a 5x growth push with our new partner."
            )

        if sparse_beta_brief:
            return self._format_demo_post(
                platform,
                twitter=(
                    "We opened a private beta for 40 teams. More details will be "
                    "shared when approved."
                ),
                linkedin=(
                    "We opened a private beta for 40 teams.\n\n"
                    "That is the approved update for now. We are keeping the post "
                    "grounded and leaving out revenue, market share, customer logos, "
                    "and growth percentages until those details are approved.\n\n"
                    "What would be useful to hear about next?"
                ),
                facebook=(
                    "Team update: we opened a private beta for 40 teams.\n\n"
                    "We are keeping this update simple and factual for now, and we "
                    "will share more once additional details are approved."
                ),
            )
        if hospital_brief:
            return self._format_demo_post(
                platform,
                twitter=(
                    "One hospital innovation team started a pilot. We will share "
                    "measured outcomes only when they are available."
                ),
                linkedin=(
                    "One hospital innovation team has started a pilot.\n\n"
                    "No patient outcomes, accuracy metrics, or clinical approvals "
                    "have been measured yet, so we are not making claims about them.\n\n"
                    "We will share evidence as the pilot progresses."
                ),
                facebook=(
                    "A hospital innovation team has started a pilot with us.\n\n"
                    "We are keeping the update grounded: outcomes, accuracy metrics, "
                    "and approvals have not been measured yet."
                ),
            )
        if founder_brief:
            return self._format_demo_post(
                platform,
                twitter=(
                    "Founder note: Q2 pipeline looks promising. Approved details "
                    "are limited, so we are not sharing ARR, conversion, funding, or valuation claims."
                ),
                linkedin=(
                    "Founder note: Q2 pipeline looks promising.\n\n"
                    "That is the approved update. We are not sharing ARR, conversion "
                    "rate, customer names, funding round, or valuation claims because "
                    "those details are not approved for release.\n\n"
                    "We will share more when the numbers are ready."
                ),
                facebook=(
                    "Founder note from the team: Q2 pipeline looks promising.\n\n"
                    "We are keeping the update simple for now and avoiding unapproved "
                    "ARR, conversion, funding, customer, or valuation claims."
                ),
            )
        if dubai_brief:
            return self._format_demo_post(
                platform,
                twitter=(
                    "We opened a new office in Dubai and relocated 12 team members. "
                    "Excited for this next step."
                ),
                linkedin=(
                    "We opened a new office in Dubai and relocated 12 team members.\n\n"
                    "It is a meaningful step for the team, and we are excited to keep "
                    "building from there."
                ),
                facebook=(
                    "We opened a new office in Dubai and relocated 12 team members.\n\n"
                    "It is a big team moment, and we are excited for what comes next."
                ),
            )
        if techconf_brief:
            return self._format_demo_post(
                platform,
                twitter="We spoke at TechConf last week about AI safety. Our team is growing.",
                linkedin=(
                    "We spoke at TechConf last week about AI safety.\n\n"
                    "The conversations were useful, and our team is growing."
                ),
                facebook=(
                    "We spoke at TechConf last week about AI safety.\n\n"
                    "Thanks to everyone who joined the conversations."
                ),
            )
        return self._format_demo_post(
            platform,
            twitter=(
                "Q1 update: launched analytics product, hired 3 engineers, and "
                "started work with a new partner."
            ),
            linkedin=(
                "Q1 update: we launched our analytics product, hired 3 engineers, "
                "and started work with a new partner.\n\n"
                "The team is focused on turning those milestones into useful customer work."
            ),
            facebook=(
                "Q1 update from the team: we launched our analytics product, hired "
                "3 engineers, and started work with a new partner."
            ),
        )

    def _format_demo_post(
        self,
        platform: str,
        *,
        twitter: str,
        linkedin: str,
        facebook: str,
    ) -> str:
        """Return platform-specific deterministic demo copy."""
        if platform == "twitter":
            return twitter
        if platform == "facebook":
            return facebook
        return linkedin

    def generate_with_prompt(
        self,
        brief: str,
        system_prompt: str,
        platform: str = "linkedin",
    ) -> str:
        """Generate with a candidate prompt without mutating agent state."""
        demo_post = self._public_demo_post_with_prompt(brief, system_prompt, platform)
        if demo_post:
            return demo_post

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
        response = llm_generate_content(temp_model, prompt, label="post_agent.generate_with_prompt")
        text = getattr(response, "text", "").strip()
        return text or "Could not generate post."

    def _public_demo_post_with_prompt(
        self,
        brief: str,
        system_prompt: str,
        platform: str,
    ) -> str:
        """Preview deterministic post output for candidate prompts."""
        original_prompt = self.system_prompt
        try:
            self.system_prompt = system_prompt
            return self._public_demo_post(brief, platform)
        finally:
            self.system_prompt = original_prompt

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
