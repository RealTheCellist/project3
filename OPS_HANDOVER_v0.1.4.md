# Ops Handover (v0.1.4-beta)

Date: 2026-04-19
Owner: TheCellist

## Daily Run
1. Run daily ops:
   - `python scripts/run_latest_daily_ops.py --owner TheCellist --build "MVP beta"`
2. Confirm outputs:
   - `data/beta_kpi_summary_YYYY-MM-DD.json`
   - `data/risk_monitor_YYYY-MM-DD.json`
   - `data/stt_profile_review_YYYY-MM-DD.json`
   - `data/stt_autoselect_{poor|normal|good}_YYYY-MM-DD.json`
   - `data/stt_rules_tuning_YYYY-MM-DD.json`

## Alert Thresholds (current)
- analyze success warning/critical: `91% / 88%`
- STT fallback warning/critical: `18% / 25%`
- p95 latency warning/critical: `3500ms / 4500ms`

## Escalation Rule
- `severity=sev2` or rollback recommended -> open incident + notify support channel.

## Rollback Trigger
- analyze success rate below critical threshold
- STT fallback rate above critical threshold
- p95 latency above critical threshold
- mobile runtime gate FAIL

## Owner Actions on Alert
1. Re-run daily ops for latest data.
2. Check `risk_monitor` + `mobile_runtime_audit` details.
3. If STT trend worsened, re-tune rules and regenerate auto-select artifacts.
4. If critical persists, execute rollback plan.

