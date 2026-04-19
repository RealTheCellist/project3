# STT Success Improvement Sprint Plan

Date: 2026-04-19

## Goal
- Raise real-device STT success rate.
- Keep fallback-rate under 20%.

## Baseline (dry-run seed)
- STT success: 33.33%
- Fallback rate: 20.83%

## Sprint Actions
1. Profile comparison on real devices (`fast`/`balanced`/`accurate`) with 20+ runs each.
2. Tune retry/timeout policy (updated to timeout 60s + up to 3 attempts with backoff).
3. Add language-specific prompts in UX for short/empty speech.
4. Track failure buckets by code (`empty_transcript`, `transcription_failed`, network timeout).

## Cycle 1 Result (2026-04-19)
- Profile review file: `data/stt_profile_review_2026-04-19.md`
- Recommendation: `balanced` (sample-size weighted winner)
- Notes:
  - `fast` latency was lower but sample size was too small.
  - `accurate` sample size and latency were both less favorable for default use.
  - Keep default `balanced` for beta and collect more runs.

## Cycle 2 Result (2026-04-20)
- Profile review file: `data/stt_profile_review_2026-04-20.md`
- Input runs: `data/beta_run_log_2026-04-20.csv` (30 runs, profile-tagged STT attempts)
- Recommendation: `fast`
- Summary:
  - `fast`: attempts=7, success_rate=85.71%, fallback_rate=14.29%, avg_latency=1942.86ms
  - `balanced`: attempts=6, success_rate=83.33%, fallback_rate=16.67%, avg_latency=2146.67ms
  - `accurate`: attempts=5, success_rate=80.00%, fallback_rate=20.00%, avg_latency=2518.00ms
- Decision:
  - Keep global default `balanced` for now.
  - Use `fast` as recommended profile for unstable network segments and low-latency paths.

## Exit Criteria
- STT success >= 70% on real runs.
- Fallback rate <= 20%.
- No sev1 incidents during two consecutive days.
