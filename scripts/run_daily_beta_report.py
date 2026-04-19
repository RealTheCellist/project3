from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path


def _run(cmd: list[str]) -> None:
    completed = subprocess.run(cmd, check=False, capture_output=True, text=True)
    if completed.returncode != 0:
        raise RuntimeError(
            f"Command failed ({completed.returncode}): {' '.join(cmd)}\n"
            f"stdout:\n{completed.stdout}\n"
            f"stderr:\n{completed.stderr}"
        )


def _load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def build_daily_report_md(
    *,
    date: str,
    owner: str,
    build_label: str,
    log_csv: Path,
    kpi_json: Path,
    audit_md: Path,
    risk_md: Path,
    risk_json: Path,
) -> str:
    kpi = _load_json(kpi_json)
    risk = _load_json(risk_json)
    audit_text = audit_md.read_text(encoding="utf-8")
    overall_pass = "PASS" in audit_text.splitlines()[-1]

    return "\n".join(
        [
            "# Daily Beta Report",
            "",
            f"Date: {date}",
            f"Owner: {owner}",
            f"Build: {build_label}",
            "",
            "## 1) KPI Snapshot",
            f"- Total runs: {kpi.get('total_runs', 0)}",
            f"- Analyze success rate: {kpi.get('analyze_success_rate', 0)}%",
            f"- STT success rate: {kpi.get('stt_success_rate', 0)}%",
            f"- STT fallback rate: {kpi.get('stt_fallback_rate', 0)}%",
            f"- Avg latency(ms): {kpi.get('avg_latency_ms', 0)}",
            f"- P95 latency(ms): {kpi.get('p95_latency_ms', 0)}",
            "",
            "## 2) Mobile Runtime Gate",
            f"- Audit overall: {'PASS' if overall_pass else 'FAIL'}",
            f"- Audit file: `{audit_md.as_posix()}`",
            "",
            "## 3) Notes",
            "- Auto-generated report. Add qualitative findings/incidents manually if needed.",
            "",
            "## 4) Risk Monitor",
            f"- severity: {risk.get('severity', 'unknown')}",
            f"- action: {risk.get('action', '-')}",
            f"- rollback_recommended: {risk.get('rollback_recommended', False)}",
            f"- risk report: `{risk_md.as_posix()}`",
            "",
            "## 5) Raw Artifacts",
            f"- Beta run log CSV path: `{log_csv.as_posix()}`",
            f"- KPI summary JSON path: `{kpi_json.as_posix()}`",
            f"- Mobile runtime audit path: `{audit_md.as_posix()}`",
            f"- Risk monitor json path: `{risk_json.as_posix()}`",
        ]
    )


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Run daily beta KPI + mobile runtime audit and generate daily report."
    )
    parser.add_argument("--date", required=True, help="YYYY-MM-DD")
    parser.add_argument("--owner", default="TheCellist")
    parser.add_argument("--build", default="MVP beta")
    args = parser.parse_args()

    project_root = Path.cwd()
    data_dir = project_root / "data"
    log_csv = data_dir / f"beta_run_log_{args.date}.csv"
    kpi_json = data_dir / f"beta_kpi_summary_{args.date}.json"
    audit_md = data_dir / f"mobile_runtime_audit_{args.date}.md"
    risk_json = data_dir / f"risk_monitor_{args.date}.json"
    risk_md = data_dir / f"risk_monitor_{args.date}.md"
    report_md = project_root / f"DAILY_BETA_REPORT_{args.date}.md"

    if not log_csv.exists():
        raise FileNotFoundError(f"Log CSV not found: {log_csv}")

    _run(
        [
            sys.executable,
            "scripts/beta_kpi_summary.py",
            "--input",
            str(log_csv),
            "--output",
            str(kpi_json),
        ]
    )
    _run(
        [
            sys.executable,
            "scripts/mobile_runtime_audit.py",
            "--input",
            str(log_csv),
            "--output",
            str(audit_md),
        ]
    )
    _run(
        [
            sys.executable,
            "scripts/risk_monitor.py",
            "--date",
            args.date,
            "--kpi-json",
            str(kpi_json),
            "--audit-md",
            str(audit_md),
            "--json-output",
            str(risk_json),
            "--md-output",
            str(risk_md),
        ]
    )

    content = build_daily_report_md(
        date=args.date,
        owner=args.owner,
        build_label=args.build,
        log_csv=log_csv,
        kpi_json=kpi_json,
        audit_md=audit_md,
        risk_md=risk_md,
        risk_json=risk_json,
    )
    report_md.write_text(content, encoding="utf-8")
    print(f"generated: {report_md}")


if __name__ == "__main__":
    main()
