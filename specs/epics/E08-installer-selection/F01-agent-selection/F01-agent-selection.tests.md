# Interactive agent-target selection — Test Contract

> The traceability matrix: every R-id in the .spec.md maps to a concrete test. The
> Reviewer fails the feature if any R-id lacks a passing test. Tests are POSIX `sh`
> assertions in `tests/test_install.sh` (the harness's own product suite, wired into
> `verification.test_command`), mirroring its existing `fail`/`pass` + grep/`[ -f ]`
> style. All installer invocations run via `sh harness-install.sh …` (non-TTY stdin),
> so `--agents` / `HARNESS_AGENTS` drive selection deterministically.

| R-id | Behavior | Test (file::assertion) | Type | Status |
|---|---|---|---|---|
| R1 | Fresh TTY install pre-checks ALL in the toggle list | `tests/test_install.sh::default_all_when_no_persisted` — a no-override run (non-TTY proxy for "no prior selection") resolves to ALL four agents; documents that the TTY pre-check baseline is ALL when `.harness/agents` is absent | shell | ⬜ |
| R2 | `--agents=claude` stamps only Claude, no other front-ends | `tests/test_install.sh::agents_claude_only_stamps_claude` — asserts `CLAUDE.md` + `.claude/agents` + `.claude/commands` exist and `GEMINI.md`, `opencode.json`, `.opencode/`, `.agent/` are **absent** | shell | ⬜ |
| R3 | Selected agent's existing stamp action runs | covered by `agents_claude_only_stamps_claude` (claude glue present) + `agents_multi_stamps_each` (`--agents=claude,opencode` ⇒ both stamped) | shell | ⬜ |
| R4 | Deselected agent's stamp action is skipped | `tests/test_install.sh::agents_claude_only_stamps_claude` — the absent-file assertions are the R4 verification | shell | ⬜ |
| R5 | `--agents` / `HARNESS_AGENTS` override resolves the set, no prompt | `tests/test_install.sh::env_override_selects` — `HARNESS_AGENTS=gemini sh harness-install.sh <T>` stamps only `GEMINI.md`; and `--agents=gemini` does the same (override wins) | shell | ⬜ |
| R6 | No-TTY + no override ⇒ ALL (back-compat) | `tests/test_install.sh` — the **existing** default fresh-install assertions (all front-ends present) plus an explicit `all_four_front_ends_present` check after a no-arg run | shell | ⬜ |
| R7 | Unknown override key ⇒ non-zero exit, no changes | `tests/test_install.sh::unknown_agent_key_rejected` — `--agents=claude,bogus` exits non-zero, error names `bogus`, and a clean target is left unstamped | shell | ⬜ |
| R8 | Selection persisted to `.harness/agents` | `tests/test_install.sh::persists_selection` — after `--agents=claude,opencode`, `.harness/agents` exists and contains exactly `claude` and `opencode` (sorted, one per line) | shell | ⬜ |
| R9 | Re-run pre-checks the previously-persisted set | `tests/test_install.sh::reprompt_baseline_is_persisted` — install with `--agents=claude`, then a re-run with **no override** under non-TTY resolves from the persisted set baseline (asserted via the add/remove reconcile test reading `.harness/agents` as the baseline, not ALL) | shell | ⬜ |
| R10 | Declarative registry of exactly the four keys | `tests/test_install.sh::registry_keys` — every key `claude\|gemini\|opencode\|antigravity` is individually selectable via `--agents=<key>`; an out-of-registry key is rejected (shares the R7 assertion) | shell | ⬜ |
| R11 | Reconciliation offered regardless of VERSION change | `tests/test_install.sh::reconcile_without_version_bump` — two consecutive installs at the **same** `VERSION` still apply a changed `--agents` selection (add/remove takes effect with no version bump between runs) | shell | ⬜ |
| R12 | Re-run **add** stamps the newly-added agent | `tests/test_install.sh::reconcile_add` — install `--agents=claude`, re-run `--agents=claude,opencode`; assert `opencode.json` + `.opencode/` now present | shell | ⬜ |
| R13 | Re-run **remove** deletes that agent's glue + warns; never `AGENTS.md`/`.harness/` | `tests/test_install.sh::reconcile_remove` — install `--agents=claude,gemini`, re-run `--agents=claude`; assert the `GEMINI.md` harness block is gone, `.claude/` survives, `AGENTS.md` still present, `.harness/` body intact, and a warning was printed | shell | ⬜ |
| R14 | MINOR `VERSION` bump + CHANGELOG entry; stamp unchanged | `tests/test_install.sh` existing `version stamped` check (`.harness-version` == source `VERSION`) + a repo check that `VERSION` == `0.21.0` is **not** frozen into the suite (per memory: no exact-VERSION freeze); CHANGELOG `[0.21.0]` entry verified by Reviewer at review | shell + review | ⬜ |
| R15 | Test suite asserts all of the above and passes | the new assertion group itself + `verification.test_command` green | shell | ⬜ |

## Behavioral / end-to-end checks (Reviewer)
- `sh harness-install.sh <T>` with no args, non-TTY → all four selectable front-ends
  stamped (claude/gemini/opencode + the antigravity no-op placeholder), `AGENTS.md`
  present, `.harness/agents` lists all keys. (R6, R8)
- `sh harness-install.sh --agents=claude <T>` → only Claude glue; re-run
  `--agents=claude,opencode` → OpenCode added; re-run `--agents=opencode` → Claude glue
  removed (with a printed warning), OpenCode kept, `AGENTS.md` untouched. (R2, R12, R13)
- `HARNESS_AGENTS=bogus sh harness-install.sh <T>` → non-zero exit, `bogus` named, no
  files written. (R7)

## Non-functional checks
- The **existing** `tests/test_install.sh` assertions (fresh layout, idempotent upgrade,
  project-file preservation, entrypoint merge, installed `init.sh` passes) remain green
  — they are the back-compat guard for R6.
- No new runtime dependency introduced (pure `sh` + grep/awk/`read`).
- Lint/shell: `harness-install.sh` stays POSIX `sh` (`set -eu`); no bashisms added.
- Per repo memory (permanent-suite anti-pattern): the new tests MUST NOT freeze the
  exact `VERSION` string nor diff DO-NOT-TOUCH files against `main` — assert behavior,
  not a literal version.
