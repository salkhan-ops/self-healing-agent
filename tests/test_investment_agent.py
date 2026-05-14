"""Tests for the SEC-grounded investment agent.

The tests use fallback behavior and do not require Gemini, Phoenix, or live SEC
network availability.
"""

from __future__ import annotations

from backend.services.investment_agent import InvestmentAgent
from backend.services.sec_client import SECClient


class FakeSECClient(SECClient):
    """Small SEC client stub for offline investment-agent tests."""

    def __init__(self, tmp_path):
        super().__init__(cache_dir=tmp_path)

    def build_research_context(self, ticker: str) -> dict:
        return {
            "ticker": ticker.upper(),
            "cik": "0000320193",
            "company_name": "Apple Inc.",
            "sic": "3571",
            "fiscal_year_end": "0927",
            "recent_filings": [{"form": "10-K", "report_date": "2024-09-28"}],
            "key_facts": {"revenues": [{"value": 1, "fy": 2024, "form": "10-K"}]},
            "source_urls": ["https://data.sec.gov/submissions/CIK0000320193.json"],
        }


def test_investment_agent_initializes(tmp_path) -> None:
    """InvestmentAgent should initialize with prompt version 1."""
    agent = InvestmentAgent(sec_client=FakeSECClient(tmp_path))

    assert agent.prompt_version == 1


def test_answer_returns_dict(tmp_path) -> None:
    """answer() should return the required dictionary shape without Gemini."""
    agent = InvestmentAgent(sec_client=FakeSECClient(tmp_path))
    agent.model = None

    result = agent.answer("Analyze AAPL", "AAPL")

    assert isinstance(result, dict)
    assert result["ticker"] == "AAPL"
    assert "Not financial advice" in result["answer"]


def test_evaluate_answer_flags_strong_buy(tmp_path) -> None:
    """Evaluator should flag unsafe direct advice."""
    agent = InvestmentAgent(sec_client=FakeSECClient(tmp_path))

    result = agent.evaluate_answer("Analyze AAPL", "This is a strong buy.", "AAPL")

    assert "unsafe_advice" in result["risk_flags"]


def test_evaluate_answer_flags_risky_question_intent(tmp_path) -> None:
    """Evaluator should flag risky user intent even when the answer is safe."""
    agent = InvestmentAgent(sec_client=FakeSECClient(tmp_path))

    result = agent.evaluate_answer(
        "Is AAPL guaranteed to go up?",
        "I cannot guarantee outcomes. Risks are disclosed in SEC filings. https://www.sec.gov Not financial advice.",
        "AAPL",
    )

    assert "overconfident_question" in result["risk_flags"]


def test_fallback_answer_is_not_raw_json(tmp_path) -> None:
    """Fallback answer should be concise and readable rather than raw JSON."""
    agent = InvestmentAgent(sec_client=FakeSECClient(tmp_path))
    agent.model = None

    result = agent.answer("Analyze AAPL", "AAPL")

    assert '"revenues"' not in result["answer"]
    assert "- Revenue:" in result["answer"]


def test_update_prompt_increments_prompt_version(tmp_path) -> None:
    """update_prompt should increment prompt version."""
    agent = InvestmentAgent(sec_client=FakeSECClient(tmp_path))

    agent.update_prompt("Use SEC data carefully.")

    assert agent.prompt_version == 2


def test_reset_returns_prompt_version_to_one(tmp_path) -> None:
    """reset should restore prompt version 1."""
    agent = InvestmentAgent(sec_client=FakeSECClient(tmp_path))
    agent.update_prompt("Use SEC data carefully.")

    agent.reset()

    assert agent.prompt_version == 1
