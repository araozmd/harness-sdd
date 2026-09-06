---
id: E27
title: Escalation tier — KEEP, cascade the umbrella's models to children
status: planned
---

# E27 — Escalation tier: keep + cascade

Drilled 2026-09-06. The delete-vs-cascade question is ANSWERED by use: on 2026-09-05
every target (harness-sdd + 15 umbrella children) was armed with sonnet-builder /
opus-escalation, and the arming required editing 16 per-child `models:` blocks by
script — the exact toil a cascade removes. `init.sh`'s ARMED/DISARMED line (v0.69.0)
stays as the visibility contract.

## Features

- **E27-F01 — umbrella `models:` cascade.** During an umbrella cascade, a child config
  key that reads `inherit` (or is absent) resolves from the COORDINATOR's
  `.harness/harness.config.yaml` `models:` block before falling back to the built-in
  default; a child's own explicit non-inherit value always wins. One coordinator edit
  then arms/re-tiers every child on the next cascade run, and the per-child escalation
  verdicts are recomputed in the same pass. Report line per child names the source
  (own | umbrella | default). Tests: cascade fixture with coordinator tiers + one
  overriding child; verdict recomputation; single-repo installs unaffected.
