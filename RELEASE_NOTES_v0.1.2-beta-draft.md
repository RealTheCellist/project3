# Release Notes `v0.1.2-beta` (Draft)

Date: 2026-04-20

## Planned Highlights
- Daily operations CI workflow (`.github/workflows/daily-ops.yml`)
- Latest-log automation runner (`scripts/run_latest_daily_ops.py`)
- Risk threshold tuning with warning/critical bands (`data/risk_thresholds.json`)
- STT profile review cycle 2 outputs (`data/stt_profile_review_2026-04-20.*`)

## Planned Ops Improvements
- Incident drill evidence added (`INCIDENT_DRILL_2026-04-20.md`)
- Daily monitoring artifacts generated for 2026-04-20

## Gate Before Finalizing
1. Validate one successful GitHub Actions scheduled run.
2. Confirm artifact upload includes all expected report files.
3. Re-check KPI/risk trend for at least 2 consecutive days.

