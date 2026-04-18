# Rollback Plan

Date: 2026-04-19
Owner: TheCellist

## Trigger Conditions
- Critical crash in core flow
- Data corruption risk
- Sustained severe KPI degradation

## Execution Steps
1. Identify last stable commit from `git log`.
2. Checkout rollback branch from stable commit.
3. Deploy backend config snapshot from previous release.
4. Validate `/health`, `/analyze-checkin`, `/report/summary`, `/stt`.
5. Publish incident + recovery notice.

## Verification Checklist
- Health check 200
- Analyze response schema valid
- Report previous period fields present
- STT fallback still functional

## Communication
- Internal: `#sumpyo-beta-support`
- External: use `INCIDENT_MESSAGE_TEMPLATE.md`
