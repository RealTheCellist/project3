# Beta Test Scenarios

Date: 2026-04-19
Target: Mobile app MVP (`Flutter -> FastAPI -> Whisper`)

## Scenario 1: Happy Path
1. Enter text manually and run analysis.
2. Record 5-10 seconds and run STT analysis.
3. Open Report tab and verify compare/trend/tags.

Expected:
- Recovery/Risk/Confidence values shown
- No crash
- Result and Report screens consistent

## Scenario 2: STT Failure + Fallback
1. Force backend STT failure (disable backend or invalid setup).
2. Start recording flow.

Expected:
- Friendly error message displayed
- Device speech-to-text fallback starts automatically
- Home diagnostics shows `stt_failed` and increased fallback rate

## Scenario 3: Network Instability
1. Disconnect network.
2. Trigger analyze and STT.
3. Reconnect and retry.

Expected:
- `network unreachable` or timeout message
- Retry succeeds after reconnect

## Scenario 4: Empty/Short Audio
1. Record silence only.
2. Submit STT request.

Expected:
- Empty transcript warning message
- No app freeze/crash

## Scenario 5: Drill-down State Restore
1. Open Top Tag drill-down.
2. Set filter/sort/search, move to next page.
3. Go back and re-open same tag.

Expected:
- Previous drill-down state restored

## Scenario 6: Export Reliability
1. Export CSV/PDF from Report tab.
2. Export filtered CSV/PDF from Tag drill-down.

Expected:
- Files are created successfully
- Summary/filter metadata included in exported outputs

## Metrics to Capture During Beta
- Analyze success rate
- STT success rate
- STT fallback rate
- Average request latency
- Number of user-reported confusion/error cases

