from __future__ import annotations

from typing import Dict, List, Optional

from pydantic import BaseModel, Field, conint, field_validator


class VoiceFeatures(BaseModel):
    speech_rate_delta: float = Field(
        default=0.0,
        ge=-1.0,
        le=1.0,
        description="User-baseline normalized delta for speech rate (-1.0 ~ 1.0).",
    )
    silence_ratio_delta: float = Field(
        default=0.0,
        ge=-1.0,
        le=1.0,
        description="User-baseline normalized delta for silence ratio (-1.0 ~ 1.0).",
    )
    energy_delta: float = Field(
        default=0.0,
        ge=-1.0,
        le=1.0,
        description="User-baseline normalized delta for vocal energy (-1.0 ~ 1.0).",
    )


class CheckinRequest(BaseModel):
    transcript: str = Field(..., min_length=1, description="STT result text.")
    self_report_stress: conint(ge=1, le=5)
    baseline_days: conint(ge=0) = 0
    trend_delta: float = Field(
        default=0.0,
        ge=-1.0,
        le=1.0,
        description="Today-vs-7day trend delta normalized to -1.0 ~ 1.0.",
    )
    voice_features: Optional[VoiceFeatures] = None

    @field_validator("transcript")
    @classmethod
    def transcript_must_not_be_blank(cls, value: str) -> str:
        stripped = value.strip()
        if not stripped:
            raise ValueError("transcript must not be blank")
        return stripped


class ComponentScore(BaseModel):
    self_report: float
    text_signal: float
    trend: float
    voice_aux: float


class AnalyzeResult(BaseModel):
    recovery_score: int
    risk_score: int
    confidence: float
    learning_mode: bool
    hold_decision: bool
    tags: List[str]
    explanation: str
    recommended_routines: List[str]
    component_scores: ComponentScore
    evidence: Dict[str, List[str]]


class ErrorResponse(BaseModel):
    error: str
    message: str
    request_id: str


class CheckinRecord(BaseModel):
    id: int
    created_at: str
    transcript: str
    recovery_score: int
    risk_score: int
    confidence: float
    hold_decision: bool
    tags: List[str]
    explanation: str


class CheckinListResponse(BaseModel):
    items: List[CheckinRecord]


class ReportTagStat(BaseModel):
    tag: str
    count: int


class ReportConfidenceBucket(BaseModel):
    low: int
    medium: int
    high: int


class ReportDailyPoint(BaseModel):
    date: str
    avg_recovery_score: float
    count: int


class ReportSummaryResponse(BaseModel):
    days: int
    total_checkins: int
    avg_recovery_score: float
    avg_risk_score: float
    avg_confidence: float
    latest_recovery_score: int | None
    latest_risk_score: int | None
    confidence_buckets: ReportConfidenceBucket
    top_tags: List[ReportTagStat]
    daily_recovery: List[ReportDailyPoint]
    previous_period: "ReportSummaryPeriod"


class ReportSummaryPeriod(BaseModel):
    total_checkins: int
    avg_recovery_score: float
    avg_risk_score: float
    avg_confidence: float


class STTResponse(BaseModel):
    transcript: str
    language: str
    provider: str
    profile: str
    model_name: str
    device: str
    compute_type: str
    duration_ms: int


class STTConfigResponse(BaseModel):
    provider: str
    profile: str
    model_name: str
    device: str
    compute_type: str
    beam_size: int
    vad_filter: bool


class STTProfilesResponse(BaseModel):
    profiles: Dict[str, Dict[str, object]]
