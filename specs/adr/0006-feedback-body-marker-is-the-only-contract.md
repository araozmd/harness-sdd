# ADR-0006 — The versioned body marker is the only contract between reporter and triage

- **Status:** accepted (E32 drill, 2026-09-25)
- **Date:** 2026-09-25

## Context

Three E32 features touch one issue: the reporter (F02) writes it, the labeler Action (F04)
classifies it, and `/sdd-triage` (F05) routes it. Reporters usually have no write access,
so GitHub silently drops any labels they set. The repo is public, so anyone can write an
issue body that looks like a report.

## Decision

A report is identified **only** by a single versioned, machine-readable marker in the
issue body (for example an HTML comment carrying the schema version, harness `VERSION`, host
and trigger type). F02 is the only writer of its format. F04 and F05 **parse** it with a
strict, allow-listed grammar and treat everything else in the body as untrusted
free text: they never execute it, never interpolate it into shell or workflow
expressions, and never copy it verbatim into a brief. An issue with a missing or malformed
marker isn't a report. A version the consumer doesn't recognize is ignored, not guessed at.

## Consequences

- The marker grammar is defined once, in F02's spec, and cited by F04 and F05.
- Anyone can spoof the marker. It only buys a label and a place in the triage list,
  which is safe because the human approval gate (E32) stands between an issue and any
  TaskStore write.
- Changing the format means bumping the marker's version, and consumers keep reading the
  old one until every installed reporter has upgraded.
