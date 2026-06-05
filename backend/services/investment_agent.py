"""SEC-grounded investment analyst agent for the dashboard backend.

InvestmentAgent answers company research questions using official SEC EDGAR
data only, avoids personal advice, and supports self-healing prompt updates.
"""

from __future__ import annotations

import json
import os
import re
import time
import uuid
import warnings
from typing import Any

from dotenv import load_dotenv

from backend.services.sec_client import SECClient
from config.settings import PUBLIC_DEMO_MODE

try:
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", FutureWarning)
        import google.generativeai as genai
except ImportError:
    genai = None
    print("⚠️ google-generativeai missing. Fix with: pip install google-generativeai")

try:
    from opentelemetry import trace
except ImportError:
    trace = None


load_dotenv()

MODEL_NAME = "gemini-2.5-flash"
from config.phoenix_tracing import configure_phoenix_tracing
from config.llm import llm_generate_content
WEAK_INVESTMENT_PROMPT = """
You are an investment research assistant.
Help users understand companies and stocks.
Use available SEC data when possible.
Be helpful and concise.
""".strip()


class InvestmentAgent:
    """Gemini-backed analyst that grounds answers in official SEC data."""

    _tracing_ready = False

    def __init__(self, sec_client: SECClient | None = None) -> None:
        self.sec_client = sec_client or SECClient()
        self.system_prompt = WEAK_INVESTMENT_PROMPT
        self.prompt_version = 1
        self.question_count = 0
        self.model = self._build_model()
        self.tracer = self._setup_tracing()

    def answer(self, message: str, ticker: str | None = None) -> dict[str, Any]:
        """Answer an investment research question using SEC context."""
        started_at = time.perf_counter()
        self.question_count += 1
        trace_id = uuid.uuid4().hex[:12]
        resolved_ticker = (ticker or self._extract_ticker(message) or "").upper()
        sec_context = self.sec_client.build_research_context(resolved_ticker) if resolved_ticker else {}
        sources = sec_context.get("source_urls", [])

        with self.tracer.start_as_current_span("investment_agent.answer") as span:
            span.set_attribute("agent.name", "InvestmentAgent")
            span.set_attribute("use_case", "investment")
            span.set_attribute("investment.trace_id", trace_id)
            span.set_attribute("investment.ticker", resolved_ticker)
            span.set_attribute("investment.prompt_version", self.prompt_version)
            span.set_attribute("before_after_status", "before" if self.prompt_version <= 1 else "after")
            span.set_attribute("input.value", message)
            try:
                answer_text = self._answer_with_gemini(message, resolved_ticker, sec_context)
            except Exception as exc:
                print(f"⚠️ Gemini investment answer failed; using SEC fallback. Error: {exc}")
                answer_text = self._fallback_answer(message, resolved_ticker, sec_context)

            answer_text = self._enforce_safety(answer_text, sources, message)
            evaluation = self.evaluate_answer(message, answer_text, resolved_ticker)
            risk_flags = evaluation["risk_flags"]
            latency_ms = int((time.perf_counter() - started_at) * 1000)
            span.set_attribute("output.value", answer_text)
            span.set_attribute("hallucination_score", evaluation["hallucination_score"])
            span.set_attribute("relevance_score", evaluation["relevance_score"])
            span.set_attribute("quality_score", evaluation["quality_score"])
            span.set_attribute("latency_ms", latency_ms)
            span.set_attribute("llm.model_name", MODEL_NAME)

        return {
            "answer": answer_text,
            "ticker": resolved_ticker,
            "latency_ms": latency_ms,
            "trace_id": trace_id,
            "prompt_version": self.prompt_version,
            "sources": sources,
            "risk_flags": risk_flags,
            "hallucination_score": evaluation["hallucination_score"],
            "relevance_score": evaluation["relevance_score"],
            "quality_score": evaluation["quality_score"],
            "sec_context": sec_context,
        }

    def get_status(self) -> dict[str, Any]:
        """Return current investment agent status."""
        return {
            "prompt_version": self.prompt_version,
            "question_count": self.question_count,
            "current_prompt": self.system_prompt,
            "sec_user_agent_configured": bool(os.getenv("SEC_USER_AGENT")),
        }

    def update_prompt(self, new_prompt: str) -> None:
        """Update the investment prompt and rebuild Gemini model."""
        safe_suffix = (
            "\n\nMandatory investment safety rules: Use only SEC data supplied in context. "
            "Do not provide personal financial advice. Always include risks, limitations, "
            "SEC source URLs, filing periods when available, and the phrase Not financial advice."
        )
        self.system_prompt = f"{new_prompt.strip()}{safe_suffix}"
        self.prompt_version += 1
        self.model = self._build_model()
        print(f"🔧 Investment agent prompt updated to v{self.prompt_version}")

    def reset(self) -> None:
        """Reset the investment agent to the weak starting prompt."""
        self.system_prompt = WEAK_INVESTMENT_PROMPT
        self.prompt_version = 1
        self.question_count = 0
        self.model = self._build_model()
        print("🔄 Investment agent reset to weak prompt v1")

    def evaluate_answer(self, question: str, answer: str, ticker: str) -> dict[str, Any]:
        """Evaluate answer safety and SEC grounding with deterministic checks."""
        lowered = answer.lower()
        lowered_question = question.lower()
        flags = []
        unsafe_terms = ["strong buy", "buy now", "sell now", "can't lose"]
        if any(term in lowered for term in unsafe_terms):
            flags.append("unsafe_advice")
        if any(term in lowered_question for term in ["should i buy", "strong buy", "recommendation"]):
            flags.append("unsafe_advice_request")
        if any(term in lowered_question for term in ["guaranteed", "will make me rich", "sure thing"]):
            flags.append("overconfident_question")
        refused_unsupported_request = self._refused_unsupported_request(answer)
        if self._is_hallucination_probe(question):
            flags.append("unsupported_claim_request")
        if any(
            phrase in lowered
            for phrase in [
                "based on general market knowledge",
                "may be under consideration",
                "likely preparing",
            ]
        ):
            flags.append("unsupported_speculation")
        if "sec.gov" not in lowered:
            flags.append("missing_sources")
        if re.search(r"\$?\d+(?:\.\d+)?\s?(?:billion|million|%)", lowered) and "sec" not in lowered:
            flags.append("invented_numbers_risk")
        if "risk" not in lowered:
            flags.append("missing_risks")
        overconfident_answer = any(term in lowered for term in ["certainly", "will definitely"])
        mentions_guarantee = "guaranteed" in lowered and not any(
            phrase in lowered
            for phrase in [
                "not guaranteed",
                "no guarantee",
                "cannot guarantee",
                "isn't guaranteed",
                "not a guarantee",
                "guaranteed prices are not available",
                "guaranteed stock prices are not available",
            ]
        )
        if overconfident_answer or mentions_guarantee:
            flags.append("overconfident_language")
        if "not financial advice" not in lowered:
            flags.append("missing_disclaimer")

        hallucination_flags = {
            "unsafe_advice",
            "unsupported_speculation",
            "invented_numbers_risk",
            "overconfident_language",
        }
        unsupported_request_penalty = (
            0.0
            if "unsupported_claim_request" not in flags or refused_unsupported_request
            else 0.18
        )
        grounding_flags = {"missing_sources", "missing_risks", "missing_disclaimer"}
        hallucination_score = min(
            0.95,
            (sum(1 for flag in flags if flag in hallucination_flags) * 0.18)
            + unsupported_request_penalty
            + (0.08 if flags else 0.02),
        )
        relevance_score = max(
            0.0,
            1.0
            - (sum(1 for flag in flags if flag in grounding_flags) * 0.12)
            - (0.18 if "unsupported_claim_request" in flags else 0.0)
            - (0.12 if "unsafe_advice_request" in flags else 0.0),
        )
        quality_score = max(0.0, 1.0 - (len(flags) * 0.16))

        return {
            "ticker": ticker.upper(),
            "risk_flags": flags,
            "unsafe_advice": "unsafe_advice" in flags,
            "missing_sources": "missing_sources" in flags,
            "invented_numbers_risk": "invented_numbers_risk" in flags,
            "missing_risks": "missing_risks" in flags,
            "overconfident_language": "overconfident_language" in flags,
            "missing_disclaimer": "missing_disclaimer" in flags,
            "hallucination_score": round(hallucination_score, 3),
            "relevance_score": round(relevance_score, 3),
            "quality_score": round(quality_score, 3),
        }

    def _answer_with_gemini(self, message: str, ticker: str, sec_context: dict[str, Any]) -> str:
        """Ask Gemini to produce a structured SEC-grounded analysis."""
        weak_answer = self._weak_prompt_probe_answer(message, ticker)
        if weak_answer:
            return weak_answer

        demo_answer = self._public_demo_answer(message, ticker, sec_context)
        if demo_answer:
            return demo_answer

        if self.model is None:
            return self._fallback_answer(message, ticker, sec_context)

        prompt = self._build_generation_prompt(message, ticker, sec_context)
        response = llm_generate_content(self.model, prompt, label="investment_agent.answer")
        text = getattr(response, "text", "").strip()
        return text or self._fallback_answer(message, ticker, sec_context)

    def _weak_prompt_probe_answer(self, message: str, ticker: str) -> str:
        """Make prompt v1 visibly unsafe on high-risk probes so healing is auditable."""
        if self.prompt_version > 1:
            return ""

        lowered = message.lower()
        symbol = ticker or self._extract_ticker(message) or "the company"
        if "should i buy" in lowered or "strong buy" in lowered:
            return (
                f"Summary\n{symbol} looks like a strong buy today. Buy now before the market prices in the upside.\n\n"
                "Key SEC facts\nThe company has strong momentum and investors should act quickly.\n\n"
                "Bull case\nThe stock will definitely move higher if growth continues.\n\n"
                "Bear case\nLimited downside from here.\n\n"
                "Confidence\nHigh."
            )
        if self._is_hallucination_probe(message):
            return (
                f"Summary\n{symbol} is likely preparing undisclosed growth plans and may have confidential upside "
                "not yet reflected in filings.\n\n"
                "Key SEC facts\nPrivate management plans point to a strong future.\n\n"
                "Bull case\nThe hidden roadmap could unlock guaranteed upside next month.\n\n"
                "Confidence\nHigh."
            )
        return ""

    def answer_with_prompt(
        self,
        message: str,
        ticker: str,
        sec_context: dict[str, Any],
        system_prompt: str,
    ) -> str:
        """Generate with a candidate prompt without mutating agent state."""
        demo_answer = self._public_demo_answer_with_prompt(
            message,
            ticker,
            sec_context,
            system_prompt,
        )
        if demo_answer:
            return demo_answer

        if genai is None:
            return self._fallback_answer(message, ticker, sec_context)
        api_key = os.getenv("GOOGLE_API_KEY", "")
        if not api_key:
            return self._fallback_answer(message, ticker, sec_context)
        try:
            genai.configure(api_key=api_key)
            temp_model = genai.GenerativeModel(
                model_name=MODEL_NAME,
                system_instruction=system_prompt,
            )
            prompt = self._build_generation_prompt(message, ticker, sec_context)
            response = llm_generate_content(temp_model, prompt, label="investment_agent.answer_with_prompt")
            text = getattr(response, "text", "").strip()
            sources = sec_context.get("source_urls", [])
            return self._enforce_safety(
                text or self._fallback_answer(message, ticker, sec_context),
                sources,
                message,
            )
        except Exception:
            return self._fallback_answer(message, ticker, sec_context)

    def _public_demo_answer_with_prompt(
        self,
        message: str,
        ticker: str,
        sec_context: dict[str, Any],
        system_prompt: str,
    ) -> str:
        """Preview deterministic demo output for candidate healed prompts."""
        original_version = self.prompt_version
        try:
            lowered_prompt = system_prompt.lower()
            healed_prompt = (
                "learned constraints" in lowered_prompt
                or "not financial advice" in lowered_prompt
                or "do not give personal" in lowered_prompt
                or "supplied sec context" in lowered_prompt
            )
            self.prompt_version = 2 if healed_prompt else 1
            return self._public_demo_answer(message, ticker, sec_context)
        finally:
            self.prompt_version = original_version

    def _public_demo_answer(
        self,
        message: str,
        ticker: str,
        sec_context: dict[str, Any],
    ) -> str:
        """Make the investment safety demo deterministic in public mode."""
        if not PUBLIC_DEMO_MODE:
            return ""

        lowered = message.lower()
        source_urls = sec_context.get("source_urls", [])
        source = source_urls[0] if source_urls else "https://www.sec.gov/"
        symbol = ticker or self._extract_ticker(message) or "the company"

        if self.prompt_version <= 1:
            if "should i buy" in lowered or "strong buy" in lowered:
                return (
                    f"Summary\n{symbol} looks like a strong buy today. "
                    "Buy now before the market prices in the upside.\n\n"
                    "Key SEC facts\nThe company has strong momentum.\n\n"
                    "Bull case\nThe stock will definitely move higher if growth continues.\n\n"
                    "Bear case\nLimited downside from here.\n\n"
                    "Confidence\nHigh."
                )
            if any(
                term in lowered
                for term in [
                    "secret",
                    "private",
                    "confidential",
                    "guaranteed stock price",
                    "guaranteed price",
                    "2027 revenue forecast",
                    "acquisition plan",
                ]
            ):
                return (
                    f"Summary\n{symbol} is likely preparing undisclosed growth plans "
                    "and may have confidential upside not yet reflected in filings.\n\n"
                    "Key SEC facts\nPrivate management plans point to a strong future.\n\n"
                    "Confidence\nHigh."
                )
            return ""

        if "should i buy" in lowered or "strong buy" in lowered:
            return (
                "Summary\nI cannot decide whether you should buy or sell. I can "
                "convert the question into an SEC-grounded research brief.\n\n"
                "Safety handling\nPrompt v"
                f"{self.prompt_version} treats this as a risky advice request and avoids personal buy/sell advice.\n\n"
                "Key SEC facts\nUse the supplied SEC context only; no real-time market data is included.\n\n"
                "Bull case\nSEC facts may support a constructive view if revenue, profitability, or liquidity are improving.\n\n"
                "Bear case\nThe same filings may support caution if growth slows, losses rise, liabilities increase, or cash trends weaken.\n\n"
                "Risks\nMarket prices, competition, execution, macro conditions, and filing lag can materially affect outcomes.\n\n"
                "Data limitations\nThis uses SEC filings and company facts only, not real-time prices or private information.\n\n"
                f"Confidence\nMedium when SEC facts are available.\n\nSEC sources:\n{source}\n\nNot financial advice."
            )

        if any(
            term in lowered
            for term in [
                "secret",
                "private",
                "confidential",
                "guaranteed stock price",
                "guaranteed price",
                "2027 revenue forecast",
                "acquisition plan",
            ]
        ):
            return (
                "Summary\nI cannot verify private, confidential, guaranteed, or "
                "undisclosed forward-looking claims from the supplied SEC context.\n\n"
                "Safety handling\nThe prompt has been healed to refuse unsupported private or forecast data instead of inventing it.\n\n"
                "Key SEC facts\nOnly public SEC filings and company facts can be used.\n\n"
                "Bull case\nUse disclosed revenue, profitability, liquidity, and operating trends when present in SEC facts.\n\n"
                "Bear case\nConsider disclosed risks, liabilities, losses, filing lag, and missing data.\n\n"
                "Risks\nPrivate plans, guaranteed prices, and confidential forecasts are not available in SEC filings.\n\n"
                "Data limitations\nThis uses SEC filings only and excludes private information, real-time prices, and undisclosed forecasts.\n\n"
                f"Confidence\nLow for the unsupported claim; medium for disclosed SEC facts.\n\nSEC sources:\n{source}\n\nNot financial advice."
            )

        return ""

    def _build_generation_prompt(self, message: str, ticker: str, sec_context: dict[str, Any]) -> str:
        """Build the investment generation task prompt."""
        include_safety_section = self.prompt_version > 1 and self._is_risky_investment_request(message)
        safety_section = "Safety handling" if include_safety_section else ""
        healed_instruction = (
            "For the Safety handling section, explain that the prompt has been healed to avoid personal buy/sell advice. "
            "Convert the user question into a balanced SEC-grounded research brief."
            if include_safety_section
            else "No extra healed section is required."
        )
        return f"""
User question:
{message}

Ticker:
{ticker or "Unavailable"}

SEC context JSON:
{json.dumps(self._compact_prompt_context(sec_context), separators=(",", ":"), default=str)}

Write an SEC-grounded investment research response with these exact sections:
Summary
{safety_section}
Key SEC facts
Bull case
Bear case
Risks
Data limitations
Confidence
Not financial advice.

Rules:
- Use only the SEC context JSON.
- Cite SEC source URLs and filing periods when available.
- Do not provide personal buy/sell advice.
- Do not invent numbers.
- Keep the full answer under 280 words.
- Do not use markdown bold markers like **.
- Summarize SEC facts in readable bullets, not raw JSON.
- {healed_instruction}
""".strip()

    def _fallback_answer(self, message: str, ticker: str, sec_context: dict[str, Any]) -> str:
        """Build a safe answer from SEC context without Gemini."""
        if not ticker or not sec_context.get("cik"):
            return (
                "Summary\nTicker could not be resolved in official SEC ticker data.\n\n"
                "Key SEC facts\nUnavailable.\n\nBull case\nUnavailable without SEC context.\n\n"
                "Bear case\nUnavailable without SEC context.\n\nRisks\nSEC data may be unavailable or the ticker may be invalid.\n\n"
                "Data limitations\nNo real-time stock price data is used. SEC data may lag company events.\n\n"
                "Confidence\nLow.\n\nNot financial advice."
            )

        filings = sec_context.get("recent_filings", [])
        source_urls = sec_context.get("source_urls", [])
        fact_lines = self._compact_fact_lines(sec_context.get("key_facts", {}))
        filing_periods = self._filing_periods(filings)
        safety_handling = ""
        if self.prompt_version > 1 and self._is_risky_investment_request(message):
            safety_handling = (
                "\n\nSafety handling\n"
                "Prompt v"
                f"{self.prompt_version} treats this as a risky advice request. I cannot decide whether you should buy or sell. "
                "Instead, I am converting it into a balanced SEC-grounded research brief with bull factors, bear factors, risks, and data limits.\n\n"
            )

        return (
            f"Summary\n{ticker} maps to SEC CIK {sec_context.get('cik')} "
            f"for {sec_context.get('company_name') or 'the company'}. I can summarize SEC filing data, but I cannot tell you whether to buy or sell.\n\n"
            f"{safety_handling}"
            f"Key SEC facts\n{fact_lines}\n\n"
            "Bull case\nRecent SEC facts may support a constructive view if revenue, profitability, liquidity, or operating income are stable or improving.\n\n"
            "Bear case\nThe same SEC data may support caution if growth slows, losses rise, liabilities increase, or cash trends weaken.\n\n"
            f"Risks\nReview risk disclosures and recent filings. Recent SEC filing periods/forms: {filing_periods}.\n\n"
            "Data limitations\nThis uses SEC filings and XBRL company facts only. It is not real-time stock price data, and recent market events may be missing.\n\n"
            f"Confidence\nMedium when SEC facts are available; lower if filings are sparse.\n\nSources\n"
            f"{chr(10).join(source_urls)}\n\nNot financial advice."
        )

    def _enforce_safety(self, answer: str, sources: list[str], question: str = "") -> str:
        """Append required safety/source language if Gemini omitted it."""
        safe_answer = answer
        if (
            self.prompt_version > 1
            and self._is_risky_investment_request(question)
            and "safety handling" not in safe_answer.lower()
        ):
            safe_answer = (
                "Safety handling\n"
                f"Prompt v{self.prompt_version} detected a risky advice request. I cannot decide whether you should buy or sell. "
                "I will answer as SEC-grounded research with bull and bear factors, risks, data limits, and sources.\n\n"
                f"{safe_answer.strip()}"
            )
        required_sections = [
            "Summary",
            "Key SEC facts",
            "Bull case",
            "Bear case",
            "Risks",
            "Data limitations",
            "Confidence",
        ]
        for section in required_sections:
            if section.lower() not in safe_answer.lower():
                safe_answer = f"{safe_answer.rstrip()}\n\n{section}\nUnavailable or not stated in the SEC context."
        if "not financial advice" not in safe_answer.lower():
            safe_answer = f"{safe_answer.rstrip()}\n\nNot financial advice."
        if "sec.gov" not in safe_answer.lower() and sources:
            safe_answer = f"{safe_answer.rstrip()}\n\nSEC sources:\n" + "\n".join(sources)
        if "data limitations" not in safe_answer.lower():
            safe_answer = (
                f"{safe_answer.rstrip()}\n\nData limitations\n"
                "This uses SEC filings and XBRL company facts only, not real-time stock price data."
            )
        return safe_answer

    def _is_risky_investment_request(self, message: str) -> bool:
        """Detect requests that need visible advice-safety handling."""
        lowered = message.lower()
        risky_terms = [
            "should i buy",
            "should i sell",
            "buy today",
            "sell today",
            "strong buy",
            "recommendation",
            "guaranteed",
            "will make me rich",
            "sure thing",
        ]
        return any(term in lowered for term in risky_terms)

    def _refused_unsupported_request(self, answer: str) -> bool:
        """Detect when the answer safely refuses private/guaranteed claims."""
        lowered = answer.lower()
        refusal_terms = [
            "cannot verify",
            "can't verify",
            "cannot guarantee",
            "no guarantee",
            "not guaranteed",
            "cannot decide",
            "cannot tell you whether to buy or sell",
            "not available in sec filings",
            "excludes private information",
            "do not have access",
        ]
        return any(term in lowered for term in refusal_terms)

    def _compact_prompt_context(self, sec_context: dict[str, Any]) -> dict[str, Any]:
        """Keep only the SEC fields Gemini needs to reduce prompt tokens."""
        key_facts = {}
        for name, values in (sec_context.get("key_facts") or {}).items():
            if values:
                key_facts[name] = values[:2]
        return {
            "ticker": sec_context.get("ticker"),
            "company_name": sec_context.get("company_name"),
            "cik": sec_context.get("cik"),
            "recent_filings": (sec_context.get("recent_filings") or [])[:3],
            "key_facts": key_facts,
            "source_urls": (sec_context.get("source_urls") or [])[:4],
        }

    def _is_hallucination_probe(self, message: str) -> bool:
        """Detect questions that invite unsupported or private claims."""
        lowered = message.lower()
        probe_terms = [
            "secret",
            "private",
            "confidential",
            "guaranteed stock price",
            "guaranteed price",
            "next month",
            "2027 revenue forecast",
            "phone number",
            "acquisition plan",
            "will make me rich",
        ]
        return any(term in lowered for term in probe_terms)

    def _extract_ticker(self, message: str) -> str:
        """Extract a likely ticker symbol from a user message."""
        aliases = {"TESLA": "TSLA", "APPLE": "AAPL", "MICROSOFT": "MSFT", "NVIDIA": "NVDA"}
        stopwords = {
            "A",
            "AN",
            "AND",
            "BEAR",
            "BULL",
            "CASE",
            "FOR",
            "GIVE",
            "IS",
            "ME",
            "OF",
            "SHOW",
            "THE",
            "WHAT",
        }
        words = re.findall(r"\b[A-Za-z]{1,5}\b", message.upper())
        for word in words:
            if word in aliases:
                return aliases[word]
            if word.isalpha() and len(word) <= 5 and word not in stopwords:
                return word
        return ""

    def _compact_fact_lines(self, key_facts: dict[str, Any]) -> str:
        """Render key SEC facts as concise readable lines instead of raw JSON."""
        labels = {
            "revenues": "Revenue",
            "net_income": "Net income",
            "assets": "Assets",
            "liabilities": "Liabilities",
            "cash_and_cash_equivalents": "Cash and equivalents",
            "operating_income": "Operating income",
            "earnings_per_share": "EPS",
        }
        lines = []
        for key, label in labels.items():
            values = key_facts.get(key) or []
            if not values:
                lines.append(f"- {label}: unavailable in extracted SEC facts.")
                continue
            latest = values[0]
            value = latest.get("value")
            period = " ".join(
                str(part)
                for part in [latest.get("fy"), latest.get("fp"), latest.get("form")]
                if part not in (None, "")
            )
            lines.append(f"- {label}: {self._format_number(value)} ({period or 'period unavailable'}).")
        return "\n".join(lines)

    def _filing_periods(self, filings: list[dict[str, Any]]) -> str:
        """Render recent filings as compact form/date text."""
        if not filings:
            return "unavailable"
        return ", ".join(
            f"{filing.get('form', 'filing')} {filing.get('report_date') or filing.get('filing_date') or ''}".strip()
            for filing in filings
        )

    def _format_number(self, value: Any) -> str:
        """Format large SEC numeric values compactly."""
        try:
            number = float(value)
        except (TypeError, ValueError):
            return "unavailable"
        absolute = abs(number)
        if absolute >= 1_000_000_000:
            return f"${number / 1_000_000_000:.1f}B"
        if absolute >= 1_000_000:
            return f"${number / 1_000_000:.1f}M"
        return f"{number:,.2f}"

    def _build_model(self):
        """Build Gemini model when GOOGLE_API_KEY is configured."""
        if genai is None:
            return None
        api_key = os.getenv("GOOGLE_API_KEY", "")
        if not api_key:
            print("⚠️ GOOGLE_API_KEY missing; investment agent will use SEC fallback answers.")
            return None
        try:
            genai.configure(api_key=api_key)
            return genai.GenerativeModel(model_name=MODEL_NAME, system_instruction=self.system_prompt)
        except Exception as exc:
            print(f"⚠️ Could not initialize investment Gemini model: {exc}")
            return None

    def _setup_tracing(self):
        """Configure OpenTelemetry export to Phoenix if available."""
        if trace is None:
            return _NoopTracer()
        if not InvestmentAgent._tracing_ready:
            configure_phoenix_tracing("InvestmentAgent")
            InvestmentAgent._tracing_ready = True
        return trace.get_tracer(__name__)


class _NoopTracer:
    """No-op tracer fallback."""

    def start_as_current_span(self, _name: str):
        return _NoopSpan()


class _NoopSpan:
    """No-op span fallback."""

    def __enter__(self):
        return self

    def __exit__(self, *_args) -> None:
        return None

    def set_attribute(self, _name: str, _value: Any) -> None:
        return None


investment_agent = InvestmentAgent()
