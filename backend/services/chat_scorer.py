"""Gemini-backed scorer for chat agent answers with rule-based fallback."""

from __future__ import annotations

import re
from pathlib import Path

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

    def __init__(self) -> None:
        self.faq_text = self._load_faq()
        self.faq_words = self._extract_faq_words()

    def score(
        self, question: str, answer: str, prompt_version: int
    ) -> dict[str, float]:
        """
        Score answer using Gemini as judge.
        Falls back to rule-based scoring if Gemini fails.
        """
        try:
            return self._score_with_gemini(question, answer)
        except Exception as exc:
            print(f"⚠️ LLM scoring failed, using rules: {exc}")
            return self._score_with_rules(answer)

    def _score_with_gemini(self, question: str, answer: str) -> dict[str, float]:
        """Ask Gemini to score the answer as a judge."""
        import json
        import os

        import google.generativeai as genai

        api_key = os.getenv("GOOGLE_API_KEY", "")
        if not api_key:
            return self._score_with_rules(answer)

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

        response = judge.generate_content(prompt)
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

    def _score_with_rules(self, answer: str) -> dict[str, float]:
        """Fallback rule-based scoring when Gemini is unavailable."""
        answer_lower = answer.lower()

        for phrase in self.GROUNDED_PHRASES:
            if phrase in answer_lower:
                return {
                    "hallucination_score": 0.05,
                    "relevance_score": 0.75,
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
