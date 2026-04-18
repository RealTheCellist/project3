from __future__ import annotations

from datetime import UTC, datetime, timedelta
import logging
import os
import tempfile
import time
import uuid

from fastapi import FastAPI, File, HTTPException, Query, Request, UploadFile
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse, Response

from app.models.schemas import (
    AnalyzeResult,
    CheckinRecord,
    CheckinListResponse,
    CheckinRequest,
    ErrorResponse,
    ReportConfidenceBucket,
    ReportDailyPoint,
    ReportSummaryResponse,
    ReportTagStat,
    STTConfigResponse,
    STTProfilesResponse,
    STTResponse,
)
from app.services.scoring import analyze_checkin
from app.services.whisper_stt import (
    STTServiceError,
    get_stt_runtime_config,
    list_stt_profiles,
    transcribe_audio_file,
)
from app.storage import init_db, insert_checkin, list_checkins


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
logger = logging.getLogger("sumpyo.api")


app = FastAPI(
    title="Sumpyo Recovery API",
    version="0.1.0",
    description="Emotion recovery coaching MVP backend.",
)

init_db()


@app.middleware("http")
async def request_logging_middleware(request: Request, call_next):
    request_id = request.headers.get("x-request-id") or str(uuid.uuid4())
    request.state.request_id = request_id
    started = time.perf_counter()

    try:
        response = await call_next(request)
    except Exception:
        elapsed_ms = (time.perf_counter() - started) * 1000
        logger.exception(
            "Unhandled exception request_id=%s method=%s path=%s elapsed_ms=%.1f",
            request_id,
            request.method,
            request.url.path,
            elapsed_ms,
        )
        raise

    elapsed_ms = (time.perf_counter() - started) * 1000
    response.headers["x-request-id"] = request_id
    response.headers["x-process-time-ms"] = f"{elapsed_ms:.1f}"
    logger.info(
        "request_id=%s method=%s path=%s status=%s elapsed_ms=%.1f",
        request_id,
        request.method,
        request.url.path,
        response.status_code,
        elapsed_ms,
    )
    return response


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    request_id = getattr(request.state, "request_id", "unknown")
    detail = exc.errors()
    logger.warning("validation_error request_id=%s detail=%s", request_id, detail)
    payload = ErrorResponse(
        error="validation_error",
        message="Invalid request payload",
        request_id=request_id,
    )
    safe_detail = jsonable_encoder(detail)
    return JSONResponse(
        status_code=422,
        content={**payload.model_dump(), "detail": safe_detail},
    )


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception):
    request_id = getattr(request.state, "request_id", "unknown")
    payload = ErrorResponse(
        error="internal_error",
        message="Unexpected server error",
        request_id=request_id,
    )
    return JSONResponse(status_code=500, content=payload.model_dump())


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.post("/analyze-checkin", response_model=AnalyzeResult)
def analyze(req: CheckinRequest, save: bool = Query(default=True)) -> AnalyzeResult:
    try:
        result = analyze_checkin(req)
        if save:
            insert_checkin(req.transcript, result)
        return AnalyzeResult(**result)
    except ValueError as err:
        raise HTTPException(status_code=400, detail=str(err)) from err


@app.get("/checkins", response_model=CheckinListResponse)
def checkins(limit: int = Query(default=20, ge=1, le=100)) -> CheckinListResponse:
    return CheckinListResponse(items=list_checkins(limit=limit))


def _parse_created_at_utc(value: str) -> datetime | None:
    normalized = value.replace(" ", "T")
    try:
        parsed = datetime.fromisoformat(normalized)
        if parsed.tzinfo is None:
            return parsed.replace(tzinfo=UTC)
        return parsed.astimezone(UTC)
    except ValueError:
        return None


def _filter_records_by_days(records: list[CheckinRecord], days: int) -> list[CheckinRecord]:
    cutoff = datetime.now(UTC) - timedelta(days=days)
    filtered: list[CheckinRecord] = []
    for item in records:
        created = _parse_created_at_utc(item.created_at)
        if created is None or created >= cutoff:
            filtered.append(item)
    return filtered


def _build_report_summary(days: int, filtered: list[CheckinRecord]) -> ReportSummaryResponse:
    total = len(filtered)
    latest_recovery = filtered[0].recovery_score if filtered else None
    latest_risk = filtered[0].risk_score if filtered else None
    avg_recovery = (
        round(sum(item.recovery_score for item in filtered) / total, 2) if total else 0.0
    )
    avg_risk = round(sum(item.risk_score for item in filtered) / total, 2) if total else 0.0
    avg_conf = round(sum(item.confidence for item in filtered) / total, 3) if total else 0.0

    low = sum(1 for item in filtered if item.confidence < 0.4)
    medium = sum(1 for item in filtered if 0.4 <= item.confidence < 0.7)
    high = sum(1 for item in filtered if item.confidence >= 0.7)

    tag_counts: dict[str, int] = {}
    for item in filtered:
        for tag in item.tags:
            tag_counts[tag] = tag_counts.get(tag, 0) + 1
    top_tags = [
        ReportTagStat(tag=tag, count=count)
        for tag, count in sorted(tag_counts.items(), key=lambda kv: kv[1], reverse=True)[:8]
    ]

    daily_acc: dict[str, list[int]] = {}
    for item in filtered:
        date_key = item.created_at[:10]
        daily_acc.setdefault(date_key, []).append(item.recovery_score)
    daily_recovery = [
        ReportDailyPoint(
            date=date_key,
            avg_recovery_score=round(sum(values) / len(values), 2),
            count=len(values),
        )
        for date_key, values in sorted(daily_acc.items())
    ]

    return ReportSummaryResponse(
        days=days,
        total_checkins=total,
        avg_recovery_score=avg_recovery,
        avg_risk_score=avg_risk,
        avg_confidence=avg_conf,
        latest_recovery_score=latest_recovery,
        latest_risk_score=latest_risk,
        confidence_buckets=ReportConfidenceBucket(low=low, medium=medium, high=high),
        top_tags=top_tags,
        daily_recovery=daily_recovery,
    )


def _pdf_escape(text: str) -> str:
    return (
        text.replace("\\", "\\\\")
        .replace("(", "\\(")
        .replace(")", "\\)")
    )


def _generate_basic_pdf(lines: list[str]) -> bytes:
    # Keep ASCII-only text for built-in Helvetica font compatibility.
    normalized = [line.encode("ascii", "replace").decode("ascii") for line in lines]
    text_stream = ["BT", "/F1 11 Tf"]
    y = 760
    for line in normalized[:42]:
        text_stream.append(f"1 0 0 1 40 {y} Tm ({_pdf_escape(line)}) Tj")
        y -= 16
    text_stream.append("ET")
    stream_body = "\n".join(text_stream).encode("latin-1")

    objects: list[bytes] = []
    objects.append(b"1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n")
    objects.append(b"2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n")
    objects.append(
        b"3 0 obj\n"
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
        b"/Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>\n"
        b"endobj\n"
    )
    objects.append(
        f"4 0 obj\n<< /Length {len(stream_body)} >>\nstream\n".encode("ascii")
        + stream_body
        + b"\nendstream\nendobj\n"
    )
    objects.append(b"5 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n")

    pdf = bytearray(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
    offsets = [0]
    for obj in objects:
        offsets.append(len(pdf))
        pdf.extend(obj)
    xref_pos = len(pdf)
    pdf.extend(f"xref\n0 {len(offsets)}\n".encode("ascii"))
    pdf.extend(b"0000000000 65535 f \n")
    for off in offsets[1:]:
        pdf.extend(f"{off:010d} 00000 n \n".encode("ascii"))
    pdf.extend(
        f"trailer\n<< /Size {len(offsets)} /Root 1 0 R >>\nstartxref\n{xref_pos}\n%%EOF\n".encode(
            "ascii"
        )
    )
    return bytes(pdf)


@app.get("/report/summary", response_model=ReportSummaryResponse)
def report_summary(
    days: int = Query(default=7, ge=1, le=365),
    limit: int = Query(default=200, ge=1, le=1000),
) -> ReportSummaryResponse:
    raw_items = list_checkins(limit=limit)
    records = [CheckinRecord(**item) for item in raw_items]
    filtered = _filter_records_by_days(records, days)
    return _build_report_summary(days=days, filtered=filtered)


@app.get("/report/export-pdf")
def report_export_pdf(
    days: int = Query(default=7, ge=1, le=365),
    limit: int = Query(default=200, ge=1, le=1000),
) -> Response:
    raw_items = list_checkins(limit=limit)
    records = [CheckinRecord(**item) for item in raw_items]
    filtered = _filter_records_by_days(records, days)
    summary = _build_report_summary(days=days, filtered=filtered)

    lines = [
        "Sumpyo Report Export",
        f"Generated At (UTC): {datetime.now(UTC).isoformat(timespec='seconds')}",
        f"Range: last {days} days",
        f"Total Checkins: {summary.total_checkins}",
        f"Avg Recovery: {summary.avg_recovery_score}",
        f"Avg Risk: {summary.avg_risk_score}",
        f"Avg Confidence: {summary.avg_confidence}",
        "",
        "Confidence Buckets:",
        f"- low: {summary.confidence_buckets.low}",
        f"- medium: {summary.confidence_buckets.medium}",
        f"- high: {summary.confidence_buckets.high}",
        "",
        "Top Tags:",
    ]
    if summary.top_tags:
        for item in summary.top_tags[:8]:
            lines.append(f"- {item.tag}: {item.count}")
    else:
        lines.append("- (none)")

    lines.extend(["", "Recent Checkins:"])
    if filtered:
        for item in filtered[:12]:
            lines.append(
                f"- {item.created_at} | rec={item.recovery_score} risk={item.risk_score} "
                f"conf={item.confidence:.2f}"
            )
    else:
        lines.append("- (no checkins in selected range)")

    pdf_bytes = _generate_basic_pdf(lines)
    filename = f"sumpyo_report_{days}d.pdf"
    return Response(
        content=pdf_bytes,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@app.post("/stt", response_model=STTResponse)
async def stt(
    file: UploadFile = File(...),
    language: str = Query(default="ko", min_length=2, max_length=10),
    profile: str = Query(default="balanced", pattern="^(fast|balanced|accurate)$"),
) -> STTResponse:
    filename = file.filename or "audio.wav"
    suffix = os.path.splitext(filename)[1] or ".wav"
    tmp_path = ""

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
            tmp_path = tmp.name
            content = await file.read()
            if not content:
                raise HTTPException(status_code=400, detail="Uploaded file is empty")
            tmp.write(content)

        result = transcribe_audio_file(tmp_path, language=language, profile=profile)
        logger.info(
            "stt_success profile=%s provider=%s duration_ms=%s model=%s device=%s",
            result.profile,
            result.provider,
            result.duration_ms,
            result.model_name,
            result.device,
        )
        return STTResponse(
            transcript=result.transcript,
            language=language,
            provider=result.provider,
            profile=result.profile,
            model_name=result.model_name,
            device=result.device,
            compute_type=result.compute_type,
            duration_ms=result.duration_ms,
        )
    except HTTPException:
        raise
    except STTServiceError as err:
        code_to_status = {
            "audio_not_found": 400,
            "empty_transcript": 422,
            "backend_not_installed": 503,
            "transcription_failed": 503,
        }
        status = code_to_status.get(err.code, 503)
        raise HTTPException(
            status_code=status,
            detail={"code": err.code, "message": err.message},
        ) from err
    finally:
        await file.close()
        if tmp_path and os.path.exists(tmp_path):
            os.remove(tmp_path)


@app.get("/stt/config", response_model=STTConfigResponse)
def stt_config(
    profile: str = Query(default="balanced", pattern="^(fast|balanced|accurate)$"),
) -> STTConfigResponse:
    cfg = get_stt_runtime_config(profile_override=profile)
    return STTConfigResponse(
        provider=cfg.provider,
        profile=cfg.profile,
        model_name=cfg.model_name,
        device=cfg.device,
        compute_type=cfg.compute_type,
        beam_size=cfg.beam_size,
        vad_filter=cfg.vad_filter,
    )


@app.get("/stt/profiles", response_model=STTProfilesResponse)
def stt_profiles() -> STTProfilesResponse:
    return STTProfilesResponse(profiles=list_stt_profiles())
