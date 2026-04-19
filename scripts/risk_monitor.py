from __future__ import annotations

import argparse
import json
from pathlib import Path


def _load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _load_audit_pass(path: Path) -> bool:
    text = path.read_text(encoding="utf-8")
    return "Overall mobile runtime gate: **PASS**" in text


def evaluate_risk(
    *,
    kpi: dict,
    audit_pass: bool,
    min_analyze_success_rate: float,
    max_fallback_rate: float,
    max_p95_latency_ms: float,
) -> dict:
    analyze_success_rate = float(kpi.get("analyze_success_rate", 0.0))
    fallback_rate = float(kpi.get("stt_fallback_rate", 0.0))
    p95_latency = float(kpi.get("p95_latency_ms", 0.0))
    total_runs = int(kpi.get("total_runs", 0))

    alerts: list[str] = []
    if analyze_success_rate < min_analyze_success_rate:
        alerts.append(
            f"analyze_success_rate low ({analyze_success_rate:.2f}% < {min_analyze_success_rate:.2f}%)"
        )
    if fallback_rate > max_fallback_rate:
        alerts.append(
            f"stt_fallback_rate high ({fallback_rate:.2f}% > {max_fallback_rate:.2f}%)"
        )
    if p95_latency > max_p95_latency_ms:
        alerts.append(
            f"p95_latency high ({p95_latency:.2f}ms > {max_p95_latency_ms:.2f}ms)"
        )
    if not audit_pass:
        alerts.append("mobile runtime audit gate failed")
    if total_runs < 20:
        alerts.append("insufficient sample size (<20 runs)")

    if not alerts:
        severity = "normal"
        action = "continue monitoring"
    elif any("analyze_success_rate low" in a for a in alerts):
        severity = "sev2"
        action = "open incident and prepare rollback decision"
    elif any("mobile runtime audit gate failed" in a for a in alerts):
        severity = "sev2"
        action = "open incident and stop external rollout"
    else:
        severity = "warning"
        action = "monitor closely and apply tuning"

    rollback_recommended = severity == "sev2"

    return {
        "severity": severity,
        "action": action,
        "rollback_recommended": rollback_recommended,
        "alerts": alerts,
        "snapshot": {
            "total_runs": total_runs,
            "analyze_success_rate": analyze_success_rate,
            "stt_fallback_rate": fallback_rate,
            "p95_latency_ms": p95_latency,
            "mobile_runtime_audit_pass": audit_pass,
        },
    }


def render_markdown(
    *,
    date: str,
    result: dict,
    kpi_json_path: Path,
    audit_md_path: Path,
) -> str:
    lines = [
        "# Daily Risk Monitor",
        "",
        f"Date: {date}",
        f"KPI source: `{kpi_json_path.as_posix()}`",
        f"Audit source: `{audit_md_path.as_posix()}`",
        "",
        f"- Severity: **{result['severity']}**",
        f"- Action: {result['action']}",
        f"- Rollback recommended: **{'YES' if result['rollback_recommended'] else 'NO'}**",
        "",
        "## Snapshot",
        f"- total_runs: {result['snapshot']['total_runs']}",
        f"- analyze_success_rate: {result['snapshot']['analyze_success_rate']}%",
        f"- stt_fallback_rate: {result['snapshot']['stt_fallback_rate']}%",
        f"- p95_latency_ms: {result['snapshot']['p95_latency_ms']}",
        f"- mobile_runtime_audit_pass: {result['snapshot']['mobile_runtime_audit_pass']}",
        "",
        "## Alerts",
    ]
    if result["alerts"]:
        lines.extend([f"- {a}" for a in result["alerts"]])
    else:
        lines.append("- none")
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description="Daily risk monitor from KPI/audit outputs.")
    parser.add_argument("--date", required=True, help="YYYY-MM-DD")
    parser.add_argument("--kpi-json", required=True, help="KPI summary JSON path")
    parser.add_argument("--audit-md", required=True, help="Mobile runtime audit markdown path")
    parser.add_argument("--json-output", default="data/risk_monitor.json")
    parser.add_argument("--md-output", default="data/risk_monitor.md")
    parser.add_argument("--min-analyze-success-rate", type=float, default=90.0)
    parser.add_argument("--max-fallback-rate", type=float, default=20.0)
    parser.add_argument("--max-p95-latency-ms", type=float, default=4000.0)
    args = parser.parse_args()

    kpi_json_path = Path(args.kpi_json)
    audit_md_path = Path(args.audit_md)
    kpi = _load_json(kpi_json_path)
    audit_pass = _load_audit_pass(audit_md_path)
    result = evaluate_risk(
        kpi=kpi,
        audit_pass=audit_pass,
        min_analyze_success_rate=args.min_analyze_success_rate,
        max_fallback_rate=args.max_fallback_rate,
        max_p95_latency_ms=args.max_p95_latency_ms,
    )

    json_out = Path(args.json_output)
    md_out = Path(args.md_output)
    json_out.parent.mkdir(parents=True, exist_ok=True)
    md_out.parent.mkdir(parents=True, exist_ok=True)
    json_out.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    md_out.write_text(
        render_markdown(
            date=args.date,
            result=result,
            kpi_json_path=kpi_json_path,
            audit_md_path=audit_md_path,
        ),
        encoding="utf-8",
    )
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

