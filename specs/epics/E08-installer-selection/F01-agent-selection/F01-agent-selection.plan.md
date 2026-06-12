# Interactive agent-target selection — Technical Plan

> Translates the .spec.md intent into design. Every decision cites the R-id(s) it
> serves. Pure POSIX sh, zero new dependencies — matches `init.sh`/`harness-install.sh`.

## Stack & dependencies
- Language: POSIX `sh` (the existing `harness-install.sh` dialect; `set -eu`).
- New dependencies: **none**. Selection UI is a pure `read` loop (no `whiptail`/
  `dialog`). (serves: R1, R9)

## Data model — persisted selection  (serves: R8, R9)
| Artifact | Location | Format | Notes |
|---|---|---|---|
| Selection state file | `<T>/.harness/agents` | one agent key per line, sorted | Harness-owned metadata, beside `.harness/.harness-version`; written/overwritten every run. Absence ⇒ "no prior selection" (fresh) → pre-check ALL (R1). |

Agent keys (the only legal tokens, used by the registry, the override parser, and the
file): `claude`, `gemini`, `opencode`, `antigravity`. (serves: R7, R10)

## Agent registry  (serves: R3, R4, R10, R13)
A declarative table near the top of `install_one` (or just above it), one row per agent.
Encode each row as a single space/`|`-delimited record the resolver iterates (POSIX sh
has no arrays of structs; a here-doc/`while read` table or a small `case`-dispatch keyed
on the agent key are both acceptable — Builder's choice). Each row carries:

| key | stamp action (existing block to gate) | owned glue paths (for removal, R13) |
|---|---|---|
| `claude` | `write_pointer CLAUDE.md` + the `.claude/agents` + `.claude/commands` emit block (installer §4 CLAUDE.md line, §5) | `<T>/.claude/agents` `<T>/.claude/commands` (regenerated dirs) + the `CLAUDE.md` harness block¹ |
| `gemini` | `write_pointer GEMINI.md` (installer §4 GEMINI.md line) | the `GEMINI.md` harness block¹ |
| `opencode` | the `.opencode/command` mirror (installer §5b) + the `opencode.json` create block (§6) | `<T>/.opencode/command` (regenerated dir); `opencode.json`² |
| `antigravity` | the E07 `.agent/` tree stamp (NOT YET PRESENT — see DO NOT TOUCH / E07-F01) | `<T>/.agent` (regenerated tree) |

¹ Removing an agent that owns only a *pointer block* inside a shared file (`CLAUDE.md`,
`GEMINI.md`): delete the marked `harness:begin..harness:end` block from that file
(reusing the same marker-aware in-place edit `write_pointer` already does — Builder may
extract a small `remove_pointer <file>` helper), and remove the file only if it becomes
empty/harness-only. Do **not** delete user prose. (serves: R13)

² `opencode.json` is currently *create-if-absent, never clobbered*. On removal, only
delete an `opencode.json` the installer itself generated; if it has been hand-edited
(differs from the generated template), **leave it and warn** rather than delete (honors
the R13 "harness-owned glue only, never hand-edited" scoping). Builder may detect this
by regenerating to a temp file and comparing, or by a generated-marker — Builder's call.

> NOTE: `AGENTS.md` and the `write_pointer AGENTS.md` call are **not** in any registry
> row — `AGENTS.md` is the shared portable entrypoint, always written, never gated,
> never removed. (serves: R-spec "Out of scope", R13)

## Selection resolution — control flow  (serves: R1, R5, R6, R7, R9, R11)
Add a `resolve_agents <target>` step that runs **inside `install_one`, before** the
entrypoint-pointer / glue blocks (§4–§6), and sets a single resolved variable
(e.g. `SELECTED` = newline list of keys). Resolution order (first match wins):

1. **Override (R5, R7).** If `--agents=<csv>` (parsed in the arg loop) or
   `HARNESS_AGENTS` env is non-empty → split on commas, trim, validate each token
   against the registry keys; on any unknown token, `die` non-zero naming the token
   (R7), making no changes. No prompt. Wins over persisted + over TTY.
2. **Interactive (R1, R9).** Else if stdin is a TTY (`[ -t 0 ]`) → read the pre-check
   baseline: the persisted `.harness/agents` if present (R9), else ALL (R1). Print the
   numbered toggle list showing each key's pre-check state; `read` toggles; confirm.
3. **No-TTY default (R6).** Else (not a TTY, no override) → `SELECTED` = ALL.

After resolution, **persist** `SELECTED` to `.harness/agents` (R8), then gate each
registry row's stamp on membership (R3/R4) and run removals for any key in the prior
persisted set but not in `SELECTED` (R13/R12 is the additive side: in `SELECTED` but not
prior ⇒ its normal stamp runs).

Re-prompt-on-update is automatic: resolution runs every `install_one`, independent of
the `UPGRADE`/`VERSION` comparison — nothing branches on `LAST_UPGRADE`/version here.
(serves: R11)

## Files to change  (serves: R#)
| File | Change | R-id |
|---|---|---|
| `harness-install.sh` | Add the **agent registry** table (declarative rows). | R3, R4, R10 |
| `harness-install.sh` | Add `--agents=<csv>` to the arg-parse `while`/`case` loop; read `HARNESS_AGENTS` env. | R5, R7 |
| `harness-install.sh` | Add `resolve_agents` (override → TTY prompt → ALL) + the pure-`read` numbered toggle UI; compute pre-check baseline from `.harness/agents` (R9) or ALL (R1). | R1, R5, R6, R7, R9 |
| `harness-install.sh` | Gate §4 CLAUDE.md/GEMINI.md pointer lines, §5 `.claude/`, §5b `.opencode/`, §6 `opencode.json`, and the (future) `.agent/` block on registry-row membership in `SELECTED`. Keep `write_pointer AGENTS.md` ungated. | R2, R3, R4 |
| `harness-install.sh` | After resolution, write `.harness/agents` (sorted keys, one per line). | R8 |
| `harness-install.sh` | Compute the removal set (prior persisted − SELECTED) and delete each removed agent's owned glue + warn; reconcile order so adds stamp and removes delete in the same run. | R12, R13 |
| `harness-install.sh` | (optional helper) `remove_pointer <file>` mirroring `write_pointer`'s marker-aware in-place edit, for gemini/claude pointer-block removal. | R13 |
| `tests/test_install.sh` | New assertion group mirroring the existing `R7`-style stamping checks: selected-only stamping, no-TTY ALL default, explicit override, unknown-key rejection, persistence round-trip, add+remove re-run. | R15 |
| `VERSION` | MINOR bump (`0.20.0` → `0.21.0`). | R14 |
| `CHANGELOG.md` | New `## [0.21.0]` entry under "Added — ✨ selectable agent targets". | R14 |
| `harness-install.sh` (header comment + `manifest.txt` body) | Document the new `.harness/agents` file and the `--agents`/`HARNESS_AGENTS` knob; note that deselected agents' glue is removed. | R8, R13 (doc) |

## DO NOT TOUCH
- **Canonical role files** `agents/*.md` — never fork/rewrite; the registry points at
  stamp actions, not role bodies.
- **`store/tasks.schema.json`** and any status enum — no schema/status change.
- **The portable core** — `init.sh`, the markdown TaskStore, `progress/` hand-offs, the
  4-file spec format. The selection lives entirely in `harness-install.sh` + its state
  file.
- **`AGENTS.md` and `write_pointer AGENTS.md`** — the shared entrypoint is always
  written and never part of a registry row (never gated, never removed).
- **`E07-F01`'s spec** (`specs/epics/E07-antigravity/F01-antigravity-support/*`) — do
  NOT edit it. Its always-stamp → stamp-if-selected rework is a separate Architect
  re-spec the human authorizes at the gate (see `.spec.md` → *E07-F01 coordination*).
  The `antigravity` registry row's stamp action stays a no-op placeholder here until
  E07-F01 builds; do not invent the `.agent/` tree in this feature.
- **Umbrella mode plumbing** (`--umbrella`, `manifest_upsert`, `--shared-repo`,
  `migrate_config`) — unchanged. Each cascade child installs non-interactively, so it
  resolves via override/ALL (R5/R6) with no umbrella-specific code.

## Approach notes
- **Back-compat is the load-bearing invariant (R6).** The very first thing to verify
  while building: a no-arg, non-TTY run must still stamp all four selectable actions
  exactly as today. The existing `tests/test_install.sh` invokes the installer via
  `sh …` with redirected stdin (not a TTY), so its current assertions are the
  back-compat guard — they must keep passing unchanged.
- **TTY detection.** Use `[ -t 0 ]`. The prompt must never run under `--agents`/
  `HARNESS_AGENTS` (R5) nor without a TTY (R6) — both are how CI and the test suite stay
  deterministic.
- **CSV grammar.** Accept lowercase keys, trim surrounding whitespace, ignore empty
  tokens (e.g. trailing comma); de-duplicate; reject unknown tokens (R7). An empty
  override value (`--agents=`) should be treated as "no override" (fall through) or an
  explicit "none" — Builder picks one and documents it; the tests pin the chosen
  behavior.
- **Removal safety (R13).** Delete only the registry-listed owned paths, and only when
  they match what the installer generates (esp. `opencode.json`: skip-and-warn if
  hand-edited). Never `rm -rf` a user dir; never touch `.harness/` body or `AGENTS.md`.
- **Persistence ordering (R8).** Write `.harness/agents` after resolution but it is fine
  to write before/after stamping as long as the persisted content equals the resolved
  set; keep keys sorted so the file is stable across runs (clean diffs, idempotent).
- Keep the Builder free to choose the exact table encoding and the toggle-UI keystroke
  grammar; the spec pins only the resolved behavior and the persisted format.
