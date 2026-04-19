# Internal Distribution Plan (v0.1.4-beta)

Date: 2026-04-19
Owner: TheCellist

## Package
- APK: `mobile/build/app/outputs/flutter-apk/app-release.apk`
- AAB: `mobile/build/app/outputs/bundle/release/app-release.aab`

## Tester Group
- Target: 3-5 internal testers
- Device mix: Android (Pixel/Galaxy), iOS optional for feature parity checks

## Distribution Message
- Build: `v0.1.4-beta`
- Focus:
  - STT `auto` profile behavior
  - network-aware stability
  - fallback and diagnostics UX clarity
- Required scenarios:
  - A: happy path recording
  - B: forced STT failure -> fallback
  - C: network off/timeout -> recovery
  - D: empty/short audio handling

## Collection
- Daily log file:
  - `data/beta_run_log_YYYY-MM-DD.csv`
- Daily report command:
  - `python scripts/run_latest_daily_ops.py --owner TheCellist --build "MVP beta"`

## Exit Gate
- analyze success >= 90%
- STT fallback <= 20%
- p95 latency <= 4000ms
- no unresolved sev2

