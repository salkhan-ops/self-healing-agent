"""Shared Phoenix tracing helpers for local and cloud deployments."""

from __future__ import annotations

from typing import Any
from urllib.request import urlopen

from config.settings import (
    PHOENIX_API_KEY,
    PHOENIX_COLLECTOR_ENDPOINT,
    PHOENIX_HOST,
    PHOENIX_PROJECT_NAME,
)

try:
    from phoenix.otel import register
except ImportError:
    register = None


def phoenix_is_available(timeout: float = 0.5) -> bool:
    """Return True when the configured Phoenix host responds."""
    try:
        with urlopen(f"{PHOENIX_HOST}/arize_phoenix_version", timeout=timeout):
            return True
    except Exception:
        return False


def configure_phoenix_tracing(service_name: str) -> Any | None:
    """Register Phoenix OTLP export without ever crashing the application."""
    if register is None:
        print("⚠️ arize-phoenix-otel is unavailable; Phoenix export is disabled.")
        return None

    if not phoenix_is_available():
        print(f"⚠️ Phoenix not reachable at {PHOENIX_HOST}; {service_name} traces stay local.")
        return None

    try:
        provider = register(
            project_name=PHOENIX_PROJECT_NAME,
            endpoint=PHOENIX_COLLECTOR_ENDPOINT,
            protocol="http/protobuf",
            batch=True,
            auto_instrument=True,
            api_key=PHOENIX_API_KEY or None,
        )
        print(f"✅ {service_name} tracing connected to Phoenix at {PHOENIX_HOST}")
        return provider
    except Exception as exc:
        print(f"⚠️ {service_name} tracing setup failed; continuing without export. Error: {exc}")
        return None
