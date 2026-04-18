from __future__ import annotations

import json
import os
import time
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Dict, Tuple


@dataclass(frozen=True)
class STTRuntimeConfig:
    provider: str
    profile: str
    model_name: str
    device: str
    compute_type: str
    beam_size: int
    vad_filter: bool


@dataclass(frozen=True)
class STTResult:
    transcript: str
    provider: str
    profile: str
    model_name: str
    device: str
    compute_type: str
    duration_ms: int


class STTServiceError(RuntimeError):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


def _env_flag(name: str, default: bool) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def _profiles() -> dict:
    return {
        "fast": {
            "model_name": "tiny",
            "beam_size": 1,
            "vad_filter": True,
        },
        "balanced": {
            "model_name": "small",
            "beam_size": 3,
            "vad_filter": True,
        },
        "accurate": {
            "model_name": "medium",
            "beam_size": 5,
            "vad_filter": True,
        },
    }


def list_stt_profiles() -> Dict[str, dict]:
    return _profiles()


def _recommendation_file_path() -> Path:
    return Path(os.getenv("STT_RECOMMENDATION_FILE", "data/stt_recommendation.json"))


def _recommended_profile_from_file() -> str | None:
    path = _recommendation_file_path()
    if not path.exists():
        return None
    try:
        with path.open("r", encoding="utf-8") as f:
            payload = json.load(f)
    except Exception:
        return None
    value = str(payload.get("recommended_profile", "")).strip().lower()
    if value in _profiles():
        return value
    return None


def get_stt_runtime_config(profile_override: str | None = None) -> STTRuntimeConfig:
    default_profile = os.getenv("STT_PROFILE", "").strip().lower() or (
        _recommended_profile_from_file() or "balanced"
    )
    profile = (profile_override or default_profile).strip().lower()
    defaults = _profiles().get(profile, _profiles()["balanced"])

    provider = os.getenv("STT_PROVIDER", "faster_whisper").strip().lower()
    model_name = os.getenv("WHISPER_MODEL_SIZE", defaults["model_name"])
    device = os.getenv("WHISPER_DEVICE", "cpu")
    compute_type = os.getenv("WHISPER_COMPUTE_TYPE", "int8")
    beam_size = int(os.getenv("WHISPER_BEAM_SIZE", str(defaults["beam_size"])))
    vad_filter = _env_flag("WHISPER_VAD_FILTER", defaults["vad_filter"])

    # OpenAI whisper backend doesn't use compute_type directly; keep for observability.
    return STTRuntimeConfig(
        provider=provider,
        profile=profile,
        model_name=model_name,
        device=device,
        compute_type=compute_type,
        beam_size=beam_size,
        vad_filter=vad_filter,
    )


@lru_cache(maxsize=1)
def _load_faster_whisper_model(model_name: str, device: str, compute_type: str):
    from faster_whisper import WhisperModel  # type: ignore

    return WhisperModel(
        model_name,
        device=device,
        compute_type=compute_type,
    )


@lru_cache(maxsize=1)
def _load_openai_whisper_model(model_name: str):
    import whisper  # type: ignore

    return whisper.load_model(model_name)


def _transcribe_faster_whisper(
    audio_path: str, language: str, cfg: STTRuntimeConfig
) -> Tuple[str, str]:
    model = _load_faster_whisper_model(cfg.model_name, cfg.device, cfg.compute_type)
    segments, _info = model.transcribe(
        audio_path,
        language=language or None,
        vad_filter=cfg.vad_filter,
        beam_size=cfg.beam_size,
    )
    text = " ".join(seg.text.strip() for seg in segments if seg.text.strip()).strip()
    return text, "faster_whisper"


def _transcribe_openai_whisper(
    audio_path: str, language: str, cfg: STTRuntimeConfig
) -> Tuple[str, str]:
    model = _load_openai_whisper_model(cfg.model_name)
    result = model.transcribe(audio_path, language=language or None)
    text = str(result.get("text", "")).strip()
    return text, "openai_whisper"


def transcribe_audio_file(
    audio_path: str, language: str = "ko", profile: str | None = None
) -> STTResult:
    file_path = Path(audio_path)
    if not file_path.exists():
        raise STTServiceError("audio_not_found", "Audio file not found")

    cfg = get_stt_runtime_config(profile_override=profile)
    started = time.perf_counter()

    try:
        if cfg.provider == "openai_whisper":
            text, used_provider = _transcribe_openai_whisper(audio_path, language, cfg)
        else:
            text, used_provider = _transcribe_faster_whisper(audio_path, language, cfg)
    except ImportError as err:
        raise STTServiceError(
            "backend_not_installed",
            "Whisper backend is not installed. Install requirements-stt.txt.",
        ) from err
    except Exception as err:
        raise STTServiceError("transcription_failed", f"STT transcription failed: {err}") from err

    if not text:
        raise STTServiceError("empty_transcript", "STT returned empty transcript")

    elapsed = int((time.perf_counter() - started) * 1000)
    return STTResult(
        transcript=text,
        provider=used_provider,
        profile=cfg.profile,
        model_name=cfg.model_name,
        device=cfg.device,
        compute_type=cfg.compute_type,
        duration_ms=elapsed,
    )
