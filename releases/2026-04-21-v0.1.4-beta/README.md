# Release Archive Manifest

Release: v0.1.4-beta
Date: 2026-04-21
Branch: main

## Included
- RELEASE_SCOPE_v0.1.4-beta.md
- RELEASE_NOTES_v0.1.4-beta.md
- RELEASE_CHECKLIST.md
- GO_NO_GO_2026-04-21-v0.1.4.md
- E2E_VALIDATION_2026-04-19.md

## STT Auto/Network Artifacts
- data/stt_autoselect_rules.json
- data/stt_autoselect_poor_2026-04-21.json
- data/stt_autoselect_normal_2026-04-21.json
- data/stt_autoselect_good_2026-04-21.json
- data/stt_rules_tuning_2026-04-21.json
- data/stt_rules_tuning_2026-04-21.md
- data/stt_runtime_sync_2026-04-21.md

## Quality Evidence
- python -m unittest discover -s tests -p "test_*.py" : PASS
- flutter test : PASS
- API contract spot test (/stt, /stt/config auto/network) : PASS

## Rollback Trigger (unchanged)
- analyze_success_rate below critical threshold
- stt_fallback_rate above critical threshold
- p95 latency above critical threshold
- mobile runtime gate FAIL

