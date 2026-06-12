# Antigravity native support — Test Contract

> The traceability matrix: every R-id in the `.spec.md` maps to a concrete, executable
> check. The Reviewer fails the feature if any R-id lacks a passing test. All checks are
> POSIX-`sh` assertions added to `tests/test_install.sh` (which is wired into
> `verification.test_command`), executed against a fresh install in the test's temp
> target `$T`. They mirror the existing `R7`-style assertions for `.claude/` and
> `.opencode/`.

| R-id | Behavior | Test (file::assertion) | Type | Status |
|---|---|---|---|---|
| R1 | `GEMINI.md` managed block boots Orchestrator against `.harness/AGENTS.md` | `tests/test_install.sh`: `grep -qF '<!-- harness:begin -->' "$T/GEMINI.md"` **and** `grep -qF '.harness/AGENTS.md' "$T/GEMINI.md"` (block reads as Orchestrator bootstrap) | install-shell | ⬜ |
| R2 | Antigravity entrypoint rule written + points at the harness | `tests/test_install.sh`: `[ -f "$T/.agent/rules/harness.md" ]` **and** `grep -qF '.harness/AGENTS.md' "$T/.agent/rules/harness.md"` **and** `grep -qF '.harness/agents/orchestrator.md' "$T/.agent/rules/harness.md"` | install-shell | ⬜ |
| R3 | Rule points at canonical roles, no copied role body | `tests/test_install.sh`: rule references `.harness/agents/orchestrator.md`; a sentinel line unique to the canonical orchestrator body is **absent** — e.g. `grep -qF '## The non-negotiable rules' "$T/.agent/rules/harness.md" && fail` (no role body embedded) | install-shell | ⬜ |
| R4 | One persona per role under `.agent/agents/`, each with `description` | `tests/test_install.sh`: for `orchestrator architect builder reviewer scout`: `[ -f "$T/.agent/agents/$r.md" ]` **and** `grep -qE '^description:' "$T/.agent/agents/$r.md"` | install-shell | ⬜ |
| R5 | Persona defers to canonical role, mandates init + `progress/` hand-off, no copied body | `tests/test_install.sh`: each persona: `grep -qF ".harness/agents/$r.md"`, `grep -qF '.harness/init.sh'`, `grep -qF '.harness/progress/'`; and the canonical-body sentinel is absent (no fork) | install-shell | ⬜ |
| R6 | All five workflow files generated under `.agent/workflows/` | `tests/test_install.sh`: for `sdd-next sdd-new sdd-plan sdd-drill sdd-fix`: `[ -f "$T/.agent/workflows/$w.md" ]` | install-shell | ⬜ |
| R7 | Each workflow carries a `description` (slash-command registration) | `tests/test_install.sh`: for each workflow: `grep -qE '^description:' "$T/.agent/workflows/$w.md"` | install-shell | ⬜ |
| R8 | Each workflow acts as its role, resolved against `.harness/agents/*.md`, carries args | `tests/test_install.sh`: `sdd-next`→`grep -qF '.harness/agents/orchestrator.md'`; `sdd-new`→`.harness/agents/inception.md`; `sdd-plan`→`.harness/agents/planner.md`; `sdd-drill`→`.harness/agents/driller.md`; `sdd-fix`→`.harness/agents/fixer.md`; and each carries `$ARGUMENTS` (`grep -qF '$ARGUMENTS'`) | install-shell | ⬜ |
| R9 | Antigravity workflow body matches the Claude command (no drift) | `tests/test_install.sh`: for each workflow: `cmp -s "$T/.claude/commands/$w.md" "$T/.agent/workflows/$w.md"` (content-equivalent, exactly as the OpenCode parity check does) | install-shell | ⬜ |
| R10 | Version stamped/bumped + CHANGELOG entry | `tests/test_install.sh`: `[ "$(cat "$T/.harness/.harness-version")" = "$(cat "$SRC/VERSION")" ]` (existing R2 check, still green); **manual/Reviewer:** `SRC/VERSION` == `0.21.0` and `CHANGELOG.md` has a `## [0.21.0]` Antigravity section | install-shell + review | ⬜ |
| R11 | Antigravity assertion group present and the whole suite passes | `tests/test_install.sh`: the new group prints `pass "Antigravity glue generated (R11)"`; full `verification.test_command` exits 0 | install-shell | ⬜ |
| R12 | Fallback model: native glue via personas + workflows + `progress/` hand-off, entrypoint documents it | `tests/test_install.sh`: presence of personas (R4) + workflows (R6) + the `.agent/rules/harness.md` hand-off/entry rule (R2) jointly evidence the working model; **Reviewer:** entrypoint rule documents the personas-plus-workflows model and asserts no Task-tool-style spawn | install-shell + review | ⬜ |

## Behavioral / end-to-end checks
- Run `sh tests/test_install.sh`: fresh install creates `$T/.agent/rules/harness.md`,
  `$T/.agent/agents/{orchestrator,architect,builder,reviewer,scout}.md`, and
  `$T/.agent/workflows/{sdd-next,sdd-new,sdd-plan,sdd-drill,sdd-fix}.md`; the upgrade
  re-run does not duplicate or error (regeneration is idempotent, like `.claude/`).
- Run the full `verification.test_command` chain from `harness.config.yaml`; it exits 0.
- Reviewer manual check: open a generated `.agent/workflows/sdd-next.md` and a
  `.agent/agents/builder.md` and confirm each is a pointer/wrapper at `.harness/…`, with
  no canonical role prose pasted in.

## Non-functional checks
- Lint: `lint_command` is empty for this repo — n/a.
- Types: `typecheck_command` is empty for this repo — n/a.
- POSIX `sh` portability: the new installer block and test assertions use only
  constructs already present in `harness-install.sh` / `tests/test_install.sh`
  (`mkdir -p`, here-docs, `cp`, `grep`, `cmp`, `[ -f ]`, `for` loops) — no new deps.
