# project3

`숨표(Sumpyo)` MVP 백엔드 초기 버전입니다.

## Quick Start

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
uvicorn app.main:app --reload
```

서버 실행 후:
- Health: `GET http://127.0.0.1:8000/health`
- Swagger: `http://127.0.0.1:8000/docs`
- 분석 API: `POST http://127.0.0.1:8000/analyze-checkin`
- 히스토리 API: `GET http://127.0.0.1:8000/checkins?limit=20`
- 리포트 요약 API: `GET http://127.0.0.1:8000/report/summary?days=7&limit=200`
- 리포트 PDF API: `GET http://127.0.0.1:8000/report/export-pdf?days=7&limit=200`
- STT API: `POST http://127.0.0.1:8000/stt` (multipart file, `profile=fast|balanced|accurate|auto`, `network=poor|normal|good`)
- STT Config: `GET http://127.0.0.1:8000/stt/config?profile=balanced&network=normal`
- STT Profiles: `GET http://127.0.0.1:8000/stt/profiles`

## 예시 요청

```json
{
  "transcript": "오늘 마감 압박이 커서 좀 불안하고 피곤해요.",
  "self_report_stress": 4,
  "baseline_days": 10,
  "trend_delta": 0.3,
  "voice_features": {
    "speech_rate_delta": 0.2,
    "silence_ratio_delta": 0.1,
    "energy_delta": -0.1
  }
}
```

## 점수 로직 (v1)

- 위험점수 = 자기보고(50) + 텍스트신호(35) + 변화추세(10) + 음성보조(5)
- 회복점수 = `100 - 위험점수`
- 음성 보조는 습관 편향을 줄이기 위해 저가중치로만 반영

## Flutter 앱 실행

Flutter 모바일 앱 코드는 `mobile/`에 있습니다.

```powershell
cd mobile
flutter pub get
flutter run
```

Windows에서 플러그인 빌드 오류가 나면 Developer Mode를 켜세요:
`start ms-settings:developers`

기본 API 주소 설정:
- Android Emulator: `http://10.0.2.2:8000`
- iOS Simulator/Windows: `http://127.0.0.1:8000`

앱에서 `Home > Analyze now`를 누르면 백엔드 `POST /analyze-checkin`을 호출합니다.
`Home > Start voice input`으로 음성 인식(STT) 텍스트 입력이 가능합니다.
`Report > CSV`로 필터된 리포트 데이터를 CSV 파일로 저장할 수 있습니다.
`Report > 로컬 PDF`는 앱에서 PDF를 생성해 저장합니다.
`Report > 서버 PDF`는 FastAPI에서 PDF를 생성해 내려받아 저장합니다.

## 운영/배포 문서

- 환경변수 템플릿: `.env.example`
- 릴리즈 체크리스트: `RELEASE_CHECKLIST.md`
- 베타 테스트 시나리오: `BETA_TEST_SCENARIOS.md`
- STT E2E 체크리스트: `STT_E2E_QA_CHECKLIST.md`
- 베타 실행 로그 템플릿: `BETA_RUN_LOG_TEMPLATE.csv`
- 일일 리포트 템플릿: `DAILY_BETA_REPORT_TEMPLATE.md`
- 일일 리포트 예시: `DAILY_BETA_REPORT_2026-04-19.md`
- 장애 공지 템플릿: `INCIDENT_MESSAGE_TEMPLATE.md`
- 지원 채널 런북: `SUPPORT_CHANNEL_RUNBOOK.md`
- 데이터 보존/삭제 정책: `DATA_RETENTION_POLICY.md`
- Go/No-Go 기록: `GO_NO_GO_2026-04-19.md`
- Go/No-Go 기록: `GO_NO_GO_2026-04-21.md`
- 롤백 계획: `ROLLBACK_PLAN.md`
- STT 튜닝 계획: `STT_TUNING_PLAN.md`
- 릴리즈 노트: `RELEASE_NOTES_v0.1.0-beta.md`
- 릴리즈 노트: `RELEASE_NOTES_v0.1.1-beta.md`
- 릴리즈 노트: `RELEASE_NOTES_v0.1.2-beta.md`
- 릴리즈 노트: `RELEASE_NOTES_v0.1.3-beta.md`
- 릴리즈 노트: `RELEASE_NOTES_v0.1.4-beta.md`
- 릴리즈 범위: `RELEASE_SCOPE_v0.1.4-beta.md`
- 릴리즈 아카이브: `releases/2026-04-19-mvp-beta/README.md`
- 릴리즈 아카이브: `releases/2026-04-21-v0.1.3-beta/README.md`
- 장애 대응 모의훈련: `INCIDENT_DRILL_2026-04-20.md`
- Actions 검증 메모: `ACTIONS_VERIFICATION_2026-04-21.md`
- 안정화 리포트: `STABILIZATION_REPORT_2026-04-21.md`
- 데이터 보존 배치 워크플로우: `.github/workflows/data-retention.yml`
- 모바일 런타임 세션 체크리스트: `MOBILE_RUNTIME_SESSION_CHECKLIST.md`

베타 KPI 집계 예시:

```powershell
python scripts/beta_kpi_summary.py ^
  --input BETA_RUN_LOG_TEMPLATE.csv ^
  --output data/beta_kpi_summary.json
```

실행 로그(24건)와 집계 산출물:
- `data/beta_run_log_2026-04-19.csv`
- `data/beta_kpi_summary_2026-04-19.json`

모바일 런타임 감사 리포트 생성:

```powershell
python scripts/mobile_runtime_audit.py ^
  --input data/beta_run_log_2026-04-19.csv ^
  --output data/mobile_runtime_audit_2026-04-19.md
```

일일 로그 누적 시작/추가:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/start_daily_beta_log.ps1 -Date 2026-04-20

powershell -ExecutionPolicy Bypass -File scripts/append_beta_log.ps1 ^
  -Date 2026-04-20 ^
  -Tester tester_a ^
  -Device "Pixel 7" ^
  -Scenario Scenario1 ^
  -Step stt_record ^
  -AnalyzeOk true ^
  -SttOk true ^
  -FallbackUsed false ^
  -LatencyMs 2100 ^
  -Outcome pass ^
  -Note "balanced profile"
```

## 백엔드 테스트

```powershell
python -m unittest discover -s tests -p "test_*.py"
```

## 모델 기반 감정분석(v2, 선택)

기본은 룰 기반이며, 아래를 설정하면 오픈소스 모델 기반 텍스트 감정 분석을 우선 사용합니다.
모델 실패/미설치 시 자동으로 룰 기반으로 폴백됩니다.
유료 LLM API(예: Claude/Anthropic) 호출은 기본 코드에 포함되어 있지 않습니다.

```powershell
pip install -r requirements-ml.txt
setx TEXT_SIGNAL_MODEL_ENABLED true
setx TEXT_SIGNAL_MODEL_NAME "joeddav/xlm-roberta-large-xnli"
```

재시작 후 FastAPI 실행:

```powershell
uvicorn app.main:app --reload
```

## Whisper STT(선택)

기본 백엔드는 `/stt` 엔드포인트를 포함하며, Whisper 백엔드 설치 후 동작합니다.

```powershell
pip install -r requirements-stt.txt
setx STT_PROVIDER faster_whisper
setx STT_PROFILE balanced
setx WHISPER_DEVICE cpu
setx WHISPER_COMPUTE_TYPE int8
```

재시작 후:

```powershell
uvicorn app.main:app --reload
```

프로파일 가이드:
- `fast`: tiny + beam 1 (속도 우선)
- `balanced`: small + beam 3 (기본 권장)
- `accurate`: medium + beam 5 (정확도 우선, 느림)

Flutter 앱에서는 Home 화면에서 STT Profile(`fast/balanced/accurate/auto`)과 Network(`poor/normal/good`)를 선택할 수 있습니다.
Home 화면의 `STT Pipeline Diagnostics` 카드에서 시도 횟수/폴백 횟수/단계 로그를 확인할 수 있습니다.

STT 에러 코드는 `detail.code`로 내려옵니다:
- `audio_not_found`
- `empty_transcript`
- `backend_not_installed`
- `transcription_failed`

Flutter 클라이언트는 STT 업로드 요청에 타임아웃 및 1회 재시도를 적용합니다.
서버 STT 실패 시 앱은 자동으로 기기 `speech_to_text` 입력으로 폴백합니다.

## STT 벤치마크

프로파일별 STT 속도/정확도(WER) 비교:

1. 매니페스트 준비  
- 예시: `scripts/stt_benchmark_manifest.example.csv`
- 컬럼: `audio_path,reference(optional),language(optional)`

2. 실행

```powershell
python scripts/stt_benchmark.py ^
  --manifest scripts/stt_benchmark_manifest.example.csv ^
  --base-url http://127.0.0.1:8000 ^
  --profiles fast,balanced,accurate ^
  --output data/stt_benchmark_results.csv
```

3. 결과
- `data/stt_benchmark_results.csv` 생성
- 콘솔에 프로파일별 평균 지연시간/평균 WER 요약 출력

4. 추천 프로파일 계산

```powershell
python scripts/stt_recommend.py --input data/stt_benchmark_results.csv
```

가중치 조정 예시(정확도 우선):

```powershell
python scripts/stt_recommend.py ^
  --input data/stt_benchmark_results.csv ^
  --latency-weight 0.3 ^
  --wer-weight 0.7 ^
  --error-penalty 1.2
```

추천 스크립트는 기본으로 `data/stt_recommendation.json`을 저장합니다.
백엔드는 `STT_PROFILE`이 비어 있으면 이 파일의 `recommended_profile`을 기본값으로 사용합니다.

환경변수로 경로를 바꿀 수 있습니다:

```powershell
setx STT_RECOMMENDATION_FILE "data/stt_recommendation.json"
```

일일 자동 리포트(집계+감사+리포트 생성):

```powershell
python scripts/run_daily_beta_report.py --date 2026-04-19 --owner TheCellist --build "MVP beta"
```

STT 프로파일 리뷰(일일 로그 기반):

```powershell
python scripts/stt_profile_review.py ^
  --input data/beta_run_log_2026-04-19.csv ^
  --json-output data/stt_profile_review_2026-04-19.json ^
  --md-output data/stt_profile_review_2026-04-19.md
```

일일 리스크 모니터:

```powershell
python scripts/risk_monitor.py ^
  --date 2026-04-19 ^
  --kpi-json data/beta_kpi_summary_2026-04-19.json ^
  --audit-md data/mobile_runtime_audit_2026-04-19.md ^
  --thresholds data/risk_thresholds.json ^
  --json-output data/risk_monitor_2026-04-19.json ^
  --md-output data/risk_monitor_2026-04-19.md
```

최신 로그 기준 일일 운영 파이프라인(집계+감사+리스크+프로파일리뷰):

```powershell
python scripts/run_latest_daily_ops.py --owner TheCellist --build "MVP beta"
```

GitHub Actions:
- `.github/workflows/daily-ops.yml` (cron + 수동 실행)
- `sev2` 발생 시 GitHub issue 자동 생성
- `SLACK_WEBHOOK_URL` secret 설정 시 Slack 알림 전송

STT 자동 프로파일 선택(네트워크 상태 기반):

```powershell
python scripts/stt_profile_autoselect.py ^
  --network normal ^
  --rules data/stt_autoselect_rules.json ^
  --review-json data/stt_profile_review_2026-04-21.json ^
  --output data/stt_autoselect_normal_2026-04-21.json
```

일일 운영 파이프라인 실행 시 최신 `stt_profile_review_YYYY-MM-DD.json` 기반으로
`poor/normal/good` 3개 네트워크 프로파일 결과를 자동 생성합니다:

```powershell
python scripts/run_latest_daily_ops.py --owner TheCellist --build "MVP beta"
```

생성 산출물:
- `data/stt_autoselect_poor_YYYY-MM-DD.json`
- `data/stt_autoselect_normal_YYYY-MM-DD.json`
- `data/stt_autoselect_good_YYYY-MM-DD.json`
- `data/stt_runtime_sync_YYYY-MM-DD.md`

로그 익명화 백필:

```powershell
python scripts/anonymize_beta_logs.py --glob "data/beta_run_log_*.csv"
```

데이터 보존/삭제 배치:

```powershell
python scripts/data_retention_job.py --dry-run
```

운영 임계치 설정 파일:
- `data/risk_thresholds.json`

STT 2차 프로파일 리뷰 산출물:
- `data/stt_profile_review_2026-04-20.json`
- `data/stt_profile_review_2026-04-20.md`
