from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path


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


def summarize(path: Path) -> dict:
    total = 0
    analyze_success = 0
    stt_success = 0
    fallback_used = 0
    latencies: list[float] = []
    by_scenario: dict[str, dict[str, int]] = {}

    with path.open("r", encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            total += 1
            scenario = (row.get("scenario") or "unknown").strip()
            sc = by_scenario.setdefault(
                scenario,
                {"total": 0, "analyze_success": 0, "stt_success": 0, "fallback_used": 0},
            )
            sc["total"] += 1

            if _to_bool(row.get("analyze_ok", "")):
                analyze_success += 1
                sc["analyze_success"] += 1
            if _to_bool(row.get("stt_ok", "")):
                stt_success += 1
                sc["stt_success"] += 1
            if _to_bool(row.get("fallback_used", "")):
                fallback_used += 1
                sc["fallback_used"] += 1

            latency = _to_float(row.get("latency_ms", ""))
            if latency is not None:
                latencies.append(latency)

    avg_latency = sum(latencies) / len(latencies) if latencies else 0.0
    p95_latency = 0.0
    if latencies:
        sorted_lat = sorted(latencies)
        idx = min(len(sorted_lat) - 1, int(len(sorted_lat) * 0.95))
        p95_latency = sorted_lat[idx]

    return {
        "total_runs": total,
        "analyze_success_rate": round((analyze_success / total) * 100, 2) if total else 0.0,
        "stt_success_rate": round((stt_success / total) * 100, 2) if total else 0.0,
        "stt_fallback_rate": round((fallback_used / total) * 100, 2) if total else 0.0,
        "avg_latency_ms": round(avg_latency, 2),
        "p95_latency_ms": round(p95_latency, 2),
        "by_scenario": by_scenario,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Summarize beta KPI log CSV.")
    parser.add_argument("--input", required=True, help="Input beta run CSV path")
    parser.add_argument(
        "--output",
        default="data/beta_kpi_summary.json",
        help="Output JSON path (default: data/beta_kpi_summary.json)",
    )
    args = parser.parse_args()

    in_path = Path(args.input)
    out_path = Path(args.output)
    summary = summarize(in_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

