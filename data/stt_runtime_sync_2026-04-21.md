# STT Runtime Sync

- date: 2026-04-21
- review_json: data/stt_profile_review_2026-04-21.json
- rules_json: data/stt_autoselect_rules.json
- generated_profiles:
  - data/stt_autoselect_poor_2026-04-21.json
  - data/stt_autoselect_normal_2026-04-21.json
  - data/stt_autoselect_good_2026-04-21.json

## Runtime env reference
- STT_AUTOSELECT_RULES_FILE=data/stt_autoselect_rules.json
- STT_PROFILE_REVIEW_FILE=data/stt_profile_review_2026-04-21.json

## App/API usage
- call /stt with profile=auto and network=poor|normal|good
- call /stt/config with profile=auto and network=poor|normal|good
