# Release Notes `v0.1.0-beta`

Date: 2026-04-19

## Highlights
- Added report period comparison with current vs previous metrics.
- Added STT pipeline diagnostics on Home tab.
- Added robust STT retry handling (up to 3 attempts, timeout/backoff tuning).
- Added tag drill-down state restore (filter/sort/query/page).
- Added mobile runtime audit tooling and operational runbooks.

## Ops & QA
- Mobile runtime audit passed:
  - `data/mobile_runtime_audit_2026-04-19.md`
- KPI summary updated:
  - `data/beta_kpi_summary_2026-04-19.json`
- Release/go-no-go docs updated:
  - `RELEASE_CHECKLIST.md`
  - `GO_NO_GO_2026-04-19.md`
  - `ROLLBACK_PLAN.md`

## Known Risks
- STT quality under unstable network/audio conditions requires ongoing tuning.

