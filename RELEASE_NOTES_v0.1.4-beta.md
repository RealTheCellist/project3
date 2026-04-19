# Release Notes `v0.1.4-beta`

Date: 2026-04-19

## Highlights
- STT API extended:
  - `POST /stt` supports `profile=fast|balanced|accurate|auto`
  - `network=poor|normal|good` query added
- STT config API extended:
  - `GET /stt/config` supports `profile=auto` + `network`
- STT auto-selection stabilized:
  - based on `data/stt_autoselect_rules.json` + `stt_profile_review_*.json`
  - override applies when fallback-rate/latency exceeds thresholds
- Flutter UI updated:
  - Home supports `auto` profile selection
  - network selector added and request pipeline connected
- Ops automation expanded:
  - daily ops generates network-based auto-select artifacts
  - runtime sync and rules tuning artifacts generated

## Validation
- Backend tests: `python -m unittest discover -s tests -p "test_*.py"` PASS
- Mobile tests: `flutter test` PASS
- STT API contract checks (`/stt`, `/stt/config`) PASS

## Operational Notes
- Recommended default for beta: app uses `profile=auto`.
- Daily ops outputs to review:
  - `data/stt_autoselect_poor_YYYY-MM-DD.json`
  - `data/stt_autoselect_normal_YYYY-MM-DD.json`
  - `data/stt_autoselect_good_YYYY-MM-DD.json`
  - `data/stt_runtime_sync_YYYY-MM-DD.md`
  - `data/stt_rules_tuning_YYYY-MM-DD.json`

## Known Risks
- Manual `network` selection can differ from actual network quality.
- Early beta periods can bias auto-selection due to limited review data.

