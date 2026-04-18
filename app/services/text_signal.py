from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, List, Tuple


@dataclass(frozen=True)
class LabelProfile:
    label: str
    keywords: Tuple[str, ...]


LABELS: Tuple[LabelProfile, ...] = (
    LabelProfile("anxiety", ("\ubd88\uc548", "\ucd08\uc870", "\uae34\uc7a5", "\uac71\uc815", "nervous", "anxious")),
    LabelProfile("fatigue", ("\ud53c\uace4", "\uc9c0\uce68", "\ud53c\ub85c", "\ud798\ub4e4", "\uc9c0\ucce4", "tired", "exhausted")),
    LabelProfile("pressure", ("\uc555\ubc15", "\ubd80\ub2f4", "\ub9c8\uac10", "\ucabc\uae30", "pressure", "deadline")),
    LabelProfile("apathy", ("\ubb34\uae30\ub825", "\uc758\uc695\uc5c6", "\uba4d\ud568", "\uc544\ubb34\uac83\ub3c4", "empty", "drained")),
    LabelProfile("stable", ("\uad1c\ucc2e", "\ud3c9\uc628", "\ucc28\ubd84", "\uc548\uc815", "calm", "steady")),
)


def _count_matches(text: str, keywords: Tuple[str, ...]) -> Tuple[int, List[str]]:
    matches: List[str] = []
    for kw in keywords:
        if kw in text:
            matches.append(kw)
    return len(matches), matches


def analyze_text_signal(transcript: str) -> Dict[str, object]:
    text = transcript.lower().strip()
    per_label_counts: Dict[str, int] = {}
    evidence: Dict[str, List[str]] = {}

    total_hits = 0
    for profile in LABELS:
        count, matches = _count_matches(text, profile.keywords)
        per_label_counts[profile.label] = count
        evidence[profile.label] = matches
        total_hits += count

    risk_labels = ("anxiety", "fatigue", "pressure", "apathy")
    risk_hits = sum(per_label_counts[label] for label in risk_labels)
    stable_hits = per_label_counts["stable"]

    raw = max(0.0, (risk_hits - 0.5 * stable_hits) / 6.0)
    text_risk = min(1.0, raw)

    sorted_labels = sorted(LABELS, key=lambda p: per_label_counts[p.label], reverse=True)
    tags = [p.label for p in sorted_labels if per_label_counts[p.label] > 0][:3]
    if not tags:
        tags = ["stable"]

    return {
        "text_risk": text_risk,
        "tags": tags,
        "evidence": evidence,
        "total_hits": total_hits,
    }
