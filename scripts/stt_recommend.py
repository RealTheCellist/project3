from __future__ import annotations

import argparse
import csv
import json
import statistics
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional


@dataclass
class ProfileStats:
    profile: str
    ok_count: int
    err_count: int
    avg_latency_ms: Optional[float]
    avg_wer: Optional[float]
    score: Optional[float]


def _to_float(value: str) -> Optional[float]:
    text = (value or "").strip()
    if not text:
        return None
    try:
        return float(text)
    except ValueError:
        return None


def load_rows(path: Path) -> List[dict]:
    if not path.exists():
        raise FileNotFoundError(f"Results CSV not found: {path}")
    with path.open("r", encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def summarize(rows: List[dict]) -> List[ProfileStats]:
    grouped: Dict[str, List[dict]] = {}
    for row in rows:
        profile = (row.get("profile") or "").strip()
        if profile:
            grouped.setdefault(profile, []).append(row)

    stats: List[ProfileStats] = []
    for profile, items in grouped.items():
        ok_items = [r for r in items if (r.get("status") or "").strip() == "ok"]
        err_items = [r for r in items if (r.get("status") or "").strip() != "ok"]
        latencies = [_to_float(str(r.get("latency_ms", ""))) for r in ok_items]
        wers = [_to_float(str(r.get("wer", ""))) for r in ok_items]
        latencies = [x for x in latencies if x is not None]
        wers = [x for x in wers if x is not None]

        avg_latency = statistics.mean(latencies) if latencies else None
        avg_wer = statistics.mean(wers) if wers else None

        stats.append(
            ProfileStats(
                profile=profile,
                ok_count=len(ok_items),
                err_count=len(err_items),
                avg_latency_ms=avg_latency,
                avg_wer=avg_wer,
                score=None,
            )
        )
    return stats


def score_profiles(
    stats: List[ProfileStats],
    latency_weight: float,
    wer_weight: float,
    error_penalty: float,
) -> List[ProfileStats]:
    latency_values = [s.avg_latency_ms for s in stats if s.avg_latency_ms is not None]
    wer_values = [s.avg_wer for s in stats if s.avg_wer is not None]

    max_latency = max(latency_values) if latency_values else 1.0
    max_wer = max(wer_values) if wer_values else 1.0

    scored: List[ProfileStats] = []
    for s in stats:
        if s.ok_count == 0:
            score = None
        else:
            latency_term = ((s.avg_latency_ms or max_latency) / max_latency) * latency_weight
            wer_term = ((s.avg_wer or 0.0) / max_wer) * wer_weight if max_wer > 0 else 0.0
            err_rate = s.err_count / max(1, s.ok_count + s.err_count)
            penalty = err_rate * error_penalty
            score = latency_term + wer_term + penalty
        scored.append(
            ProfileStats(
                profile=s.profile,
                ok_count=s.ok_count,
                err_count=s.err_count,
                avg_latency_ms=s.avg_latency_ms,
                avg_wer=s.avg_wer,
                score=score,
            )
        )

    scored.sort(
        key=lambda x: (x.score is None, x.score if x.score is not None else 999999)
    )
    return scored


def print_report(scored: List[ProfileStats]) -> None:
    print("[stt recommendation report]")
    for s in scored:
        print(
            f"- {s.profile}: ok={s.ok_count}, err={s.err_count}, "
            f"avg_latency_ms={None if s.avg_latency_ms is None else round(s.avg_latency_ms, 1)}, "
            f"avg_wer={None if s.avg_wer is None else round(s.avg_wer, 4)}, "
            f"score={None if s.score is None else round(s.score, 4)}"
        )
    if scored and scored[0].score is not None:
        print(f"[recommended_profile] {scored[0].profile}")
    else:
        print("[recommended_profile] unable_to_decide")


def write_recommendation_json(scored: List[ProfileStats], output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    best = next((s for s in scored if s.score is not None), None)
    payload = {
        "recommended_profile": best.profile if best else None,
        "generated_from": "scripts/stt_recommend.py",
        "profiles": [
            {
                "profile": s.profile,
                "ok_count": s.ok_count,
                "err_count": s.err_count,
                "avg_latency_ms": s.avg_latency_ms,
                "avg_wer": s.avg_wer,
                "score": s.score,
            }
            for s in scored
        ],
    }
    with output.open("w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
    print(f"[saved] recommendation json: {output}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Recommend STT profile from benchmark CSV")
    parser.add_argument(
        "--input",
        type=Path,
        default=Path("data/stt_benchmark_results.csv"),
        help="Benchmark result CSV path.",
    )
    parser.add_argument("--latency-weight", type=float, default=0.4)
    parser.add_argument("--wer-weight", type=float, default=0.6)
    parser.add_argument("--error-penalty", type=float, default=1.0)
    parser.add_argument(
        "--output-json",
        type=Path,
        default=Path("data/stt_recommendation.json"),
        help="Output recommendation JSON path.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    rows = load_rows(args.input)
    stats = summarize(rows)
    if not stats:
        raise SystemExit("No profile rows found in CSV.")
    scored = score_profiles(
        stats,
        latency_weight=args.latency_weight,
        wer_weight=args.wer_weight,
        error_penalty=args.error_penalty,
    )
    print_report(scored)
    write_recommendation_json(scored, args.output_json)


if __name__ == "__main__":
    main()
