# Antigravity native support — Test Contract

> The traceability matrix: every R-id in the `.spec.md` maps to a concrete, executable
> check. The Reviewer fails the feature if any R-id lacks a passing test. All checks are
> POSIX-`sh` assertions in `tests/test_install.sh` (wired into `verification.test_command`),
> run against a fresh install in the test's temp target `$T`. They mirror the existing
> `R7`-style assertions for `.claude/` and `.opencode/`.
>
> **Re-spec:** the target dir is **`.agents/` (plural)**, and the assertions test
> registration-meaningful **shape** (correct dir, `description`, role resolves to
> `.harness/agents/*.md`, no forked body, byte-equality, deselect-safety) — **not** mere
> file presence. The bare-file personas (R4/R5) are tested for **shape only**: nothing
> here asserts they register as Antigravity subagents (that is unconfirmed — Open
> question 2).

| R-id | Behavior | Test (file::assertion) | Type | Status |
|---|---|---|---|---|
| R1 | `GEMINI.md` managed block boots Orchestrator against `.harness/AGENTS.md`, written for antigravity-only too | `tests/test_install.sh`: `grep -qF '<!-- harness:begin -->' "$T/GEMINI.md"` **and** `grep -qF '.harness/AGENTS.md' "$T/GEMINI.md"`; plus the `--agents=antigravity` test asserts GEMINI.md + its block + `.agents/rules/harness.md` exist with NO CLAUDE.md/opencode.json | install-shell | ⬜ |
| R2 | Antigravity entrypoint rule written under **`.agents/rules/`** + points at the harness | `tests/test_install.sh`: `[ -f "$T/.agents/rules/harness.md" ]` **and** `grep -qF '.harness/AGENTS.md' "$T/.agents/rules/harness.md"` **and** `grep -qF '.harness/agents/orchestrator.md' "$T/.agents/rules/harness.md"` | install-shell | ⬜ |
| R3 | Rule points at canonical roles, **no copied role body** | `tests/test_install.sh`: rule references `.harness/agents/orchestrator.md`; the canonical-orchestrator sentinel `$AG_SENTINEL` is **absent** — `grep -qF "$AG_SENTINEL" "$T/.agents/rules/harness.md" && fail` (no role body embedded) | install-shell | ⬜ |
| R4 | One persona per role under **`.agents/agents/`**, each with `description` (shape only — best-effort) | `tests/test_install.sh`: for `orchestrator architect builder reviewer scout`: `[ -f "$T/.agents/agents/$r.md" ]` **and** `grep -qE '^description:' "$T/.agents/agents/$r.md"` | install-shell | ⬜ |
| R5 | Persona **defers** to canonical role, mandates init + `progress/`, no copied body | `tests/test_install.sh`: each persona: `grep -qF ".harness/agents/$r.md"`, `grep -qF '.harness/init.sh'`, `grep -qF '.harness/progress/'`; and `$AG_SENTINEL` is **absent** (no fork) | install-shell | ⬜ |
| R6 | All five workflow files under **`.agents/workflows/`** | `tests/test_install.sh`: for `sdd-next sdd-new sdd-plan sdd-drill sdd-fix`: `[ -f "$T/.agents/workflows/$w.md" ]` | install-shell | ⬜ |
| R7 | Each workflow carries a `description` (slash-command registration) | `tests/test_install.sh`: for each workflow: `grep -qE '^description:' "$T/.agents/workflows/$w.md"` | install-shell | ⬜ |
| R8 | Each workflow **resolves its role** against `.harness/agents/*.md`, carries args | `tests/test_install.sh`: `sdd-next`→`grep -qF '.harness/agents/orchestrator.md'`; `sdd-new`→`.harness/agents/inception.md`; `sdd-plan`→`.harness/agents/planner.md`; `sdd-drill`→`.harness/agents/driller.md`; `sdd-fix`→`.harness/agents/fixer.md`; each carries `$ARGUMENTS` (`grep -qF '$ARGUMENTS'`) — all under `$T/.agents/workflows/` | install-shell | ⬜ |
| R9 | Antigravity workflow body **byte-identical** to the Claude command (no drift) | `tests/test_install.sh`: for each workflow: `cmp -s "$T/.claude/commands/$w.md" "$T/.agents/workflows/$w.md"` (content-equivalent, exactly as the OpenCode parity check) | install-shell | ⬜ |
| R10 | Version stamped + CHANGELOG entry naming `.agents/` | `tests/test_install.sh`: `[ "$(cat "$T/.harness/.harness-version")" = "$(cat "$SRC/VERSION")" ]` (existing stamp check, green); **manual/Reviewer:** `SRC/VERSION` == `0.22.0` (single MINOR, no further bump) and `CHANGELOG.md`'s `## [0.22.0]` Antigravity section reads `.agents/` (plural); manifest HARNESS-OWNED list names `.agents/{rules,agents,workflows}/*` | install-shell + review | ⬜ |
| R11 | Antigravity assertion group present, **shape-not-existence**, suite passes | `tests/test_install.sh`: the group asserts correct plural dir + `description` + role-resolution + `$ARGUMENTS` + `cmp -s` byte-equality + absent sentinel (per R2–R9 above), prints `pass "Antigravity glue generated (R11)"`; full `verification.test_command` exits 0 | install-shell | ⬜ |
| R12 | Fallback model: durable glue via `.agents/rules/` entrypoint + `description`-gated `.agents/workflows/` + `progress/` hand-off; entrypoint documents it; personas best-effort | `tests/test_install.sh`: presence + shape of the rule (R2/R3) and workflows (R6–R9) jointly evidence the working model; **Reviewer:** the `.agents/rules/harness.md` body documents the rules+workflows+`progress/` model and asserts neither a Task-tool spawn NOR a registered bare-file subagent | install-shell + review | ⬜ |
| R13 | Deselect removes **only pristine** `.agents/` glue, keeps user files, never `rm -rf` | `tests/test_install.sh` (`antigravity deselect is byte-exact`): after `--agents=antigravity` install then `--agents=claude`, a user-overwritten standard-named `.agents/agents/builder.md` **survives** with its content; pristine `.agents/agents/reviewer.md`, `.agents/workflows/sdd-next.md`, `.agents/rules/harness.md` are **removed**; `.agents/` dir **survives** because the user file keeps it non-empty. Plus `GEMINI.md shared by gemini+antigravity`: GEMINI.md kept while either owner remains, removed once neither does. | install-shell | ⬜ |

## Behavioral / end-to-end checks
- Run `sh tests/test_install.sh`: a fresh install creates `$T/.agents/rules/harness.md`,
  `$T/.agents/agents/{orchestrator,architect,builder,reviewer,scout}.md`, and
  `$T/.agents/workflows/{sdd-next,sdd-new,sdd-plan,sdd-drill,sdd-fix}.md`; the upgrade
  re-run does not duplicate or error (regeneration is idempotent, like `.claude/`).
- Run the full `verification.test_command` chain from `harness.config.yaml`; it exits 0.
- Confirm no stray singular `.agent/` literal remains in the Antigravity glue paths of
  `harness-install.sh` / `tests/test_install.sh`.
- Reviewer manual check: open a generated `.agents/workflows/sdd-next.md` and a
  `.agents/agents/builder.md` and confirm each is a pointer/wrapper at `.harness/…`, with
  no canonical role prose pasted in; confirm `.agents/rules/harness.md` documents the R12
  working model (rules + `description`-gated workflows + `.harness/progress/` hand-off) and
  makes no Task-tool-spawn or registered-subagent claim.

## Non-functional checks
- Lint: `lint_command` is empty for this repo — n/a.
- Types: `typecheck_command` is empty for this repo — n/a.
- POSIX `sh` portability: the installer block and test assertions use only constructs
  already present (`mkdir -p`, here-docs, `cp`, `grep`, `cmp`, `[ -f ]`, `for` loops) —
  no new deps.
