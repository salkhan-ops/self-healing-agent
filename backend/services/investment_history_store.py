"""Shared in-memory history for investment analyst answers."""

from __future__ import annotations

MAX_HISTORY = 50
_history: list[dict] = []


def add_investment_entry(entry: dict) -> None:
    _history.append(entry)
    if len(_history) > MAX_HISTORY:
        _history.pop(0)


def list_investment_entries(limit: int | None = None) -> list[dict]:
    if limit is None:
        return list(_history)
    return list(_history[-limit:])


def clear_investment_entries() -> None:
    _history.clear()
