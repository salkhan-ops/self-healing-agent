"""Best-effort public-demo request limiters.

Cloud Run can run more than one instance, so these counters are intentionally
lightweight and per-process. They are guardrails against accidental judge/demo
spend, not a global quota system.
"""

from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass, field

from fastapi import Request

from config.settings import PUBLIC_DEMO_MODE


def demo_client_key(request: Request) -> str:
    """Build a privacy-light key from available session/client hints."""
    session_id = request.headers.get("x-session-id", "").strip()
    if session_id:
        return f"session:{session_id[:64]}"

    forwarded_for = request.headers.get("x-forwarded-for", "")
    client_ip = forwarded_for.split(",", 1)[0].strip()
    if not client_ip and request.client:
        client_ip = request.client.host

    user_agent = request.headers.get("user-agent", "")[:96]
    return f"client:{client_ip or 'unknown'}:{user_agent}"


@dataclass
class InMemoryDemoLimiter:
    """Simple per-instance counter keyed by browser/client identity."""

    name: str
    limit: int
    counts: dict[str, int] = field(default_factory=lambda: defaultdict(int))

    def check_and_increment(self, key: str) -> tuple[bool, int]:
        """Return (allowed, remaining_after_request)."""
        if not PUBLIC_DEMO_MODE:
            return True, max(0, self.limit)

        used = self.counts[key]
        if used >= self.limit:
            print(f"🛑 Public demo limit blocked: limiter={self.name} key_hash={hash(key)}")
            return False, 0

        self.counts[key] = used + 1
        return True, max(0, self.limit - self.counts[key])

    def refund(self, key: str) -> int:
        """Undo one allowed request when no paid/demo work was needed."""
        if not PUBLIC_DEMO_MODE:
            return max(0, self.limit)

        self.counts[key] = max(0, self.counts[key] - 1)
        return max(0, self.limit - self.counts[key])
