"""Official SEC EDGAR API client for investment research context.

SECClient fetches ticker mappings, company submissions, and XBRL company facts
from official SEC endpoints with a required User-Agent and local JSON cache.
"""

from __future__ import annotations

import json
import os
import time
from pathlib import Path
from typing import Any

import httpx
from dotenv import load_dotenv


load_dotenv()

PROJECT_ROOT = Path(__file__).resolve().parents[2]
SEC_CACHE_DIR = PROJECT_ROOT / "data" / "sec_cache"
TICKER_URL = "https://www.sec.gov/files/company_tickers.json"
SUBMISSIONS_URL = "https://data.sec.gov/submissions/CIK{cik}.json"
COMPANY_FACTS_URL = "https://data.sec.gov/api/xbrl/companyfacts/CIK{cik}.json"


class SECClient:
    """Fetch and normalize company research data from official SEC APIs."""

    def __init__(self, cache_dir: Path | str = SEC_CACHE_DIR) -> None:
        self.cache_dir = Path(cache_dir)
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        self.user_agent = os.getenv("SEC_USER_AGENT", "SelfHealingAgent/1.0 contact@example.com")
        self.timeout = 20.0
        self._last_request_at = 0.0

    def get_cik_for_ticker(self, ticker: str) -> str:
        """Resolve a stock ticker to a padded 10-digit SEC CIK string."""
        clean_ticker = ticker.strip().upper()
        if not clean_ticker:
            return ""

        mapping = self._get_ticker_mapping()
        for item in mapping.values():
            if str(item.get("ticker", "")).upper() == clean_ticker:
                return self._pad_cik(item.get("cik_str"))

        return ""

    def get_company_profile(self, ticker: str) -> dict[str, Any]:
        """Return company profile metadata from SEC submissions."""
        cik = self.get_cik_for_ticker(ticker)
        if not cik:
            return {"ticker": ticker.upper(), "error": "Ticker not found in SEC mapping."}

        submissions = self._get_json(SUBMISSIONS_URL.format(cik=cik), f"submissions_{cik}.json")
        if not submissions:
            return {"ticker": ticker.upper(), "cik": cik, "error": "SEC submissions unavailable."}

        return {
            "ticker": ticker.upper(),
            "cik": cik,
            "company_name": submissions.get("name", ""),
            "sic": str(submissions.get("sic", "")),
            "sic_description": submissions.get("sicDescription", ""),
            "fiscal_year_end": submissions.get("fiscalYearEnd", ""),
            "entity_type": submissions.get("entityType", ""),
        }

    def get_company_facts(self, ticker: str) -> dict[str, Any]:
        """Return SEC company facts JSON for a ticker."""
        cik = self.get_cik_for_ticker(ticker)
        if not cik:
            return {"ticker": ticker.upper(), "error": "Ticker not found in SEC mapping."}

        facts = self._get_json(COMPANY_FACTS_URL.format(cik=cik), f"companyfacts_{cik}.json")
        return facts or {"ticker": ticker.upper(), "cik": cik, "error": "SEC company facts unavailable."}

    def get_recent_filings(
        self,
        ticker: str,
        forms: list[str] | None = None,
    ) -> list[dict[str, Any]]:
        """Return the latest filing for each requested form type."""
        forms = forms or ["10-K", "10-Q", "8-K"]
        cik = self.get_cik_for_ticker(ticker)
        if not cik:
            return []

        submissions = self._get_json(SUBMISSIONS_URL.format(cik=cik), f"submissions_{cik}.json")
        recent = submissions.get("filings", {}).get("recent", {}) if submissions else {}
        filings = []

        for index, form in enumerate(recent.get("form", [])):
            if form not in forms:
                continue
            accession = self._safe_list_value(recent, "accessionNumber", index)
            accession_compact = accession.replace("-", "")
            filings.append(
                {
                    "form": form,
                    "filing_date": self._safe_list_value(recent, "filingDate", index),
                    "report_date": self._safe_list_value(recent, "reportDate", index),
                    "accession_number": accession,
                    "primary_document": self._safe_list_value(recent, "primaryDocument", index),
                    "source_url": (
                        f"https://www.sec.gov/Archives/edgar/data/{int(cik)}/{accession_compact}/"
                        f"{self._safe_list_value(recent, 'primaryDocument', index)}"
                    ),
                }
            )

        latest_by_form: dict[str, dict[str, Any]] = {}
        for filing in filings:
            latest_by_form.setdefault(filing["form"], filing)

        return list(latest_by_form.values())

    def build_research_context(self, ticker: str) -> dict[str, Any]:
        """Build a compact SEC research context for the investment agent."""
        clean_ticker = ticker.strip().upper()
        cik = self.get_cik_for_ticker(clean_ticker)
        profile = self.get_company_profile(clean_ticker) if cik else {}
        facts = self.get_company_facts(clean_ticker) if cik else {}
        recent_filings = self.get_recent_filings(clean_ticker)
        key_facts = self._extract_key_facts(facts)
        source_urls = [
            TICKER_URL,
            SUBMISSIONS_URL.format(cik=cik) if cik else "",
            COMPANY_FACTS_URL.format(cik=cik) if cik else "",
            *[filing["source_url"] for filing in recent_filings if filing.get("source_url")],
        ]

        return {
            "ticker": clean_ticker,
            "cik": cik,
            "company_name": profile.get("company_name", ""),
            "sic": profile.get("sic", ""),
            "fiscal_year_end": profile.get("fiscal_year_end", ""),
            "recent_filings": recent_filings,
            "key_facts": key_facts,
            "source_urls": [url for url in source_urls if url],
        }

    def _get_ticker_mapping(self) -> dict[str, Any]:
        """Fetch or load cached SEC company ticker mapping."""
        return self._get_json(TICKER_URL, "company_tickers.json") or {}

    def _get_json(self, url: str, cache_name: str) -> dict[str, Any]:
        """Fetch JSON with local cache fallback and graceful network handling."""
        cache_path = self.cache_dir / cache_name
        if cache_path.exists():
            try:
                return json.loads(cache_path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                pass

        try:
            self._respect_sec_pacing()
            response = httpx.get(
                url,
                headers={"User-Agent": self.user_agent, "Accept-Encoding": "gzip, deflate"},
                timeout=self.timeout,
            )
            if response.status_code in {403, 404, 429}:
                print(f"⚠️ SEC request returned {response.status_code} for {url}")
                return {}
            response.raise_for_status()
            data = response.json()
            cache_path.write_text(json.dumps(data), encoding="utf-8")
            return data
        except Exception as exc:
            print(f"⚠️ SEC request failed for {url}: {exc}")
            return {}

    def _respect_sec_pacing(self) -> None:
        """Avoid rapid repeated SEC requests from this process."""
        elapsed = time.monotonic() - self._last_request_at
        if elapsed < 0.12:
            time.sleep(0.12 - elapsed)
        self._last_request_at = time.monotonic()

    def _extract_key_facts(self, facts: dict[str, Any]) -> dict[str, list[dict[str, Any]]]:
        """Extract common financial facts from SEC XBRL company facts."""
        us_gaap = facts.get("facts", {}).get("us-gaap", {}) if facts else {}
        concepts = {
            "revenues": ["Revenues", "RevenueFromContractWithCustomerExcludingAssessedTax"],
            "net_income": ["NetIncomeLoss"],
            "assets": ["Assets"],
            "liabilities": ["Liabilities"],
            "cash_and_cash_equivalents": ["CashAndCashEquivalentsAtCarryingValue"],
            "operating_income": ["OperatingIncomeLoss"],
            "earnings_per_share": ["EarningsPerShareDiluted", "EarningsPerShareBasic"],
        }
        extracted = {}
        for label, concept_names in concepts.items():
            extracted[label] = self._latest_units_for_concepts(us_gaap, concept_names)
        return extracted

    def _latest_units_for_concepts(
        self,
        us_gaap: dict[str, Any],
        concept_names: list[str],
    ) -> list[dict[str, Any]]:
        """Return recent annual/quarterly values for candidate XBRL concepts."""
        for concept_name in concept_names:
            concept = us_gaap.get(concept_name)
            if not concept:
                continue
            units = concept.get("units", {})
            unit_values = units.get("USD") or units.get("USD/shares") or []
            sorted_values = sorted(
                unit_values,
                key=lambda item: (
                    self._safe_int(item.get("fy")),
                    str(item.get("fp") or ""),
                    str(item.get("end") or ""),
                ),
                reverse=True,
            )
            return [
                {
                    "concept": concept_name,
                    "value": item.get("val"),
                    "form": item.get("form"),
                    "fy": item.get("fy"),
                    "fp": item.get("fp"),
                    "end": item.get("end"),
                    "filed": item.get("filed"),
                    "unit": "USD/shares" if "shares" in str(units.keys()) else "USD",
                }
                for item in sorted_values[:6]
            ]
        return []

    def _pad_cik(self, value: Any) -> str:
        """Pad a CIK value to the official 10-digit SEC format."""
        try:
            return str(int(value)).zfill(10)
        except (TypeError, ValueError):
            return ""

    def _safe_int(self, value: Any) -> int:
        """Convert SEC numeric fields safely for sorting."""
        try:
            return int(value)
        except (TypeError, ValueError):
            return 0

    def _safe_list_value(self, data: dict[str, list[Any]], key: str, index: int) -> str:
        """Read an indexed list value from SEC recent filings data."""
        values = data.get(key, [])
        if index >= len(values):
            return ""
        return str(values[index] or "")
