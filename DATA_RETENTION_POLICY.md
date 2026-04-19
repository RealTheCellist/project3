# Data Retention & Deletion Policy (MVP)

Date: 2026-04-19
Scope: Sumpyo MVP beta

## Data Collected
- Check-in transcript text
- Analysis outputs (recovery/risk/confidence/tags)
- Operational logs (request id, processing time)
- STT pipeline diagnostics counters

## Retention
- Beta run logs: retain 30 days
- Check-in DB for beta: retain 90 days
- Incident logs: retain 180 days

## Deletion
- User-request deletion: within 7 days
- End-of-beta purge: execute DB backup + anonymization + deletion
- Temporary audio files: delete immediately after STT processing

## Batch Operations
- Daily retention job script: `scripts/data_retention_job.py`
  - default: log/report artifacts 30 days, checkins 90 days
  - dry-run: `python scripts/data_retention_job.py --dry-run`
- GitHub Actions schedule:
  - `.github/workflows/data-retention.yml`
- Log anonymization backfill:
  - `python scripts/anonymize_beta_logs.py --glob "data/beta_run_log_*.csv"`

## Access Control
- Access limited to project team members
- No public sharing of raw transcripts
- KPI reports should use aggregated/anonymized data

## Compliance Notes
- Product is not a medical diagnosis tool
- Emergency risk text must direct users to crisis resources
