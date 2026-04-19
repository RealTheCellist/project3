# Internal Release Checklist (v0.1.4)

Date: 2026-04-19

## 1) Android signing/app id
- [x] `applicationId` fixed: `com.sumpyo.sumpyo_mobile`
- [x] Release signing config wired in Gradle (`key.properties` aware)
- [x] Fallback signing path for local/CI (debug signing) documented
- [x] `key.properties.example` created

## 2) Build artifacts
- [x] `flutter build apk --release` completed
- [ ] `flutter build appbundle --release` completed  
  - blocker: Windows Developer Mode is required for plugin symlink support
- [ ] Artifact paths verified:
  - [x] `mobile/build/app/outputs/flutter-apk/app-release.apk`
  - `mobile/build/app/outputs/bundle/release/app-release.aab`

## 3) Internal install verification
- [ ] Fresh install on Android device
- [ ] Update install over previous internal build
- [ ] Permission prompts (microphone/storage) verified
- [ ] Core flow smoke test:
  - Home input -> analyze
  - STT record -> transcript -> analyze
  - Report CSV/PDF export

## 4) Release handover
- [x] Ops monitoring docs linked (`README`, risk monitor, daily ops)
- [x] E2E validation linked (`E2E_VALIDATION_2026-04-19.md`)
- [x] v0.1.5 backlog drafted
