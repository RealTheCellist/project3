# Release Archive Manifest

Release: v0.1.3-beta
Date: 2026-04-21
Branch: main

## Included
- RELEASE_NOTES_v0.1.3-beta.md
- DATA_RETENTION_POLICY.md
- SUPPORT_CHANNEL_RUNBOOK.md
- GO_NO_GO_2026-04-21.md
- STABILIZATION_REPORT_2026-04-21.md

## Privacy & Retention
- scripts/anonymize_beta_logs.py
- scripts/data_retention_job.py
- .github/workflows/data-retention.yml

## Daily Ops (2-day evidence)
- DAILY_BETA_REPORT_2026-04-20.md
- DAILY_BETA_REPORT_2026-04-21.md
- data/beta_kpi_summary_2026-04-20.json
- data/beta_kpi_summary_2026-04-21.json
- data/risk_monitor_2026-04-20.json
- data/risk_monitor_2026-04-21.json

## Rollback Trigger (unchanged)
- analyze_success_rate < critical threshold
- stt_fallback_rate > critical threshold
- p95 latency > critical threshold
- runtime audit gate FAIL
