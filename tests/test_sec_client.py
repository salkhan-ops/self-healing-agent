"""Tests for the official SEC EDGAR client.

These tests avoid depending on live SEC availability and verify graceful local
behavior, CIK formatting, ticker extraction, and cache setup.
"""

from __future__ import annotations

from backend.services.sec_client import SECClient


def test_sec_client_initializes(tmp_path) -> None:
    """SECClient should initialize and create its cache directory."""
    client = SECClient(cache_dir=tmp_path)

    assert client.cache_dir.exists()
    assert client.user_agent


def test_cik_padding_works(tmp_path) -> None:
    """CIK values should be padded to 10 digits."""
    client = SECClient(cache_dir=tmp_path)

    assert client._pad_cik(320193) == "0000320193"


def test_ticker_extraction_from_cached_mapping(tmp_path) -> None:
    """Ticker resolution should work from cached SEC company_tickers JSON."""
    cache_file = tmp_path / "company_tickers.json"
    cache_file.write_text('{"0":{"cik_str":320193,"ticker":"AAPL","title":"Apple Inc."}}')
    client = SECClient(cache_dir=tmp_path)

    assert client.get_cik_for_ticker("aapl") == "0000320193"


def test_cache_directory_exists(tmp_path) -> None:
    """Cache directory should exist immediately after initialization."""
    client = SECClient(cache_dir=tmp_path / "sec_cache")

    assert client.cache_dir.exists()


def test_methods_fail_gracefully_if_network_unavailable(tmp_path) -> None:
    """Unknown tickers and unavailable SEC responses should not raise."""
    cache_file = tmp_path / "company_tickers.json"
    cache_file.write_text("{}")
    client = SECClient(cache_dir=tmp_path)

    assert client.get_company_profile("NO_SUCH_TICKER_123").get("error")
    assert client.get_recent_filings("NO_SUCH_TICKER_123") == []
