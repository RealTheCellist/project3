# Support Channel Runbook

Date: 2026-04-19
Owner: TheCellist

## Channels
- Primary: Team chat `#sumpyo-beta-support`
- Secondary: Email `sumpyo-beta-support@naver.com`
- Incident bridge: Team call room `Sumpyo War Room`

## SLA Targets
- First response: within 15 minutes (business hours)
- Triage complete: within 60 minutes
- Critical incident update cadence: every 30 minutes

## Triage Labels
- `sev1`: service down / data loss risk
- `sev2`: major feature degraded (STT fail spike)
- `sev3`: minor defect / workaround exists

## Intake Template
- reporter:
- device/os:
- app build:
- flow: (Analyze / STT / Report / Export)
- symptom:
- screenshot/log:

## Escalation
1. Support owner confirms reproducibility.
2. If `sev1` or `sev2`, open incident using `INCIDENT_MESSAGE_TEMPLATE.md`.
3. Assign engineering owner and ETA.
4. Post resolution + root cause summary.

## Daily Risk Thresholds
- Analyze success rate:
  - warning < 91%
  - critical < 88% (`sev2`)
- STT fallback rate:
  - warning > 18%
  - critical > 25% (`sev2`)
- P95 latency:
  - warning > 3500ms
  - critical > 4500ms (`sev2`)
- Mobile runtime audit FAIL: stop external rollout and escalate

Run:
- `python scripts/risk_monitor.py --date YYYY-MM-DD --kpi-json data/beta_kpi_summary_YYYY-MM-DD.json --audit-md data/mobile_runtime_audit_YYYY-MM-DD.md --thresholds data/risk_thresholds.json --json-output data/risk_monitor_YYYY-MM-DD.json --md-output data/risk_monitor_YYYY-MM-DD.md`
