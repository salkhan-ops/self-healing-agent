"""Real self-healing loop for the social media post agent."""

from __future__ import annotations

import json
import re
import warnings
from dataclasses import dataclass
from typing import Any

try:
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", FutureWarning)
        import google.generativeai as genai
except ImportError:
    genai = None

from config.settings import GOOGLE_API_KEY
from backend.services.post_agent import post_agent
from backend.services.post_history_store import list_posts
from backend.services.post_scorer import post_scorer


@dataclass
class PostHealingResult:
    """Structured result for one post-agent healing pass."""

    old_prompt: str
    new_prompt: str
    root_cause: str
    root_cause_explanation: str
    before_scores: dict[str, float]
    after_scores: dict[str, float]
    verification_traces: list[dict[str, Any]]


class PostHealer:
    """Diagnose and rewrite the post agent from actual failed post history."""

    def heal_recent_posts(self) -> PostHealingResult | None:
        """Heal from recent hallucinated post generations when evidence exists."""
        history = list_posts(limit=12)
        problematic = [
            item
            for item in history
            if float(item.get("hallucination_score", 0.0)) > 0.4
        ]
        if not problematic:
            return None

        old_prompt = post_agent.system_prompt
        root_cause, explanation = self._analyze(problematic)
        new_prompt = self._rewrite_prompt(old_prompt, problematic, root_cause, explanation)
        if not new_prompt or new_prompt.strip() == old_prompt.strip():
            return None

        verification = self._verify(new_prompt, problematic[:3])
        before_scores = self._average_scores(problematic[:3])
        after_scores = self._average_scores(verification)
        return PostHealingResult(
            old_prompt=old_prompt,
            new_prompt=new_prompt,
            root_cause=root_cause,
            root_cause_explanation=explanation,
            before_scores=before_scores,
            after_scores=after_scores,
            verification_traces=verification,
        )

    def _analyze(self, traces: list[dict]) -> tuple[str, str]:
        if genai is None or not GOOGLE_API_KEY:
            raise RuntimeError("Gemini is required for real post healing analysis")
        genai.configure(api_key=GOOGLE_API_KEY)
        model = genai.GenerativeModel(model_name="gemini-2.5-flash")
        prompt = f"""
You are diagnosing failures in a social media post generation agent.

Each trace contains the raw brief, generated post, and evaluator scores:
{json.dumps(traces, indent=2, default=str)}

Choose the dominant failure category from:
- INVENTED_METRICS
- UNSUPPORTED_SUPERLATIVES
- BRIEF_DRIFT
- OTHER

Return ONLY JSON:
{{"category": "INVENTED_METRICS", "explanation": "Short explanation grounded in the traces."}}
""".strip()
        response = model.generate_content(prompt)
        parsed = self._parse_json(getattr(response, "text", ""))
        category = str(parsed.get("category") or "OTHER").strip().upper()
        explanation = str(parsed.get("explanation") or "").strip()
        if not explanation:
            explanation = "Generated posts added claims not supported by the source briefs."
        return category, explanation

    def _rewrite_prompt(
        self,
        current_prompt: str,
        traces: list[dict],
        category: str,
        explanation: str,
    ) -> str:
        if genai is None or not GOOGLE_API_KEY:
            raise RuntimeError("Gemini is required for real post prompt rewriting")
        genai.configure(api_key=GOOGLE_API_KEY)
        model = genai.GenerativeModel(model_name="gemini-2.5-flash")
        prompt = f"""
Rewrite this SOCIAL MEDIA POST GENERATION system prompt to fix the observed failures.

Current prompt:
{current_prompt}

Root cause category: {category}
Root cause explanation: {explanation}

Failed examples:
{json.dumps(traces, indent=2, default=str)}

Requirements for the new system prompt:
- It must remain a social media copywriter prompt, not customer support.
- It must use only facts explicitly present in the raw brief.
- It must forbid invented metrics, percentages, revenue, team size, rankings, awards, and unsupported superlatives.
- It may improve tone and wording without adding factual claims.
- It must be concise, production-ready, and written as direct instructions to the model.
- Return ONLY the new system prompt text.
""".strip()
        response = model.generate_content(prompt)
        return getattr(response, "text", "").strip()

    def _verify(self, candidate_prompt: str, examples: list[dict]) -> list[dict[str, Any]]:
        traces: list[dict[str, Any]] = []
        for item in examples:
            brief = str(item.get("brief", ""))
            platform = str(item.get("platform", "linkedin"))
            post = post_agent.generate_with_prompt(brief, candidate_prompt, platform)
            scores = post_scorer.score(brief, post, prompt_version=post_agent.prompt_version + 1)
            traces.append(
                {
                    "brief": brief,
                    "platform": platform,
                    "post": post,
                    "hallucination_score": scores["hallucination_score"],
                    "relevance_score": scores["relevance_score"],
                }
            )
        return traces

    def _average_scores(self, traces: list[dict]) -> dict[str, float]:
        if not traces:
            return {"hallucination_score": 0.0, "relevance_score": 0.0}
        return {
            "hallucination_score": sum(float(t.get("hallucination_score", 0.0)) for t in traces) / len(traces),
            "relevance_score": sum(float(t.get("relevance_score", 0.0)) for t in traces) / len(traces),
        }

    def _parse_json(self, text: str) -> dict[str, Any]:
        cleaned = re.sub(r"^```(?:json)?", "", text.strip()).strip()
        cleaned = re.sub(r"```$", "", cleaned).strip()
        try:
            return json.loads(cleaned)
        except json.JSONDecodeError:
            match = re.search(r"\{.*\}", cleaned, flags=re.DOTALL)
            return json.loads(match.group(0)) if match else {}


post_healer = PostHealer()
