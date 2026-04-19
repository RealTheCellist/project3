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

## 4) Manual device E2E status
- Reference checklist: `STT_E2E_QA_CHECKLIST.md`
- Completed now:
  - Scenario E (auto-selection by network) via API-level verification: PASS
- Pending (requires physical-device runtime):
  - Scenario A: Happy path recording
  - Scenario B: Forced server STT failure -> fallback
  - Scenario C: Network timeout/unreachable recovery
  - Scenario D: Empty speech handling

## Conclusion
- 3번(운영 품질 고도화): 완료
- 4번(E2E 검증 라운드): 자동화 검증 완료, 실기기 검증 4개 시나리오 남음

