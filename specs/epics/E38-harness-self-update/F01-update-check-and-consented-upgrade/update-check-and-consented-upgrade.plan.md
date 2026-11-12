# init.sh update check + consented upgrade — Technical Plan

> Translates the .spec.md intent into design. Every table row cites the `R-id`(s) it
> serves or the `ADR-NNNN` that defers it (ADR-0009). Start high-level; don't
> over-specify internals that might be wrong.

## Stack & dependencies
- Language/framework: POSIX `sh` for the new tool (same ethos as `harness-install.sh`;
  must run under `dash`), bash for the `init.sh` hook (that file already is bash). `git`
  is the only runtime dependency, and it is already a hard harness prerequisite.
- New dependencies: **none**. No `timeout(1)` (absent on macOS), no `gh`, no `jq`, no
  `diffstat`. The `ls-remote` bound is a background process polled with `sleep` and killed on
  expiry (the house pattern; the Builder chooses the exact shape). Line counts come from
  `diff` output.
- Tests: one new POSIX-sh suite, `tests/test_update_check.sh`, discovered by
  `tools/run-tests.sh`; python3 only for the one real-PTY cell (python3 is already required
  by the local TaskStore).

## Data model  (serves: R5, R6, R12)
No database. Three on-disk artifacts, all under `.harness/progress/` (VCS-ignored by the
`progress/*/` rule every installed `.harness/.gitignore` carries):

| Entity | Field | Type | Notes | R-id |
|---|---|---|---|---|
| `progress/update-check/last` | `checked` | epoch seconds | written on every attempt, success or failure (R3 caches failure) | R5, R3 |
| `progress/update-check/last` | `latest` | `vX.Y.Z` or empty | empty = last attempt failed / no parseable tag | R5, R4 |
| `progress/update-check/last` | `declined` | `vX.Y.Z` or absent | set when the human answers anything but `y` at R6 **or** at the R11 preview; compared by equality | R6 |
| `progress/update-check/repo/` | — | git checkout | the fetched tag; reused across runs (fetch is idempotent) | R7 |
| `progress/upgrade-backup/<old>/` | `<relative body path>` | file copy | one per R11-listed file, same path as under `.harness/` | R12 |
| `progress/upgrade-backup/<old>/preservation/<label>/` | `harness.config.yaml`, `CLAUDE.md`, `AGENTS.md` | file copy | `<label>` = `root` for the target, else the manifest repo key | R8, R9, R12 |
| `harness.config.yaml` | `update.check` | `true`/`false` | shipped `true`; `false` ⇒ silent skip | R2 |
| `harness.config.yaml` | `update.remote` | string | shipped `""` ⇒ default URL; a fork sets its own | R1 |

Record format: one `key=value` per line (`grep`/`sed` readable, like `.harness/.agents`).

## API / interface  (serves: R1, R2, R3, R6, R7, R11)
The tool is a CLI; its contract is subcommands, env inputs and exit codes.

| Method | Path | Request | Response | R-id |
|---|---|---|---|---|
| `sh tools/harness-update.sh check` | run by `init.sh` as a subprocess, cwd `HARNESS_DIR` | env: `HARNESS_DIR` (set by init.sh), `HARNESS_UPDATE_CHILD=1` when `umbrella.root` is non-empty, `HARNESS_UPDATE_UMBRELLA_DIR=<dir>` and `HARNESS_UPDATE_UMBRELLA_MANIFEST=<abs manifest file>` when the manifest resolves, optional `HARNESS_UPDATE_REMOTE`, `HARNESS_UPDATE_TTL`, `HARNESS_UPDATE_TIMEOUT`, `HARNESS_UPDATE_ASSUME_TTY`, `HARNESS_SKIP_UPDATE_CHECK` | stdout: 0 or 1 notice line, plus the prompt when interactive; exit `0` = continue the gate, `10` = consent given (init.sh execs `upgrade`); never any other code | R1, R2, R3, R4, R5, R6 |
| `exec sh tools/harness-update.sh upgrade` | exec'd by `init.sh` on exit 10 only | same env; stdin inherited (the human's terminal, or the test's pipe) | preview → `Proceed with the upgrade? [y/N]` → backups → installer → preservation proof → report. Exit `3` upgraded (re-run required), `2` declined at preview (no writes), `4` preservation violated (originals in the backup dir), `5` fetch/installer failure | R7, R8, R9, R10, R11, R12 |
| `init.sh` hook | section after 2b (umbrella detection), before 2c | no new flags | `[ -f .harness-version ] && [ -z "$HARNESS_SKIP_UPDATE_CHECK" ]` ⇒ run `check`; rc 10 ⇒ `exec` upgrade; any other rc ⇒ continue (`|| true` discipline: the hook can never fail the gate) | R1, R2, R6, R7 |
| `<fetched>/harness-install.sh <project-root>` | invoked by `upgrade`, stdin `</dev/null`, no `--agents`/`--builder-backend`/`--pr-loop` | — | the installer's own non-interactive upgrade path: recorded selection/backend/pr_loop kept, `migrate_config` appends, pointer block replaced | R7 |
| `<fetched>/harness-install.sh --umbrella <umbrella-dir>` | same, when `HARNESS_UPDATE_UMBRELLA_DIR` (the manifest file's parent, resolved from `UMBRELLA_MANIFEST` relative to `HARNESS_DIR`) is set | — | the cascade; exit `3` = unlanded = success here | R10 |
| `sed -n "s/^HARNESS_BODY_PROSE='\(.*\)'$/\1/p"` (and `_LOCAL`) over `<fetched>/harness-install.sh` | run by `upgrade` | the body paths that installer will copy = the R11 file set (the same extraction `tests/lib/umbrella/migration.sh` already uses); empty ⇒ fixed fallback list + a preview line saying so | R11 |

Interactivity is decided **inside the tool** (`[ -t 0 ] && [ -t 1 ]`, or the hook env), so
`check` run as a subprocess with inherited fds sees the same terminals `init.sh` does.

## Decision table of `check`  (serves: R1–R6, R10)
The Builder implements exactly this; `tests.md` pins every cell.

| layout | opt-out | cache | remote | tags vs installed | tty | contacts remote? | prints | prompts | rc |
|---|---|---|---|---|---|---|---|---|---|
| source (no stamp) | – | – | – | – | any | no | nothing | no | gate unchanged |
| child (`umbrella.root`) | – | – | – | – | any | no | nothing | no | gate unchanged |
| installed | env or config | – | – | – | any | no | nothing | no | gate unchanged |
| installed | none | fresh, `latest` newer | – | – | no | no | notice | no | gate unchanged |
| installed | none | fresh, `latest` newer, `declined`=latest | – | – | yes | no | notice | no | gate unchanged |
| installed | none | fresh, `latest` same/empty | – | – | any | no | nothing | no | gate unchanged |
| installed | none | stale/absent | fails | – | any | once | nothing | no | gate unchanged (cache rewritten) |
| installed | none | stale/absent | hangs > timeout | – | any | once, killed | nothing | no | gate unchanged, within bound |
| installed | none | stale/absent | ok | none parseable / older / same | any | once | nothing | no | gate unchanged |
| installed | none | stale/absent | ok | newer | no | once | notice | no | gate unchanged |
| installed | none | stale/absent | ok | newer | yes, answer ≠ y | once | notice | yes | gate unchanged, `declined` recorded |
| installed | none | stale/absent | ok | newer | yes, answer y | once | notice | yes | `check` rc 10 → `upgrade` |
| coordinator (manifest) | none | any | ok | newer | yes, y | once | notice | yes | `upgrade --umbrella` path |

## Files to change  (serves: R1–R12)
| File | Change | R-id |
|---|---|---|
| `tools/harness-update.sh` | create — POSIX sh, `#!/bin/sh`, mode 0755; functions only, last line `main "$@"` (self-replacement safety); subcommands `check` and `upgrade`; config readers for `update.check` / `update.remote` scoped to the top-level `update:` block; version parse/compare; bounded `ls-remote`; cache read/write; fetch; conflict set via the fetched installer's `HARNESS_BODY_PROSE`/`HARNESS_BODY_LOCAL` + `git -C repo show v<old>:<path>`; preview; backups; installer invocation; preservation proof; report | R1, R2, R3, R4, R5, R6, R7, R8, R9, R10, R11, R12 |
| `init.sh` | modify — new section "2b2. Update check (E38-F01)" after the umbrella-manifest block: stamp + opt-out guard, pass `HARNESS_UPDATE_CHILD` / `HARNESS_UPDATE_UMBRELLA_DIR` from the already-parsed `UMBRELLA_ROOT` / `UMBRELLA_MANIFEST` (one parser, no second awk), run `check`, `exec` `upgrade` on rc 10, otherwise continue; a comment block in the house style explaining why opt-out is silent and why `exec` | R1, R2, R6, R7 |
| `harness.config.yaml` | modify — append the shipped `update:` block (`check: true`, `remote: ""`) with its comment, after `change_size:` | R1, R2 |
| `harness-install.sh` | modify — `migrate_config()` gains one append-only entry for the `update:` block (header + both keys at EOF when the top-level `update:` header is absent; section-scoped presence check, like `_cfg_has_umbrella_manifest`) | R2 |
| `tools/run-tests.sh` | modify — `export HARNESS_SKIP_UPDATE_CHECK=1` beside the `HARNESS_RUN_TESTS_NESTED` export, with a comment: every suite that runs an installed `init.sh` stays off the network; the update suite re-enables per call | R2 |
| `tests/test_update_check.sh` | create — the behavioral suite (see tests.md): fake remote fixture, installed-target fixture, git shim for the hang cell, PTY cell, umbrella fixture | R1, R2, R3, R4, R5, R6, R7, R8, R9, R10, R11, R12 |
| `tests/test_install.sh` | modify — add `tools/harness-update.sh` to `test_source_scripts_are_executable()`'s `_sse_expected` set; assert the installed copy `.harness/tools/harness-update.sh` exists, is executable and `cmp`-identical to source (same shape as the `pr-gate.sh` / `run-tests.sh` assertions); assert the shipped config and an upgraded (migrated) config both carry `update.check` and `update.remote` with existing values untouched | R7, R2 |
| `docs/INSTALL.md` | modify — under `## Upgrade`, new `### Staying current — the update check (E38-F01)`: the notice, when it prompts, the opt-outs, the remote key for forks, the cache/TTL, what is previewed/backed up/proved, the exit codes, and that the result must still be committed (links to the drift-guard subsection) | R1, R6, R11, R12 |
| `README.md` | modify — one sentence beside the existing `./init.sh` gate mention: `init.sh` tells you when a newer harness ships and, at a terminal, offers to install it | R1 |
| `CHANGELOG.md` | modify — `## [0.109.0]` entry "Added — init.sh update check + consented upgrade (E38-F01)" (MINOR: the installed body gains a capability) | R1 |
| `VERSION` | modify — bump MINOR (`0.108.0` → `0.109.0`); tests never freeze the literal | R1 |

## Deferred  (ADR-0009 — bolt-ons the stage excludes)
> Stage: production — read from `specs/product.md` frontmatter.

Deferred: none — stage is production

## DO NOT TOUCH
- `harness-install.sh` beyond the one `migrate_config()` entry — no new flag, no update
  logic inside the installer (the brief's "reuse, don't reimplement" constraint; a flag would
  also widen `tests/test_install.sh`'s wiring surface for nothing).
- `tools/harness-owned-paths.sh` — untouched; the preview's file set comes from the fetched
  installer's own body lists, and the drift guard keeps its own definition.
- `init.sh` sections 1b (drift guard), 2a2/2b (umbrella detection) — read their variables,
  do not change their logic or output.
- `tests/test_init_drift_guard.sh`, `tests/test_cascade.sh`, `tests/lib/umbrella/*` —
  reuse their fixture shapes by copying the few helper lines into the new suite; do not edit
  them (the runner's exported opt-out keeps them hermetic without edits).
- `.claude/agents/*`, `.claude/commands/*` — generated; nothing here changes an emitter.
- `state/tasks.json`, `specs/epics/**` of other features, `progress/inbox/E38-F01.md`.

## Approach notes
**Sequencing (walking skeleton first).** R1 is the end-to-end slice: fake remote → `check`
→ notice line from an installed `init.sh`. Build the fake-remote fixture with the first test
and reuse it everywhere: copy the source tree (as `tests/test_self_drift.sh`'s `fixture()`
does), `git init`, commit, tag `v$CUR` (where `CUR=$(cat VERSION)`); then write
`VERSION=$NEXT` (NEXT derived from CUR by bumping MINOR — never a literal) plus one marker
line in `agents/scout.md`, commit, tag `v$NEXT`; serve it as `file://<path>` (a `--depth`
fetch over a plain local path is ignored with a warning; `file://` is what tests pass). An
`OLDER`-only remote tags `v0.0.1`; the "none parseable" remote tags `nightly`, `v1.2`,
`v9.9.9-rc1`. Positive controls everywhere an absence is asserted (the drift-guard suite's
anti-tautology rule): a silent cell is paired with the same fixture made loud by one change.

**Version compare.** Split on `.`, compare three integers; strip an optional leading `v`
from both sides. `.harness-version` is written by the installer as bare `X.Y.Z`.

**Bounded ls-remote.** Run `git ls-remote --tags "$remote"` with output to a temp file in
the background, poll `kill -0` at 1 s (or finer) steps up to the timeout, `kill` on expiry,
treat a killed or non-zero run as failure. Set `GIT_TERMINAL_PROMPT=0` so a private or typo'd
remote can never block on a credential prompt — that is the one way an "interactive" tool
could hang the gate. For ssh remotes, set `GIT_SSH_COMMAND` to the ssh command git itself would
pick (`$GIT_SSH_COMMAND`, else `core.sshCommand`, else the quoted `$GIT_SSH` program path, else
`ssh`) with `-o BatchMode=yes` appended — never a bare `ssh`, which would override the user's
custom command or key (tests.md C3b precedence table).

**Cache semantics.** Read the record first; if `checked` is within TTL, use `latest`
(possibly empty ⇒ silent) and `declined`. Otherwise attempt, then rewrite `checked` and
`latest` (preserve `declined` only when it still equals the new `latest`). Tests force a
stale cache with `HARNESS_UPDATE_TTL=0` and a fresh one by pre-writing the record.

**Consent flow.** `check` prints the notice; when interactive and not declined, prints the
prompt, reads one line with `read -r`, returns 10 on `y`/`Y`, else records `declined` and
returns 0. `init.sh`: `rc=0; sh "$HARNESS_DIR/tools/harness-update.sh" check || rc=$?;
[ "$rc" = 10 ] && exec sh "$HARNESS_DIR/tools/harness-update.sh" upgrade`. `check` must
never return another non-zero code (wrap internals so a bug degrades to silence, matching
the drift guard's fail-safe direction).

**Upgrade flow (order is load-bearing).** 1 fetch the tag into `progress/update-check/repo`
(`git clone --no-checkout` once, then `git fetch --tags` + `git checkout -q v<new>`; ensure
`v<old>` is fetched too when it exists). 2 build the in-scope repo list: `root` plus, when
`HARNESS_UPDATE_UMBRELLA_DIR` is set, each `path:` under `repos:` in the manifest (the same
minimal YAML read `init.sh` 2b performs — this is a read in the tool, bounded to `repos:` →
`<key>:` → `path:`) that has `.harness/harness.config.yaml`. 3 compute the conflict set
for the target only: read `HARNESS_BODY_PROSE` + `HARNESS_BODY_LOCAL` from the fetched
installer (fallback list if empty); for each entry that is a directory, `find` its regular
files under `.harness/`, for a file entry take it directly; for each `<rel>`,
`git -C repo cat-file -e v<old>:<rel>` then `cmp` against `git show`; absent ⇒ "locally
added". Nothing outside those entries is ever listed (so `.harness-version`, `.agents`,
`manifest.txt`, `harness.config.yaml`, `progress/`, `state/` are out by construction).
4 print the preview — remote URL, `v<old> → v<new>`, the file lines, the R8/R9 sentence —
and ask. Every git call that takes the remote passes it after `--`; a remote starting with
`-` makes `check` silent and `upgrade` exit 5 with a message. 5 on
`y`: create the backup dir (choose a fresh name if it exists), copy listed files and the
preservation snapshots. 6 run the installer with stdin `</dev/null`, stdout/stderr passed
through, env `CODEX_HOME`/`HOME` untouched. 7 accept exit 0 (single) or 0/3 (umbrella); any
other exit ⇒ report + exit 5. 8 preservation proof: config lines as an ordered subsequence
(an `awk` two-pointer walk is enough; blank lines included), entrypoint bytes outside the
block via `sed -n` ranges or `awk` split at the two markers + `cmp`. 9 report; exit 3.

**Why the subsequence rule.** `migrate_config` only appends or inserts lines; the three
value writers (`set_builder_backend`, `set_pr_loop_enabled`, `set_umbrella_root`) rewrite a
single value token and are skipped when the value already matches — which is always the case
on this path. So "every old line still present, in order" is both the strongest check the
existing contract supports and exactly the promise the brief makes.

**Self-replacement.** The tool is overwritten by step 6 while it runs. Two layers: `init.sh`
has already `exec`'d (no gate process remains), and the tool's body is functions + a final
`main "$@"`, so the interpreter has read the whole file before `main` starts. The installer's
`rm_owned_tree` + `cp -R` also replaces the inode rather than writing in place, which the
Builder may note in a comment but must not rely on.

**Output discipline.** All update lines go to stdout except errors (stderr). Exactly one
`🔔` line per gate run, ever. The tool prints nothing on any R2/R3/R4 path, so suites that
snapshot gate output keep passing even when run outside the runner with a reachable remote
(only a genuinely newer upstream tag would add one line).

**Umbrella fixture.** Reuse the shape of `tests/lib/umbrella/audit.sh`'s `mk_umb` +
`cascade` + `land` (copy the dozen lines; do not source the lib, it owns its own `T`). Give
one child an explicit override (`test_command: "pytest -q"`) and a `models:` tier that
differs from the coordinator's; convert one child with `--thin` so R10's "stays stubs" cell is
real. Children must be committed before the upgrade so the E24-F02 audit's only drift is the
upgrade itself (installer exit 3 is then the expected success code).

**Docs.** `docs/INSTALL.md` gets the operator-facing contract; the `init.sh` comment block
explains the design (silent opt-out, `exec`, bound) in the file's established voice, so the
next reader of the gate does not have to find this plan.
