"""FastAPI application for the Self-Healing AI Agent dashboard.

This app exposes REST routes for metrics, reports, schedules, agent control,
FAQ editing, and a WebSocket endpoint for live run progress.
"""

from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import select

from backend.database import AsyncSessionLocal, MetricSnapshot, Report, init_db
from backend.routes import agent, chat, faq, metrics, reports, scheduler
from backend.routes.investment import router as investment_router
from backend.routes.posts import router as posts_router
from backend.services.agent_runner import websocket_manager
from backend.services.scheduler_svc import scheduler_service


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Initialize database and scheduler for the dashboard app."""
    await init_db()
    await scheduler_service.start()
    try:
        yield
    finally:
        await scheduler_service.shutdown()


app = FastAPI(title="Self-Healing AI Agent Dashboard API", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:3000",
        "http://localhost:8000",
        "*",
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(metrics.router)
app.include_router(reports.router)
app.include_router(scheduler.router)
app.include_router(agent.router)
app.include_router(faq.router)
app.include_router(chat.router, prefix="")
app.include_router(investment_router)
app.include_router(posts_router)


@app.get("/health")
async def health() -> dict[str, str]:
    """Return a simple health check response."""
    return {"status": "ok"}


@app.get("/embed/widget", response_class=HTMLResponse)
async def embed_widget() -> HTMLResponse:
    """Return an iframe-friendly mini dashboard widget."""
    async with AsyncSessionLocal() as session:
        metric_result = await session.execute(
            select(MetricSnapshot).order_by(MetricSnapshot.timestamp.desc()).limit(1)
        )
        report_result = await session.execute(select(Report).order_by(Report.timestamp.desc()).limit(1))
        metric = metric_result.scalar_one_or_none()
        report = report_result.scalar_one_or_none()

    health_score = 0.0
    if metric is not None:
        raw_score = 100 - (metric.hallucination_score * 100) + (metric.relevance_score * 100) / 2
        health_score = max(0.0, min(100.0, raw_score))

    last_report = report.problem if report is not None else "No reports generated yet."
    root_cause = report.root_cause if report is not None else "Waiting for first self-healing run."
    health_color = "#2ED573" if health_score >= 70 else "#FFA502" if health_score >= 45 else "#FF4757"

    html = f"""
<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <style>
      body {{
        margin: 0;
        background: #0A0A0F;
        color: #FFFFFF;
        font-family: Inter, Arial, sans-serif;
      }}
      .widget {{
        box-sizing: border-box;
        width: 100%;
        min-height: 220px;
        padding: 18px;
        background: #12121A;
        border: 1px solid #1A1A28;
        border-radius: 12px;
      }}
      .label {{
        color: #8B8BA7;
        font-size: 12px;
        letter-spacing: 0.04em;
        text-transform: uppercase;
      }}
      .score {{
        margin-top: 8px;
        color: {health_color};
        font-size: 48px;
        font-weight: 800;
        line-height: 1;
      }}
      .report {{
        margin-top: 18px;
        padding-top: 16px;
        border-top: 1px solid #1A1A28;
      }}
      .title {{
        margin-top: 6px;
        font-size: 15px;
        font-weight: 700;
      }}
      .cause {{
        margin-top: 6px;
        color: #8B8BA7;
        font-size: 13px;
        line-height: 1.4;
      }}
    </style>
  </head>
  <body>
    <div class="widget">
      <div class="label">Self-Healing Agent Health</div>
      <div class="score">{health_score:.0f}</div>
      <div class="report">
        <div class="label">Last Report</div>
        <div class="title">{last_report}</div>
        <div class="cause">{root_cause}</div>
      </div>
    </div>
  </body>
</html>
"""
    return HTMLResponse(content=html)


@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket) -> None:
    """Stream live agent progress to connected dashboard clients."""
    await websocket_manager.connect(websocket)
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        websocket_manager.disconnect(websocket)


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("backend.main:app", host="0.0.0.0", port=8000, reload=True)
