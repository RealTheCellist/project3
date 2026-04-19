from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from pathlib import Path


@dataclass
class ProfileAgg:
    attempts: int = 0
    success: int = 0
    fallback: int = 0
    latency_sum: float = 0.0

    def add(self, row: dict) -> None:
        attempts = int(row.get("attempts", 0) or 0)
        success = int(row.get("success", 0) or 0)
        fallback = int(row.get("fallback", 0) or 0)
        latency = float(row.get("avg_latency_ms", 0.0) or 0.0)

        self.attempts += attempts
        self.success += success
        self.fallback += fallback
        self.latency_sum += latency * attempts

    def to_metrics(self) -> dict:
        if self.attempts <= 0:
            return {
                "attempts": 0,
                "success_rate": 0.0,
                "fallback_rate": 0.0,
                "avg_latency_ms": 0.0,
            }
        return {
            "attempts": self.attempts,
            "success_rate": round((self.success / self.attempts) * 100, 2),
            "fallback_rate": round((self.fallback / self.attempts) * 100, 2),
            "avg_latency_ms": round(self.latency_sum / self.attempts, 2),
        }


def _load_json(path: Path) -> dict | None:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None


def _find_review_files(data_dir: Path, days: int) -> list[Path]:
    files = sorted(data_dir.glob("stt_profile_review_*.json"))
    if days <= 0:
        return files
    return files[-days:]


def _best_profile(summary: dict[str, dict]) -> str:
    # Score: prioritize low fallback + low latency, then success rate.
    best = "balanced"
    best_score = -10_000.0
    for profile, m in summary.items():
        attempts = float(m["attempts"])
        if attempts <= 0:
            continue
        success = float(m["success_rate"])
        fallback = float(m["fallback_rate"])
        latency = float(m["avg_latency_ms"])
        sample_bonus = min(10.0, attempts)
        score = success - (fallback * 1.5) - (latency / 180.0) + sample_bonus
        if score > best_score:
            best_score = score
            best = profile
    return best


def _suggest_rules(summary: dict[str, dict]) -> dict:
    best = _best_profile(summary)

    fast_fb = float(summary.get("fast", {}).get("fallback_rate", 0.0))
    balanced_fb = float(summary.get("balanced", {}).get("fallback_rate", 0.0))
    accurate_fb = float(summary.get("accurate", {}).get("fallback_rate", 0.0))
    fast_lat = float(summary.get("fast", {}).get("avg_latency_ms", 0.0))
    balanced_lat = float(summary.get("balanced", {}).get("avg_latency_ms", 0.0))
    accurate_lat = float(summary.get("accurate", {}).get("avg_latency_ms", 0.0))

    # Conservative thresholds from observed gap between fast and others.
    fallback_threshold = round(max(12.0, min(22.0, (fast_fb + balanced_fb) / 2.0)), 1)
    latency_threshold = round(max(1800.0, min(2400.0, (fast_lat + balanced_lat) / 2.0)), 1)

    good_profile = "balanced"
    if balanced_fb > fallback_threshold or balanced_lat > latency_threshold:
        good_profile = "fast"
    elif accurate_fb <= fallback_threshold and accurate_lat <= latency_threshold + 250.0:
        good_profile = "accurate"

    return {
        "preferred_default": best,
        "network_rules": {
            "poor": "fast",
            "normal": best,
            "good": good_profile,
        },
        "fallback_rate_override_threshold": fallback_threshold,
        "latency_override_threshold_ms": latency_threshold,
        "observed": {
            "fast": {"fallback_rate": fast_fb, "avg_latency_ms": fast_lat},
            "balanced": {"fallback_rate": balanced_fb, "avg_latency_ms": balanced_lat},
            "accurate": {"fallback_rate": accurate_fb, "avg_latency_ms": accurate_lat},
        },
    }


def _render_md(files: list[Path], summary: dict[str, dict], suggested: dict) -> str:
    lines = [
        "# STT Rules Tuning",
        "",
        "## Input Review Files",
    ]
    lines.extend([f"- `{p.as_posix()}`" for p in files])
    lines.extend(["", "## Aggregated Metrics"])
    for profile in ("fast", "balanced", "accurate"):
        m = summary.get(profile, {})
        lines.append(
            f"- `{profile}`: attempts={m.get('attempts', 0)}, "
            f"success_rate={m.get('success_rate', 0.0)}%, "
            f"fallback_rate={m.get('fallback_rate', 0.0)}%, "
            f"avg_latency_ms={m.get('avg_latency_ms', 0.0)}"
        )
    lines.extend(
        [
            "",
            "## Suggested Rules",
            f"- preferred_default: `{suggested['preferred_default']}`",
            f"- network poor: `{suggested['network_rules']['poor']}`",
            f"- network normal: `{suggested['network_rules']['normal']}`",
            f"- network good: `{suggested['network_rules']['good']}`",
            f"- fallback threshold: `{suggested['fallback_rate_override_threshold']}`",
            f"- latency threshold(ms): `{suggested['latency_override_threshold_ms']}`",
        ]
    )
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description="Tune STT auto-select rules from recent profile reviews.")
    parser.add_argument("--data-dir", default="data")
    parser.add_argument("--days", type=int, default=3)
    parser.add_argument("--json-output", default="data/stt_rules_tuning_latest.json")
    parser.add_argument("--md-output", default="data/stt_rules_tuning_latest.md")
    args = parser.parse_args()

    data_dir = Path(args.data_dir)
    files = _find_review_files(data_dir, args.days)
    if not files:
        raise SystemExit("No stt_profile_review_*.json files found.")

    agg = {p: ProfileAgg() for p in ("fast", "balanced", "accurate")}
    for f in files:
        payload = _load_json(f)
        if not payload or not isinstance(payload, dict):
            continue
        profiles = payload.get("profiles", {})
        if not isinstance(profiles, dict):
            continue
        for p in agg.keys():
            row = profiles.get(p, {})
            if isinstance(row, dict):
                agg[p].add(row)

    summary = {p: agg[p].to_metrics() for p in agg.keys()}
    suggested = _suggest_rules(summary)
    output = {
        "input_files": [p.as_posix() for p in files],
        "summary": summary,
        "suggested_rules": suggested,
    }

    json_out = Path(args.json_output)
    md_out = Path(args.md_output)
    json_out.parent.mkdir(parents=True, exist_ok=True)
    md_out.parent.mkdir(parents=True, exist_ok=True)
    json_out.write_text(json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8")
    md_out.write_text(_render_md(files, summary, suggested), encoding="utf-8")
    print(json.dumps(output, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

