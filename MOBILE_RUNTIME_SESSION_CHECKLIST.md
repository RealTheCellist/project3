# Mobile Runtime Session Checklist

Date: YYYY-MM-DD  
Tester:  
Device/OS:  
Build:

## Required Steps
- [ ] `manual_text` (Analyze typed text)
- [ ] `stt_record` (Flutter -> FastAPI -> Whisper)
- [ ] `stt_fallback` (force backend STT fail -> device fallback)
- [ ] `report_compare` (open report compare card and verify values)
- [ ] `export_csv` (report export)
- [ ] `export_pdf_local` or `export_pdf_server`

## Logging Rule
- Append each step result to `data/beta_run_log_YYYY-MM-DD.csv`.
- Required columns:
  - `timestamp,tester,device,scenario,step,analyze_ok,stt_ok,fallback_used,latency_ms,outcome,note`

## Acceptance (for Release Checklist Mobile Runtime)
- Total physical-device runs >= 20
- All required steps above observed at least once with pass evidence
- Run audit:
  - `python scripts/mobile_runtime_audit.py --input data/beta_run_log_YYYY-MM-DD.csv --output data/mobile_runtime_audit_YYYY-MM-DD.md`

