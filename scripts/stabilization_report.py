from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


KPI_PATTERN = re.compile(r"^beta_kpi_summary_(\d{4}-\d{2}-\d{2})\.json$")
RISK_PATTERN = re.compile(r"^risk_monitor_(\d{4}-\d{2}-\d{2})\.json$")


def _load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _latest_dates(data_dir: Path, pattern: re.Pattern[str], count: int) -> list[str]:
    dates: list[str] = []
    for p in data_dir.iterdir():
        m = pattern.match(p.name)
        if m:
            dates.append(m.group(1))
    return sorted(dates)[-count:]


def build_report(data_dir: Path, days: int) -> str:
    kpi_dates = _latest_dates(data_dir, KPI_PATTERN, days)
    risk_dates = set(_latest_dates(data_dir, RISK_PATTERN, days))
    if not kpi_dates:
        return "# Stabilization Report\n\nNo KPI files found."

    lines = [
        "# Stabilization Report",
        "",
        f"Window: latest {len(kpi_dates)} day(s)",
        "",
        "## Daily Snapshot",
    ]

    stable = True
    for d in kpi_dates:
        kpi = _load_json(data_dir / f"beta_kpi_summary_{d}.json")
        risk_path = data_dir / f"risk_monitor_{d}.json"
        risk = _load_json(risk_path) if d in risk_dates and risk_path.exists() else {}
        sev = str(risk.get("severity", "unknown"))
        if sev not in {"normal", "warning"}:
            stable = False
        fallback = float(kpi.get("stt_fallback_rate", 0.0))
        if fallback > 20.0:
            stable = False
        lines.append(
            f"- {d}: analyze={kpi.get('analyze_success_rate', 0)}%, "
            f"fallback={fallback}%, p95={kpi.get('p95_latency_ms', 0)}ms, severity={sev}"
        )

    lines.extend(
        [
            "",
            "## Assessment",
            f"- Stabilization state: **{'STABLE' if stable else 'WATCH'}**",
            "- Criteria: severity not critical and fallback-rate <= 20%",
        ]
    )
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description="Build stabilization report from daily KPI/risk files.")
    parser.add_argument("--days", type=int, default=3)
    parser.add_argument("--output", default="STABILIZATION_REPORT.md")
    args = parser.parse_args()

    root = Path.cwd()
    data_dir = root / "data"
    report = build_report(data_dir, args.days)
    out = Path(args.output)
    out.write_text(report, encoding="utf-8")
    print(f"generated: {out}")


if __name__ == "__main__":
    main()

