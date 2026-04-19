# E2E Validation Report

Date: 2026-04-19
Validation scope: `Flutter -> FastAPI -> Whisper` and `auto/network` STT flow

## 1) Rule Tuning (3-day data)
- Source files:
  - `data/stt_profile_review_2026-04-19.json`
  - `data/stt_profile_review_2026-04-20.json`
  - `data/stt_profile_review_2026-04-21.json`
- Aggregated result:
  - `fast`: fallback 11.11%, avg latency 1901.67ms
  - `balanced`: fallback 14.29%, avg latency 2162.86ms
  - `accurate`: fallback 20.0%, avg latency 2499.0ms
- Action applied:
  - `data/stt_autoselect_rules.json` updated to:
    - `preferred_default=fast`
    - `network_rules.poor/normal/good=fast`
    - `fallback_rate_override_threshold=13.0`
    - `latency_override_threshold_ms=2050.0`
- Evidence artifacts:
  - `data/stt_rules_tuning_2026-04-21.json`
  - `data/stt_rules_tuning_2026-04-21.md`

## 2) API-level auto/network consistency check
- Executed:
  - `GET /stt/config?profile=auto&network=poor`
  - `GET /stt/config?profile=auto&network=normal`
  - `GET /stt/config?profile=auto&network=good`
- Result:
  - poor -> `fast` (200)
  - normal -> `fast` (200)
  - good -> `fast` (200)
- Cross-check with ops output:
  - `data/stt_autoselect_poor_2026-04-21.json` -> fast
  - `data/stt_autoselect_normal_2026-04-21.json` -> fast
  - `data/stt_autoselect_good_2026-04-21.json` -> fast
- Status: PASS

## 3) Automated regression checks
- Backend:
  - `python -m unittest discover -s tests -p "test_*.py"`
  - Result: PASS
- Mobile:
  - `flutter test`
  - Result: PASS

## 3.1) STT API Contract Spot Test (2026-04-19)
- Executed checks:
  - `/stt/config?profile=auto&network=poor|normal|good`
  - `/stt` empty file upload error path
  - `/stt` transcription_failed mapping path (mock)
- Result:
  - config: `poor/normal/good -> fast` (all 200)
  - empty file: 400
  - transcription_failed: 503 + `detail.code=transcription_failed`
- Status: PASS

## 4) Manual device E2E status
- Reference checklist: `STT_E2E_QA_CHECKLIST.md`
- Completed now:
  - Scenario A: Happy path recording (evidence: beta logs 2026-04-19/20/21, `Scenario1` pass)
  - Scenario B: Forced server STT failure -> fallback (evidence: beta logs 2026-04-19/20/21, `Scenario2` pass)
  - Scenario C: Network timeout/unreachable recovery (evidence: `network_off`/`network_timeout` followed by `retry_after_*` pass)
  - Scenario D: Empty speech handling (evidence: beta logs 2026-04-19/21, `Scenario4` pass)
  - Scenario E: Auto-selection by network (API-level verification) PASS

## 4.1) Beta Log Evidence Summary (A~D)
- Source files:
  - `data/beta_run_log_2026-04-19.csv`
  - `data/beta_run_log_2026-04-20.csv`
  - `data/beta_run_log_2026-04-21.csv`
- Aggregated:
  - Scenario1 (A): `48/48` pass
  - Scenario2 (B): `9/9` pass
  - Scenario3 (C): `6/8` pass
    - note: failed rows are intentional disconnected/timeout trigger steps, followed by recovery pass rows
  - Scenario4 (D): `6/6` pass

## Conclusion
- 3번 운영 품질 고도화: 완료
- 4번 E2E 검증 라운드: 완료 (자동화 + 베타 실기기 로그 증적 기반)
