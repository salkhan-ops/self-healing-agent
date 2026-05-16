"""Tests for the Self-Healing AI Agent loop.

These tests verify the main components work in local development, even when
Gemini credentials or the local Phoenix server are not available.
"""

from __future__ import annotations

from types import SimpleNamespace

from agent.analyzer import RootCause
from agent.evaluator import Evaluator
from agent.improver import PromptImprover
from agent.reporter import Reporter
from agent.task_agent import TaskAgent
from agent.trace_reader import TraceReader
from agent.verifier import VerificationResult


def test_task_agent_returns_string_answer() -> None:
    """TaskAgent should always return a string answer."""
    agent = TaskAgent()

    answer = agent.answer("What is your return policy?")

    assert isinstance(answer, str)
    assert answer.strip()


def test_trace_reader_connects_to_phoenix_gracefully() -> None:
    """TraceReader should attempt a local Phoenix connection without crashing."""
    reader = TraceReader()

    traces = reader.get_recent_traces(limit=10)

    assert isinstance(traces, list)
    assert reader.endpoint.startswith("http://localhost:6006")


def test_trace_reader_uses_mcp_response_for_recent_traces(monkeypatch) -> None:
    """TraceReader should normalize traces returned by the MCP integration."""
    reader = TraceReader()

    monkeypatch.setattr(reader, "_phoenix_is_available", lambda: True)
    monkeypatch.setattr(
        reader,
        "query_phoenix_via_mcp",
        lambda query, params=None: {
            "result": {
                "traces": [
                    {
                        "context.trace_id": "trace-123",
                        "context.span_id": "span-456",
                        "input.value": "What is your return policy?",
                        "output.value": "Unused items can be returned within 30 days.",
                        "duration_ms": 125,
                    }
                ]
            }
        },
    )

    traces = reader.get_recent_traces(limit=1)

    assert traces == [
        {
            "context.trace_id": "trace-123",
            "context.span_id": "span-456",
            "input.value": "What is your return policy?",
            "output.value": "Unused items can be returned within 30 days.",
            "duration_ms": 125,
            "trace_id": "trace-123",
            "span_id": "span-456",
            "question": "What is your return policy?",
            "answer": "Unused items can be returned within 30 days.",
            "latency_ms": 125,
            "hallucination_score": None,
            "relevance_score": None,
        }
    ]


def test_trace_reader_parses_text_content_from_mcp_result() -> None:
    """Fallback MCP text blocks should become regular dictionaries."""
    reader = TraceReader()

    parsed = reader._mcp_content_to_json(
        [SimpleNamespace(type="text", text='{"traces": [{"trace_id": "trace-1"}]}')]
    )

    assert parsed == {"traces": [{"trace_id": "trace-1"}]}


def test_evaluator_returns_scores_between_zero_and_one() -> None:
    """Evaluator should return bounded hallucination and relevance scores."""
    evaluator = Evaluator()
    traces = [
        {
            "question": "What is your return policy?",
            "answer": "You can return most unused items within 30 days of delivery for a refund.",
            "latency_ms": 1000,
        }
    ]

    result = evaluator.score_traces(traces)

    assert 0.0 <= result.hallucination_score <= 1.0
    assert 0.0 <= result.relevance_score <= 1.0
    assert result.latency_ms >= 0


def test_improver_returns_different_prompt() -> None:
    """PromptImprover should save history and return a changed prompt."""
    improver = PromptImprover()
    old_prompt = "Answer customer support questions from the FAQ."
    root_cause = RootCause(
        category="GUESSING",
        explanation="Agent guessed when the FAQ did not contain enough information.",
    )

    new_prompt = improver.improve(old_prompt, root_cause)

    assert new_prompt != old_prompt
    assert improver.prompt_history == [old_prompt]
    assert "faq" in new_prompt.lower()


def test_reporter_creates_file(tmp_path) -> None:
    """Reporter should write a timestamped report file."""
    reporter = Reporter(reports_dir=tmp_path)
    evaluation = Evaluator().score_traces(
        [
            {
                "question": "Do you ship internationally?",
                "answer": "Yes, we ship internationally.",
                "latency_ms": 1000,
            }
        ]
    )
    verification = VerificationResult(
        improved=True,
        before_scores={
            "hallucination_score": evaluation.hallucination_score,
            "relevance_score": evaluation.relevance_score,
            "latency_ms": evaluation.latency_ms,
        },
        after_scores={
            "hallucination_score": 0.0,
            "relevance_score": 0.8,
            "latency_ms": 900.0,
        },
        delta_scores={
            "hallucination_score": -evaluation.hallucination_score,
            "relevance_score": 0.8 - evaluation.relevance_score,
            "latency_ms": -100.0,
        },
        improvement_percent=25.0,
    )
    root_cause = RootCause(category="GUESSING", explanation="Prompt allowed guessing.")

    report = reporter.generate(
        evaluation,
        root_cause,
        verification,
        "old prompt",
        "new prompt with FAQ and do not guess and I don't know based on the FAQ.",
    )

    assert report.file_path
    assert "SELF-HEALING REPORT" in report.content
    assert tmp_path.joinpath(report.file_path.split("/")[-1]).exists()
