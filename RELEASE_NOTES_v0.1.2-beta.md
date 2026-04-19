# Release Notes `v0.1.2-beta`

Date: 2026-04-21

## Highlights
- Added daily operations CI workflow (`.github/workflows/daily-ops.yml`).
- Added latest-log automation runner (`scripts/run_latest_daily_ops.py`).
- Added risk threshold tuning with warning/critical bands (`data/risk_thresholds.json`).
- Added STT profile review cycle outputs and recommendation artifacts.
- Added incident drill evidence and linked rollback/escalation process.

## Operational Status
- Daily monitoring pipeline active (KPI + runtime audit + risk monitor + STT profile review).
- Runtime gate PASS on recent operational datasets.
- Risk monitor status remained `normal` in recent runs.

## Artifacts
- `DAILY_BETA_REPORT_2026-04-20.md`
- `data/beta_kpi_summary_2026-04-20.json`
- `data/mobile_runtime_audit_2026-04-20.md`
- `data/risk_monitor_2026-04-20.json`
- `data/stt_profile_review_2026-04-20.json`

## Known Risks
- STT quality may degrade under poor network/audio conditions.
- Continue threshold monitoring and rollback readiness.
