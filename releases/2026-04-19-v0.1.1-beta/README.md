# Release Archive Manifest

Release: v0.1.1-beta
Date: 2026-04-19
Branch: main

## Core Docs
- RELEASE_NOTES_v0.1.1-beta.md
- RELEASE_CHECKLIST.md
- GO_NO_GO_2026-04-19.md
- SUPPORT_CHANNEL_RUNBOOK.md
- ROLLBACK_PLAN.md
- STT_TUNING_PLAN.md

## Automation Added
- scripts/start_daily_beta_log.ps1
- scripts/append_beta_log.ps1
- scripts/run_daily_beta_report.py
- scripts/stt_profile_review.py
- scripts/risk_monitor.py

## Artifacts
- data/beta_run_log_2026-04-19.csv
- data/beta_kpi_summary_2026-04-19.json
- data/mobile_runtime_audit_2026-04-19.md
- data/stt_profile_review_2026-04-19.json
- data/stt_profile_review_2026-04-19.md
- data/risk_monitor_2026-04-19.json
- data/risk_monitor_2026-04-19.md

## Rollback Trigger
- analyze_success_rate < 90%
- stt_fallback_rate > 20%
- p95_latency_ms > 4000
- mobile runtime audit FAIL
