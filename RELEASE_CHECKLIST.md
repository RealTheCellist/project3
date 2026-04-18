# Release Checklist (MVP)

## 1. Code & Quality Gate
- [ ] `python -m unittest discover -s tests -p "test_*.py"` passes
- [ ] `flutter analyze` passes
- [ ] `flutter test` passes
- [ ] No blocker bug in Home / Result / Routine / Report core flow

## 2. Backend Runtime Check
- [ ] `GET /health` is OK
- [ ] `POST /analyze-checkin` returns valid score/tags/routines
- [ ] `GET /report/summary` includes `previous_period`
- [ ] `POST /stt` works with selected profile (`fast|balanced|accurate`)
- [ ] Error codes are verified (`audio_not_found`, `empty_transcript`, `backend_not_installed`, `transcription_failed`)

## 3. Mobile Runtime Check
- [ ] Analyze flow works from typed text
- [ ] STT recording flow works (`Flutter -> FastAPI -> Whisper`)
- [ ] STT fallback to device speech works on backend failure
- [ ] Report compare card renders current vs previous metrics
- [ ] Tag drill-down state restore works (filter/sort/search/page)
- [ ] CSV/PDF exports work on target device

## 4. Environment & Config
- [ ] `.env` created from `.env.example`
- [ ] STT profile fixed for release target (`balanced` recommended)
- [ ] Model mode decision fixed:
  - [ ] Rule-only mode
  - [ ] Open-source model mode
- [ ] Recommendation file path exists if used (`data/stt_recommendation.json`)

## 5. Beta Ops Readiness
- [ ] Daily KPI logging rule defined (attempts, fallbacks, success rate)
- [ ] Support channel ready for user issues
- [ ] Incident message template prepared
- [ ] Data retention / deletion policy statement reviewed

## 6. Release Decision
- [ ] Go/No-Go review completed
- [ ] Release build archived with version/date
- [ ] Rollback plan confirmed

