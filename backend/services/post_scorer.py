"""LLM-as-judge scorer for generated social media posts.

Asks Gemini to score each post for hallucination (invented facts not in the
brief) and relevance (post matches the brief's intent). Falls back to
rule-based scoring if Gemini fails.
"""

from __future__ import annotations

import json
import os
import re

from config.llm import llm_generate_content

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
    "elite",
    "powerhouse",
    "supercharge",
    "rapid growth",
    "thunderclap",
    "industry-wide movement",
    "record-breaking",
    "breakout quarter",
    "world-class",
    "industry-leading",
    "best-in-class",
    "unparalleled",
    "unprecedented",
    "crushing it",
    "massive",
    "explosive",
    "viral",
    "keynote",
    "fortune 500",
    "market share",
    "arr",
    "valuation",
    "funding round",
    "conversion rate",
    "patient outcomes",
    "clinical approvals",
    "signed enterprise contracts",
    "roi",
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

        response = llm_generate_content(judge, prompt, label="post_scorer.score")
        text = getattr(response, "text", "").strip()
        text = re.sub(r"^```(?:json)?", "", text).strip()
        text = re.sub(r"```$", "", text).strip()
        parsed = json.loads(text)

        unsupported_hype_count = self._unsupported_hype_count(brief, post)
        judge_hallucination = float(max(0.0, min(1.0, parsed["hallucination_score"])))
        rule_hallucination = self._hallucination_from_count(unsupported_hype_count)
        calibrated_hallucination = max(judge_hallucination, rule_hallucination)

        return {
            "hallucination_score": calibrated_hallucination,
            "relevance_score": float(max(0.0, min(1.0, parsed["relevance_score"]))),
            "latency_ms": 0.0,
        }

    def _score_with_rules(self, brief: str, post: str) -> dict[str, float]:
        """Rule-based fallback for invented facts and brief overlap."""
        post_lower = post.lower().replace("-", " ")
        brief_lower = brief.lower().replace("-", " ")
        invented = self._unsupported_hype_count(brief, post)
        invented += self._forbidden_term_count(brief, post)

        percentages_in_post = re.findall(r"\d+%", post_lower)
        percentages_in_brief = re.findall(r"\d+%", brief_lower)
        invented_pct = len(set(percentages_in_post) - set(percentages_in_brief))
        invented += invented_pct * 2

        expansion_claims = re.findall(r"\b\d+(?:\.\d+)?x\b", post_lower)
        expansion_claims_in_brief = re.findall(r"\b\d+(?:\.\d+)?x\b", brief_lower)
        invented += len(set(expansion_claims) - set(expansion_claims_in_brief)) * 2

        hallucination = self._hallucination_from_count(invented)

        relevance_brief = self._brief_text_for_relevance(brief_lower)
        brief_words = set(re.findall(r"[a-z0-9]+", relevance_brief))
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
        brief_lower = brief.lower().replace("-", " ")
        post_lower = post.lower().replace("-", " ")
        return sum(
            1
            for phrase in INVENTION_PHRASES
            if phrase in post_lower and phrase not in brief_lower
        )

    def _forbidden_term_count(self, brief: str, post: str) -> int:
        """Count terms the brief explicitly says are unavailable or forbidden."""
        brief_lower = brief.lower().replace("-", " ")
        post_lower = post.lower().replace("-", " ")
        forbidden_terms = [
            "revenue",
            "market share",
            "fortune 500",
            "growth percentage",
            "growth percentages",
            "arr",
            "conversion rate",
            "customer names",
            "funding round",
            "valuation",
            "patient outcomes",
            "accuracy metrics",
            "clinical approvals",
            "benchmark",
            "signed enterprise contracts",
            "roi",
        ]
        count = 0
        for term in forbidden_terms:
            if term not in post_lower:
                continue
            term_is_negated_in_post = any(
                term in sentence
                and any(
                    marker in sentence
                    for marker in [
                        "avoid",
                        "avoiding",
                        "unapproved",
                        "not sharing",
                        "not making",
                        "not make",
                        "will not",
                        "cannot",
                        "no ",
                    ]
                )
                for sentence in re.split(r"(?<=[.!?])\s+", post_lower)
            )
            brief_forbids_term = (
                f"no {term}" in brief_lower
                or f"not add {term}" in brief_lower
                or f"not approved" in brief_lower and term in brief_lower
                or f"not disclosed" in brief_lower and term in brief_lower
                or f"not measured" in brief_lower and term in brief_lower
                or f"not been measured" in brief_lower and term in brief_lower
            )
            post_negates_term = (
                f"no {term}" in post_lower
                or f"not {term}" in post_lower
                or f"{term} not" in post_lower
                or f"{term} is not" in post_lower
                or f"unapproved {term}" in post_lower
                or term_is_negated_in_post
            )
            if brief_forbids_term and not post_negates_term:
                count += 2
        return count

    def _hallucination_from_count(self, invented: int) -> float:
        """Return 0.0 for clean posts so the UI does not imply tiny healing risk."""
        if invented <= 0:
            return 0.0
        return min(0.08 + invented * 0.22, 0.95)

    def _brief_text_for_relevance(self, brief_lower: str) -> str:
        """Remove safety instructions so relevance measures the actual update."""
        sentences = re.split(r"(?<=[.!?])\s+", brief_lower)
        keep = [
            sentence
            for sentence in sentences
            if not any(
                marker in sentence
                for marker in [
                    "do not add",
                    " not add ",
                    "no ",
                    "not approved",
                    "not disclosed",
                    "not measured",
                    "not been measured",
                ]
            )
        ]
        return " ".join(keep) if keep else brief_lower

    def _rules_are_confident(self, score: dict[str, float]) -> bool:
        """Avoid LLM judging when cheap rules are already decisive."""
        hallucination = float(score.get("hallucination_score", 0.0))
        relevance = float(score.get("relevance_score", 0.0))
        clear_failure = hallucination >= 0.4
        clear_pass = hallucination <= 0.1 and relevance >= 0.9
        return clear_failure or clear_pass


post_scorer = PostScorer()
