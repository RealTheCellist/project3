from __future__ import annotations

import os
from dataclasses import dataclass
from functools import lru_cache
from typing import Dict, List, Optional


@dataclass(frozen=True)
class ModelConfig:
    enabled: bool
    model_name: str
    hypothesis_template: str
    max_chars: int


def _env_flag(name: str, default: bool) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def get_model_config() -> ModelConfig:
    return ModelConfig(
        enabled=_env_flag("TEXT_SIGNAL_MODEL_ENABLED", False),
        model_name=os.getenv("TEXT_SIGNAL_MODEL_NAME", "joeddav/xlm-roberta-large-xnli"),
        hypothesis_template=os.getenv(
            "TEXT_SIGNAL_HYPOTHESIS_TEMPLATE", "이 문장은 {} 상태를 나타낸다."
        ),
        max_chars=int(os.getenv("TEXT_SIGNAL_MAX_CHARS", "1200")),
    )


@lru_cache(maxsize=1)
def _get_zero_shot_pipeline():
    from transformers import pipeline  # type: ignore

    cfg = get_model_config()
    return pipeline(
        "zero-shot-classification",
        model=cfg.model_name,
        tokenizer=cfg.model_name,
    )


def analyze_text_signal_model(transcript: str) -> Optional[Dict[str, object]]:
    cfg = get_model_config()
    if not cfg.enabled:
        return None

    text = transcript.strip()
    if not text:
        return None

    text = text[: cfg.max_chars]
    labels = ["anxiety", "fatigue", "pressure", "apathy", "stable"]

    label_map_ko = {
        "anxiety": "불안",
        "fatigue": "피로",
        "pressure": "압박",
        "apathy": "무기력",
        "stable": "안정",
    }

    try:
        clf = _get_zero_shot_pipeline()
        output = clf(
            text,
            candidate_labels=labels,
            hypothesis_template=cfg.hypothesis_template,
            multi_label=True,
        )
    except Exception:
        # Any model init/inference failure should fall back to rules.
        return None

    scores_raw: Dict[str, float] = {}
    for label, score in zip(output.get("labels", []), output.get("scores", [])):
        scores_raw[str(label)] = float(score)

    # Ensure all labels exist.
    scores = {k: float(scores_raw.get(k, 0.0)) for k in labels}

    # Risk estimate centered on risk labels with stability discount.
    risk_prob = (
        0.28 * scores["anxiety"]
        + 0.26 * scores["fatigue"]
        + 0.24 * scores["pressure"]
        + 0.22 * scores["apathy"]
    )
    text_risk = max(0.0, min(1.0, risk_prob - 0.25 * scores["stable"]))

    ordered = sorted(labels, key=lambda label: scores[label], reverse=True)
    tags = ordered[:3]

    evidence: Dict[str, List[str]] = {}
    for label in labels:
        ko = label_map_ko[label]
        evidence[label] = [f"{ko}:{scores[label]:.2f}"]

    total_hits = max(1, sum(1 for label in labels if scores[label] >= 0.35))

    return {
        "text_risk": text_risk,
        "tags": tags,
        "evidence": evidence,
        "total_hits": total_hits,
        "source": "model",
    }
