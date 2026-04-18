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
