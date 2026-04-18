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
2. Tune retry/timeout policy (currently timeout 45s + 1 retry).
3. Add language-specific prompts in UX for short/empty speech.
4. Track failure buckets by code (`empty_transcript`, `transcription_failed`, network timeout).

## Exit Criteria
- STT success >= 70% on real runs.
- Fallback rate <= 20%.
- No sev1 incidents during two consecutive days.
