"""Report API routes for the dashboard backend.

These endpoints list reports, return report details, and export report data
as CSV or a minimal PDF download.
"""

from __future__ import annotations

import csv
from io import StringIO
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query, Response
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from backend.database import Report, get_session
from backend.models import ReportResponse


router = APIRouter(prefix="/api/reports", tags=["reports"])


@router.get("", response_model=list[ReportResponse])
async def list_reports(session: AsyncSession = Depends(get_session)) -> list[Report]:
    """Return all saved reports, newest first."""
    try:
        statement = select(Report).order_by(Report.timestamp.desc())
        result = await session.execute(statement)
        return list(result.scalars().all())
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Could not load reports: {exc}") from exc


@router.get("/{report_id}", response_model=ReportResponse)
async def get_report(report_id: int, session: AsyncSession = Depends(get_session)) -> Report:
    """Return one report by id."""
    report = await session.get(Report, report_id)
    if report is None:
        raise HTTPException(status_code=404, detail="Report not found.")

    return report


@router.get("/{report_id}/export")
async def export_report(
    report_id: int,
    format: Literal["pdf", "csv"] = Query("csv"),
    session: AsyncSession = Depends(get_session),
) -> Response:
    """Download a report as CSV or a simple PDF document."""
    report = await session.get(Report, report_id)
    if report is None:
        raise HTTPException(status_code=404, detail="Report not found.")

    if format == "csv":
        return _csv_response(report)

    return _pdf_response(report)


def _csv_response(report: Report) -> Response:
    """Serialize a report to CSV for download."""
    output = StringIO()
    writer = csv.writer(output)
    writer.writerow(
        [
            "id",
            "timestamp",
            "run_id",
            "problem",
            "root_cause",
            "fix_applied",
            "before_hallucination",
            "before_relevance",
            "before_latency",
            "after_hallucination",
            "after_relevance",
            "after_latency",
            "improvement_percent",
            "human_needed",
            "content_text",
        ]
    )
    writer.writerow(
        [
            report.id,
            report.timestamp,
            report.run_id,
            report.problem,
            report.root_cause,
            report.fix_applied,
            report.before_hallucination,
            report.before_relevance,
            report.before_latency,
            report.after_hallucination,
            report.after_relevance,
            report.after_latency,
            report.improvement_percent,
            report.human_needed,
            report.content_text,
        ]
    )
    return Response(
        content=output.getvalue(),
        media_type="text/csv",
        headers={"Content-Disposition": f'attachment; filename="report_{report.id}.csv"'},
    )


def _pdf_response(report: Report) -> Response:
    """Create a tiny valid PDF with the report text and return it for download."""
    content = report.content_text or f"Self-Healing Report\n\nProblem: {report.problem}"
    pdf_bytes = _minimal_pdf_bytes(content)
    return Response(
        content=pdf_bytes,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="report_{report.id}.pdf"'},
    )


def _minimal_pdf_bytes(text: str) -> bytes:
    """Build a dependency-free single-page PDF from plain text."""
    safe_lines = [line.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)") for line in text.splitlines()]
    stream_lines = ["BT", "/F1 10 Tf", "50 780 Td"]

    for index, line in enumerate(safe_lines[:45]):
        if index:
            stream_lines.append("0 -14 Td")
        stream_lines.append(f"({line[:100]}) Tj")

    stream_lines.append("ET")
    stream = "\n".join(stream_lines)
    objects = [
        "1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj",
        "2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj",
        "3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >> endobj",
        "4 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> endobj",
        f"5 0 obj << /Length {len(stream.encode('latin-1', errors='replace'))} >> stream\n{stream}\nendstream endobj",
    ]
    body = "%PDF-1.4\n" + "\n".join(objects) + "\n"
    return body.encode("latin-1", errors="replace") + b"%%EOF\n"
