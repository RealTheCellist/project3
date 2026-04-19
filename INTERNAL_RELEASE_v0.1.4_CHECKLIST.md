# Internal Release Checklist (v0.1.4)

Date: 2026-04-19

## 1) Android signing/app id
- [x] `applicationId` fixed: `com.sumpyo.sumpyo_mobile`
- [x] Release signing config wired in Gradle (`key.properties` aware)
- [x] Fallback signing path for local/CI (debug signing) documented
- [x] `key.properties.example` created

## 2) Build artifacts
- [x] `flutter build apk --release` completed
- [x] `flutter build appbundle --release` completed
- [x] Artifact paths verified:
  - [x] `mobile/build/app/outputs/flutter-apk/app-release.apk`
  - [x] `mobile/build/app/outputs/bundle/release/app-release.aab`

## 3) Internal install verification
- [x] Fresh install on Android device
- [x] Update install over previous internal build
- [x] Permission prompts (microphone/storage) verified
- [x] Core flow smoke test:
  - Home input -> analyze
  - STT record -> transcript -> analyze
  - Report CSV/PDF export
  - evidence:
    - `data/mobile_runtime_audit_2026-04-21.md` (overall PASS)
    - `data/beta_run_log_2026-04-21.csv` (`Scenario1~6` pass records)

## 4) Release handover
- [x] Ops monitoring docs linked (`README`, risk monitor, daily ops)
- [x] E2E validation linked (`E2E_VALIDATION_2026-04-19.md`)
- [x] v0.1.5 backlog drafted
