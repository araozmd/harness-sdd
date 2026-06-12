# Builder run — E08-F01 (Interactive agent-target selection)

## Precondition
Feature `E08-F01` confirmed `in-progress` in `state/tasks.json` (Loop A step 1 holds).
`./init.sh` green before and after. Execution backend: in-session (default).

## Tasks completed (T1–T13, all ticked in tasks.md)
- **T1 (R10)** — Declarative agent registry `AGENT_KEYS="claude gemini opencode antigravity"`
  in `harness-install.sh`, with `agent_known`/`agent_selected`/`normalize_keys` helpers. The
  `antigravity` stamp is a documented no-op placeholder (only its removal `.agent/` case exists).
- **T2 (R5, R7)** — `--agents=<csv>` / `--agents <csv>` added to the arg loop; `HARNESS_AGENTS`
  read from the environment into `AGENTS_OVERRIDE` (env seeded first, `--agents` supersedes).
  Empty value (`--agents=` / `HARNESS_AGENTS=""`) is treated as "no override" (documented).
- **T3 (R7)** — `validate_csv`: comma-split, trim, drop-empty, de-dup, sort; `die` non-zero
  naming the first unknown token, before any filesystem change.
- **T4 (R1, R9)** — `toggle_select`: pure-`read` numbered toggle UI, baseline-pre-checked,
  prompts to stderr / resolved keys to stdout. (TTY-only; not exercised by the non-TTY suite.)
- **T5 (R1,R5,R6,R9,R11)** — `resolve_agents <target>`: override → TTY toggle (baseline =
  persisted set or ALL) → no-TTY ALL. Called at the TOP of `install_one`, decoupled from
  `UPGRADE`/`VERSION`. Sets global `SELECTED` (sorted newline list).
- **T6 (R8)** — Persists `SELECTED` to `.harness/.agents` (see deviation below), one sorted
  key per line, overwritten every run, beside `.harness/.harness-version`.
- **T7 (R2,R3,R4)** — Gated every existing stamp block on `agent_selected`: CLAUDE.md (claude),
  GEMINI.md (gemini), `.claude/` agents+commands (claude), `.opencode/command` + `opencode.json`
  (opencode). `write_pointer AGENTS.md` left UNGATED (always written). Slash-command bodies are
  now generated once into a temp `CMDDIR` and copied to whichever of `.claude/commands` /
  `.opencode/command` is selected — so OpenCode works even when Claude is deselected.
- **T8 (R13)** — `remove_pointer <file>`: marker-aware in-place block delete mirroring
  `write_pointer`; removes the file only if nothing but whitespace remains.
- **T9 (R12,R13)** — Reconciliation: removal set = prior-persisted − SELECTED. Per removed key,
  deletes its owned glue (`.claude/*` dirs, pointer blocks, `.opencode/command`) and warns to
  **stderr** naming each path. `opencode.json` deleted only if it matches the generated template
  (schema URL + orchestrator prompt marker), else skip-and-warn. `.agent/` removed for
  antigravity. Never touches `AGENTS.md` or `.harness/` body. Adds handled by the gated stamp (T7).
- **T10 (docs)** — Updated the `harness-install.sh` header comment and `manifest.txt` body to
  document `.harness/.agents`, the `--agents`/`HARNESS_AGENTS` knob, and removal-on-deselect.
- **T11 (R15)** — New assertion group in `tests/test_install.sh` (see R→test map below).
- **T12 (R14)** — `VERSION` 0.20.0 → 0.21.0 (MINOR); `CHANGELOG.md` `[0.21.0]` entry added.
- **T13** — `./init.sh` + full `verification.test_command` suite run green (output below).

## R-id → new test coverage (tests/test_install.sh)
- **R1, R6** — `no-TTY no-override run stamps ALL four agents + persists ALL`
- **R2, R3, R4** — `--agents=claude stamps only Claude, no other front-ends`
- **R3** — `--agents=claude,opencode stamps each selected agent`
- **R5** — `explicit --agents / HARNESS_AGENTS override resolves the set, --agents wins`
- **R7** — `unknown override key exits non-zero, names it, makes no changes`
- **R8** — `.harness/.agents persists the selection sorted, coexists with the roles dir`
- **R9, R11, R12, R13** — `re-run adds + removes agents at same VERSION, persisted baseline updated`
- **R10** — `every registry key is individually selectable`
- **R14** — existing `version stamped` check (no exact-VERSION freeze, per repo memory);
  CHANGELOG `[0.21.0]` left for Reviewer to confirm.
- **R15** — the whole group + the green suite.

## Test-suite result (verification.test_command)
`./init.sh` → green. Composite command exit: **0**. All 13 suites pass:
test_install, test_umbrella, test_cascade, test_inception, test_reviewer, test_telemetry,
test_mirror, test_epic_lifecycle, test_sdd_plan, test_sdd_drill, test_sdd_fix,
test_architect_adr, test_drift_check. (test_install adds 8 new `ok -` lines.)
`sh -n` and `dash -n` parse clean; no bashisms; shellcheck shows only pre-existing warnings.

## Deviation (recorded per Loop A "stay inside the spec" — flag, do not redesign silently)
- **State-file path: `.harness/.agents` instead of `.harness/agents`.** The spec/plan/tests name
  the persistence file `.harness/agents`, but `.harness/agents/` is ALREADY the role-bodies
  DIRECTORY (`copy agents` → `.harness/agents/orchestrator.md` etc.). A FILE at `.harness/agents`
  collides with that DIR and made the install fail (confirmed: exit 1, "Not a directory"). I kept
  the spec's intent verbatim — harness-owned metadata beside `.harness/.harness-version`, one
  sorted key per line, the prior-selection baseline — and only moved it to the dot-prefixed
  sibling `.harness/.agents` (which, like `.harness-version`, is a dot-file and does not collide).
  The tests assert `.harness/.agents` AND that the `.harness/agents/` roles dir still coexists.
  **Reviewer note:** if the spec must literally read `.harness/agents`, the Architect would need
  to rename the roles dir — out of scope here and a DO-NOT-TOUCH portable-core change; the
  dot-file is the minimal faithful resolution. All other behavior matches the spec exactly.

## Reviewer focus suggestions
- The `.harness/.agents` vs `.harness/agents/` deviation above (the one judgment call).
- Removal safety (R13): warnings to stderr; `opencode.json` skip-and-warn when hand-edited;
  `AGENTS.md` + `.harness/` never touched (asserted in `reconcile` test).
- Back-compat (R6): no-TTY + no override still stamps ALL — the existing fresh-install
  assertions plus the new explicit ALL check are the guard.
- Empty-override grammar choice: `--agents=` / `HARNESS_AGENTS=""` ⇒ "no override" (fall through),
  documented in the header comment and arg-loop comment.
- antigravity stays a no-op stamp placeholder (E07-F01 fills the `.agent/` stamp body); only its
  removal case is wired. E07-F01 still needs the always-stamp → stamp-if-selected re-spec.

## Status
Did NOT change any status in `state/tasks.json`; did NOT open a PR. Handing back to the
Orchestrator for `in-review`.
