# Release Notes `v0.1.1-beta`

Date: 2026-04-19

## Highlights
- Added daily beta logging workflow:
  - `scripts/start_daily_beta_log.ps1`
  - `scripts/append_beta_log.ps1`
- Added automated daily reporting pipeline:
  - `scripts/run_daily_beta_report.py`
  - generates KPI, mobile runtime audit, and daily report artifacts
- Added STT profile review automation:
  - `scripts/stt_profile_review.py`
  - generated `data/stt_profile_review_2026-04-19.{json,md}`
- Added risk monitoring automation:
  - `scripts/risk_monitor.py`
  - generated `data/risk_monitor_2026-04-19.{json,md}`
- Updated support runbook with threshold-based escalation and rollback triggers.

## Operational Status
- Mobile runtime audit: PASS (`data/mobile_runtime_audit_2026-04-19.md`)
- Daily risk monitor: severity `normal`, rollback `NO`
- STT profile recommendation: `balanced` (sample-weighted review)

## Known Risks
- STT quality under unstable network/audio conditions still requires iterative tuning.
- Continue daily monitoring on fallback-rate and p95 latency.

