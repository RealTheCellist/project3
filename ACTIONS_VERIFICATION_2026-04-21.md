# Actions Verification (2026-04-21)

## CI Workflow
- File exists: `.github/workflows/daily-ops.yml`
- Local equivalent run validated: `python scripts/run_latest_daily_ops.py`

## Manual GitHub Run
- Required: GitHub web UI `Actions > Daily Ops > Run workflow`
- Note: CLI trigger requires `gh` auth token/session on this machine.

## Expected Artifact Set
- `DAILY_BETA_REPORT_YYYY-MM-DD.md`
- `data/beta_kpi_summary_YYYY-MM-DD.json`
- `data/mobile_runtime_audit_YYYY-MM-DD.md`
- `data/risk_monitor_YYYY-MM-DD.json`
- `data/stt_profile_review_YYYY-MM-DD.json`
