"""Shared in-memory history for generated social media posts."""

from __future__ import annotations

MAX_HISTORY = 50
_post_history: list[dict] = []


def add_post(entry: dict) -> None:
    """Append a generated post entry and trim old rows."""
    _post_history.append(entry)
    if len(_post_history) > MAX_HISTORY:
        _post_history.pop(0)


def list_posts(limit: int | None = None) -> list[dict]:
    """Return recent post history in insertion order."""
    if limit is None:
        return list(_post_history)
    return list(_post_history[-limit:])


def clear_posts() -> None:
    """Clear all generated post history."""
    _post_history.clear()
