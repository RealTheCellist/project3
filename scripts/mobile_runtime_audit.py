from __future__ import annotations

import argparse
import csv
from pathlib import Path


def _to_bool(value: str) -> bool:
    return str(value).strip().lower() in {"1", "true", "yes", "y"}


def _has(rows: list[dict[str, str]], *, step: str, key: str, expect: bool) -> bool:
    for row in rows:
        if row.get("step", "").strip() != step:
            continue
        if _to_bool(row.get(key, "")) == expect:
            return True
    return False


def audit(rows: list[dict[str, str]]) -> dict[str, object]:
    total = len(rows)
    summary = {
        "total_runs": total,
        "meets_min_20_runs": total >= 20,
        "analyze_typed_text_ok": _has(
            rows, step="manual_text", key="analyze_ok", expect=True
        ),
        "stt_recording_flow_ok": _has(rows, step="stt_record", key="stt_ok", expect=True),
        "stt_fallback_ok": _has(
            rows, step="stt_fallback", key="fallback_used", expect=True
        ),
        "report_compare_ok": _has(
            rows, step="report_compare", key="analyze_ok", expect=True
        ),
        "export_csv_ok": _has(rows, step="export_csv", key="analyze_ok", expect=True),
        "export_pdf_local_ok": _has(
            rows, step="export_pdf_local", key="analyze_ok", expect=True
        ),
        "export_pdf_server_ok": _has(
            rows, step="export_pdf_server", key="analyze_ok", expect=True
        ),
    }
    summary["exports_ok"] = bool(
        summary["export_csv_ok"]
        and (summary["export_pdf_local_ok"] or summary["export_pdf_server_ok"])
    )
    summary["mobile_runtime_all_pass"] = bool(
        summary["meets_min_20_runs"]
        and summary["analyze_typed_text_ok"]
        and summary["stt_recording_flow_ok"]
        and summary["stt_fallback_ok"]
        and summary["report_compare_ok"]
        and summary["exports_ok"]
    )
    return summary


def render_markdown(summary: dict[str, object], source_csv: str) -> str:
    def mark(v: bool) -> str:
        return "PASS" if v else "FAIL"

    return "\n".join(
        [
            "# Mobile Runtime Audit",
            "",
            f"Source: `{source_csv}`",
            "",
            f"- Total runs >= 20: **{mark(bool(summary['meets_min_20_runs']))}** ({summary['total_runs']})",
            f"- Analyze flow (typed text): **{mark(bool(summary['analyze_typed_text_ok']))}**",
            f"- STT recording flow: **{mark(bool(summary['stt_recording_flow_ok']))}**",
            f"- STT fallback flow: **{mark(bool(summary['stt_fallback_ok']))}**",
            f"- Report compare flow: **{mark(bool(summary['report_compare_ok']))}**",
            f"- Export flow (CSV + PDF): **{mark(bool(summary['exports_ok']))}**",
            "",
            f"Overall mobile runtime gate: **{mark(bool(summary['mobile_runtime_all_pass']))}**",
        ]
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Audit mobile runtime checklist from beta run CSV.")
    parser.add_argument("--input", required=True, help="Beta run CSV path")
    parser.add_argument(
        "--output",
        default="data/mobile_runtime_audit.md",
        help="Audit markdown output path",
    )
    args = parser.parse_args()

    input_path = Path(args.input)
    rows: list[dict[str, str]] = []
    with input_path.open("r", encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        rows = [dict(r) for r in reader]

    summary = audit(rows)
    md = render_markdown(summary, args.input)
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(md, encoding="utf-8")
    print(md)


if __name__ == "__main__":
    main()

