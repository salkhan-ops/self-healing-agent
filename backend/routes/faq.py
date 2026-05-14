"""FAQ API routes for the dashboard backend.

These endpoints let the dashboard read and replace the local FAQ knowledge
base used by the Self-Healing AI Agent.
"""

from __future__ import annotations

from pathlib import Path

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel


router = APIRouter(prefix="/api/faq", tags=["faq"])
FAQ_PATH = Path(__file__).resolve().parents[2] / "data" / "faq.txt"


class FAQUpdateRequest(BaseModel):
    """Request body for replacing the full FAQ text."""

    content: str


@router.get("")
async def get_faq() -> dict[str, str]:
    """Return the full FAQ content as text."""
    try:
        return {"content": FAQ_PATH.read_text(encoding="utf-8")}
    except OSError as exc:
        raise HTTPException(status_code=500, detail=f"Could not read FAQ: {exc}") from exc


@router.put("")
async def update_faq(payload: FAQUpdateRequest) -> dict[str, str]:
    """Replace the full FAQ content."""
    try:
        FAQ_PATH.write_text(payload.content, encoding="utf-8")
        return {"status": "updated", "content": payload.content}
    except OSError as exc:
        raise HTTPException(status_code=500, detail=f"Could not update FAQ: {exc}") from exc
