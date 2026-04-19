# STT E2E QA Checklist

Date: 2026-04-19 (updated: 2026-04-19)
Scope: Flutter -> FastAPI -> Whisper (+ fallback to device speech_to_text)

## Preconditions
- FastAPI server running (`uvicorn app.main:app --reload`)
- `/stt` endpoint available
- Flutter app installed on physical Android/iOS device
- Microphone permission granted

## Scenario A: Happy path (server STT success, auto mode)
1. Open Home tab.
2. Set STT profile to `auto`, network to `normal`.
3. Tap `Start recording`, speak 5~10 seconds, tap `Stop recording`.
4. Confirm result tab opens with recovery score.
5. Confirm Home -> STT Pipeline Diagnostics includes:
- `pipeline_started`
- `uploading_audio`
- `stt_ok`
- `analyzing_text`
- `pipeline_done`

Pass criteria:
- No fallback used.
- Transcript length > 0.
- Analyze result generated.
- Diagnostics line includes selected `profile/network`.

## Scenario B: Server STT failure -> fallback
1. Temporarily stop backend STT provider or force `/stt` error.
2. Repeat recording flow (`profile=auto`, network=`normal`).
3. Confirm app shows friendly error text.
4. Confirm device speech input fallback starts.
5. Confirm Home diagnostics includes `stt_failed`.

Pass criteria:
- Fallback starts automatically.
- `fallback-rate` increments.
- Friendly message includes actionable tip (`profile=auto` and network selection).

## Scenario C: Network timeout/unreachable
1. Disconnect device network (or point API to unreachable host).
2. Trigger analyze and STT requests (`profile=auto`, network=`poor`).
3. Confirm user-facing message:
- `timed out` or `network unreachable`
4. Reconnect network and retry.

Pass criteria:
- Error messages are actionable.
- App recovers on retry.

## Scenario D: Empty speech / empty transcript
1. Record with silence only.
2. Confirm backend returns `[empty_transcript]` path.
3. Confirm app message suggests speaking longer.

Pass criteria:
- No crash.
- Guidance message shown.

## Scenario E: Auto-selection by network
1. Call `GET /stt/config?profile=auto&network=poor`.
2. Call `GET /stt/config?profile=auto&network=normal`.
3. Call `GET /stt/config?profile=auto&network=good`.
4. Compare returned `profile` values with latest ops outputs:
- `data/stt_autoselect_poor_YYYY-MM-DD.json`
- `data/stt_autoselect_normal_YYYY-MM-DD.json`
- `data/stt_autoselect_good_YYYY-MM-DD.json`

Pass criteria:
- API config result is consistent with ops-generated auto-select artifacts.

## Metrics to capture
- Attempts
- Fallbacks
- Fallback rate
- Success rate (pipeline_done / attempts)
- Median latency (manual stopwatch acceptable for MVP)
