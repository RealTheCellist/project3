from __future__ import annotations

import argparse
import csv
import json
from dataclasses import dataclass
from pathlib import Path


PROFILES = ("fast", "balanced", "accurate")


@dataclass
class ProfileStats:
    attempts: int = 0
    success: int = 0
    fallback: int = 0
    latency_sum: float = 0.0
    latency_count: int = 0

    def to_dict(self) -> dict:
        success_rate = (self.success / self.attempts * 100) if self.attempts else 0.0
        fallback_rate = (self.fallback / self.attempts * 100) if self.attempts else 0.0
        avg_latency = self.latency_sum / self.latency_count if self.latency_count else 0.0
        return {
            "attempts": self.attempts,
            "success": self.success,
            "success_rate": round(success_rate, 2),
            "fallback": self.fallback,
            "fallback_rate": round(fallback_rate, 2),
            "avg_latency_ms": round(avg_latency, 2),
        }


def _to_bool(value: str) -> bool:
    return str(value).strip().lower() in {"1", "true", "yes", "y"}


def _to_float(value: str) -> float | None:
    raw = str(value).strip()
    if not raw:
        return None
    try:
        return float(raw)
    except ValueError:
        return None


def _infer_profile(note: str) -> str | None:
    n = (note or "").lower()
    for p in PROFILES:
        if f"profile={p}" in n:
            return p
    for p in PROFILES:
        if p in n:
            return p
    return None


def summarize(csv_path: Path) -> dict:
    stats = {p: ProfileStats() for p in PROFILES}
    unknown_attempts = 0

    with csv_path.open("r", encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            step = (row.get("step") or "").strip().lower()
            if step not in {"stt_record", "stt_fallback"}:
                continue

            profile = _infer_profile(row.get("note", ""))
            if profile is None:
                unknown_attempts += 1
                continue

            st = stats[profile]
            st.attempts += 1
            if _to_bool(row.get("stt_ok", "")):
                st.success += 1
            if _to_bool(row.get("fallback_used", "")):
                st.fallback += 1
            latency = _to_float(row.get("latency_ms", ""))
            if latency is not None and latency > 0:
                st.latency_sum += latency
                st.latency_count += 1

    details = {p: stats[p].to_dict() for p in PROFILES}
    recommendation = _recommend(details)
    return {
        "source_csv": csv_path.as_posix(),
        "unknown_profile_attempts": unknown_attempts,
        "profiles": details,
        "recommended_profile": recommendation["profile"],
        "recommendation_reason": recommendation["reason"],
    }


def _recommend(details: dict[str, dict]) -> dict[str, str]:
    # Weighted score: prioritize success, then fallback rate, then latency.
    # Add sample-size guardrail: <3 attempts gets heavy penalty.
    best_profile = "balanced"
    best_score = -10_000.0
    best_reason = "default"

    for profile, d in details.items():
        attempts = float(d["attempts"])
        success_rate = float(d["success_rate"])
        fallback_rate = float(d["fallback_rate"])
        avg_latency = float(d["avg_latency_ms"]) if d["avg_latency_ms"] else 9999.0

        sample_penalty = 0.0
        if attempts < 3:
            sample_penalty = (3 - attempts) * 20.0
        latency_penalty = min(30.0, avg_latency / 200.0)
        score = success_rate - (fallback_rate * 0.7) - latency_penalty - sample_penalty

        if score > best_score:
            best_score = score
            best_profile = profile
            best_reason = (
                f"score={score:.2f}, success={success_rate:.2f}%, "
                f"fallback={fallback_rate:.2f}%, latency={avg_latency:.2f}ms, attempts={attempts:.0f}"
            )

    return {"profile": best_profile, "reason": best_reason}


def render_md(summary: dict) -> str:
    lines = [
        "# STT Profile Review",
        "",
        f"Source: `{summary['source_csv']}`",
        f"- Unknown profile attempts: {summary['unknown_profile_attempts']}",
        "",
        "## Per Profile",
    ]
    for p in PROFILES:
        d = summary["profiles"][p]
        lines.extend(
            [
                f"- `{p}`: attempts={d['attempts']}, success_rate={d['success_rate']}%, "
                f"fallback_rate={d['fallback_rate']}%, avg_latency_ms={d['avg_latency_ms']}",
            ]
        )
    lines.extend(
        [
            "",
            "## Recommendation",
            f"- recommended_profile: **{summary['recommended_profile']}**",
            f"- reason: {summary['recommendation_reason']}",
        ]
    )
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description="Review STT profile performance from beta log CSV.")
    parser.add_argument("--input", required=True, help="input beta run CSV")
    parser.add_argument("--json-output", default="data/stt_profile_review.json")
    parser.add_argument("--md-output", default="data/stt_profile_review.md")
    args = parser.parse_args()

    input_path = Path(args.input)
    summary = summarize(input_path)

    json_out = Path(args.json_output)
    md_out = Path(args.md_output)
    json_out.parent.mkdir(parents=True, exist_ok=True)
    md_out.parent.mkdir(parents=True, exist_ok=True)

    json_out.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    md_out.write_text(render_md(summary), encoding="utf-8")

    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

