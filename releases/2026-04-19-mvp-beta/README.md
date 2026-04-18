# Release Archive Manifest

Release: 2026-04-19-mvp-beta
Branch: main

## Included Docs
- RELEASE_CHECKLIST.md
- GO_NO_GO_2026-04-19.md
- BETA_TEST_SCENARIOS.md
- STT_E2E_QA_CHECKLIST.md
- SUPPORT_CHANNEL_RUNBOOK.md
- DATA_RETENTION_POLICY.md

## KPI Artifacts
- data/beta_run_log_2026-04-19.csv
- data/beta_kpi_summary_2026-04-19.json

## Rollback Trigger
- Analyze success rate < 85%
- STT fallback rate > 45% sustained for 24h

## Rollback Action
1. Revert to previous stable commit.
2. Restart backend with previous config.
3. Notify beta users using incident template.
