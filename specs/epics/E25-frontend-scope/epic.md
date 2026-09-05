---
id: E25
title: Front-end scope — Claude-first defaults, non-Claude front-ends parked
status: planned
---

# E25 — Front-end scope: park non-Claude front-ends

Drilled 2026-09-05 from the v0.69.0 ablation campaign (operator-approved plan). The
multi-front-end matrix (codex, opencode, gemini, antigravity) is the largest single
share of installer complexity and test surface, while every active target now runs
Claude-only (both umbrellas re-selected 2026-09-05; the escalation arming verdict only
arms cleanly under a single front-end). Doctrine: float don't pin — park by DEFAULT
FLIP first, collect usage evidence, delete code only when evidence says nobody opts in.

## Features

- **E25-F01 — Claude-first selection defaults.** The undetected-host fallback for a
  FRESH target and the interactive prompt default become `claude` only (today:
  "selecting all front-ends"). Explicit `--agents=<csv>` / `HARNESS_AGENTS` keep every
  key working, unchanged; an existing install's recorded selection is never clobbered
  (the host_fallback_keeps_selection arm stays). Docs say plainly that non-Claude
  front-ends are parked-by-default and how to opt in. Tests pin both fallback arms.

## Deliberately NOT in this epic (yet)

Deleting the non-Claude emitters and their suites. That is the E21-F07 move one step
too early: a default flip is reversible and produces the usage evidence (who still
passes --agents=codex?) that justifies — or refutes — the deletion. Revisit after two
release cycles. E99-F145 (opencode pr-fixer emitter defect) stays parked on this epic:
it now only affects explicit opt-in users, and its fix-or-retire follows the evidence.
