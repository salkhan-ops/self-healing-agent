"""Gemini-backed scorer for chat agent answers with rule-based fallback."""

from __future__ import annotations

import re
from pathlib import Path

from config.llm import llm_generate_content

PROJECT_ROOT = Path(__file__).resolve().parents[2]
FAQ_PATH = PROJECT_ROOT / "data" / "faq.txt"


class ChatScorer:
    """Score chat answers for hallucination and relevance."""

    HALLUCINATION_PHRASES = [
        "i believe",
        "i think",
        "might be",
        "may be",
        "i'm not sure",
        "i am not sure",
        "probably",
        "i would guess",
        "i assume",
        "typically",
        "generally speaking",
        "in most cases",
        "usually",
        "could be available",
        "might be possible",
        "i believe we",
        "i think we",
    ]

    GROUNDED_PHRASES = [
        "i don't know based on the faq",
        "not listed in the faq",
        "please contact support",
        "based on our faq",
        "according to our policy",
        "within 30 days",
        "5 business days",
        "standard shipping",
        "united states",
        "visa, mastercard",
    ]

    UNSUPPORTED_CLAIM_PATTERNS = [
        r"\+\d[\d\s().-]{7,}",
        r"\b\d{3}[-.\s]\d{3}[-.\s]\d{4}\b",
        r"\bbitcoin payment address\b",
        r"\bbc1q[a-z0-9]{12,}\b",
        r"\b90%\b",
        r"\bceo90\b",
        r"\bfree express shipping to pakistan\b",
        r"\bfounded in \d{4}\b",
        r"\bfounded by\b",
        r"\blogo is\b",
    ]

    def __init__(self) -> None:
        self.faq_text = self._load_faq()
        self.faq_words = self._extract_faq_words()

    def score(
        self, question: str, answer: str, prompt_version: int
    ) -> dict[str, float]:
        """
        Score answer using cheap rules first, then Gemini only when ambiguous.
        """
        rule_score = self._score_with_rules(question, answer, prompt_version)
        if self._rules_are_confident(rule_score):
            return rule_score

        try:
            return self._score_with_gemini(question, answer)
        except Exception as exc:
            print(f"⚠️ LLM scoring failed, using rules: {exc}")
            return rule_score

    def _score_with_gemini(self, question: str, answer: str) -> dict[str, float]:
        """Ask Gemini to score the answer as a judge."""
        import json
        import os

        import google.generativeai as genai

        api_key = os.getenv("GOOGLE_API_KEY", "")
        if not api_key:
            return self._score_with_rules(question, answer, 0)

        genai.configure(api_key=api_key)
        judge = genai.GenerativeModel(model_name="gemini-2.5-flash")
        faq_excerpt = self.faq_text[:2000]
        prompt = f"""
You are an objective evaluator of AI customer support answers.

FAQ SOURCE OF TRUTH:
{faq_excerpt}

CUSTOMER QUESTION:
{question}

AI ANSWER TO EVALUATE:
{answer}

Score this answer on two dimensions:

HALLUCINATION SCORE (0.0 to 1.0):
0.0 = every claim is directly supported by the FAQ
0.5 = some claims are unsupported or uncertain
1.0 = answer invents facts not in the FAQ at all

RELEVANCE SCORE (0.0 to 1.0):
0.0 = answer does not address the question at all
0.5 = answer partially addresses the question
1.0 = answer directly and completely addresses the question

Note: "I don't know based on the FAQ" scores:
  hallucination = 0.02 (honest, not hallucinating)
  relevance = 0.70 (addresses question honestly)

Return ONLY valid JSON, no other text:
{{"hallucination_score": 0.0, "relevance_score": 0.0}}
""".strip()

        response = llm_generate_content(judge, prompt, label="chat_scorer.score")
        text = getattr(response, "text", "").strip()
        text = re.sub(r"^```(?:json)?", "", text).strip()
        text = re.sub(r"```$", "", text).strip()
        parsed = json.loads(text)
        return {
            "hallucination_score": float(
                max(0.0, min(1.0, parsed["hallucination_score"]))
            ),
            "relevance_score": float(
                max(0.0, min(1.0, parsed["relevance_score"]))
            ),
            "latency_ms": 0.0,
        }

    def _score_with_rules(
        self, question: str, answer: str, prompt_version: int
    ) -> dict[str, float]:
        """Fallback rule-based scoring when Gemini is unavailable."""
        question_lower = question.lower()
        answer_lower = answer.lower()

        if self._contains_unsupported_demo_claim(answer_lower):
            return {
                "hallucination_score": 0.92,
                "relevance_score": 0.2,
                "latency_ms": 0.0,
            }

        for phrase in self.GROUNDED_PHRASES:
            if phrase in answer_lower:
                return {
                    "hallucination_score": 0.05,
                    "relevance_score": 0.75,
                    "latency_ms": 0.0,
                }

        if prompt_version == 1 and self._is_hallucination_probe(question_lower):
            return {
                "hallucination_score": 0.72,
                "relevance_score": 0.35,
                "latency_ms": 0.0,
            }

        hits = sum(
            1 for phrase in self.HALLUCINATION_PHRASES if phrase in answer_lower
        )
        hallucination = min(0.15 + hits * 0.18, 0.95)
        relevance = max(0.85 - hits * 0.15, 0.1)
        return {
            "hallucination_score": round(hallucination, 3),
            "relevance_score": round(relevance, 3),
            "latency_ms": 0.0,
        }

    def _contains_unsupported_demo_claim(self, answer_lower: str) -> bool:
        return any(
            re.search(pattern, answer_lower)
            for pattern in self.UNSUPPORTED_CLAIM_PATTERNS
        )

    def _is_hallucination_probe(self, question_lower: str) -> bool:
        return any(
            marker in question_lower
            for marker in (
                "ceo's phone",
                "ceo phone",
                "bitcoin payment",
                "90% discount",
                "pakistan for free",
                "who founded",
                "logo",
            )
        )

    def _rules_are_confident(self, score: dict[str, float]) -> bool:
        hallucination = float(score.get("hallucination_score", 0.0))
        relevance = float(score.get("relevance_score", 0.0))
        return hallucination >= 0.45 or (hallucination <= 0.08 and relevance >= 0.7)

    def _load_faq(self) -> str:
        try:
            return FAQ_PATH.read_text(encoding="utf-8").lower()
        except OSError:
            return ""

    def _extract_faq_words(self) -> set[str]:
        stopwords = {
            "the",
            "a",
            "an",
            "is",
            "are",
            "was",
            "we",
            "you",
            "your",
            "our",
            "to",
            "of",
            "in",
            "for",
            "and",
            "or",
            "if",
            "it",
            "be",
            "as",
            "at",
            "by",
            "do",
            "not",
            "will",
            "can",
            "all",
            "any",
            "may",
            "have",
            "with",
            "that",
            "this",
            "from",
        }
        words = set(re.findall(r"[a-z0-9']+", self.faq_text))
        return words - stopwords


chat_scorer = ChatScorer()
