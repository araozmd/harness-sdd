# E04-F01 — Architect hand-off note

## What I produced
Four spec files under `specs/epics/E04-intake/F01-inception/`:
- `inception.spec.md` — frontmatter (id E04-F01, status pending, sdd true,
  autonomous false, depends_on []), Context, Business rules, 16 EARS criteria
  (R1–R16), Out of scope, Open questions.
- `inception.plan.md` — "prose, not runtime code" approach (portable role file +
  Claude slash command + two additive doc edits, no new deps), files-to-change with a
  DO NOT TOUCH list, each decision citing R-ids.
- `inception.tasks.md` — 14 atomic tasks (T1–T14), including the MINOR VERSION bump
  and CHANGELOG/tag as explicit PR-step tasks (T13/T14).
- `inception.tests.md` — full R1→R16 traceability matrix split into scriptable static
  checks (`tests/test_inception.sh`, in `tests/test_install.sh` style) plus a
  documented manual `/sdd-new` walkthrough (§A new feature, §B new epic, §C fail-stop).

## R-ids defined
- R1 portable role file; R2 `/sdd-new` slash command; R3 pending tasks.json entry;
  R4 inbox brief at `progress/inbox/<id>.md`; R5 brief frontmatter+sections;
  R6 schema re-validation; R7 validation fail-stop; R8 single-altitude triage;
  R9 new-epic creates epic.md + F01; R10 next-sequential ids, no reuse;
  R11 never writes spec files; R12 pending-only, never advances;
  R13 no change to schema/orchestrator/architect, no new status;
  R14 text-only ≤3 options; R15 completion report + "run /sdd-next";
  R16 docs describe the pre-pending step.

## Decisions / assumptions
- Encoded the brief as the only new structural artifact; referenced the existing
  `progress/inbox/E04-F01.md` as the canonical brief template (R5).
- Touch-list fixed to: create `agents/inception.md` + `.claude/commands/sdd-new.md`;
  modify `AGENTS.md` (role list) + `docs/WORKFLOW.md` (pre-pending step). DO NOT TOUCH
  `store/tasks.schema.json`, `agents/orchestrator.md`, `agents/architect.md`,
  `.claude/commands/sdd-next.md`, and any other feature's spec files.
- A `.claude/agents/inception.md` sub-agent shim is explicitly OPTIONAL / not required
  by any R-id — the intake spawn path is the `/sdd-new` slash command, not the
  Orchestrator's Task tool.
- `--from-file` batch mode captured as BOTH an Out-of-scope item and an Open question;
  not specced (per brief).
- Next-sequential id allocation chosen (R10); flagged as an Open question for human
  confirmation as a long-term policy.
- VERSION bump (MINOR ✨) + CHANGELOG + tag are listed as Builder/PR tasks (T13/T14),
  not as acceptance criteria — per `CLAUDE.md`.

## Open questions for the human (surface at the gate)
1. Confirm `--from-file` batch mode stays deferred for v1 (interactive-only).
2. Confirm next-sequential id allocation (vs. fill-the-gap) as the long-term policy.

## Status
Did NOT change any status (still `pending`) and wrote no production code. Ready for the
Orchestrator to set `spec-ready` and the human gate.
