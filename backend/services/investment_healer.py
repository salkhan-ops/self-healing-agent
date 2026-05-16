"""Real self-healing loop for the SEC-grounded investment analyst."""

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
from backend.services.investment_agent import investment_agent
from backend.services.investment_history_store import list_investment_entries


@dataclass
class InvestmentHealingResult:
    old_prompt: str
    new_prompt: str
    root_cause: str
    root_cause_explanation: str
    before_scores: dict[str, float]
    after_scores: dict[str, float]
    verification_traces: list[dict[str, Any]]


class InvestmentHealer:
    """Diagnose and improve the investment agent from its own bad answers."""

    def heal_recent_answers(self) -> InvestmentHealingResult | None:
        history = list_investment_entries(limit=12)
        problematic = [item for item in history if item.get("risk_flags")]
        if not problematic:
            return None
        old_prompt = investment_agent.system_prompt
        category, explanation = self._analyze(problematic)
        new_prompt = self._rewrite_prompt(old_prompt, problematic, category, explanation)
        if not new_prompt or new_prompt.strip() == old_prompt.strip():
            return None
        verification = self._verify(new_prompt, problematic[:3])
        return InvestmentHealingResult(
            old_prompt=old_prompt,
            new_prompt=new_prompt,
            root_cause=category,
            root_cause_explanation=explanation,
            before_scores=self._average_scores(problematic[:3]),
            after_scores=self._average_scores(verification),
            verification_traces=verification,
        )

    def _analyze(self, traces: list[dict]) -> tuple[str, str]:
        model = self._model()
        prompt = f"""
You are diagnosing failures in an SEC-grounded investment analyst.

Each trace includes the user question, generated answer, SEC-derived risk flags, and quality score:
{json.dumps(traces, indent=2, default=str)}

Choose the dominant failure category from:
- UNSUPPORTED_SPECULATION
- UNSAFE_ADVICE
- MISSING_GROUNDING
- MISSING_DISCLOSURE
- OTHER

Return ONLY JSON:
{{"category": "UNSUPPORTED_SPECULATION", "explanation": "Short trace-grounded explanation."}}
""".strip()
        parsed = self._parse_json(getattr(model.generate_content(prompt), "text", ""))
        category = str(parsed.get("category") or "OTHER").strip().upper()
        explanation = str(parsed.get("explanation") or "").strip()
        return category, explanation or "Answers violated SEC-grounding or investment-safety constraints."

    def _rewrite_prompt(self, current_prompt: str, traces: list[dict], category: str, explanation: str) -> str:
        model = self._model()
        prompt = f"""
Rewrite this INVESTMENT ANALYST system prompt to fix the observed failures.

Current prompt:
{current_prompt}

Root cause category: {category}
Root cause explanation: {explanation}

Failed examples:
{json.dumps(traces, indent=2, default=str)}

Requirements:
- It must remain an SEC-grounded investment analyst prompt, not customer support.
- It must use only supplied SEC context for factual claims.
- It must forbid unsupported speculation, private/confidential claims, guarantees, and personal buy/sell advice.
- It must require balanced bull case, bear case, risks, data limitations, SEC sources, and "Not financial advice."
- It must be concise and production-ready.
- Return ONLY the new system prompt text.
""".strip()
        return getattr(model.generate_content(prompt), "text", "").strip()

    def _verify(self, candidate_prompt: str, examples: list[dict]) -> list[dict[str, Any]]:
        traces: list[dict[str, Any]] = []
        for item in examples:
            question = str(item.get("question", ""))
            ticker = str(item.get("ticker", ""))
            sec_context = item.get("sec_context") or {}
            answer = investment_agent.answer_with_prompt(question, ticker, sec_context, candidate_prompt)
            evaluation = investment_agent.evaluate_answer(question, answer, ticker)
            traces.append({
                "question": question,
                "ticker": ticker,
                "answer": answer,
                "risk_flags": evaluation["risk_flags"],
                "quality_score": evaluation["quality_score"],
            })
        return traces

    def _average_scores(self, traces: list[dict]) -> dict[str, float]:
        if not traces:
            return {"quality_score": 0.0, "risk_flag_count": 0.0}
        return {
            "quality_score": sum(float(t.get("quality_score", 0.0)) for t in traces) / len(traces),
            "risk_flag_count": sum(len(t.get("risk_flags", [])) for t in traces) / len(traces),
        }

    def _model(self):
        if genai is None or not GOOGLE_API_KEY:
            raise RuntimeError("Gemini is required for real investment healing")
        genai.configure(api_key=GOOGLE_API_KEY)
        return genai.GenerativeModel(model_name="gemini-2.5-flash")

    def _parse_json(self, text: str) -> dict[str, Any]:
        cleaned = re.sub(r"^```(?:json)?", "", text.strip()).strip()
        cleaned = re.sub(r"```$", "", cleaned).strip()
        try:
            return json.loads(cleaned)
        except json.JSONDecodeError:
            match = re.search(r"\{.*\}", cleaned, flags=re.DOTALL)
            return json.loads(match.group(0)) if match else {}


investment_healer = InvestmentHealer()
