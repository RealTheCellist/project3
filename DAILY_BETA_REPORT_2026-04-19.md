# Daily Beta Report

Date: 2026-04-19
Owner: TheCellist
Build: MVP beta (local validation run)

## 1) KPI Snapshot
- Total runs: 3
- Analyze success rate: 100.0%
- STT success rate: 33.33%
- STT fallback rate: 33.33%
- Avg latency(ms): 2273.33
- P95 latency(ms): 3800.0

## 2) Major Findings
- 분석 성공률은 100%로 안정적이며 점수/태그 산출 파이프라인은 정상 동작.
- STT는 폴백 체인이 동작해 장애 상황에서도 분석 흐름은 유지됨.
- 현재 샘플 수가 3건으로 적어, 실제 베타 판단용으로는 표본 확대가 필요.

## 3) Blockers / Incidents
- Blocker 없음.
- 시나리오 2에서 서버 STT 실패를 의도적으로 유도했고, 폴백 동작 확인 완료.

## 4) Actions for Tomorrow
1. 실제 기기 기준으로 시나리오 1~6을 최소 20건 이상 수집.
2. STT 성공률 향상을 위해 프로파일(`balanced`/`accurate`) 비교 재측정.
3. 사용자 메시지(타임아웃/네트워크/빈 음성) 가이드 문구 체감 테스트.

## 5) Raw Artifacts
- Beta run log CSV path: `BETA_RUN_LOG_TEMPLATE.csv`
- KPI summary JSON path: `data/beta_kpi_summary.json`
- Screen recordings / screenshots: (to be attached)

