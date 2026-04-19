# Incident Drill Report

Date: 2026-04-20  
Owner: TheCellist  
Type: `sev2` simulation

## Scenario
- Trigger: STT fallback-rate spike above warning threshold in a hypothetical traffic burst.
- Expected behavior:
  - Support owner opens incident in `#sumpyo-beta-support`
  - Engineering triage within 60 minutes
  - Decision gate against `ROLLBACK_PLAN.md`

## Drill Steps
1. Opened incident template from `INCIDENT_MESSAGE_TEMPLATE.md`.
2. Filled intake with simulated affected devices and impacted flow (`STT`).
3. Applied threshold decision path from `SUPPORT_CHANNEL_RUNBOOK.md`.
4. Reviewed rollback triggers and validation checklist in `ROLLBACK_PLAN.md`.

## Result
- Escalation path was clear and executable.
- No ambiguity found in owner assignment and communication channel.
- Rollback decision remained `NO` in this drill scenario.

## Follow-ups
1. Add a one-line quick command block in runbook for on-call copy/paste.
2. Record real incident IDs in this document for future audit traceability.

