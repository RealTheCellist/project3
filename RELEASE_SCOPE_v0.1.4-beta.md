# Release Scope `v0.1.4-beta`

Date: 2026-04-19  
Owner: TheCellist

## Goal
- STT 자동 프로파일 선택(`profile=auto`)을 실사용 가능한 베타 기능으로 고정한다.
- 네트워크 상태(`network=poor|normal|good`)를 앱/백엔드/운영 파이프라인에서 동일하게 사용한다.

## In Scope
- Backend
  - `/stt`, `/stt/config`에 `profile=auto`와 `network` 파라미터 적용
  - rules + review 기반 자동 선택 로직 안정화
- Mobile (Flutter)
  - Home 화면에 `STT profile(auto 포함)` + `network` 선택 UI 제공
  - `Flutter -> FastAPI` 요청에 `network` 쿼리 전달
- QA/Test
  - STT auto/network 관련 백엔드 테스트 추가
  - Flutter 위젯 테스트에 STT 컨트롤 검증 추가
- Ops
  - `run_latest_daily_ops.py`에서 네트워크별 auto-select 결과 자동 생성
  - 런타임 연동 레퍼런스 문서(`stt_runtime_sync_YYYY-MM-DD.md`) 자동 생성

## Out of Scope
- 유료 LLM 폴백 도입 (Claude 등)
- Android/iOS 스토어 배포
- STT 엔진 교체(Whisper 외 엔진) 자체 구현

## Acceptance Criteria
- 앱에서 `profile=auto` + `network` 선택 후 STT 요청 성공
- 백엔드 테스트/모바일 테스트 모두 통과
- 일일 ops 실행 시 네트워크별 산출물 3종(`poor/normal/good`) 생성
- README/운영 문서가 실제 동작과 일치

## Risks
- 실제 네트워크 품질과 사용자가 선택한 network 값이 불일치할 수 있음
- 리뷰 데이터 부족 시 auto-selection 정확도가 떨어질 수 있음

## Mitigation
- STT Diagnostics에 선택값(profile/network) 표시
- 일일 profile review 기반 규칙 임계치 주기적 보정
- fallback-rate/latency 임계치 초과 시 override 적용

