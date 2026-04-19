# Week 1 Monitoring Plan

Window: 2026-04-20 ~ 2026-04-26
Release: v0.1.4-beta

## Daily Routine
1. Run:
   - `python scripts/run_latest_daily_ops.py --owner TheCellist --build "MVP beta"`
2. Check:
   - `data/beta_kpi_summary_YYYY-MM-DD.json`
   - `data/risk_monitor_YYYY-MM-DD.json`
   - `data/stt_profile_review_YYYY-MM-DD.json`
   - `data/stt_rules_tuning_YYYY-MM-DD.json`
3. If warning/critical triggered:
   - open incident thread
   - evaluate rules tuning + rollback readiness

## KPI Guardrails
- analyze success warning/critical: `91% / 88%`
- fallback warning/critical: `18% / 25%`
- p95 latency warning/critical: `3500ms / 4500ms`

## Daily Record Template
- Date:
- analyze success:
- fallback rate:
- p95 latency:
- severity:
- action:

