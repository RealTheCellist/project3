from __future__ import annotations

from typing import Dict, List

from app.models.schemas import CheckinRequest, ComponentScore
from app.services.model_signal import analyze_text_signal_model
from app.services.text_signal import analyze_text_signal


TAG_LABELS_KO = {
    "anxiety": "\ubd88\uc548",
    "fatigue": "\ud53c\ub85c",
    "pressure": "\uc555\ubc15",
    "apathy": "\ubb34\uae30\ub825",
    "stable": "\uc548\uc815",
}


def _clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def _map_self_report(stress_1_to_5: int) -> float:
    return (stress_1_to_5 / 5.0) * 50.0


def _map_text_signal(text_risk_0_to_1: float) -> float:
    return _clamp(text_risk_0_to_1, 0.0, 1.0) * 35.0


def _map_trend_delta(trend_delta: float) -> float:
    normalized = _clamp((trend_delta + 1.0) / 2.0, 0.0, 1.0)
    return normalized * 10.0


def _map_voice_aux(req: CheckinRequest) -> float:
    if not req.voice_features:
        return 0.0
    vf = req.voice_features
    composite = (vf.speech_rate_delta + vf.silence_ratio_delta + vf.energy_delta) / 3.0
    normalized = _clamp((composite + 1.0) / 2.0, 0.0, 1.0)
    return normalized * 5.0


def _recommend_routines(tags: List[str]) -> List[str]:
    if "anxiety" in tags:
        return ["4-7-8 \ud638\ud761 3\ubd84", "\uc9e7\uc740 \uc0b0\ucc45 5\ubd84"]
    if "fatigue" in tags:
        return ["\ubaa9/\uc5b4\uae68 \uc2a4\ud2b8\ub808\uce6d 3\ubd84", "\ub208 \ud734\uc2dd 2\ubd84"]
    if "pressure" in tags:
        return ["\ud560 \uc77c 3\uac1c\ub9cc \uc7ac\uc815\ub82c 3\ubd84", "\uc9d1\uc911 \ud0c0\uc774\uba38 10\ubd84"]
    if "apathy" in tags:
        return ["\ubb3c \ud55c \ucef5 + \uae30\uc9c0\uac1c 2\ubd84", "\uc544\uc8fc \uc791\uc740 \uc2dc\uc791 \ud589\ub3d9 1\uac1c"]
    return ["\ud604\uc7ac \ub9ac\ub4ec \uc720\uc9c0: \ud638\ud761 2\ubd84", "\uc624\ub298 \uac10\uc0ac 1\ubb38\uc7a5"]


def _compute_confidence(req: CheckinRequest, total_hits: int) -> float:
    transcript_len_factor = min(1.0, len(req.transcript.strip()) / 120.0)
    evidence_factor = min(1.0, total_hits / 3.0)
    baseline_factor = min(1.0, req.baseline_days / 14.0)
    confidence = 0.25 + 0.35 * transcript_len_factor + 0.25 * evidence_factor + 0.15 * baseline_factor
    return round(_clamp(confidence, 0.0, 1.0), 2)


def _to_ko_tags(tags: List[str]) -> List[str]:
    return [TAG_LABELS_KO.get(tag, tag) for tag in tags]


def _to_ko_evidence(evidence: Dict[str, List[str]]) -> Dict[str, List[str]]:
    converted: Dict[str, List[str]] = {}
    for key, value in evidence.items():
        converted[TAG_LABELS_KO.get(key, key)] = value
    return converted


def analyze_checkin(req: CheckinRequest) -> Dict[str, object]:
    text_result = analyze_text_signal_model(req.transcript) or analyze_text_signal(
        req.transcript
    )
    text_risk = float(text_result["text_risk"])

    comp = ComponentScore(
        self_report=round(_map_self_report(req.self_report_stress), 2),
        text_signal=round(_map_text_signal(text_risk), 2),
        trend=round(_map_trend_delta(req.trend_delta), 2),
        voice_aux=round(_map_voice_aux(req), 2),
    )

    risk_score = int(round(comp.self_report + comp.text_signal + comp.trend + comp.voice_aux))
    risk_score = int(_clamp(risk_score, 0.0, 100.0))
    recovery_score = int(_clamp(100 - risk_score, 0.0, 100.0))

    learning_mode = req.baseline_days < 14
    confidence = _compute_confidence(req, int(text_result["total_hits"]))
    hold_decision = confidence < 0.45

    tags_en = list(text_result["tags"])
    tags_ko = _to_ko_tags(tags_en)
    routines = _recommend_routines(tags_en)

    if hold_decision:
        explanation = "\ub370\uc774\ud130 \uc2e0\ub8b0\ub3c4\uac00 \ub0ae\uc544 \uc624\ub298\uc740 \ud310\ub2e8\uc744 \ubcf4\ub958\ud558\uace0, \uccb4\ud06c\uc778\uc744 2~3\ud68c \ub354 \uc313\ub294 \uac83\uc744 \uad8c\uc7a5\ud569\ub2c8\ub2e4."
    elif learning_mode:
        explanation = "\ud559\uc2b5\uae30\uac04 \uacb0\uacfc\uc785\ub2c8\ub2e4. \uac1c\uc778 \uae30\uc900\uc120\uc774 \uc644\uc131\ub418\uba74 \ubcc0\ud654\ub97c \ub354 \uc815\ud655\ud788 \uc548\ub0b4\ud569\ub2c8\ub2e4."
    else:
        explanation = f"\ucd5c\uadfc \ud328\ud134\uc0c1 {', '.join(tags_ko[:2])} \uc2e0\ud638\uac00 \ubcf4\uc5ec \uc9e7\uc740 \ud68c\ubcf5 \ub8e8\ud2f4\uc744 \uad8c\uc7a5\ud569\ub2c8\ub2e4."

    return {
        "recovery_score": recovery_score,
        "risk_score": risk_score,
        "confidence": confidence,
        "learning_mode": learning_mode,
        "hold_decision": hold_decision,
        "tags": tags_ko,
        "explanation": explanation,
        "recommended_routines": routines,
        "component_scores": comp,
        "evidence": _to_ko_evidence(text_result["evidence"]),
    }
