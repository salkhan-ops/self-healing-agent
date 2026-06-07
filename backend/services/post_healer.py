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
from config.llm import llm_generate_content
from backend.services.learning_memory import learning_memory
from backend.services.post_agent import post_agent
from backend.services.post_history_store import list_posts
from backend.services.post_scorer import INVENTION_PHRASES, post_scorer


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

    LOCAL_PATCH_CATEGORIES = {"INVENTED_METRICS", "UNSUPPORTED_SUPERLATIVES"}

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

        # Known failure patterns use deterministic prompt patches, so one
        # verification example is enough. Ambiguous Gemini rewrites still verify
        # a wider sample.
        verify_count = 1 if root_cause in self.LOCAL_PATCH_CATEGORIES else 3
        verification = self._verify(new_prompt, problematic[:verify_count])
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
        local_category, local_explanation = self._analyze_with_rules(traces)
        if local_category in self.LOCAL_PATCH_CATEGORIES:
            learning_memory.remember_patch(
                "posts", local_category, self._patch_for_category(local_category)
            )
            return local_category, local_explanation

        if genai is None or not GOOGLE_API_KEY:
            return local_category, local_explanation
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
        response = llm_generate_content(model, prompt, label="post_healer.analyze")
        parsed = self._parse_json(getattr(response, "text", ""))
        category = str(parsed.get("category") or "OTHER").strip().upper()
        explanation = str(parsed.get("explanation") or "").strip()
        if not explanation:
            explanation = "Generated posts added claims not supported by the source briefs."
        return category, explanation

    def _analyze_with_rules(self, traces: list[dict]) -> tuple[str, str]:
        if any(
            post_scorer._forbidden_term_count(  # noqa: SLF001 - shared scorer rule for local diagnosis.
                str(t.get("brief", "")),
                str(t.get("post", "")),
            )
            > 0
            for t in traces
        ):
            return (
                "INVENTED_METRICS",
                "Generated posts used claims the brief explicitly said were unavailable or unapproved.",
            )

        joined_posts = "\n".join(str(t.get("post", "")) for t in traces).lower()
        joined_briefs = "\n".join(str(t.get("brief", "")) for t in traces).lower()

        post_percentages = set(re.findall(r"\d+%|\d+(?:\.\d+)?x", joined_posts))
        brief_percentages = set(re.findall(r"\d+%|\d+(?:\.\d+)?x", joined_briefs))
        if post_percentages - brief_percentages:
            return (
                "INVENTED_METRICS",
                "Generated posts introduced metrics, percentages, or growth claims absent from the source brief.",
            )

        unsupported_hype = [
            phrase
            for phrase in INVENTION_PHRASES
            if phrase in joined_posts and phrase not in joined_briefs
        ]
        if unsupported_hype:
            return (
                "UNSUPPORTED_SUPERLATIVES",
                "Generated posts used unsupported hype/superlatives instead of staying factual.",
            )

        return (
            "OTHER",
            "Generated posts added claims not supported by the source briefs.",
        )

    def _rewrite_prompt(
        self,
        current_prompt: str,
        traces: list[dict],
        category: str,
        explanation: str,
    ) -> str:
        cached_patch = learning_memory.get_patch("posts", category)
        if cached_patch:
            return self._append_patch(current_prompt, cached_patch)

        if category in self.LOCAL_PATCH_CATEGORIES:
            patch = self._patch_for_category(category)
            learning_memory.remember_patch("posts", category, patch)
            return self._append_patch(current_prompt, patch)

        if genai is None or not GOOGLE_API_KEY:
            return self._append_patch(current_prompt, self._patch_for_category("OTHER"))
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
- It must explicitly forbid unsupported hype words such as "epic", "revolutionary", "monumental", "game-changing", "groundbreaking", and "transformative" unless those exact words appear in the raw brief.
- Prefer plain factual phrasing over promotional exaggeration when the brief is sparse.
- It may improve tone and wording without adding factual claims.
- It must be concise, production-ready, and written as direct instructions to the model.
- Return ONLY the new system prompt text.
""".strip()
        response = llm_generate_content(model, prompt, label="post_healer.rewrite_prompt")
        return getattr(response, "text", "").strip()

    def _patch_for_category(self, category: str) -> str:
        patches = {
            "INVENTED_METRICS": (
                "Learned rule: never invent metrics, percentages, revenue, growth rates, "
                "rankings, awards, customer counts, or team size. Use numbers only when "
                "the raw brief explicitly provides them."
            ),
            "UNSUPPORTED_SUPERLATIVES": (
                "Learned rule: do not use unsupported superlatives or hype words such as "
                "epic, revolutionary, monumental, explosive, game-changing, groundbreaking, "
                "or transformative unless the exact word appears in the raw brief. Prefer "
                "plain factual phrasing."
            ),
            "OTHER": (
                "Learned rule: every factual claim must be grounded in the raw brief. "
                "If the brief is sparse, write a concise factual post rather than adding claims."
            ),
        }
        return patches.get(category, patches["OTHER"])

    def _append_patch(self, current_prompt: str, patch: str) -> str:
        if patch.lower() in current_prompt.lower():
            retry_patch = (
                "High priority retry rule: previous learned constraints did not reduce "
                "hallucination enough. Override any earlier instruction to exaggerate, "
                "maximize engagement, use strong numbers, or add powerful superlatives. "
                "Generate only claims directly supported by the raw brief, and use a "
                "plain factual tone when the brief is sparse."
            )
            if retry_patch.lower() in current_prompt.lower():
                return current_prompt
            return f"{current_prompt.rstrip()}\n- {retry_patch}"
        return f"{current_prompt.rstrip()}\n\nLEARNED CONSTRAINTS:\n- {patch}"

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
