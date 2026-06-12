# Architect run — E08-F01 (Interactive agent-target selection)

## What I specced
Four files under `specs/epics/E08-installer-selection/F01-agent-selection/`:
`.spec.md` (15 EARS requirements R1–R15), `.plan.md`, `.tasks.md` (T1–T13), `.tests.md`
(R1–R15 traceability). The feature gates the **existing** stamp blocks in
`harness-install.sh` (Claude `CLAUDE.md`+`.claude/`, Gemini `GEMINI.md`, OpenCode
`opencode.json`+`.opencode/`, the future E07 Antigravity `.agent/` tree) on an
interactive selection, persists the choice to `.harness/agents`, and re-prompts +
reconciles (add/remove) on every re-run — decoupled from `VERSION`. Non-interactive runs
honor `--agents=<csv>` / `HARNESS_AGENTS=<csv>` and default to ALL with no TTY
(back-compat). MINOR bump 0.20.0 → 0.21.0 + CHANGELOG entry are in the task list.

Architecture artifacts (`specs/architecture.md`/`vision.md`/`adr/`) are **absent** —
recorded in the `.spec.md`, no fabricated ADR citation, no `## Architecture alignment`
section (graceful degradation). No `slices[]` — single-repo, no umbrella obligations.

## Decisions on the four open questions
1. **Selection UI** — pure-`read` numbered toggle list, **zero new deps** (no
   whiptail/dialog). Honors harness leanness; only runs on a TTY.
2. **Persistence** — dedicated `.harness/agents` file (newline-separated keys), beside
   `.harness-version`. Chosen over *deriving* from existing files because derivation
   cannot tell "deliberately deselected" from "never installed".
3. **Remove semantics** — **delete** the deselected agent's regenerated glue + warn,
   scoped to harness-owned paths only (`opencode.json` is skip-and-warn if hand-edited;
   `AGENTS.md` and `.harness/` body never touched).
4. **Registry** — declarative table, one row per agent (`claude`, `gemini`, `opencode`,
   `antigravity`), so a future agent is one entry and Antigravity is a natural row.

## What the human should weigh at the gate
- **E07-F01 re-spec dependency (the big one).** E07-F01 is `spec-ready` with
  `depends_on: ["E08-F01"]` but its approved spec still says "**always** stamp
  Antigravity" (its R2/R4/R6 are "on every run…"). Under E08-F01, Antigravity becomes
  **stamp-if-selected**. E07-F01 must be sent back to the Architect (always-stamp →
  stamp-if-selected) **before it builds**. I did NOT edit E07-F01's spec — flagged only.
  Until E07-F01 builds, the `antigravity` registry row's stamp action is a documented
  **no-op placeholder**; the selection/persistence/removal plumbing is specced now so
  E07-F01 only fills in the stamp body.
- Confirm the three UI/persistence/removal decisions above (esp. **deletion** of
  generated glue on de-select — residual risk if a user hand-edited a generated
  `.claude/commands/*.md`; the spec mitigates by scoping to harness-owned paths +
  skip-and-warn for `opencode.json`).
- Empty-override grammar (`--agents=`): spec leaves the "none vs. fall-through" choice to
  the Builder but requires the tests to pin whichever is chosen.

## Status
Did NOT change any status in `state/tasks.json`. All four files written. Ready for the
`spec-ready` gate.
