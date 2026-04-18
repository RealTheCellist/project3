# Daily Beta Report

Date: 2026-04-19
Owner: TheCellist
Build: MVP beta (24-run seed/dry-run set)

## 1) KPI Snapshot
Note: This KPI set is generated from seed/dry-run entries for pipeline rehearsal, not final production telemetry.

- Total runs: 24
- Analyze success rate: 91.67%
- STT success rate: 33.33%
- STT fallback rate: 20.83%
- Avg latency(ms): 3655.83
- P95 latency(ms): 3800.0

## 2) Major Findings
- Analysis pipeline stays above 90% success in the rehearsal set.
- STT fallback path works and preserves service continuity.
- Failures are concentrated in network-off / timeout scenarios.

## 3) Blockers / Incidents
- No blocker found in dry-run.
- Two expected failures were induced for network-off/timeout.

## 4) Actions for Tomorrow
1. Run 20+ real physical-device sessions to replace seed entries.
2. Re-measure STT profiles under different network conditions.
3. Tune timeout/retry and re-check fallback-rate target (<20%).

## 5) Raw Artifacts
- Beta run log CSV path: `data/beta_run_log_2026-04-19.csv`
- KPI summary JSON path: `data/beta_kpi_summary_2026-04-19.json`
- Screen recordings / screenshots: `mobile/screenshots/actual_screen_full.png`
