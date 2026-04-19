# Sprint Kickoff v0.1.5

Date: 2026-04-19
Source backlog: `BACKLOG_v0.1.5.md`

## Sprint Goal
- Improve STT reliability and UX trust in ambiguous network/audio conditions.

## Priority 1 Scope (Start)
1. Network UX improvement
   - add clearer network hint and mismatch guidance
2. STT reliability telemetry
   - classify retry reasons and expose summary in diagnostics
3. Fallback UX refinement
   - error-code specific guidance copy tuning

## Definition of Done
- tests added/updated
- no regression in `flutter test` and backend unit tests
- docs updated in README + release notes draft

## Risks
- Overfitting rules to short-term beta trends
- Increased UX complexity from extra controls

## Mitigation
- Keep auto as default path
- Use ops evidence before changing thresholds

