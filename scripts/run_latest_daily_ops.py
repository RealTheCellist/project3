from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path


LOG_PATTERN = re.compile(r"^beta_run_log_(\d{4}-\d{2}-\d{2})\.csv$")


def _run(cmd: list[str]) -> None:
    completed = subprocess.run(cmd, check=False, capture_output=True, text=True)
    if completed.returncode != 0:
        raise RuntimeError(
            f"command failed ({completed.returncode}): {' '.join(cmd)}\n"
            f"stdout:\n{completed.stdout}\n"
            f"stderr:\n{completed.stderr}"
        )


def _find_latest_date(data_dir: Path) -> str | None:
    dates: list[str] = []
    for p in data_dir.glob("beta_run_log_*.csv"):
        m = LOG_PATTERN.match(p.name)
        if m:
            dates.append(m.group(1))
    if not dates:
        return None
    return max(dates)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Run daily ops pipeline for a specific date or latest beta log date."
    )
    parser.add_argument("--date", help="YYYY-MM-DD; if omitted, use latest beta_run_log_*.csv")
    parser.add_argument("--owner", default="TheCellist")
    parser.add_argument("--build", default="MVP beta")
    args = parser.parse_args()

    root = Path.cwd()
    data_dir = root / "data"
    date = args.date or _find_latest_date(data_dir)
    if not date:
        print("no beta log found in data/. nothing to run.")
        return

    daily_log = data_dir / f"beta_run_log_{date}.csv"
    if not daily_log.exists():
        print(f"log not found: {daily_log}")
        return

    _run(
        [
            sys.executable,
            "scripts/run_daily_beta_report.py",
            "--date",
            date,
            "--owner",
            args.owner,
            "--build",
            args.build,
        ]
    )
    _run(
        [
            sys.executable,
            "scripts/stt_profile_review.py",
            "--input",
            str(daily_log),
            "--json-output",
            f"data/stt_profile_review_{date}.json",
            "--md-output",
            f"data/stt_profile_review_{date}.md",
        ]
    )
    review_json = f"data/stt_profile_review_{date}.json"
    rules_json = "data/stt_autoselect_rules.json"
    for network in ("poor", "normal", "good"):
        _run(
            [
                sys.executable,
                "scripts/stt_profile_autoselect.py",
                "--network",
                network,
                "--rules",
                rules_json,
                "--review-json",
                review_json,
                "--output",
                f"data/stt_autoselect_{network}_{date}.json",
            ]
        )

    runtime_sync = root / "data" / f"stt_runtime_sync_{date}.md"
    runtime_sync.write_text(
        "\n".join(
            [
                "# STT Runtime Sync",
                "",
                f"- date: {date}",
                f"- review_json: {review_json}",
                f"- rules_json: {rules_json}",
                "- generated_profiles:",
                f"  - data/stt_autoselect_poor_{date}.json",
                f"  - data/stt_autoselect_normal_{date}.json",
                f"  - data/stt_autoselect_good_{date}.json",
                "",
                "## Runtime env reference",
                "- STT_AUTOSELECT_RULES_FILE=data/stt_autoselect_rules.json",
                f"- STT_PROFILE_REVIEW_FILE=data/stt_profile_review_{date}.json",
                "",
                "## App/API usage",
                "- call /stt with profile=auto and network=poor|normal|good",
                "- call /stt/config with profile=auto and network=poor|normal|good",
                "",
            ]
        ),
        encoding="utf-8",
    )
    print(f"daily ops completed for {date}")


if __name__ == "__main__":
    main()
