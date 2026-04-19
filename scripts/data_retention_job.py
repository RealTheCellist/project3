from __future__ import annotations

import argparse
import re
import sqlite3
from datetime import datetime, timedelta, UTC
from pathlib import Path


DATE_TOKEN = re.compile(r"(\d{4}-\d{2}-\d{2})")


def _extract_date(name: str) -> datetime | None:
    m = DATE_TOKEN.search(name)
    if not m:
        return None
    try:
        return datetime.strptime(m.group(1), "%Y-%m-%d").replace(tzinfo=UTC)
    except ValueError:
        return None


def purge_files(data_dir: Path, keep_days: int, dry_run: bool) -> list[str]:
    cutoff = datetime.now(UTC) - timedelta(days=keep_days)
    removed: list[str] = []
    patterns = [
        "beta_run_log_*.csv",
        "beta_kpi_summary_*.json",
        "mobile_runtime_audit_*.md",
        "risk_monitor_*.json",
        "risk_monitor_*.md",
        "stt_profile_review_*.json",
        "stt_profile_review_*.md",
    ]
    for pat in patterns:
        for p in data_dir.glob(pat):
            d = _extract_date(p.name)
            if d is None or d >= cutoff:
                continue
            removed.append(p.as_posix())
            if not dry_run:
                p.unlink(missing_ok=True)
    return removed


def purge_daily_reports(root: Path, keep_days: int, dry_run: bool) -> list[str]:
    cutoff = datetime.now(UTC) - timedelta(days=keep_days)
    removed: list[str] = []
    for p in root.glob("DAILY_BETA_REPORT_*.md"):
        d = _extract_date(p.name)
        if d is None or d >= cutoff:
            continue
        removed.append(p.as_posix())
        if not dry_run:
            p.unlink(missing_ok=True)
    return removed


def purge_checkins(db_path: Path, keep_days: int, dry_run: bool) -> int:
    if not db_path.exists():
        return 0
    conn = sqlite3.connect(db_path)
    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT COUNT(*) FROM checkins WHERE datetime(created_at) < datetime('now', ?)",
            (f"-{keep_days} days",),
        )
        count = int(cur.fetchone()[0])
        if not dry_run and count > 0:
            cur.execute(
                "DELETE FROM checkins WHERE datetime(created_at) < datetime('now', ?)",
                (f"-{keep_days} days",),
            )
            conn.commit()
            cur.execute("VACUUM")
        return count
    finally:
        conn.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="Run retention purge for beta artifacts and checkins.")
    parser.add_argument("--log-days", type=int, default=30)
    parser.add_argument("--report-days", type=int, default=30)
    parser.add_argument("--checkin-days", type=int, default=90)
    parser.add_argument("--db-path", default="data/sumpyo.db")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    root = Path.cwd()
    data_dir = root / "data"
    data_dir.mkdir(parents=True, exist_ok=True)

    removed_logs = purge_files(data_dir, args.log_days, args.dry_run)
    removed_reports = purge_daily_reports(root, args.report_days, args.dry_run)
    old_checkins = purge_checkins(root / args.db_path, args.checkin_days, args.dry_run)

    print(f"dry_run={args.dry_run}")
    print(f"removed_log_like_files={len(removed_logs)}")
    for p in removed_logs[:20]:
        print(f" - {p}")
    print(f"removed_daily_reports={len(removed_reports)}")
    for p in removed_reports[:20]:
        print(f" - {p}")
    print(f"checkins_older_than_{args.checkin_days}d={old_checkins}")


if __name__ == "__main__":
    main()

