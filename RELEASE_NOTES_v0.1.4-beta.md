# Release Notes `v0.1.4-beta`

Date: 2026-04-19

## Highlights
- STT API 확장:
  - `POST /stt` now supports `profile=fast|balanced|accurate|auto`
  - `network=poor|normal|good` 쿼리 지원
- STT Config API 확장:
  - `GET /stt/config`에 `profile=auto`, `network` 지원
- STT 자동 선택 로직 적용:
  - `data/stt_autoselect_rules.json` + `stt_profile_review_*.json` 기반 선택
  - fallback-rate/latency 임계치 초과 시 recommended profile override
- Flutter UI 확장:
  - Home 화면에서 `auto` profile 선택 가능
  - `network` 선택 드롭다운 추가 및 요청 반영
- Ops 자동화 강화:
  - `scripts/run_latest_daily_ops.py`가 네트워크별 auto-select 산출물 생성
  - `data/stt_runtime_sync_YYYY-MM-DD.md` 자동 생성

## Validation
- Backend tests: `python -m unittest discover -s tests -p "test_*.py"` PASS
- Mobile tests: `flutter test` PASS

## Operational Notes
- 권장 사용 패턴: 앱에서 `profile=auto` 사용 + 현재 체감 네트워크 상태 선택
- 일일 ops 실행 후 다음 파일 확인:
  - `data/stt_autoselect_poor_YYYY-MM-DD.json`
  - `data/stt_autoselect_normal_YYYY-MM-DD.json`
  - `data/stt_autoselect_good_YYYY-MM-DD.json`
  - `data/stt_runtime_sync_YYYY-MM-DD.md`

## Known Risks
- 네트워크 상태 수동 선택값이 실제 상태와 다르면 추천 profile이 빗나갈 수 있음
- 초기 베타 구간에서는 review 데이터 부족으로 auto 추천이 보수적으로 동작할 수 있음

