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

## Access Control
- Access limited to project team members
- No public sharing of raw transcripts
- KPI reports should use aggregated/anonymized data

## Compliance Notes
- Product is not a medical diagnosis tool
- Emergency risk text must direct users to crisis resources
