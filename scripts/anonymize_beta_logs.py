from __future__ import annotations

import argparse
import csv
import hashlib
from pathlib import Path


def _short_sha(value: str) -> str:
    return hashlib.sha256(value.strip().lower().encode("utf-8")).hexdigest()[:12]


def process_file(path: Path) -> bool:
    with path.open("r", encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        rows = [dict(r) for r in reader]
        fields = list(reader.fieldnames or [])

    if not fields:
        return False

    changed = False
    if "tester_hash" not in fields:
        fields.append("tester_hash")
        changed = True
    if "device_hash" not in fields:
        fields.append("device_hash")
        changed = True

    for row in rows:
        tester = str(row.get("tester", ""))
        device = str(row.get("device", ""))
        target_tester = _short_sha(tester) if tester else ""
        target_device = _short_sha(device) if device else ""
        if row.get("tester_hash", "") != target_tester:
            row["tester_hash"] = target_tester
            changed = True
        if row.get("device_hash", "") != target_device:
            row["device_hash"] = target_device
            changed = True

    if not changed:
        return False

    with path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)
    return True


def main() -> None:
    parser = argparse.ArgumentParser(description="Add anonymized hash fields to beta run logs.")
    parser.add_argument("--glob", default="data/beta_run_log_*.csv")
    args = parser.parse_args()

    changed = 0
    for p in sorted(Path.cwd().glob(args.glob)):
        if process_file(p):
            changed += 1
            print(f"updated: {p.as_posix()}")
    print(f"done. changed_files={changed}")


if __name__ == "__main__":
    main()

