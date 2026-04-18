# STT E2E QA Checklist

Date: 2026-04-19
Scope: Flutter -> FastAPI -> Whisper (+ fallback to device speech_to_text)

## Preconditions
- FastAPI server running (`uvicorn app.main:app --reload`)
- `/stt` endpoint available
- Flutter app installed on physical Android/iOS device
- Microphone permission granted

## Scenario A: Happy path (server STT success)
1. Open Home tab.
2. Set STT profile to `balanced`.
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

## Scenario B: Server STT failure -> fallback
1. Temporarily stop backend STT provider or force `/stt` error.
2. Repeat recording flow.
3. Confirm app shows friendly error text.
4. Confirm device speech input fallback starts.
5. Confirm Home diagnostics includes `stt_failed`.

Pass criteria:
- Fallback starts automatically.
- `fallback-rate` increments.

## Scenario C: Network timeout/unreachable
1. Disconnect device network (or point API to unreachable host).
2. Trigger analyze and STT requests.
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

## Metrics to capture
- Attempts
- Fallbacks
- Fallback rate
- Success rate (pipeline_done / attempts)
- Median latency (manual stopwatch acceptable for MVP)
