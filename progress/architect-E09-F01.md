# Architect hand-off — E09-F01

## What was produced
Four spec files written under `specs/epics/E09-doc-quality/F01-doc-critic/`:

- `E09-F01.spec.md` — functional spec with 18 EARS requirements (R1–R18)
- `E09-F01.plan.md` — technical plan: files to change, DO NOT TOUCH list, approach notes, risks
- `E09-F01.tasks.md` — 12 atomic tasks for the Builder
- `E09-F01.tests.md` — traceability matrix R-id → test

## Open questions resolved (from the Inception brief)
- **One reviewer or three?** → One parameterized role (`agents/doc-critic.md`) with a
  `target-type` argument (`plan-output`, `epic-decomposition`, `feature-spec`).
- **Who invokes it?** → The generating agent spawns the critic as a sub-agent after
  writing its outputs (Planner after `/sdd-plan`, Driller after `/sdd-drill`,
  Architect after drafting the four-file spec).
- **Failure posture?** → Best-effort/never-blocking; the generating agent proceeds and
  appends a note to `progress/<run>/` on error or timeout.
- **Where do findings go?** → Inline fixes in the reviewed docs plus a brief progress
  note under `progress/<run>/`.

## Risks noted
- Critic could become a gate if not kept advisory — mitigated by R5/R6.
- Token burn from over-review — mitigated by narrow per-target scopes (R3) and the
  calibration rule (R4).
- Three invocation points could drift — mitigated by one shared role file and tests
  that assert consistent invocation strings.
- Installer could miss the new role — mitigated by R13 + `test_install.sh` assertions.

## Architecture alignment note
`specs/architecture.md` does not exist and `specs/adr/` is empty, so the spec records
`ADRs touched: none` and proceeds from the brief alone, per the graceful-degradation
rules in `agents/architect.md`.

## Status
E09-F01 is **spec-ready**.
