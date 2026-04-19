# STT Rules Tuning

## Input Review Files
- `data/stt_profile_review_2026-04-19.json`
- `data/stt_profile_review_2026-04-20.json`
- `data/stt_profile_review_2026-04-21.json`

## Aggregated Metrics
- `fast`: attempts=18, success_rate=88.89%, fallback_rate=11.11%, avg_latency_ms=1901.67
- `balanced`: attempts=14, success_rate=85.71%, fallback_rate=14.29%, avg_latency_ms=2162.86
- `accurate`: attempts=10, success_rate=80.0%, fallback_rate=20.0%, avg_latency_ms=2499.0

## Suggested Rules
- preferred_default: `fast`
- network poor: `fast`
- network normal: `fast`
- network good: `fast`
- fallback threshold: `12.7`
- latency threshold(ms): `2032.3`
