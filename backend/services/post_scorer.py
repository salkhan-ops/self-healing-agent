"""LLM-as-judge scorer for generated social media posts.

Asks Gemini to score each post for hallucination (invented facts not in the
brief) and relevance (post matches the brief's intent). Falls back to
rule-based scoring if Gemini fails.
"""

from __future__ import annotations

import json
import os
import re

INVENTION_PHRASES = [
    "%",
    "x growth",
    "epic",
    "revolutionary",
    "monumental",
    "game-changing",
    "groundbreaking",
    "transformative",
    "disrupting",
    "world-class",
    "industry-leading",
    "best-in-class",
    "unparalleled",
    "unprecedented",
    "crushing it",
    "massive",
    "explosive",
    "viral",
]

GROUNDED_PHRASES = [
    "excited for",
    "proud of",
    "grateful",
    "looking forward",
    "announced",
    "launched",
    "joined",
    "welcomed",
]


class PostScorer:
    """Score generated posts for hallucination and relevance."""

    def score(self, brief: str, post: str, prompt_version: int) -> dict[str, float]:
        """Score a generated post against its source brief."""
        rule_score = self._score_with_rules(brief, post)
        if self._rules_are_confident(rule_score):
            return rule_score

        try:
            return self._score_with_gemini(brief, post)
        except Exception as exc:
            print(f"⚠️ Post LLM scoring failed, using rules: {exc}")
            return rule_score

    def _score_with_gemini(self, brief: str, post: str) -> dict[str, float]:
        """Ask Gemini to judge the post against the brief."""
        import google.generativeai as genai

        api_key = os.getenv("GOOGLE_API_KEY", "")
        if not api_key:
            return self._score_with_rules(brief, post)

        genai.configure(api_key=api_key)
        judge = genai.GenerativeModel(model_name="gemini-2.5-flash")
        prompt = f"""
You are evaluating an AI-generated social media post.

SOURCE BRIEF (ground truth):
{brief}

GENERATED POST:
{post}

Score on two dimensions:

HALLUCINATION SCORE (0.0 to 1.0):
0.0 = every claim in the post is directly supported
      by the brief
0.5 = some claims are implied but not stated
1.0 = post invents specific numbers, percentages,
      superlatives, or facts not in the brief at all

Treat unsupported hype words as unsupported claims when they are not present
in the brief. Examples include "epic", "revolutionary", "monumental",
"game-changing", "groundbreaking", and "transformative".

RELEVANCE SCORE (0.0 to 1.0):
0.0 = post does not reflect the brief at all
0.5 = post captures some of the brief
1.0 = post accurately represents all key points
      in the brief

Return ONLY valid JSON, no other text:
{{"hallucination_score": 0.0, "relevance_score": 0.0}}
""".strip()

        response = judge.generate_content(prompt)
        text = getattr(response, "text", "").strip()
        text = re.sub(r"^```(?:json)?", "", text).strip()
        text = re.sub(r"```$", "", text).strip()
        parsed = json.loads(text)

        unsupported_hype_count = self._unsupported_hype_count(brief, post)
        judge_hallucination = float(max(0.0, min(1.0, parsed["hallucination_score"])))
        calibrated_hallucination = max(
            judge_hallucination,
            min(0.08 + unsupported_hype_count * 0.22, 0.95),
        )

        return {
            "hallucination_score": calibrated_hallucination,
            "relevance_score": float(max(0.0, min(1.0, parsed["relevance_score"]))),
            "latency_ms": 0.0,
        }

    def _score_with_rules(self, brief: str, post: str) -> dict[str, float]:
        """Rule-based fallback for invented facts and brief overlap."""
        post_lower = post.lower()
        brief_lower = brief.lower()
        invented = self._unsupported_hype_count(brief, post)

        percentages_in_post = re.findall(r"\d+%", post_lower)
        percentages_in_brief = re.findall(r"\d+%", brief_lower)
        invented_pct = len(set(percentages_in_post) - set(percentages_in_brief))
        invented += invented_pct * 2
        hallucination = min(0.08 + invented * 0.22, 0.95)

        brief_words = set(re.findall(r"[a-z0-9]+", brief_lower))
        post_words = set(re.findall(r"[a-z0-9]+", post_lower))
        stopwords = {
            "the",
            "a",
            "an",
            "is",
            "are",
            "we",
            "our",
            "to",
            "of",
            "and",
            "for",
            "in",
        }
        brief_words -= stopwords
        post_words -= stopwords

        if not brief_words:
            relevance = 0.5
        else:
            overlap = len(post_words & brief_words)
            relevance = min(overlap / len(brief_words) * 1.5, 1.0)

        return {
            "hallucination_score": round(hallucination, 3),
            "relevance_score": round(relevance, 3),
            "latency_ms": 0.0,
        }

    def _unsupported_hype_count(self, brief: str, post: str) -> int:
        """Count hype or invention phrases present only in the generated post."""
        brief_lower = brief.lower()
        post_lower = post.lower()
        return sum(
            1
            for phrase in INVENTION_PHRASES
            if phrase in post_lower and phrase not in brief_lower
        )

    def _rules_are_confident(self, score: dict[str, float]) -> bool:
        """Avoid LLM judging when cheap rules are already decisive."""
        hallucination = float(score.get("hallucination_score", 0.0))
        relevance = float(score.get("relevance_score", 0.0))
        clear_failure = hallucination >= 0.4
        clear_pass = hallucination <= 0.1 and relevance >= 0.9
        return clear_failure or clear_pass


post_scorer = PostScorer()
