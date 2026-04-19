# Release Notes `v0.1.3-beta`

Date: 2026-04-21

## Highlights
- Added privacy enhancement for beta logs:
  - anonymized fields `tester_hash`, `device_hash` in daily log format
  - backfill utility `scripts/anonymize_beta_logs.py`
- Added retention/deletion automation:
  - `scripts/data_retention_job.py`
  - scheduled workflow `.github/workflows/data-retention.yml`
- Completed 2-day stabilization evidence:
  - daily reports, KPI summaries, runtime audit, risk monitor (2026-04-20/21)
- Added STT auto-selection draft:
  - `scripts/stt_profile_autoselect.py`
  - rules in `data/stt_autoselect_rules.json`

## Operational Snapshot
- Runtime gate: PASS (recent daily windows)
- Risk severity: normal
- Fallback-rate: under configured warning threshold in latest runs

## Notes
- GitHub Actions manual dispatch still requires repository web UI interaction.
- Continue daily monitoring and threshold-based escalation.

