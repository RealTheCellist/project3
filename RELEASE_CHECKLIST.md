# Release Checklist (MVP)

Note: Mobile runtime items below require physical-device verification. Seed/dry-run logs are not counted as final evidence.

## 1. Code & Quality Gate
- [x] `python -m unittest discover -s tests -p "test_*.py"` passes
- [x] `flutter analyze` passes
- [x] `flutter test` passes
- [x] No blocker bug in Home / Result / Routine / Report core flow

## 2. Backend Runtime Check
- [x] `GET /health` is OK
- [x] `POST /analyze-checkin` returns valid score/tags/routines
- [x] `GET /report/summary` includes `previous_period`
- [x] `POST /stt` works with selected profile (`fast|balanced|accurate`)
- [x] Error codes are verified (`audio_not_found`, `empty_transcript`, `backend_not_installed`, `transcription_failed`)

## 3. Mobile Runtime Check
- [ ] Analyze flow works from typed text
- [ ] STT recording flow works (`Flutter -> FastAPI -> Whisper`)
- [ ] STT fallback to device speech works on backend failure
- [ ] Report compare card renders current vs previous metrics
- [x] Tag drill-down state restore works (filter/sort/search/page)
- [ ] CSV/PDF exports work on target device

## 4. Environment & Config
- [x] `.env` created from `.env.example`
- [x] STT profile fixed for release target (`balanced` recommended)
- [x] Model mode decision fixed:
  - [x] Rule-only mode
  - [ ] Open-source model mode
- [x] Recommendation file path exists if used (`data/stt_recommendation.json`)

## 5. Beta Ops Readiness
- [x] Daily KPI logging rule defined (attempts, fallbacks, success rate)
- [x] Support channel ready for user issues
- [x] Incident message template prepared
- [x] Data retention / deletion policy statement reviewed

## 6. Release Decision
- [x] Go/No-Go review completed
- [x] Release build archived with version/date
- [x] Rollback plan confirmed

