# Backlog v0.1.5

Date: 2026-04-19

## Priority 1
- Improve network UX:
  - auto-detect network quality suggestion
  - reduce manual mismatch risk for `network` selector
- STT reliability:
  - add retry reason telemetry (timeout/server/backend)
  - refine fallback trigger messaging by error code

## Priority 2
- Model/analysis quality:
  - optional open-source text model mode gating and rollback switch
  - confidence calibration report for ambiguous expressions
- Performance:
  - reduce end-to-end STT latency p95 under 3000ms target

## Priority 3
- Distribution hardening:
  - signed Android internal release pipeline
  - install/update migration checklist automation
- Product polish:
  - Home guidance localization and copy pass
  - report export UX improvements

## Done before opening v0.1.5 sprint
- finalize internal release build artifacts
- close any sev2/sev1 incidents
- freeze v0.1.4-beta docs and tags

