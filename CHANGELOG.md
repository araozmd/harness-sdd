# Changelog

All notable changes to the harness body are recorded here. Versions follow
[SemVer](https://semver.org/) and are stamped into every install's
`.harness/.harness-version` (see `CLAUDE.md` → Versioning).

## [0.52.0] — 2026-08-03

### Added — ✨ the cascade audits whether the upgrade was landed (E24-F02)

`harness-install.sh --umbrella` printed `✅ umbrella cascade complete` after it had *written*
files, with no opinion about whether any of it was committed. The `~/repos/viernes` cascade
produced exactly that green finish and five children each carrying 26–29 uncommitted files.

E24-F01 made the consumer notice; this closes the producing side, so the guard is a backstop
rather than the normal way anyone finds out. One operator upgrading N repos in one command is
precisely where N-way manual follow-up gets skipped.

The cascade now ends with a per-target audit and exits **3** when anything is unlanded —
deliberately not the generic failure code `1`, because "the install broke" and "the install
succeeded and is unlanded" are different outcomes and conflating them loses the only
information that makes the code actionable. A target that is not a git work tree is reported
and never counted. `--dry-run` skips the audit, as it writes nothing.

**It reports; it never commits.** Committing into N repos the operator did not ask you to
commit into is a far larger claim on their working tree, and the constraints it would have to
honour — never stage unrelated work, never touch a foreign branch — are the accidents this
epic exists to prevent. The brief left the commit path open and asked for the smaller change
that fully fixes the problem; report-and-exit does, because the defect was being *told* the
upgrade was complete when it was not.

### Changed — ♻️ one definition of "what the harness owns"

The path set the drift guard checks moved out of `init.sh` into **`tools/harness-owned-paths.sh`**,
which both `init.sh` and the new audit call. E99-F10 needed four corrections to that set in a
single week — `.codex`/`.gemini` claimed wholesale, symlinked ledgers, non-regular ledger
entries, wildcard basenames — and every one was a false positive that failed the *mandatory*
gate on a file the operator owns. A second inline copy in the installer would have had to
relearn all four.

The logic is **moved, not rewritten**: the 27 existing drift-guard assertions pass unchanged,
which is the extraction's regression contract. On top of that, R8 is *differential* — it
perturbs a project-owned path, a body path, root glue, and a user file in the `.agents/` tree,
and requires `init.sh` and the audit to agree on all four **and** to be right. Asserting that
both files merely reference the helper would prove nothing about agreement.

`init.sh` degrades to a warning if the helper is absent (a torn install must not halt the
harness every session), consistent with every other ambiguous case in that guard.

## [0.51.2] — 2026-08-02

### Fixed — 🐛 a fresh seed no longer inherits the harness's own `blocking_severities` (E99)

`harness.config.yaml` is seeded into a target by **copying** the harness repo's own file, so
any `pr_loop` value this repo sets for itself silently became every target's default. That
was already handled for `enabled` — a target may not have the Codex GitHub App — and is now
handled the same way for `blocking_severities`.

This repo raises its own threshold to **`P0,P1,P2`**. Across E24-F01 (PR #98) and E99-F10
(PR #100) — seven review rounds — every real defect arrived tagged **P2**, and none arrived
as P0/P1 after the first round. Six of them let the drift guard claim a path the installer
does not own, failing the *mandatory* `init.sh` gate on an operator's own file; one made the
guard print `installed harness matches the commit` over an edited body. The gate said
`merge` on nine findings that had to be fixed anyway, so the configuration and the actual
review behaviour disagreed almost every round.

That is a calibration mismatch, not a judgement call: Codex severities are tuned for
application code, where a wrong output is one bad response. In a **gate**, a wrong output is
the gate vouching for something it never checked. But the reasoning is a property of what
this repo builds — for an ordinary product repo, blocking on P2 spends rounds on findings
that never blocked anything, which is the cost E21 exists to control. So the raise is local
and the shipped default stays `P0,P1`. `nit` remains non-blocking everywhere.

The seed also drops the run of comment lines explaining a value it overwrites, so a target
never reads a rationale sitting above a value that contradicts it. Comments on keys the seed
keeps — including a target's own hand-written ones — survive untouched.

The `/sdd-pr-loop` runbook now **reads** the key instead of asserting `P2`/`nit` never block.
That was the one blocking finding on this change's own review, and it was the sharpest defect
it could have shipped: classification is performed by the agent following that prose, so a
raised config plus a runbook saying P2 is excluded means P2s never reach `blocking.json`, the
gate reads the empty set as "reviewed, nothing blocking", and auto-merge proceeds over
findings the repo just declared blocking — the threshold would have looked raised and behaved
unchanged. Both maintained copies (the canonical body and the checked-in source-layout copy)
were updated; the historical passages about PR #86/#89 stay as written, being accurate
past-tense facts rather than instructions.

Pinned by `test_pr_loop.sh` R15b, which asserts the **source** genuinely carries the raised
value before checking the seeded one, and R49b, which asserts both runbook copies read the key
rather than hardcoding the answer. Without that precondition the assertion would pass
just as well against a source that was never raised, proving nothing about the forcing.

## [0.51.1] — 2026-08-02

### Fixed — 🐛 the drift guard over-claimed shared namespaces and lost its diagnostic on a large drift (E99-F10)

Three follow-ups against the E24-F01 guard, filed from PR #98 round 3 rather than fixed in
a fourth review round.

**`.codex/agents/` and `.gemini/agents/` are shared with the operator.** The installer says
so explicitly — "Codex's project-local role namespace is shared with the operator" — and
preserves foreign or edited role files. The guard claimed both directories wholesale, so a
project's own `.codex/agents/project-role.toml` failed the **mandatory** gate and halted
every agent step. That is the same false-positive class the `.agents/` narrowing fixed one
round earlier, in the two directories that narrowing did not reach.

They are now claimed **per file**, resolved from the installer's own ownership ledger at
`.harness/.model-agents/<tool>/` — a byte copy of each per-role file it last wrote. That
listing *is* the owned set, so `init.sh` needs no duplicated `MODEL_ROLES` list and stays
correct when that list changes. No ledger ⇒ nothing claimed for that tool, which is the
fail-safe direction: a missed drift costs a warning, a false positive costs the harness.

**A drift larger than the pipe buffer printed no diagnostic at all.** `printf | head -n 10`
early-closes the pipe; the upstream `printf` takes SIGPIPE and exits 141, and under
`set -o pipefail` + `set -e` that aborted the gate *before* the elision count, the recovery
command, and the `fail()` message. Measured on macOS: ~70KB of porcelain output does not
trip it, ~176KB does. `sed -n '1,10p'` reads to EOF, so nothing early-closes.

**The recovery command could not be pasted from a path containing whitespace.** `$PROJECT_ROOT`
was interpolated unquoted, so git received only its first word as `-C` and exited 128 — on
the one line whose entire purpose is to be copied. Now single-quoted, with embedded quotes
escaped.

Review round 1 added a fourth: a **symlinked ownership ledger** is not a ledger. `-d` and
the glob both follow symlinks, so a symlinked `.model-agents/<tool>` enumerated an external
directory and turned arbitrary basenames there into owned pathspecs — failing the mandatory
gate on an operator role file no stamp claims, which is the very class this fix exists to
close. The guard now mirrors the installer's own three-level refusal
(`harness-install.sh:2606-2618`) rather than trusting a ledger the installer itself would
not write to.

Round 2 added the general form of the same rule: a ledger entry must be a **regular file**.
`-e` accepted a directory named `project-role.toml`, promoted its basename to an owned
pathspec, and failed the gate on the operator's role file of that name. The installer writes
byte copies and nothing else, so `-f` rejects directory, fifo, socket and device in one test
rather than adding another special case.

Round 3 closed the remaining shape — not *which* ledger entries count, but how their names
are **interpolated**. A basename is data: `:(literal)` stops a stamp named `project-*.toml`
being read as an fnmatch wildcard that claims the operator's `project-role.toml`, and one
shared shell-quoting helper now escapes the root and every pathspec alike, so a stamp named
`operator's-role.toml` no longer produces a `list them` command that cannot parse.

Pinned by seven cases in `tests/test_init_drift_guard.sh` (18 → 27 assertions), each
asserting its own fixture preconditions. That discipline earned its keep here: the first
draft of the SIGPIPE case used 1,200 files (~70KB), stayed under the pipe buffer, and
**survived** the mutation that restores `head -n 10` — it was asserting nothing. It now
measures the porcelain output and fails if the fixture ever drops below the threshold.

## [0.51.0] — 2026-08-02

### Added — ✨ `init.sh` refuses to run on an unlanded harness (E24-F01)

`harness-install.sh` stamps `VERSION` into `.harness/.harness-version`
(`harness-install.sh:2194`), but exactly one caller ever read it: the *next* installer run,
deciding upgrade-vs-fresh (`harness-install.sh:1794`). At runtime the stamp was dead
metadata — `init.sh` referenced neither it, nor `VERSION`, nor whether the installed body
was committed. An upgrade that was written but never landed was therefore
indistinguishable from one that was landed.

That gap is not theoretical. A v0.50.x umbrella cascade across five children left 26–29
uncommitted files in each. Nothing failed, for days: every Builder and Reviewer spawned
there read agent prompts no commit describes, and three children ran the change-size
classifier against a committed `harness.config.yaml` with no `change_size` block while
`migrate_config()` had already appended that block to the working tree.

`init.sh` now checks, between its structural checks and its TaskStore validation, that the
harness-owned paths match what the branch records. Drift fails the gate with the count, a
capped sample of the paths, and the command that lists the rest.

**One check, not two.** `.harness-version` is itself a tracked file inside the harness-owned
tree and every upgrade rewrites it, so a half-applied upgrade surfaces through the same
dirty-tree check that catches the prompts. No second signal exists at runtime: `init.sh` has
no access to the harness *source* it was installed from, so installed-vs-latest is not a
comparison it can make.

**Scope is ownership, not diff size.** The checked set is `.harness/` minus the PROJECT-OWNED
paths (`harness.config.yaml`, `init.project.sh`, `specs/product.md`, `specs/epics/`, `state/`,
`progress/`), plus the generated front-end glue at the project root (`.claude/agents/`,
`.claude/commands/`, `.agents/`, `.codex/agents/`, `.gemini/agents/`, `opencode.json`). It is
deliberately *not* an enumeration of the ~29 owned files, which would duplicate the
installer's knowledge in a second place and drift from it.

**False positives are the dominant risk** — this gate runs before every agent step, so a
misfire halts the harness and gets the guard disabled. Every ambiguous case degrades to a
silent skip or a warning, never a failure: no install stamp, no git work tree, or a body that
is not version-controlled at all. `HARNESS_SKIP_DRIFT_CHECK=1` overrides it per invocation
(an env var, not a config key — a config key gets set once during a bad afternoon and
disables the guard forever), and the skip prints a line rather than staying silent.

The guard reports; it never repairs. No auto-commit, no auto-reinstall, no writes of any kind.
Landing the upgrade is the producing side's job — E24-F02.

Round-1 review hardening (PR #98): the suite now **executes** `.harness/init.sh` rather than
`sh`-ing it — `init.sh` is bash (`set -euo pipefail`, a bash array), so on any system whose
`/bin/sh` is dash it died at line 8 before the guard ran, making the verification command
unconditionally red in CI while passing on macOS where `/bin/sh` is bash in POSIX mode.
`run_gate()` now asserts the harness banner appears, so an interpreter-level death can never
again be read as a gate verdict. `git status` is called with **`-uall`**: an upgrade that
*adds* a body file leaves it untracked, and `status.showUntrackedFiles=no` in any repo or
global gitconfig made the guard print "matches the commit" over exactly that drift. And the
"list them" recovery command is now derived from the pathspec array instead of a
hand-written approximation that had already drifted from it — it omitted `.codex/agents/`,
`.gemini/agents/` and `opencode.json` and dropped every `:(exclude)`.

Round-2 review hardening (PR #98) closed three more holes, all in the checked path set.
`.agents/` is a **user-owned** tree in which the installer owns only `rules/*`, `agents/*`,
`workflows/*` and the `sdd-*` skill units, so the blanket pathspec would have failed the
mandatory gate on a project's own `.agents/skills/mine/SKILL.md` — the false positive this
feature named as its dominant risk. The generated OpenCode glue (`.opencode/command/*`,
`.opencode/agent/pr-fixer.md`) was outside every pathspec, so an opencode target reported
clean over edited harness glue. And the R9 probe now asks about the installed **body**
alone: a repo that gitignores `.harness/` while tracking the root glue had a non-zero
combined count, skipped the warn-only branch, and then — git being unable to report the
ignored body either — printed `✅ installed harness matches the commit` over an edited
`.harness/agents/builder.md`. A false clean is the worst output this feature can emit.

Pinned by `tests/test_init_drift_guard.sh`, a behavioral suite that installs real targets and
reads the gate's exit code. Four of its requirements assert an absence or a pass, so each is
paired with a positive control on the same fixture where only the discriminating fact differs
— an expected value with more than one producing code path proves nothing. R9 in particular
pins the `ls-files`-before-`status` ordering: `git status --porcelain -- .harness/` reports
`?? .harness/` when nothing is tracked, so a status-first implementation would read an
un-version-controlled install as drift and hard-fail it.

## [0.50.2] — 2026-08-02

### Fixed — 🐛 change-size charged the harness body and agent surfaces to the product budget (E99-F71/F89)

`tools/change-size.sh` counts the working tree INCLUDING untracked files, deliberately: the
in-session Builder has no commit step, so a `<merge-base>...HEAD` diff would report tier `ok`
with zero production lines on precisely the branch the check exists to measure (pinned by
`test_change_size.sh` R5b). That inclusion also charged installer output to whatever branch
was under review, and the tier went wrong in both directions:

- four `.mutbak` backups in the tree → `production 1104 lines / 2 files` against a true
  `42 / 1`, a **26x overstatement**. Since mutation campaigns became routine, `.mutbak` files
  are now the EXPECTED state during review, so this misfired more often over time, not less;
- a consumer's 78 untracked install artifacts (2154 lines) → `ESCALATE 3965 / 87` for a branch
  that measured `ADVISE 1811 / 9`. Both PRs had their tier re-derived by hand.

The reported root cause prescribed measuring `<base>..HEAD` instead of the working tree. That
was **rejected**: it reintroduces the defect R5b prevents, trading a 26x overstatement for a
100% understatement on a check whose whole purpose is to fire before the Builder commits. The
rejection is now recorded in the script so it is not attempted a third time.

The fix is classification, not concealment. The harness body and the agent surfaces this
installer writes — `.harness/`, `.claude/{agents,commands}/`, `.agents/`, `.codex/`,
`.opencode/` — are installer OUTPUT in every consumer, so they join the built-in `generated`
classifier and are excluded from the budget entirely. They stay **tracked**: the documented
install workflow is committed-and-shared, and ignoring them would leave every Codex skill,
Antigravity rule and OpenCode command out of a fresh clone, making `.claude/` first-class and
every other front end second-class. Scoped deliberately — `.claude/agents/` and
`.claude/commands/` only, never `.claude/` wholesale, and no root file: `CLAUDE.md` is
hand-authored per repo and still counts as production.

Only genuinely machine-local artifacts are ignored, because no clone should receive them:
`*.mutbak` (per-developer review scratch) at the project root, and `__pycache__/` + `*.pyc`
under `.harness/` — the latter already ignored by the harness source's own root `.gitignore`,
just never propagated to consumers.

Pinned by `test_change_size.sh` R5d (gitignored scratch never moves the count, while untracked
real work still does — witness: 42 lines vs 2442 with `--exclude-standard` dropped) and R5e
(generated surfaces stay tracked and classified out — witness: 80 lines vs 1980 without the
classifier), plus `test_install.sh` assertions that the agent surfaces are NOT ignored.

## [0.50.1] — 2026-08-02

### Fixed — 🐛 the `pin.` comment over-claimed what an unpinned tier does on Codex (E23 follow-up)

E23-F01 made role registration independent of model routing: selecting Codex now always
writes all six `.codex/agents/*.toml`, and `gen_codex_agent` simply omits the `model` key
when the role inherits or its tier is unpinned. The guidance around `models.pin.` was
written before that and still said an unpinned tier "stamps nothing" — which now reads as
"you get no role definition at all" rather than the truth, "you get the role definition
without a `model` key". Semantics are unchanged; only the wording was wrong.

Corrected in all four places the claim appeared, so they cannot drift apart:

- `harness.config.yaml` and the matching migration heredoc in `harness-install.sh` — these
  two are required to stay **byte-identical** (a fresh install copies the config verbatim,
  an upgrade only migrates), so fixing one without the other would have split them.
- The `model_alias` comment in `harness-install.sh`, which describes the absent Codex /
  OpenCode alias entries.
- `docs/INSTALL.md` → "Pinning an exact model", now cross-referencing "Where the values
  land", which already described the post-E23 behavior correctly.

### Changed — 📝 board bookkeeping

- `specs/epics/E17-model-routing/epic.md` listed `E17-F01` as `pending` in its feature
  table while `state/tasks.json` had it `done`. The feature table now matches the board.

No behavior change: comments and documentation only. Surfaced by the E23 drift check.

## [0.50.0] — 2026-08-01

### Fixed — 🐛 the pr-loop chased findings it was configured to ignore (E99)

Measured on this repo's telemetry and `.pr-loop/` cache: **20 of 43 Codex-fix commits
addressed P2s**, a severity `pr_loop.blocking_severities` (default `P0,P1`) explicitly
excludes. PR #89 reported **zero blocking findings in all three rounds** and still spent
three rounds and three P2 commits; PR #86 was clean at rounds 6, 7 and 8 with CI green and
ran on to **round 12** against `max_rounds: 4`.

The classification was never wrong — `blocking.json` was correctly empty every time. What
was missing is that the ACTION was left to the driving agent's prose reading of the runbook,
and prose is something an agent can talk itself out of when a reviewer bot keeps posting.

- **New `tools/pr-gate.sh`** — reads the round cache the loop already wrote and prints one
  binding verdict: `merge` (0), `fix` (6), `escalate` (7), `needs-human` (8), usage/unreadable
  (4). Zero blocking findings ⇒ `merge`, at any round. It **fails closed**: a missing, empty
  or non-array `blocking.json` is never a `merge`. Scope is deliberately narrow — a `merge`
  verdict says "the review converged", NOT "this PR may merge"; the CI-green check and
  `tools/pr-stack-guard.sh` remain separate gates.
- **An empty `blocking.json` is not by itself evidence of a clean review.** A round where
  the watcher timed out has an empty blocking set for the opposite reason — no review landed.
  The first version of the gate answered `merge` there. Caught on this change's own PR #90,
  where Codex replied **54s inside the 900s ceiling** and the 60s-interval watcher missed it.
  The gate now re-derives the round's review state via `wait-for-codex.sh evaluate` before it
  reads `blocking.json` at all, and reports `unresolved` (exit 9) when no review has landed.
  The verification is deliberately independent rather than a caller-supplied flag: the point
  of the gate is not to take the loop's word for it.
- **The gate asks the budget question first and probes the review only to justify a merge**
  (Codex P1 x3 on PR #90 round 2). Three ordering defects in the first cut: a *clean* review
  legitimately has no `blocking.json` — the runbook skips classification on watcher exit 3 —
  so demanding the file sent every banner/reaction clean review to `needs-human`; probing the
  review state on a *blocking* round returned `unresolved` for every ordinary round, because
  step 6 re-fetches `pr.json` after a fixer pushes and the cached head moves past the head the
  findings were filed against; and the runbook branched on the round budget **before** calling
  the gate, so a clean round at the cap could never merge. Now: blocking findings ⇒ pure budget
  decision with no probe; empty/absent blocking set ⇒ prove a review landed. Inline findings
  with no `blocking.json` fail closed — unclassified severities prove nothing.
- **The gate is asked exactly ONCE per round** (Codex P1, PR #90 round 3). Consolidating the
  verdict into step 5 left a second call in step 6, after the fixers push. The fix commits do
  not rewrite `blocking.json`, so that second call necessarily re-read the same non-empty set,
  returned `fix`/`escalate` again, and routed the driver back through step 5 forever. Step 6
  now confirms CI and **advances** to a fresh review; `tests/test_pr_gate.sh` R8 asserts the
  call count in both maintained copies.
- **`/sdd-pr-loop` now calls the gate** and states that non-blocking findings are excluded by
  configuration, not oversight — a P2 on a PR the gate calls `merge` belongs in its own PR.
- **`max_rounds` is now a budget for the PR, not for one invocation.** The round counter
  resumed from `round=1` on every run, so re-running `/sdd-pr-loop` silently granted a fresh
  budget — how #86 reached round 12 without the round-4 `needs-human` hand-off ever firing.
  It now resumes from the highest round already in the cache. The base-change restart still
  re-derives round 1 correctly, because it moves stale rounds to `stale-<ts>/` first.
- Removed a **pre-existing duplicated sentence fragment** in the installer's `/sdd-pr-loop`
  heredoc that had been shipping to every consumer.

### Changed — ⚡ the suite runs concurrently and reports only failures (E99)

`verification.test_command` was a hand-maintained chain of **27 `&&`-joined suites** that
every feature appended to. It cost the Reviewer, every round, on two axes:

- **634s wall clock**, serially.
- **~77KB (~19k tokens) of output on a fully GREEN run** — 32KB of it `test_install.sh`
  installer warnings — all of which the Reviewer read to learn one bit.

- **New `tools/run-tests.sh`** — discovers `tests/test_*.sh` and runs them concurrently
  (`--jobs`, default 8; `--serial` to bisect). On green it prints **one line**; on red it
  fails, names each failing suite and surfaces its output **in full**. Measured here:
  **634s → 171s, all 27 suites still passing.**
- `verification.test_command` is now `sh tools/run-tests.sh`. Because it DISCOVERS suites,
  adding a `tests/test_*.sh` no longer means hand-editing the scalar.
- The suites were already mutually isolated (per-case `mktemp` fixtures, sandboxed `HOME`
  and `CODEX_HOME`, no writes into `state/`, `specs/`, `progress/`); concurrency is a claim
  about that, and a suite that passes `--serial` but fails under `--jobs` is an isolation
  bug in the suite, not a reason to pin the runner.

### Added — ✅ `tests/test_pr_gate.sh`

Twelve assertions over both tools: the verdict table, the P2-only-PR case that motivated the
work, fail-closed behaviour on unreadable input, both maintained `/sdd-pr-loop` copies
actually calling the gate, and the runner's quiet-green / loud-red contract.

## [0.49.1] — 2026-07-29

### Fixed — 🐛 change-size `--format json` escapes every C0 control character (E99-F08)

P2 deferred at the merge of PR #83 (E99-F07).

- **`_json_escape` escaped only `\`, `"` and tab** (`tools/change-size.sh`). E99-F07 moved the
  tracked path scan to `git diff --numstat -z`, which stops git C-quoting special characters —
  so a raw control byte in a tracked pathname now reaches the JSON emitter **unencoded**. A
  tracked `src/a<CR>b.js` made `--format json` **exit 0 while emitting JSON that `jq` rejects**
  with an invalid-control-character error: fail-silent on a machine interface, discovered only
  when the consuming parser dies. The escape now handles the **class** rather than adding a CR
  rule beside the tab rule: short escapes for `\b \t \n \f \r`, `\u00XX` for every other C0
  control (U+0000–U+001F), via a single awk pass keyed on an ordered control table. DEL
  (U+007F) is deliberately **not** escaped — it is not a C0 control and JSON does not require
  it. New regression coverage (R8d in `tests/test_change_size.sh`) round-trips tracked
  pathnames containing a raw CR (short-escape branch) and a raw VT (`\u00XX` branch) through
  `--format json`, with jq-free assertions so the coverage does not vanish on a jq-less host.

### Fixed — 🐛 change-size misclassifies a pathname containing a literal newline (PR #89, Codex P2)

- **The NUL-framing repair `tr '\0' '\n'` made a content LF indistinguishable from a record
  separator** (`tools/change-size.sh`). A tracked `a<LF>b.js` split mid-path and the counts
  landed on the first fragment; a `x<LF>_test.py` was charged to **production** because the
  classifier never saw the test suffix — the JSON stayed parseable and the number was wrong.
  The framing parse is now byte-exact and adds **no new dependency**: `od -An -v -tu1`
  (POSIX, 8-bit clean by design) renders the stream as decimal bytes and awk reassembles
  NUL-framed fields, folds renames onto the destination exactly as before, and encodes each
  pathname (`\` → `\\`, then LF → `\n`) for the newline-framed pipeline; the classifier awk
  decodes in a single left-to-right pass **before** matching, and the concentration list
  decodes only at emission. The concentration list's exclusion filter matches on the
  **decoded** pathname too: a configured `test_paths`/`generated_paths` regex can tell the
  encoded and decoded forms apart (`^foo\\nbar[.]js$` hits the encoded form of a real-LF
  path), so matching the transit form could drop a production file from — or add a generated
  file to — `top_production_files` while the totals said the opposite. (An earlier revision
  of this fix used python3, which `init.sh` only guarantees for the `tasks: local` backend —
  caught in review.) New regression coverage: R8e round-trips newline-bearing tracked,
  untracked, and renamed-onto pathnames through `--format json` byte-exact and asserts the
  test/production split; R8f pins both encoded-vs-decoded mismatch directions against a
  configured `generated_paths` regex. Both were mutation-verified against their defect
  shapes.

## [0.49.0] — 2026-07-29

### Added — ✨ Native Codex skills and inherited role registration (E23-F01)

- Selecting Codex now installs `$sdd-next`, `$sdd-new`, `$sdd-plan`, `$sdd-drill`,
  `$sdd-fix`, and `$sdd-fix-parallel` as repository-local
  `.agents/skills/<name>/SKILL.md` artifacts. `$sdd-pr-loop` follows the existing
  opt-in `pr_loop.enabled` gate. Every skill includes explicit-only
  `agents/openai.yaml` metadata and maps text accompanying `$skill` to `$ARGUMENTS`.
- Codex now always receives exactly six project-local `.codex/agents/*.toml` role
  definitions. Inherited and unpinned roles omit `model`; concrete Codex pins add it
  only to the roles that resolve to that pin.

### Changed — 📝 Safe retirement of global Codex prompts

- Current installs no longer create, overwrite, or advertise
  `${CODEX_HOME:-$HOME/.codex}/prompts/sdd-*.md` as an active command surface and do
  not require `HOME` or `CODEX_HOME`.
- Ungated legacy prompts are preserved because their cross-target ownership is
  unknowable. Only byte-pristine legacy `sdd-pr-loop` is reclaimed, and only when its
  readable ownership ledger proves that no live target still claims it.
- Last-written stamps make selected Codex skill/role updates and deselection
  ownership-safe. Foreign or edited files are preserved; empty named directories are
  pruned without recursively deleting the shared `.agents/` tree.

## [0.48.0] — 2026-07-29

### Added — ✨ Stacked-PR lane for reviewability (E21-F04)

- **`tools/pr-stack-guard.sh`** offline merge-order guard. Given a PR's `baseRefName` and
  the list of open PR head branches, it exits `6` when a child PR is stacked on an
  unmerged parent and `0` only when the base is the repository's actual default branch.
- **`/sdd-pr-loop`** now fetches and uses the PR's real `baseRefName` / `baseRefOid` for
  diff computation, round-cache keying, and merge-gate evaluation instead of assuming
  `main`. It enforces the parent-before-child merge order for stacked PRs and restarts
  review from round 1 when a stacked parent is rebased.
- **Documentation** in `docs/WORKFLOW.md` describes when to use the lane, how to cut wave
  boundaries, and the manual restack procedure. Stacking is explicitly scoped to
  safely-splittable features and provides incremental review, not atomic delivery.

### Changed

- `pr-stack-guard.sh` requires `--default-branch` from the caller; it no longer hard-codes
  `main`. This prevents ordinary PRs in repositories whose default branch is not `main`
  from being misclassified as stacked.

## [0.47.0] — 2026-07-29

### Added — ✨ OpenCode concurrency probe + model helper (E22-F01)

- **`/sdd-test-concurrency`** command is now installed for the OpenCode front-end. It
  spawns two trivial subagents, measures whether OpenCode executes them concurrently, and
  writes a durable marker (`.harness/.opencode-parallel`: `supported` or `sequential`).
- **`--with-opencode-parallel=true|false`** installer flag overrides the marker.
- **`tools/opencode-model-helper.sh`** lists the models OpenCode sees, maps them to the
  harness tiers (`reasoning`/`standard`/`cheap`) by name heuristic, and emits ready-to-paste
  `pin.opencode.*` YAML. Pass `--apply` to append missing pins to `harness.config.yaml`
  without overwriting existing values.

### Changed — 📝 `/sdd-fix-parallel` is opt-in for OpenCode

`/sdd-fix-parallel` requires native concurrent sub-agent delegation. On OpenCode the
installer now reads the marker written by `/sdd-test-concurrency` and stamps the command
**only** when the marker says `supported` or when `--with-opencode-parallel=true` is passed.
The command is omitted by default on a fresh OpenCode install. Use serial `/sdd-fix` if
concurrency is not available.

## [0.46.3] — 2026-07-29

### Fixed — 🐛 change-size path handling, symlinks, handoff coverage and trend caching (E99-F07)
Four non-blocking findings deferred at the merge of PR #78, all reproducible.

- **`git diff --numstat` C-quoted TRACKED paths too** (`tools/change-size.sh`). The untracked
  side moved to `ls-files -z` during that review; the tracked side still parsed plain
  `--numstat`. `core.quotePath=false` governs non-ASCII bytes only — it does **not** stop git
  C-quoting a path containing `"`, a backslash or a tab, so `src/foo".spec.js` arrived as
  `"src/foo\".spec.js"` and its trailing quote defeated the `[._-](test|spec)\.[a-z]+$` suffix
  rule. A **test** file was charged to the **production** budget and the tier was silently
  overstated. Now `--numstat -z`, which git never encodes.
- `-z` also reframes numstat records, so the parser handles the real format rather than
  assuming it: a **rename** emits an empty path field followed by two extra fields, and is now
  folded into one record keyed on the destination instead of becoming phantom records. A
  literal **tab** in a pathname is no longer hidden behind C-quoting either, so both awk passes
  rejoin fields 3..NF (bare `$3` truncated `src/a<TAB>b.spec.js` to `src/a`, losing the
  classifier suffix), and `--format json` escapes the tab — a raw control character inside a
  JSON string is invalid and the caller only finds out when `jq` dies.
- **Untracked symlinks were followed** (`tools/change-size.sh`). `[ -f ]` follows a link, so a
  link to a regular file passed the guard and the line count read the **target**. git stores a
  symlink as a blob holding its link value: exactly one line. A link to a 2,000-line file
  contributed 2,000 lines before commit and 1 after — reintroducing the commit-coupling the
  uncommitted-work measurement exists to remove. A `-h` test now precedes `[ -f ]`, which also
  brings broken links and links to directories (previously dropped to 0) in line with git.
- **The pre-PR change-size handoff only fired in parallel-fix mode** (`agents/orchestrator.md`)
  — a coverage hole in the feature as shipped, not a nit. The instruction sat inside the fenced
  *Targeted parallel-fix worker mode*, so only `/sdd-fix-parallel` E99 workers ran it; ordinary
  features on the main `in-review` flow, and umbrella child PRs, never reached it and the tier
  never reached those PR bodies. It is now stated on the **main path** as
  *### The pre-PR change-size handoff*, cited by `agents/reviewer.md` and `docs/WORKFLOW.md`,
  and applied explicitly to umbrella child PRs. The worker mode keeps its load-bearing `--repo`
  caveat: `HARNESS_DIR` locates the *script*, not the tree under measurement.
- **`--cache` paths containing whitespace** (`tools/pr-round-trend.sh`). The concentration pass
  concatenated the round files into one unquoted word list, so a cache dir under a path with a
  space in it split into several arguments, every `cat` failed, and `top_files` came back empty
  under the `|| true`. The verdict still printed "SPLIT THIS PR" while naming **no seams** —
  losing the concentration data on exactly the non-converging handoff that exists to carry it.
- Not in scope, documented inline as unsupported: a filename containing a literal **newline**.
  `-z` framing handles every other special character.

### Changed — 📝 `agents/builder.md`: two rules about assertions that pass without proving anything
Guidance added to an existing role prompt's `## Principles` — no new capability, hence `Changed`.
**Five** assertions added while fixing the above passed while the guarantee named in their own
failure message was absent; the fifth was the guard written to stop the other four. That is a
rule gap, not five accidents, so the lens now lives in the installed body:
- **An assertion is only worth its expected value being reachable one way.** Ask of every
  assertion whether the expected value could be produced by any path other than the one the
  failure message names. If it can, the test passes whether or not the guarantee holds and its
  message misleads the next maintainer — worse than no assertion, because it stops anyone looking.
  Prove the answer by reverting the fix in place; the question is not reliable as a reasoning
  exercise.
- **A test asserting a PROSE contract must grep the SECTION it names, not the whole file**, with
  a copy-pasteable `awk` extraction recipe. A whole-file grep is satisfied by any unrelated
  occurrence of the phrase elsewhere in the file — including one the same change just added,
  which is exactly how three of the five slipped through.

## [0.46.2] — 2026-07-29

### Fixed — 🐛 `fix-worktree.sh` runs under the caller's locale; `C` is scoped to the ASCII slug globs (E99-F04)
- E99-F03 exported `LC_ALL=C` for the whole of `tools/fix-worktree.sh`. Three successive Codex
  rounds on PR #65 each found that export leaking into code the **target repo** owns: the
  project init gate (P1, round 2), the `post-checkout` hook and checkout filters fired by
  `git worktree add` (round 3), and the `reference-transaction` hook fired by `git branch -d`
  during teardown and `git update-ref -d` during create's rollback (round 4, deferred here).
- Rounds 2 and 3 were patched surface-by-surface. `reference-transaction` fires on essentially
  **every** ref update, so continuing that strategy converges on un-pinning the whole script —
  and no test can prove such an allowlist complete. The default is therefore **inverted**: the
  helper now runs under the **caller's** locale, and pins `LC_ALL=C` around exactly one region,
  the bracket-range `case` globs in `validate_key`, restoring the caller's locale on every exit
  path (including `die`) before any git call or foreign code runs.
- Every other read in the file was audited per call and left un-pinned: each is either
  exit-status-only or parses output that is ASCII by construction — object ids, refnames,
  absolute paths, `worktree list --porcelain` records split on literal ASCII prefixes, and
  `status --porcelain` tested only for emptiness. None is compared with a range glob.
- The E99-F03 defect stays fixed: `validate_key` still rejects non-ASCII-lowercase slugs under
  every locale, and the three previously-closed foreign-code surfaces stay closed — now by
  construction rather than by per-call escapes, which are removed as dead code.
- Teardown/rollback **ordering** — the worktree is retired before the branch ref in both paths,
  but for two *different* reasons, now documented separately. In `do_teardown` git enforces it:
  `branch -d`/`-D` refuse to delete a branch that is checked out in a worktree. In
  `rollback_create` git does **not** enforce it — `update-ref -d` has no such guard and will
  delete the ref out from under the checkout — but deleting the ref first leaves that worktree
  on an unborn branch, so the non-forced `worktree remove` then refuses and the residual is
  "registration present, branch absent": the one state `teardown` hard-refuses, which a re-run
  cannot reconcile. The retained order's worst residual is "registration retired, branch
  preserved", which a re-run of `teardown` does reconcile. Both diagnostics now name that state
  and that recovery instead of implying nothing moved.

## [0.46.1] — 2026-07-28

### Fixed — 🐛 the `/sdd-pr-loop` first-response probe is scoped to the current round (E99-F05)
- `tools/wait-for-codex.sh` arms a first-response probe (`HARNESS_FIRST_RESPONSE`, default
  180s) whose job is to exit `5` with a named remedy when the Codex GitHub App cannot answer
  at all — instead of making the caller wait out the full 900s ceiling for a review that can
  never arrive.
- `wfc_bot_seen` counted Codex issue comments and reviews with **no freshness filter**, and
  an earlier round's comments and reviews never leave the PR. So from round 2 on, the probe
  was disarmed on the very first poll by activity that predated the round's `@codex review`,
  and a repo whose App had gone away produced a plain timeout (exit `2`) instead of the
  missing-App diagnostic. Observed live on PR #68, rounds 2–6.
- Both counts are now filtered by the round's trigger timestamp — the same `trigger-ts.txt`
  anchor the resolution conditions already use (`created_at` for issue comments, `submittedAt`
  for reviews). An empty anchor (the no-trigger-id compat path) keeps the filter a no-op.
- The reaction check is deliberately left **unfiltered**: `reactions.json` is fetched per poll
  from *this* round's trigger comment id, so a 👀 there is round-scoped by construction and
  still counts as a first response.
- No change to the exit-code contract (`0` findings / `1` pending / `2` timeout / `3` clean /
  `4` usage / `5` no-first-response), the freshness guards, the three clean-signal forms, or
  the exact-literal bot-login match.

## [0.46.0] — 2026-07-28

### Added — ✨ `/sdd-pr-loop` reports whether the review is converging (E21-F03)
- `pr_loop.max_rounds` caps the loop and labels the PR `needs-human`, but never said what the
  human should **conclude**. The observed conclusion is "run it again": on
  `viernes-ai/viernes-bookings-api` PR #76 the operator posted `@codex review` twelve times by
  hand, and rounds 5–12 cost roughly 2M input tokens and 8 hours of wall clock to keep
  rediscovering that the diff was too large to review in one pass.
- The evidence was already on the PR and nobody aggregated it — the per-round blocking-finding
  count: `1 3 1 2 1 3 1 2 2 1 2 1`. A **decaying** count means the review is converging and one
  more round is rational. A **flat** count means the reviewer is sampling a surface larger than
  one pass can cover, so another round buys another *sample*, not more confidence.
- New `tools/pr-round-trend.sh` reads only `.pr-loop/<pr>/round-*/blocking.json` — files the
  loop already writes — and reports the series, a verdict (`converging` / `non-converging` /
  `insufficient`) and where the findings concentrate. No `gh`, no network, no new state; `jq`
  was already a `/sdd-pr-loop` precondition, so no new dependency.
- The rule is deliberately the simplest one that separates the two cases, because it has to be
  explainable inside a `needs-human` message: **the last 3 rounds each produced at least one
  blocking finding**. A least-squares slope would be defensible and unreadable.
- A round that aborted before classifying has no `blocking.json` and is **excluded** from the
  series rather than counted as zero — counting it would fake a convergence that never happened.
- New step 4b in `/sdd-pr-loop`; the cap row and the `needs-human` terminal state now carry the
  verdict, and on `non-converging` the message says **split this PR** and lists the files the
  findings concentrate on as candidate seams.
- **Advisory throughout**: exit 0 at every verdict, no change to when the cap fires, and no
  change to the watcher's exit-code contract, freshness guards or clean-signal detection.
- Round dirs are ordered by their **numeric** suffix. A shell glob is lexicographic, so at ten
  or more rounds `round-10..12` sort before `round-2` and the last-N window would trend rounds
  7–9 while calling them the latest — inverting the verdict on exactly the twelve-round PR this
  exists for.
- One unparseable `blocking.json` no longer empties the concentration list: the aggregation runs
  over the rounds already validated, so an aborted round cannot cost the handoff its seam names.
- `--format json` escapes finding paths, so a filename containing `"` no longer produces output
  that exits 0 and cannot be parsed.
- The installer's **generated** command body was updated alongside the source-layout copy, and
  `tests/test_pr_loop.sh` asserts against the installed body — editing only the source copy is
  a wiring gap that has been raised as a blocking review finding in this repo before, so the
  mutation (remove step 4b from the heredoc only) is verified to fail the suite.

## [0.45.0] — 2026-07-28

### Added — ✨ Pre-PR change-size check on the Reviewer → PR handoff (E21-F02)
- E21-F01 put a budget where the sizing *decision* is made; this puts a measurement where that
  decision is last *reversible*. Nothing between local approval and PR creation looked at how
  large a branch actually was — on `viernes-bookings-api` E14-F05 the branch was 17,202
  additions across 77 files before any number was attached to it, and the first entity to
  notice was a paid reviewer, twelve times.
- New `tools/change-size.sh` (POSIX sh + git + awk, no `gh`, no network — it runs *before* a
  PR exists). Measures the diff from the **merge base**, classifies every changed file, reports
  the tier, and when over budget lists the production files carrying the most additions.
- **It never blocks.** Exit 0 at every tier including `escalate`; the only non-zero exit is `4`
  (not a repo / no resolvable base ref / bad flag) and that measures nothing. A tool that could
  fail a branch for being large would be a hard cap wearing an advisory label.
- Reports **where** the lines are, not just how many: the actionable question at the handoff is
  *where do I cut*. On PR #76 a bare total would have been equally true of the 15,500 low-risk
  lines and the 1,716 that carried two thirds of the findings.
- Classification is additive: new `change_size.test_paths` / `generated_paths` take extended
  regexes **added** to the built-in multi-ecosystem defaults (JS/TS, Python, Go, Ruby,
  Java/Kotlin/C#, common lockfiles and vendor dirs), never substituted for them.
- `agents/reviewer.md` runs it before approving and records the tier and the decision in its
  verdict; `agents/orchestrator.md` runs it before opening the PR and carries the tier into the
  PR body. Documented in `docs/WORKFLOW.md`.
- Budget correctness: **binary** files now occupy the file budget (git reports `-` for their
  line counts, and discarding the record meant 30 production images reported
  `production_files: 0` and tier `ok`), and untracked paths are read **NUL-delimited** because
  `ls-files` C-quotes a name containing `"`, a backslash or a tab regardless of
  `core.quotePath` — the encoded text was used as the pathname, so those files vanished from
  the measurement entirely.
- Classifier robustness: a configured `test_paths`/`generated_paths` regex containing whitespace
  stays **one** alternative (it was word-split, so `(^|/)integration tests/` became
  `(^|/)integration|tests/` and every production path starting with `integration` silently left
  the budget), and untracked lines are counted with `awk NR` rather than `wc -l`, which counts
  newlines and therefore reported a one-line file with no trailing newline as **zero** additions.
- New behavioral suite `tests/test_change_size.sh` (registered in `verification.test_command`)
  drives the tool against a real throwaway git repo — a grep over the script would prove
  nothing about whether a test file counts as production, which is the failure that makes the
  number meaningless. Two fixture defects were found and fixed while writing it: the fixture's
  own rewritten `.harness/` config was landing in the measured diff, and R7's original
  `thing_spec.rb` already matched a built-in pattern, so it would have passed without ever
  exercising the config hook.

## [0.44.0] — 2026-07-28

### Added — ✨ Change-size discipline: a feature-size budget the Driller and Architect honor (E21-F01)
- Nothing in the harness bounded the size of a feature. `agents/driller.md` decomposed an epic
  with no size rule and `agents/architect.md` specced whatever it was handed, so the sizing
  decision was made implicitly at drill time and never revisited. Measured consequence
  (`viernes-ai/viernes-bookings-api` PR #76, E14-F05): one feature carrying R1–R36 / T1–T25
  became a PR of 17,202 additions across 77 files whose review did **not converge in twelve
  `@codex review` rounds** — a flat per-round blocking-finding rate (20 P1 + 15 P2), meaning a
  clean round would have been indistinguishable from a round that sampled a quiet region.
- New advisory `change_size:` block in `harness.config.yaml`, seeded on fresh install and
  migrated on upgrade: `advise_lines: 1500`, `escalate_lines: 3000`, `advise_files: 25`,
  `escalate_files: 50`, `max_requirements: 12`. An absent block behaves exactly as those
  defaults, matching the `telemetry:` / `fix_lane:` / `models:` convention.
- **Two soft tiers, no hard wall.** Both tiers produce a *recorded decision*; neither refuses
  work. A single cap is the wrong instrument twice over: an agent-written change is
  legitimately denser than a hand-written one, and a rename sweep or generated contract can be
  thousands of lines at near-zero review risk per line. Review risk concentrates rather than
  spreading — in PR #76, 10% of the files carried 67% of the findings — so the budget prompts a
  split *along seams*, not a refusal.
- Budgets are **production** lines: tests are a deliberate quality choice the Reviewer already
  enforces (a passing test per `R-id`) and must not be penalised by the instrument that governs
  review surface. Requirement count is the drill-time proxy because it is the only size signal
  that exists before any code does, and each `R-id` obliges a test.
- `agents/driller.md` now splits an over-budget candidate into siblings sequenced on
  `depends_on` and records the decision (or the deliberate non-split) in the epic's `epic.md`.
  `agents/architect.md` now stops before writing the four spec files when a feature would
  exceed the budget, reports the count and the seams, and — where a human directs it to proceed
  — records an explicit override line in the `.spec.md`. Neither role emits a `blocked` record
  on size: `blocked` is a closed vocabulary about dependencies and ownership.
- Documented in `docs/WORKFLOW.md` ("Change-size discipline"). Asserted in
  `tests/test_sdd_drill.sh` (both role files carry the rule and its non-blocking boundary;
  the shipped defaults cannot be silently retuned) and `tests/test_install.sh` (block seeded
  on fresh install, appended exactly once on migration, and the presence check tolerates a
  target's annotated `change_size:   # tuned` line rather than shadowing it with a second block).
- **On micro-specs:** the [pattern](https://www.augmentcode.com/guides/micro-specs-pattern-ai-agent-test-coverage)
  is already implemented here — an EARS `R-id` *is* an atomic single-behavior spec and the
  Reviewer already mandates a test per `R-id`. E14-F05 had 36 working micro-specs and was still
  unreviewable, because nothing mapped a micro-spec to a **deliverable**. This release adds the
  missing grouping rule, not another authoring phase; over-applied spec ceremony has its own
  documented failure mode
  ([Böckeler](https://martinfowler.com/articles/exploring-gen-ai/sdd-3-tools.html)).

## [0.43.1] — 2026-07-28

### Fixed — 🐛 Installer keeps `.harness/progress/` run dirs out of a consumer's VCS (E99-F06)
- The harness **source** has always ignored its own per-run agent output (`progress/*/` in
  its root `.gitignore`), but that ignore was never propagated to installed targets. The
  seeded `.harness/.gitignore` covered `telemetry.jsonl`, `jira.pat` and
  `state/tasks.json.lock` only — so in every consumer each agent run dir was committable,
  and in practice got committed. Measured on `viernes-ai/viernes-bookings-api` PR #76:
  796 lines across 6 files (**5% of that PR's additions**) were `.harness/progress/`
  pr-loop round scratch, shipped inside the product diff and re-read by the reviewer on
  each of twelve review rounds.
- `harness-install.sh` now seeds `progress/*/` plus the re-inclusions that keep the durable
  artifacts tracked (`!progress/.gitkeep`, `!progress/README.md`, `!progress/inbox/`,
  `!progress/inbox/**`). **Order is load-bearing**: `progress/*/` excludes the `inbox`
  directory itself and git does not descend into an excluded directory, so
  `!progress/inbox/**` alone would silently ignore every Architect brief.
- The append path (an existing `.harness/.gitignore`) now matches whole LINES (`grep -qxF`)
  instead of substrings. With negations in the list a substring match is unsafe:
  `!progress/inbox/` is a substring of `!progress/inbox/**`, so a file holding only the
  latter would suppress the former and lose the briefs. Still append-only — a target's own
  entries are never rewritten or reordered.
- A new ignore rule does **not** untrack an already-tracked file; an existing target must
  run `git rm -r --cached .harness/progress/<run-dir>` once itself. The installer
  deliberately does not do this — untracking files in someone's repo is not its call.
- `tests/test_install.sh` asserts the behavior with `git check-ignore` on a throwaway repo
  (run output ignored, briefs and `history.md` still tracked) rather than by grepping for
  strings, because no grep can see the ordering the re-inclusion depends on. Both the
  dropped-ignore and the dropped-directory-re-inclusion mutations fail the suite.

## [0.43.0] — 2026-07-28

### Added — ✨ the installer asks a third question: `pr_loop.enabled` (E20-F02)
- The toggle this work stream was opened for: **the human running the installer is the one
  who marks the PR-loop enablement.** E18-F01 made `pr_loop.enabled` opt-in (default
  `false`); turning it on has been a one-line hand-edit of `.harness/harness.config.yaml`
  ever since, discoverable only by reading source comments. The installer now **asks**, as
  one more plain line-oriented prompt right after the E20-F01 backend question:

  ```
  Enable the Codex PR review loop on this install? (E20-F02)
    1) false   stamp no /sdd-pr-loop glue — the opt-in default
    2) true    stamp /sdd-pr-loop + the pr-fixer sub-agent
               NEEDS the Codex GitHub App on this repo plus an authed `gh`.
               Nothing is probed now; the first /sdd-pr-loop run reports it.
    choose 1/2 [Enter keeps false]:
  ```

- **The opt-in default does not change.** This adds a prompt, not a new default. Pressing
  Enter keeps whatever the target already has, and a fresh install still cannot inherit the
  harness source repo's own `pr_loop.enabled: true` — `seed_pr_loop_optin` is unmodified and
  still normalizes a freshly copied config to `false` **before** the resolved value is
  applied, so "no answer ⇒ off" is enforced twice. The only route to `true` on a fresh
  target is an explicit `2` / `yes` / `--pr-loop=true`.
- **Scripted installs: `--pr-loop=<true|false>`** (also `--pr-loop <value>`). Suppresses the
  prompt; an empty value means *no override*, exactly like `--agents=` and
  `--builder-backend=`; an illegal value aborts non-zero **before** anything is created or
  modified in the target. With no TTY and no override nothing is asked and the config is
  left **byte-identical**, so CI keeps today's behavior exactly.
- **No environment twin, on purpose.** `HARNESS_PR_LOOP_ENABLED` keeps its exact E18-F01
  meaning: one of five **per-run** overrides (with `HARNESS_AUTO_MERGE`,
  `HARNESS_MAX_ROUNDS`, …) that gates a single run, still wins over the config for what that
  run stamps, and changes **no byte** of `harness.config.yaml`. Making one member of that
  family persist would turn `HARNESS_PR_LOOP_ENABLED=false ./harness-install.sh <target>`
  from "don't stamp on this run" into "permanently disable this target's loop". The layering
  is *the flag/prompt persists, the env overrides the run* — with exactly one warning when
  the two disagree, and none when they agree or the variable is unset.
- **The flip is reconciled inside the same run.** The write lands after the config
  seed/migrate stage and before glue generation, so answering `2` stamps `/sdd-pr-loop` and
  the `pr-fixer` sub-agent immediately, and answering `1` on a later re-run reclaims all of
  it through E18-F01's existing pass — including the `.sdd-pr-loop.owners` ledger, so a
  target flipping its own gate off never deletes a global Codex prompt another target still
  claims. E18-F01's unconditional command-body generation (the pristine reference that
  reclamation byte-compares against) is untouched.
- **No install-time preflight.** Enabling the loop probes nothing: the installer is POSIX
  `sh` with zero dependencies and never invokes `gh` or `jq`, which stay loop-runtime
  requirements. The prompt states the precondition instead, and `/sdd-pr-loop`'s own
  fail-fast diagnoses it at the one moment that can be accurate — the Codex GitHub App may
  legitimately be installed *after* the harness.
- **The config write is surgical.** Only the one scalar on the gate line is replaced,
  preserving its indentation and any trailing comment verbatim; where the `pr_loop:` section
  exists with no `enabled:` key at all, the canonical line is inserted after the header. A
  same-named `enabled:` under any other section, every comment, blank line and unrelated
  hand-edit survive, and a seeded target and an upgraded one converge on byte-identical
  blocks for both values.
- Docs: `docs/INSTALL.md` gains a "third question" section (the prompt, `--pr-loop=`, the
  per-run env ruling, the no-preflight ruling, re-run-to-change); the `pr_loop:` comment
  block in `harness.config.yaml` and in the installer's migration heredoc document the
  prompt in byte-identical text. Checks live in `tests/test_installer_toggles.sh`.

## [0.42.0] — 2026-07-28

### Added — ✨ the installer asks a second question: `execution.builder.backend` (E20-F01)
- Until now the installer asked exactly **one** question — which front-ends to stamp — and
  every other install-shaping choice was a hand-edit of `.harness/harness.config.yaml`
  discovered by reading source comments. The most consequential of those,
  **`execution.builder.backend`** (`in-session` vs `delegate` — the single seam an external
  executor plugs into), is now asked out loud, as a plain numbered follow-up prompt right
  after the front-end picker confirms.
- **The picker itself is untouched.** The new question is a separate line-oriented `read`
  prompt, not a row inside the checkbox list: that list is keyed on agent keys and emits a
  sorted key list, an enum has no `[x]`/`[ ]` meaning in it, and its raw-mode path (stty
  state, EXIT/INT traps, raw Ctrl-C bytes) is the highest-risk code in the installer. A
  `read` prompt is also identical on both interactive rungs, so the new toggle needs no
  fallback ladder of its own.
- **Scripted twin: `--builder-backend=<in-session|delegate>` / `HARNESS_BUILDER_BACKEND`**,
  exactly symmetric with `--agents` / `HARNESS_AGENTS`. The flag wins over the env var,
  both suppress the prompt, an **empty** value means *no override*, and an illegal value
  aborts non-zero **before anything is created or modified** in the target.
- **Nothing changes for anyone pressing Enter, or for CI.** Enter keeps the value the
  target already has (`in-session` on a fresh install), an unrecognized answer keeps it
  too, and a run with **no TTY and no override** asks nothing and leaves
  `harness.config.yaml` byte-identical.
- **The config is never rewritten wholesale.** Only the one scalar on the `backend:` line
  is replaced; its indentation, its trailing comment, and every other comment and
  hand-edit in the file survive byte-for-byte. Re-applying the same value is a no-op.
  `migrate_config` gained one entry so a config predating the `execution:` block gets it
  appended once, append-only — and that appended block is **byte-identical to the one a
  fresh install seeds**, the convergence rule `migrate_config` already states for its
  `models:` and `pr_loop:` entries, now asserted for `execution:` too.
- **The seeded `harness.config.yaml` documents the new surface where you edit it.** The
  `execution:` block's comment header names the prompt, `--builder-backend=` and
  `HARNESS_BUILDER_BACKEND`, so the majority path — a fresh install — is the discoverable
  one.
- **Choosing `delegate` before wiring `delegate_cmd` warns and proceeds** — it is neither
  refused nor silently downgraded to `in-session`. `delegate_cmd` is a free-text command
  the installer does not prompt for, so refusing would mean the prompt could never turn
  delegation on at all; downgrading would make the installer lie about what was chosen.
  The warning names `execution.builder.delegate_cmd` and the file to edit, and the Builder
  role already stops and reports if it is still empty when work starts.
- Change the value later by **re-running the installer** — the same reconfiguration path
  front-end selection already uses. `--print-agents` still prints exactly two stdout lines.
- New suite `tests/test_installer_toggles.sh`, wired into `verification.test_command`.

## [0.41.0] — 2026-07-28

### Changed — ✨ a fresh interactive install pre-checks the CLI you are in (E19-F02)
- E19-F01 built the detection and the explicit `--agents=host` mode but deliberately
  changed no default. This release spends it: on a **first, interactive** install into a
  target with **no existing install**, the agent picker now opens with the **detected host
  pre-checked and the other front-ends unchecked**, so installing from inside one CLI no
  longer stamps the other four's glue *and you do not have to know a flag exists*.
- **It is a pre-check, not a restriction.** The picker is already on screen: spacebar adds
  any other front-end before you confirm. That is precisely why the guess is made only
  here — where a human can correct it before anything is written.
- **The pre-check is the host ALONE**, never unioned with `claude`. Unioning would
  re-create the same complaint for every non-Claude user, in a harness whose premise is
  that the front-end is interchangeable.
- **An upgrade is never narrowed by detection.** "Existing install" is the presence of
  `.harness/.harness-version`, not of `.harness/.agents` — so a **pre-E08 install** (every
  front-end stamped, no persisted selection) still pre-checks **all** of them, and
  pressing Enter on an upgrade can never delete glue you are using. On an install that
  does carry a selection, that selection is the baseline, exactly as before.
- **Undetected still means everything**, and **nothing changes without a TTY**: a piped or
  CI run with no override still stamps all five front-ends, byte-for-byte as before. No
  removal authority, pristine-compare rule or `.sdd-pr-loop.owners` ledger behavior
  changes.
- **`--print-agents`' `baseline=` line now reports the picker's pre-check set**, so the
  diagnostic advertises the new default instead of the old one. For every *undetected*
  target it prints exactly what it printed before.
- **Documented in `docs/INSTALL.md`**: the new fresh-install default with its three cases,
  and — new section — that **re-running the installer** is the supported way to change the
  selection later (it re-opens the picker pre-checked from `.harness/.agents` and applies
  both additions and removals), a fact that previously lived only in a source header
  comment.

## [0.40.0] — 2026-07-28

### Added — ✨ `--agents=host`: install the glue for the CLI you are actually in (E19-F01)
- A human who works in exactly one coding-agent CLI used to get all five front-ends
  stamped into their repo — `GEMINI.md`, `opencode.json`, an Antigravity `.agents/` tree
  and global Codex prompts alongside the glue they wanted. The installer now understands a
  **`host` resolution mode**: `--agents=host` (or `HARNESS_AGENTS=host`) resolves to the
  single front-end this installer session is running in and stamps only that one.
- **Detection reads session markers, never ambient configuration.** A variable counts only
  when the front-end injects it into the environment of the processes it launches.
  Verified empirically, one row per front-end: `claude` (`CLAUDECODE`,
  `CLAUDE_CODE_ENTRYPOINT`; Claude Code 2.1.220), `codex` (`CODEX_THREAD_ID`; codex-cli
  0.145.0), `opencode` (`OPENCODE`, `OPENCODE_PID`; opencode 1.18.5) and `antigravity`
  (`ANTIGRAVITY_AGENT`, `ANTIGRAVITY_CONVERSATION_ID`; agy 1.1.8). `gemini` has no
  verified marker and is deliberately **undetectable** rather than guessed at.
  Config/credential variables are forbidden by rule — `CODEX_HOME`, `HOME`, `TERM_PROGRAM`
  and anything ending `_API_KEY` — because they prove only that you *use* a tool, never
  that this run was launched from it.
- **A miss is normal operation, never an error.** Markers for two or more front-ends at
  once (what nesting looks like) is treated as *undetected* with a stderr diagnostic, not
  as a tie to break. An undetected `host` run falls back to **ALL** front-ends on a target
  with no existing install (byte-identical to today's no-override default) and to the
  target's **persisted `.harness/.agents`** selection on one that already carries an
  install — so it can never silently widen a claude-only repo back to five front-ends.
  One line reports which happened.
- **New `HARNESS_HOST_AGENT=<key>`** — declare your host once (e.g. in a shell profile)
  for a front-end with no verified marker. An invalid value warns and is ignored; it never
  aborts an install.
- **New `--print-agents <target>`** — prints `host=<key or empty>` and `baseline=<keys>`,
  writes nothing, exits 0. It shares the resolution helpers with the real install, so the
  preview cannot disagree with what an actual run would do.
- **Strictly additive.** `host` is a resolution *mode*, not a sixth agent key: it is never
  added to `AGENT_KEYS`, never offered as a picker row, and never written to
  `.harness/.agents` (`--agents=host,gemini` is rejected). An install that does not name
  `host` behaves exactly as it did before — same no-TTY default, same explicit-CSV
  behavior, same interactive pre-check baseline, same `PRIOR_AGENTS` removal rules and the
  same `.sdd-pr-loop.owners` ledger authority over the shared global Codex prompts.
- New suite `tests/test_agents_host.sh` (wired into `verification.test_command`), every
  detection-sensitive case run under `env -i` with a sandboxed `CODEX_HOME`; the E08 block
  in `tests/test_install.sh` gains the end-to-end `host` case.

## [0.39.0] — 2026-07-27

### Added — ✨ `/sdd-pr-loop` + vendored Codex watcher, opt-in via `pr_loop.enabled` (E18-F01)
- The harness told its own agents to run `/pr-loop` in three places but shipped no such
  command — it came from the separate multi-cli-orchestrator skill set at
  `~/.agents/skills/`. The moment those skills are uninstalled (or on any fresh consumer
  that never had them) the documented review workflow pointed at a command that does not
  exist, and the watcher path it named was dangling. The loop is now **vendored into the
  harness** as first-class, installer-generated glue.
- **New command `/sdd-pr-loop <pr>`** — one body, mirrored byte-identically into
  `.claude/commands/`, `.opencode/command/`, `.agents/workflows/` and the GLOBAL
  `${CODEX_HOME:-~/.codex}/prompts/` — **only where `pr_loop.enabled` is `true`; nothing
  is stamped by default**. It preflights, posts `@codex review`, launches the
  watcher in the background, classifies `P0|P1|P2|nit`, spawns one fixer per blocking
  comment, escalates on a stall, and merges when every gate is green.
- **New watcher `tools/wait-for-codex.sh`** — the vendored background poller, converted to
  POSIX `sh` and installed executable. Three modes: `wait` (the source contract, exit `0`
  findings / `2` timeout / `3` clean / `4` usage), `preflight <pr>` (gh + auth + jq + repo
  slug + open PR; posts nothing; exit `5` with a one-line diagnostic naming the failed
  check), and `evaluate <round-dir>` (a pure, offline re-run of the same freshness rules —
  invokes no `gh`). A new **first-response probe** exits `5` naming the Codex GitHub App
  when nothing answers within `HARNESS_FIRST_RESPONSE` (default 180s), instead of polling
  to the 900s ceiling. All four vendored source files, the `--paginate --slurp` fetches
  and the three independent clean signals are preserved.
- **New canonical role `agents/pr-fixer.md`** — front-end neutral (one comment, one fix,
  one commit, one return), with gated shims for Claude (`.claude/agents/pr-fixer.md`),
  OpenCode (`.opencode/agent/pr-fixer.md`, `mode: subagent`) and Antigravity
  (`.agents/agents/pr-fixer.md`). No `pr-fixer` artifact is created for codex or gemini —
  those apply fixes in-session — and the model-routing role map is untouched, so
  `opencode.json` and `.harness/.opencode.stamp` stay byte-identical either way.
- **New `pr_loop:` config block** (`enabled`, `auto_merge`, `max_rounds`,
  `blocking_severities`, `merge_strategy`), seeded on a fresh install and appended
  byte-identically by `migrate_config` on upgrade. Absence of the block — or of any key —
  behaves exactly as the documented defaults. Each key takes a `HARNESS_*` env override;
  the execution knobs (`HARNESS_POLL_INTERVAL`, `HARNESS_POLL_CEILING`,
  `HARNESS_FIRST_RESPONSE`, `HARNESS_DRY_RUN`) are env-only.
- **`pr_loop.enabled` is OPT-IN — a fresh install seeds `false` and stamps no
  `/sdd-pr-loop` glue at all.** The gate is on **only** when the key resolves to the
  literal `true`; an absent block, an absent key, an empty value and any other token alike
  mean off. The loop functions only on a repository with the **Codex GitHub App** plus an
  authed `gh`, so defaulting it on would give every fresh install a command that could do
  nothing but fail its own preflight. Turning it on is a one-line edit of
  `.harness/harness.config.yaml` plus a re-run of the installer (E20-F01 will offer the
  choice at install time). The seed never inherits the *harness source repo's* own value,
  which stays `true` because that repo does have the App.
- **`pr_loop.enabled` back to `false` reclaims the glue** from every *still-selected* front-end (a
  new §7b reconciliation pass, since the existing deselect loop only reconciles
  front-ends that left the selection), pristine-only in the user-owned `$CODEX_HOME`
  prompts dir and the `.agents/` tree, pruning only dirs left empty. Flipping it back on
  restores byte-identical glue. The command body is generated into the neutral `CMDDIR` on
  **every** run regardless of the gate — that copy is the pristine reference reclamation
  compares against.
- **Clean break on env vars**: no `MCO_*`, `.mco-cache`, `~/.agents/skills`, `route-task`
  or `start-feature` token remains in the harness body. The round cache moved to
  `<HARNESS_DIR>/.pr-loop/<pr>/round-<n>/`, ignored by both the seeded
  `.harness/.gitignore` and the source repo's own `.gitignore`.
- `gh` and `jq` are **loop-runtime** dependencies only: `init.sh` gains no gate, so a
  target with neither still passes the environment check.
- New suite `tests/test_pr_loop.sh` (wired into `verification.test_command`);
  `tests/test_install.sh` asserts `/sdd-pr-loop` generation + deselect removal per
  front-end. Docs updated: `README.md`, `docs/INSTALL.md`, `docs/WORKFLOW.md`,
  `docs/HARNESS.md`, `CLAUDE.md`, `agents/orchestrator.md`.

## [0.38.1] — 2026-07-27

### Fixed — 🐛 Slug validation in `fix-worktree.sh` is locale-independent (E99-F03)
- `validate_key()` screens the fix slug with the shell glob `*[!a-z0-9-]*`. Bracket
  ranges in a `case` glob are resolved through the active locale's **collation order**,
  not ASCII, so under the common developer default `en_US.UTF-8` an uppercase slug like
  `Bad-Slug` fell inside `a-z`, the negated class did not match, and the invalid slug was
  **accepted** — a malformed value then propagated into the branch and worktree names the
  helper creates on disk. Under `C` the same expression rejected it correctly.
- `tools/fix-worktree.sh` now pins `LC_ALL=C` (exported) next to `set -u`, so every glob
  in the file means ASCII and the `git` plumbing output it parses stays deterministic.
  The `case` patterns are unchanged — with `LC_ALL=C` in force they were already correct.
  `[[:lower:]]` was deliberately **not** used: that class is itself locale-defined and
  would newly accept accented lowercase, widening the slug grammar instead of fixing it.
- The bug hid because `verification.test_command` runs in a C locale, where the
  expression behaves. `tests/test_fix_worktree.sh` gains
  `test_slug_rejection_is_locale_independent`, which drives the helper under **both**
  `en_US.UTF-8` and `C` (skipping cleanly where a locale is absent) and asserts rejection
  plus no ref/registration/path mutation — so the hole is caught in C-locale CI too, not
  only on a developer laptop.
- The C pin stops at **foreign code**. `fix-worktree.sh` executes code owned by the target
  repo at three surfaces — the project init gate (`init.sh`, which sources
  `.harness/init.project.sh`), `run` commands, and the `post-checkout` hook plus checkout
  (smudge) filters that `git worktree add` fires — and all three now run under the
  **caller's** locale, restored from the value captured before the pin. Exporting C into
  them was a real defect, not just a broad blast radius: a consumer whose
  `init.project.sh` requires UTF-8 failed its own gate, and `create` then rolled back an
  otherwise valid worktree.
- A caller with `LC_ALL` unset gets it restored as **unset**, not empty, so their
  `LANG`/`LC_*` layering resurfaces — an empty `LC_ALL` is ignored by some
  implementations and honored by others.
- `worktree add` is safe to un-pin precisely because its output is discarded and only its
  exit status is read; every remaining `git` call in the helper is read-only plumbing that
  **is** parsed and stays under `C`, so the determinism the pin was chosen for is intact.
- `tests/test_fix_worktree.sh` gains `test_child_commands_see_caller_locale`, whose init,
  `run`, and post-checkout-hook legs are each independently mutation-sensitive.
- Scope is only this glob: the `grep -Eq '^[a-z0-9-]+$'` validators in `harness-install.sh`
  and the Python `re` validator in `init.sh` were verified unaffected and left alone.

## [0.38.0] — 2026-07-27

### Added — ✨ Per-role model selection (E17-F01)
- Added a front-end-agnostic `models:` block to `harness.config.yaml` (seeded on a
  fresh install, append-migrated onto a preserved config) that maps each of the six
  SDD roles — `orchestrator architect builder reviewer scout doc-critic` — onto the
  tier vocabulary `reasoning | standard | cheap | inherit`, plus a
  `models.pin.<front-end>.<tier>` escape hatch written verbatim (see the two guards
  below).
- Taught `harness-install.sh` to stamp the resolved per-role model into the native
  agent-definition convention of every **selected** front-end: `model:` frontmatter in
  `.claude/agents/*.md` and `.agents/agents/*.md`, a `"model"` member in
  `opencode.json`, and two new conditionally-created project-local artifacts,
  `.gemini/agents/*.md` and `.codex/agents/*.toml` (never `$CODEX_HOME`).
- Built-in tiers resolve to floating vendor aliases only (`opus`/`sonnet`/`haiku`,
  `pro`/`flash`) — the harness ships no version-pinned model id. `codex` and
  `opencode` have no floating alias, so an unpinned tier there stamps nothing and the
  installer prints one advisory line naming the `pin.` key to set.
- **Opt-in and inert by default**: `inherit` compiles to key omission on every
  front-end (the literal string is never written), so an absent, empty or all-`inherit`
  block leaves the generated tree byte-identical to a harness without model routing —
  no model key, no `.gemini/`/`.codex/` directory, no `.harness/.opencode.stamp`,
  no `.harness/.model-agents/`. Moving a previously-stamped target back to all-`inherit`
  **reconciles** it: the pristine per-role files are reclaimed and the harness-created
  directories pruned, so the switch back to session inheritance actually takes effect
  instead of leaving the old `model` keys discoverable.
- Refined the `opencode.json` never-clobber contract so model changes can land: it is
  regenerated only when byte-identical to `.harness/.opencode.stamp` or to a freshly
  generated model-free body, and otherwise left untouched with a warning. Deselection
  reclaims every stamped artifact through the existing pristine byte-comparison.
  `.harness/.model-agents/` extends that stamp device to `.gemini/agents/` and
  `.codex/agents/`, so reclamation stays correct even when the `models:` block is edited
  in the same run — a user-edited artifact is still never deleted, only warned about.
- An unrecognized tier warns and resolves as `inherit` (never fatal). A pin is otherwise
  written verbatim, with exactly two guards: an `opencode` pin without a `/` and a pin
  whose value is the tier name `"inherit"` are each warned about and dropped, stamping
  nothing. Documented in `docs/INSTALL.md`; added `tests/test_model_routing.sh` to
  `verification.test_command`.

## [0.37.1] — 2026-07-27

### Fixed — 🐛 ADR-citation resolution is namespace- and qualifier-aware (E99-F50)
- `init.sh` section 2c resolved a cited `ADR-NNNN` **only** against `specs/adr/`, so a
  project that keeps a second, legitimate ADR namespace (`specs/<product>/adr/`, e.g.
  the platform-vs-product altitude split) got a standing wall of false-positive
  warnings — 18 of them in one downstream install, every one of them wrong.
- ADR spaces are now first-class. A **namespace** is a directory literally named `adr/`
  under `specs/`; only `*.md` sitting directly in it counts as an ADR. Its **token** is
  the parent directory's basename, with `platform` reserved for the root space
  `specs/adr/`. The spaces are independent and normally **collide** (`0023` in both,
  different content), so resolution is **qualifier-aware**:
  - **Qualified** — `<ns>/ADR-NNNN`, or `<ns> ADR-NNNN` when `<ns>` is a real namespace
    token — resolves against **that namespace only**. `platform ADR-0023` still warns
    when only `bookings/0023` exists; an unknown `<ns>/` never resolves. This is the
    cross-namespace typo the sweep exists to catch, and it is now caught.
  - **Bare** — `ADR-NNNN` asserts no namespace, so it resolves against **any** of them
    and warns only when it resolves in **none**. Deliberate: pre-convention corpora and
    single-namespace projects write bare ids, and inferring a namespace the author never
    wrote would recreate the false-positive wall.
  - **Known, accepted hole:** a **bare** citation is therefore *not* namespace-checked —
    in a multi-namespace project a bare cross-namespace typo passes silently. Write the
    qualifier to get it checked. This trade-off is recorded in `init.sh` section 2c, in
    `agents/reviewer.md`, and taught by `agents/architect.md` +
    `specs/_templates/feature.spec.md`.
- **The extractor normalizes before it matches**, because the optional qualifier group is
  blunt at both boundaries. (a) A `|` is appended to every id, so a citation can never be
  eaten as the *qualifier* of the id next to it — without it `ADR-0042 ADR-0001` produced
  one match whose "qualifier" `adr-0042` was then discarded and **never looked up**, a
  coverage regression against the plain `ADR-[0-9]{4}` scan. The delimiter must be a
  suffix; a prefix would break the legitimate `<ns> ADR-NNNN` form. (b) Emphasis/quote
  wrappers (`*`, `"`, backtick, `'`) are stripped, so a real qualifier written
  `**platform** ADR-0023` stays qualified instead of being silently demoted to bare.
  `_` is deliberately not stripped — underscore is legal in a namespace token.
- The per-namespace index is built **once** per run, so each citation costs one string
  match. A third namespace needs no code change. The index now takes only ADRs sitting
  *directly* in an `adr/` directory (an `adr/archive/` subtree is not a namespace),
  matching what the comment always claimed. The `searched:`/success lines are
  comma-joined so a namespace path containing a space stays unambiguous.
- **Contract sync (same rule at every altitude).** `agents/reviewer.md` no longer
  requires every cited id to resolve under `specs/adr/` and no longer preconditions its
  check on `specs/adr/` specifically — it states the qualified/bare rule verbatim, so an
  id `init.sh` certifies clean is never re-flagged at review time (and a product-
  namespace-only project gets a Reviewer check at all). `agents/architect.md`,
  `specs/_templates/feature.spec.md`, `docs/SPEC-FORMAT.md` and `docs/WORKFLOW.md` teach
  the qualifier convention and drop the single-namespace assumption.
- Unchanged by design: warn-only (never gates), zero dependencies, the
  `## Architecture alignment` section scoping, the trailing unresolved-count line, and
  the complete no-op when `specs/` holds no `adr/` directory at all.
- `tests/test_adr_citation.sh` gains R7 (a citation resolving in a second namespace is
  silent while a genuinely unresolvable id is the *only* warning), R8 (a project whose
  *only* ADR space is a product namespace still gets a live sweep, not a no-op), R9 (a
  qualified citation does **not** resolve cross-namespace, in both directions, and an
  unknown namespace warns), R10 (a bare citation stays permissive-any and an ordinary
  prose word is not promoted to a qualifier), R11 (contract coherence — each of the
  **five** contract files, `agents/reviewer.md`, `agents/architect.md`,
  `specs/_templates/feature.spec.md`, `docs/SPEC-FORMAT.md`, `docs/WORKFLOW.md`, plus
  `init.sh`, pinned independently), R12 (two adjacent ids on one line are **both**
  checked, in every bracket/bullet/indent/slash form, and no bogus namespace token is
  invented) and R13 (a qualifier wrapped in emphasis/quotes stays qualified).

## [0.37.0] — 2026-07-25

### Added — ✨ Deterministic next-task selection (E16-F03)
- Added the executable, zero-dependency Node 18+ `tools/next-task.mjs` selector
  with strict JSON output, canonical feature/slice ordering, exact dependency
  diagnostics, target and owner scopes, and umbrella fail/merge/integration
  precedence.
- Made valid selector output authoritative for the Orchestrator while retaining
  the complete Markdown routing policy as a reported fallback when Node is
  unavailable or output is invalid. Selection remains read-only and no gate,
  status, schema, dependency, ownership, or rollup policy changed.
- Installed the selector verbatim and executable, documented source/installed
  troubleshooting, and added differential feature/slice/owner/error fixtures,
  immutable-input checks, reordered byte determinism, and a 2,000-feature
  performance contract.

## [0.36.0] — 2026-07-25

### Added — ✨ Harness rationale and deletion ledger (E16-F02)
- Added a cold-readable `docs/RATIONALE.md` that explains why repository-changing,
  long-running agent work needs more than repeated prompting and separates
  current-model capability compensation from durable trust-and-intent controls.
- Added the complete 21-row C1–C8/D1–D13 retention ledger with repository pointers,
  mechanism-specific reconsideration evidence, a retain-by-default protocol, and
  the ADR-0001/E16-F03 boundary for replacing prose routing without removing the
  human-auditable gate policy.
- Added bounded primary-source notes, explicit METR study limitations, source and
  installed navigation, byte-identical installer coverage, offline link/inventory
  checks, and full-suite wiring without runtime or role-contract changes.

## [0.35.0] — 2026-07-25

### Added — ✨ Dependency-cycle and blocked-selection diagnostics (E16-F01)
- Added the executable stdlib-only `tools/task-diagnostics.py` helper with
  deterministic feature/slice SCC witnesses, graceful empty-board behavior, and
  actionable direct-input errors.
- Integrated warn-only cycle paths into source and installed `init.sh` after the
  canonical TaskStore validator, preserving all existing gate exit semantics.
- Pinned the seven stable no-selection reason codes, exact human templates,
  canonical ordering, scoped ownership behavior, and read-only informational
  contract for the Orchestrator, local store, and future E16-F03 selector.
- Added executable graph, 2,000-node scale, installed-layout, schema/status
  invariance, documentation, and full-suite regression coverage.

## [0.34.0] — 2026-07-25

### Added — ✨ Bounded isolated parallel maintenance fixes (E15-F03)
- Added `/sdd-fix-parallel`, a portable coordinator that provisions isolated F02
  worktrees before one atomic F01 claim, overlaps safe targeted workers, and
  serializes shared or unknown paths.
- Added targeted Orchestrator rules for Builder/Reviewer rounds, one PR and
  `/pr-loop` per fix, merge-before-done, failure isolation, and safe teardown.
- Kept each pre-provisioned F02 identity for the entire worker lifecycle and added
  coordinator-owned bookkeeping-PR persistence plus updated-base reconciliation
  before non-forced teardown. Parallel preflight rejects the delegate Builder
  backend with the serial fallback.
- Added `fix_lane` defaults, expected-path brief metadata, all-frontend installer
  generation/ownership, documentation, and permanent disposable coverage.

## [0.33.0] — 2026-07-25

### Added — ✨ Safe worktree-per-fix isolation lifecycle (E15-F02)
- Added the portable executable `tools/fix-worktree.sh` with deterministic
  `create`, exact-context `run`, and non-forced `teardown` operations for isolated
  `feat/E99-Fn-slug` branches under `.claude/worktrees/`.
- Creation resolves and snapshots a local default/base branch instead of ambient
  `HEAD`, fails closed on dirty or colliding state, links only the documented
  four-file personal layer, and safely rolls back unchanged failed provisioning.
- Teardown proves exact identity, cleanliness, merged ancestry, and canonical
  primary/base alignment before non-forced worktree removal and safe branch
  deletion; unsafe or unexpected state is preserved with a recovery diagnostic.
- The installer ships the helper executable and append-seeds
  `.claude/worktrees/` exactly once without clobbering existing ignore rules.
  Configuration-layering documentation and disposable Git integration coverage
  define the local-link and runtime-lock boundaries.

## [0.32.1] — 2026-07-25

### Fixed — 🐛 Board-write contracts use the mandatory lock helper (E15-F01)
- Routed the Inception, Fixer, Planner, and Driller structural TaskStore mutations
  through the existing `tasks-lock.py apply --mutator` path, with allocation and
  target checks repeated against the fresh board read inside the lock. Removed the
  obsolete direct-edit + inline-validation instructions.
- Routed slice mutations through guarded `apply --mutator` and documented feature/
  epic status rollups through `set-status`, so every persisted board write uses the
  single advisory lock without adding helper commands or changing helper behavior.
- Added static regression coverage for the role/store contracts and completed the
  E15-F01 test traceability matrix and behavioral checks for R12 and R13.

## [0.32.0] — 2026-07-25

### Added — ✨ ADR-citation id resolution: Reviewer soft flag + init.sh warn-only sweep (E99-F02)
- **Reviewer check extended to id resolution** (`agents/reviewer.md`): where architecture
  artifacts exist and the spec is `sdd: true`, each `ADR-NNNN` cited in a feature spec's
  `## Architecture alignment` section must **also resolve to an existing
  `specs/adr/NNNN-*.md` file**. A cited-but-nonexistent id is a **soft flag** for the
  Builder/Architect to investigate — reusing the existing "suspected but not provably
  violated → flag, don't block" verdict rule, **never a hard reject** (a dangling id may be
  a typo *or* an ADR legitimately renamed/removed since the spec was written). The check
  still never fires for a legacy/no-architecture feature or an `sdd: false` brief-only item.
- **`init.sh` session-start sweep (warn-only, additive)** — new section 2c scans every
  `specs/epics/**/*.spec.md` carrying the `## Architecture alignment` section and warns on
  any `ADR-NNNN` cited **inside that section** (incidental mentions elsewhere don't count)
  that resolves to no `specs/adr/NNNN-*.md`, surfacing the typo at session start instead of
  waiting for review. Zero-dep (grep/awk/ls), **never fails the gate**, and a complete no-op
  when `specs/adr/` is absent (graceful degradation, mirroring the Reviewer precondition).
- **New suite `tests/test_adr_citation.sh`** (R1–R6) covers dangling-id warn, all-resolve
  silence, `ADRs touched: none`, section-scoped extraction, and the no-`specs/adr/` no-op;
  wired into `verification.test_command` in `harness.config.yaml`. No status/schema change;
  the Architect's "cite ids or `ADRs touched: none`" contract is untouched — resolution is a
  strict refinement.

## [0.31.0] — 2026-07-24

### Added — 🔒 Board write lock: flock-guarded read-modify-write on tasks.json (E15-F01)
- **New advisory-lock helper `tools/tasks-lock.py`** (installed body, executable) guards every
  persisted `state/tasks.json` mutation. It owns the whole critical section in **one process**:
  acquire a portable stdlib **`fcntl.flock`** on the sibling lockfile `state/tasks.json.lock`
  (resolved with `cwd = HARNESS_DIR`) → **re-read `state/tasks.json` from disk inside the lock**
  → apply the single status mutation → validate (`json` parse **and** `store/tasks.schema.json`
  schema check) → atomically replace the file (write-temp-then-`os.replace`) → release. Re-reading
  *inside* the lock is the point: two near-simultaneous writers (E15 parallel fix chains) can no
  longer lose an update (last-writer-wins clobber).
- **Fail-stop, no torn file** — a mutation that fails validation aborts non-zero, releases the
  lock, and leaves the original `state/tasks.json` byte-for-byte intact.
- **Bounded acquisition, never a silent hang** — lock acquisition is bounded by a ~10s timeout;
  on timeout it exits non-zero with an actionable error naming the lockfile and the timeout,
  never blocking forever and never writing unlocked.
- **No-op for serial callers** — for a single (uncontended) caller the lock is taken immediately
  and the output is byte-equivalent to the old read-modify-write, so `/sdd-next` and existing
  tests are unchanged. The `store.on_write_command` hook fires **after** the lock is released,
  never inside the critical section. **No new status value and no `store/tasks.schema.json`
  change** — only the concurrency discipline around the write.
- **Portable** — depends only on `python3` + stdlib `fcntl` (already a write-path dependency);
  it does **not** use the Linux-only `flock(1)` binary (absent on macOS). Single-host scope;
  cross-machine coordination is out of scope.
- **Installer wiring** — `harness-install.sh` copies + `chmod +x`'s the helper into
  `.harness/tools/` and gitignores the runtime lockfile (`state/tasks.json.lock`) in the seeded
  `.harness/.gitignore`; `tests/test_install.sh` asserts a fresh install ships the executable
  helper. `store/local.md`'s `set_status` contract is amended to mandate the lock protocol.

### Fixed — board write lock robustness (Codex #46 P1 ×2, pre-release under 0.31.0)
- **Helper resolves `HARNESS_DIR` from its own path, not `cwd`.** `tools/tasks-lock.py` now
  derives the board root from `__file__` (`<HARNESS_DIR>/tools/tasks-lock.py` ⇒ parent-of-parent)
  when `HARNESS_DIR` is unset, so the documented `set_status` invocation is correct from **any
  cwd** in both the source layout (`tools/…`, board `state/tasks.json`) and the installed layout
  (`.harness/tools/…`, board `.harness/state/tasks.json`) — no `.harness/.harness` double-nesting
  and no requirement to hand-set `HARNESS_DIR`. An explicit `HARNESS_DIR` env var still wins as a
  highest-precedence escape hatch. `store/local.md`'s `set_status` contract is corrected to match.
- **Zero-dependency fallback validator now enforces the `slices` invariant.** When `jsonschema`
  is unavailable, the minimal validator mirrors the schema's cross-field rule: a **sliced feature
  may be `done` only when every slice is `done` and `merged`**. Previously the fallback stopped
  after the status-enum check, so `set-status <sliced-feature> done` on unfinished slices could
  atomically persist a board that `init.sh` later rejects (and prematurely unblock dependents).
  No schema/status change; single-repo features are unaffected.
- **One shared board validator (Codex #46 r2 P1, id 3649182844).** Extracted a single canonical
  validator, `tools/validate-board.py`, and made **both** consumers use it: `init.sh` now calls it
  as a CLI (identical success/failure lines and stderr contract) and `tools/tasks-lock.py` imports
  its `validate(data, schema) -> list[str]` in-process while holding the lock, before the atomic
  `os.replace`. This deletes the partial hand-rolled fallback in `tasks-lock.py` that silently
  accepted boards `init.sh` rejected (e.g. a non-boolean `sdd`, malformed `slices`). The validator
  prefers `jsonschema.Draft7Validator` when importable and otherwise runs the **complete**
  zero-dependency structural check (required keys, types, id patterns, enums, owner defaults,
  slices rules, and the sliced-`done` cross-field invariant) — the exact behaviour `init.sh`
  carried before, now shared verbatim so both paths accept/reject identically. Shipped executable
  by `harness-install.sh` and asserted by `tests/test_install.sh`.
- **Reject non-finite / negative lock timeouts (Codex #46 r2 P2, id 3649182846).** `argparse`'s
  `float()` accepted `--timeout nan`/`inf`, which poisoned the deadline arithmetic (`nan` makes
  `monotonic() >= deadline` always False → unbounded wait against a contended lock; `+inf` is an
  infinite bound). The helper now validates the timeout is **finite and non-negative** up front and
  exits non-zero with a clear message before entering the poll loop, restoring the bounded-
  acquisition contract (R5).
- **Minimal-diff status writes preserve existing board formatting (Codex #46 r3 P2, id 3649236637).**
  `set-status` now patches ONLY the addressed object's `"status"` value token in the original file
  text, leaving every other byte untouched, instead of parsing → `json.dumps(indent=2)` →
  re-serializing (which rewrote unrelated entries — e.g. expanding a sibling feature's inline
  `depends_on` array — on any board not already `indent=2`-canonical). This restores the promised
  serial byte-equivalence (R6) and keeps Git diffs / merge-conflict surface minimal, exactly when
  E15 introduces parallel branches. The result is still `json`-parsed and schema-validated through
  the shared `tools/validate-board.py` before the atomic `os.replace`, so an invalid outcome (bad
  id, illegal status, sliced-`done` invariant) still fail-stops with the board intact. The
  `apply --mutator` path is unchanged (external mutators may alter arbitrary structure).
- **Ignore the source-layout board lockfile (Codex #46 r3 P2, id 3649236638).** The
  `state/tasks.json.lock` ignore was seeded only into an installed consumer's `.harness/.gitignore`.
  In this source repo the documented `python3 tools/tasks-lock.py set-status …` creates the lock at
  root-relative `state/tasks.json.lock`, which the root `.gitignore` did not cover — dirtying the
  worktree. Added `/state/tasks.json.lock` to the repo root `.gitignore` (the installed-layout
  `.harness/.gitignore` entry is unchanged).
- **Canonical board + lock across git worktrees (Codex #46 r4 P1, id 3649274119).** The E15
  F02/F03 parallel-fix flow runs each fix in its OWN linked git worktree. Previously
  `tools/tasks-lock.py` resolved the board (and its lockfile) relative to whatever worktree it
  ran in, so each worker read/wrote a **different** worktree-local `state/tasks.json` and contended
  on a **different** `state/tasks.json.lock` inode — the `flock` did not serialize cross-worktree
  writers, so R1's no-lost-update guarantee was absent in exactly the scenario the epic targets.
  The helper now resolves **both** the board and the lockfile to the **single canonical location in
  the MAIN working tree**: precedence is (1) explicit `HARNESS_DIR` override, else (2) when inside a
  git repo/worktree, the main worktree root via `git rev-parse --git-common-dir` (its parent),
  re-applying the source-vs-installed subpath (computed relative to `git rev-parse --show-toplevel`)
  under that root, else (3) the prior `__file__` self-location. Git runs via `subprocess` with the
  helper's own directory as cwd and a bounded timeout; **any** git failure (not a repo, git absent,
  timeout, unexpected layout) degrades to (3) — never crashes, never blocks. Every worker in every
  worktree now shares one board and one lock inode, so concurrent writers from different worktrees
  cannot lose an update.
- **Locate the status token STRUCTURALLY by id, not by textual key order (Codex #46 r4 P2, id
  3649274120).** The minimal-diff `set-status` writer found the target's status as the first
  `"status"` at-or-after the `"id"` match. JSON imposes no key order, so a board that orders
  `status` **before** `id` in an object made the patch land on the **next** object's status —
  silently transitioning the wrong task while validation still passed. The writer now resolves the
  addressed object **structurally by id**: it anchors on the unique `"id": "<target>"`, delimits
  THAT object's character span with a brace-aware, string-literal-aware scan, and replaces only the
  `status` value token that lives at object depth 1 inside that span (a nested slice's status is
  never mistaken for the object's own). The minimal-diff property is preserved (only the addressed
  status token changes; unrelated inline arrays/formatting untouched) and the reparsed result is
  still schema-validated through the shared `tools/validate-board.py` before the atomic `os.replace`.
- **Run git worktree discovery from INSIDE the worktree in the source layout (Codex #46 r5 P1, id
  3649327432).** The canonical-board resolution (id 3649274119) ran both `git rev-parse` calls with
  `os.path.dirname(self_dir)` as cwd. In the **installed** layout the self-located harness dir is
  `<root>/.harness`, whose parent (`<root>`) is still inside the repo, so discovery worked and the
  R12 test passed. In the **source** layout the harness dir **is** the worktree toplevel, so its
  parent is the repo's PARENT — git ran OUTSIDE the worktree, `--git-common-dir` / `--show-toplevel`
  failed (or resolved a different repo), and the helper fell back to the LINKED worktree's own board;
  `set-status` then mutated only the linked copy while the MAIN board stayed unchanged, defeating the
  shared-board/shared-lock guarantee (R12) in the exact parallel-worktree scenario. Git discovery now
  runs from `os.path.dirname(os.path.abspath(__file__))` (the helper's `tools/` dir), which is inside
  the current worktree in **both** layouts, so source and installed resolve the main worktree
  identically. The R12 behavioural test now also covers the source layout (harness dir == worktree
  toplevel) with a real linked `git worktree`, asserting the transition lands on the MAIN board and
  contends on the MAIN `state/tasks.json.lock`; it fails against the old `dirname(self_dir)` cwd and
  passes after the fix.
- **`init.sh` rejects installs that can't run the lock helper (Codex #46 r6 P1, id 3649368481).**
  Since this feature makes `python3 tools/tasks-lock.py` the **mandatory** `set_status` write path,
  a python3-less install that previously warned-and-continued (`⚠️ python3 not found — skipping …`)
  would report "environment ready" yet fail on the first Orchestrator transition with
  `python3: not found`. The local-backend gate now **hard-fails** (non-zero, clear message) when
  `python3` is absent, and additionally verifies the stdlib **`fcntl`** module the lock helper needs
  is importable — so an unsupported interpreter is caught at `init.sh` time, not mid-transition.
  `tests/test_board_lock.sh` gains a case that runs `init.sh` under a python3-less `PATH` and asserts
  the non-zero exit with a message naming python3 and the reason.
- **Preserve the TaskStore file mode across the atomic replace (Codex #46 r6 P2, id 3649368484).**
  The guarded write created a fresh temp file (per the process umask) and `os.replace`d it in, which
  reset the board's permission bits — silently widening a `0600` board to `0644` (exposing data) or
  narrowing a shared `0664` board (breaking another account's later writes). The helper now copies
  the original board's mode (`stat.S_IMODE(os.stat(board).st_mode)`) onto the temp file **inside the
  lock, before the replace**, preserving fail-stop semantics. `tests/test_board_lock.sh` asserts a
  `0600` board stays `0600` and a `0664` board stays `0664` across a `set-status`.
- **Fail SAFE on canonical-board resolution; never a silent wrong-board write (Codex #46 r6 P1, id
  3649368478).** Under `git init --separate-git-dir` or a submodule, the main worktree path is
  **provably unrecoverable** from a linked worktree (`git rev-parse --git-common-dir` reports the
  separate metadata dir, whose parent is not the main worktree, and git stores no back-pointer to
  the primary working tree). The previous auto-discovery either resolved `HARNESS_DIR` to the
  boardless metadata dir (`board not found`) or silently fell back to the linked worktree's OWN
  board — a silent wrong-board write defeating the shared-board guarantee. Resolution is now
  strict-precedence and fail-safe: **(1)** explicit `HARNESS_DIR` override [highest precedence, set
  by the F03 `/sdd-fix-parallel` coordinator]; **(2)** best-effort auto-discovery for the standard
  `.git` worktree layout — **accepted only when the canonical board actually exists** there
  (`<canonical>/state/tasks.json`); **(3)** otherwise, when running inside a **linked** worktree,
  a **loud non-zero fail** with an actionable message demanding an explicit `HARNESS_DIR` (never a
  silent fall-back to the linked worktree's own board), while the ordinary non-worktree / serial
  `/sdd-next` case keeps the `__file__` self-location. Standard-layout worktrees still auto-resolve;
  exotic layouts fail safe; the coordinator's `HARNESS_DIR` injection makes ALL layouts correct.
  `tests/test_board_lock.sh` gains **R12sgd**: from a `separate-git-dir` linked worktree, a
  `set-status` with **no** `HARNESS_DIR` exits non-zero with the actionable message while the main
  board AND the linked worktree's own board stay byte-unchanged, and the same call **with**
  `HARNESS_DIR=<main>` (the coordinator path) lands on the main board. The spec's **R12** and the
  F03 brief (`progress/inbox/E15-F03.md`) are updated to require the coordinator to inject
  `HARNESS_DIR`.
- **Distinguish linked worktrees from separate-git-dir primaries (Codex #46 r7 P2, id 3649430729).**
  `_in_linked_worktree()` detected a linked worktree by comparing the common `.git` dir's **parent**
  with the worktree toplevel. But a **PRIMARY** checkout made with `git init --separate-git-dir`
  (or a submodule primary) also keeps its common dir OUTSIDE the working tree, so that comparison
  returned `true` and misclassified the primary as linked — combined with a failed canonical
  board-existence check, ordinary **serial** `set-status` then exited demanding `HARNESS_DIR`, so
  plain serial orchestration could not transition tasks in that layout without an undocumented
  override. Detection now compares `git rev-parse --git-dir` with `git rev-parse --git-common-dir`
  (both realpath-normalized): **equal ⇒ any primary checkout** (colocated, separate-git-dir, or
  submodule) ⇒ NOT linked ⇒ the serial self-location fallback applies with no spurious `HARNESS_DIR`
  demand; **distinct ⇒ a genuine linked worktree** ⇒ the existing loud-fail-if-no-canonical-board
  behavior is unchanged. Any git failure still degrades to not-linked / self-location — never
  crashes, never blocks. `tests/test_board_lock.sh` gains **R12sgdp**: a `separate-git-dir` PRIMARY
  checkout runs `set-status` with **no** `HARNESS_DIR` and must succeed and transition its own board
  (fails on the old parent-comparison logic, passes on the git-dir-vs-common-dir logic); the R12sgd
  linked-worktree loud-fail and the R12wt/R12src worktree cases stay green.
- **Common-dir remapping is now reserved for genuine linked worktrees (Codex #46 r8 P1, id
  3649460575).** `_canonical_harness_dir()` ran the `--git-common-dir` → main-worktree-root remap
  unconditionally, including for **PRIMARY** checkouts. In a primary made with
  `git init --separate-git-dir`, the parent of the (external) metadata dir is an **unrelated**
  directory — and if that directory happened to hold another harness board, the
  board-existence check ACCEPTED it as canonical, so `set-status` silently mutated that unrelated
  board while the real checkout stayed stale (reproduced: checkout still `pending`, metadata-parent
  board flipped to `in-progress`). A primary checkout already **is** the main working tree and has
  nothing to remap, so the remap is now gated on `_in_linked_worktree()`: primaries always
  self-locate, and common-dir remapping applies only to a genuine linked worktree. Cross-worktree
  canonical resolution (R12wt/R12src), the separate-git-dir linked loud-fail (R12sgd) and the
  separate-git-dir primary serial path (R12sgdp) are unchanged. `tests/test_board_lock.sh` gains
  **R12sgdx**: a `separate-git-dir` primary whose metadata dir sits **inside a decoy harness dir
  with its own board** must transition its OWN board and leave the decoy byte-unchanged with no
  lockfile created there (fails on unconditional remapping, passes once gated).
- **`python3` documented as a local-backend prerequisite in `AGENTS.md` (Codex #46 r8 P2, id
  3649460576).** The r6 P1 turned `init.sh`'s python3 check from warn-and-continue into a hard
  fail, which — because rule 1 halts all work on a non-zero `init.sh` — makes python3 a
  prerequisite for *any* harness work on the local backend, not just for locked status writes. The
  breaking dependency change was recorded here but not on the entrypoint agents actually read;
  `AGENTS.md` rule 1 now states the `python3` + stdlib `fcntl` requirement, when it became
  mandatory, and the remedy.
- **Invoke the Bash-only `init.sh` with `bash` in the R14py3 test (Codex #46 r9 P1, id
  3649498024).** `tests/test_board_lock.sh` ran the python3-less gate check as `sh ./init.sh`.
  `init.sh` declares `#!/usr/bin/env bash` and uses `set -o pipefail`, so wherever `/bin/sh` is
  **dash** — typical Ubuntu CI — the shebang is bypassed and the script aborts at line 8 with
  `Illegal option -o pipefail`, **never reaching the python3 gate**. The run still exited non-zero
  (so the must-fail assertion passed vacuously) but printed no python3 message, so the two message
  greps failed and the configured `test_board_lock.sh` suite went **red on CI while passing on
  macOS**, where `/bin/sh` is bash in POSIX mode and does support `pipefail`. The case now invokes
  `bash ./init.sh` and additionally requires `bash` to be reachable through the PATH shim (else it
  skips cleanly). Verified by reproducing the dash condition: `sh` → `Illegal option -o pipefail`
  with zero python3 mentions; `bash` → the exact hard-fail message the assertions expect.
- **Restrict id resolution to real task objects (Codex #46 r9 P2, id 3649498027).** The
  minimal-diff writer anchored on the **first textual** `"id": "<target>"` in the whole document.
  The board schema permits additional properties, so a board may carry an extension object (a
  mirror record, a cache entry) whose `id` equals a real feature or epic id; if it appeared earlier
  in the file and had a `status`, `set-status` silently updated **that** object and left the
  addressed task unchanged — and the result still schema-validated, so nothing surfaced the wrong
  write. Resolution now **walks the board structurally** — root → `epics[]` elements → each epic's
  `features[]` elements, matching only a **direct** `id` member at each level — so only a genuine
  epic or feature is addressable and anything outside those two arrays is invisible. The string
  mask backing the brace/bracket scans is computed once per resolution and threaded through
  (previously recomputed per call), keeping resolution linear rather than quadratic on large
  boards. `tests/test_board_lock.sh` gains **R13ext**: a board with colliding-id extension objects
  both **before** `epics` and **nested inside** the epic must transition the real feature (and the
  real epic), leave both decoys `synced`, and still change exactly one status token.
- **Duplicate `status` member fails STOP instead of silently no-opping (Codex #46 r10 P2, id
  3649544829).** JSON permits duplicate members and `json.loads` keeps the **last**, while a
  first-match text patch rewrites the **first** — so on such a board the helper exited 0 having
  persisted a file whose **effective** status never changed, and post-write validation still
  passed. The sole supported write path could therefore silently drop a requested transition. The
  writer now refuses to patch an object carrying more than one direct `status` member, exiting
  non-zero with a message naming the id and the count, board byte-unchanged (R4 semantics).
  Relatedly, object **selection** now reads a duplicated `id` as its **last** value, matching
  `json.loads`, so the text walk can never select an object whose effective id differs.
  `tests/test_board_lock.sh` gains **R13dup**.
- **Preserve board ownership across the atomic replace (Codex #46 r10 P2, id 3649544831).** The
  mode copy added in r6 carried permission bits but not ownership. In a multi-account checkout the
  board is group-owned so several accounts can write it via the `0664` group bit; without setgid
  inheritance on the directory the temp file takes the **current** writer's group, so `os.replace`
  silently re-grouped the board and locked the other accounts out of the mandatory write path. The
  helper now also copies the original `st_uid`/`st_gid` onto the temp file inside the lock.
  Best-effort by construction — `chown` is privileged in the general case, so an `EPERM` refusal
  (or a platform without it) is swallowed rather than failing the write; the mode copy already
  covers the common single-owner case.
- **Document the linked-worktree fail-loud branch in `store/local.md` (Codex #46 r10 P2, id
  3649544832).** The local-backend contract still described resolution as "works from any worktree,
  resolves the main board automatically", which no longer matched the fail-safe behavior: from a
  **linked** worktree under `separate-git-dir`/submodule layouts the helper deliberately exits
  non-zero demanding an explicit `HARNESS_DIR`, so anyone driving it by hand outside the
  `/sdd-fix-parallel` coordinator hit an undocumented hard failure. The contract now states the
  corrected precedence (primary checkouts are never remapped — they already *are* the main working
  tree), the one case that exits non-zero, and the `HARNESS_DIR=…` invocation that resolves it.

## [0.30.0] — 2026-07-10

### Added — ✨ Jira mirror completed via REST API + Bearer PAT, no MCP (E12-F01)
- **Filled the recognized `jira` stub** in `tools/sync-board.mjs` (rather than forking a
  second Jira code path): the shared `jira`/`azure-boards` stub is split so `azure-boards`
  stays a recognized no-op stub while `jira` runs a real one-way projection of
  `state/tasks.json` onto a Jira **Server / Data Center** project. Transport is the **Jira
  REST API only** (`/rest/api/2/…`, dependency-free built-in `fetch`), authenticated with an
  `Authorization: Bearer <PAT>` header — **never MCP**, so it works inside MCP-restricted
  enterprises. Jira **Cloud** (Basic auth) is out of F01 scope, documented as a future
  extension.
- **PAT hygiene** — the PAT is resolved from the **`JIRA_PAT`** env var (precedence) else a
  gitignored **`pat_file`** (default `jira.pat`, resolved under the harness dir ⇒
  `.harness/jira.pat` in a consumer, trimmed); it is **never** written to
  `state/tasks.json`, `harness.config.yaml`, logs, or any committed file. Config
  (`base_url`/`project_key`) is validated and the PAT resolved **before** any network call
  (fail-closed); a missing PAT or missing config exits non-zero naming the requirement, and a
  Jira **401/403** exits non-zero with an actionable, PAT-free message.
- **Configurable mapping** — harness epics → Jira **Epic** and features → **Story** by
  default, overridable via `mirror.board.issue_type_map`; feature status → Jira workflow state
  via the provider-neutral `mirror.board.status_map` (identity default), transitioned in
  place. Reconcile is **idempotent** (each feature matched by a stable `harness:<id>` label —
  a re-run updates rather than duplicating). `assignee` is a recognized **no-op for `jira`**
  in F01 (owner→assignee deferred to E10-F03). `--dry-run` prints intents and mutates nothing.
- **Hardened PAT log hygiene + transition matching (Codex #44 r2 P2 ×2)** — Jira response
  bodies for **non-401/403** errors are now scrubbed via a `redactSecret(text, PAT)` helper
  before hitting stderr, so a bad-URL / debug-proxy body that echoes the `Authorization`
  header can never print `Bearer <PAT>` (redacted to `Bearer ***REDACTED***`). Status
  transitions are now matched by **destination `to.name === wantState` only** (the
  match-by-action-`name` fallback is removed): a transition whose action name matches but
  lands on a different state can no longer be selected, and when nothing lands on the mapped
  state the issue is left unchanged with a "no matching transition" report instead of a false
  success.
- **Config seed + gitignore** — `harness-install.sh` seeds the inert Jira `mirror.board` keys
  (`base_url`/`project_key`/`pat_file`/`issue_type_map`) and append-seeds the default PAT-file
  path into `.harness/.gitignore` so a provisioned PAT can never be committed by default;
  `tests/test_install.sh` asserts the executable tool ships and the PAT file is gitignored.
- **Docs pinned** — `store/board-mirror.md` gains a **jira contract** section (Server/DC REST
  + Bearer PAT, Cloud out of scope, `JIRA_PAT`/`pat_file` precedence, issue-type + status
  maps, REST-only / no-MCP, one-way, assignee deferral); `store/jira.md` cross-references it
  and clarifies the implemented **mirror** vs the still-stub **backend**.
- **Regression guardrails** — `tests/test_mirror.sh` gains behavioral `jira` cases against a
  stubbed recording REST endpoint (REST-only / no-MCP, single code path, Bearer PAT header,
  env/file PAT precedence, fail-closed missing-PAT/missing-config, idempotent reconcile,
  issue-type + status maps, assignee no-op, one-way, `--dry-run`, 401/403, PAT-never-leaks,
  docs pin). Assertions are behavior/shape only — no exact-VERSION pin and no diff of
  DO-NOT-TOUCH files against `main`.
- **Optional `mirror.board.epic_name_field`** (Codex #44 P2) — an additive, inert-by-default
  Jira Server/DC "Epic Name" custom field id (e.g. `customfield_10011`). When set, the epic
  `POST /issue` payload carries it (= the epic summary) so Server/DC projects that require
  Epic Name on the create screen don't 400 and halt the sync; empty/absent ⇒ omitted
  (unchanged default). Epic-only, create-only. Seeded inert in `harness.config.yaml` +
  `harness-install.sh`, documented in `store/board-mirror.md`, guarded by `tests/test_mirror.sh`.

## [0.29.0] — 2026-07-10

### Added — ✨ GitHub Projects (v2) mirror completed via `gh` CLI, no MCP (E11-F01)
- **Strengthened fail-closed preflight** in `tools/sync-board.mjs` for the `github-projects`
  provider — before any board-mutating call it verifies `gh` is present, is at least
  `2.31.0` (the first release with stable `gh project` Projects-v2 subcommands), and that its
  token carries the required `project` + `repo` scopes (via `gh auth status`). Any failure
  exits non-zero with an actionable message naming `gh` and the Projects-v2 / scope
  requirement, so a preflight failure never leaves the board half-written. Transport stays
  **`gh` CLI only — never MCP**; the inert-default (empty provider ⇒ no `gh` contact) and the
  config-first validation order are preserved.
- **Pinned contract in docs** — `store/board-mirror.md` now states the supported surface is
  **GitHub Projects (v2)** (Classic unsupported), names the minimum `gh` version (`2.31.0`)
  and the `project` + `repo` auth scopes, and reaffirms the `gh`-only / no-MCP transport and
  the one-way (`tasks.json` → board; agents never read the board) invariant.
- **Installer wiring asserted** — `tests/test_install.sh` now asserts a fresh install ships an
  **executable** `.harness/tools/sync-board.mjs` (the mirror tool was already copied +
  `chmod +x`'d by `harness-install.sh`; the assertion closes the wiring gap).
- **Regression guardrails** — `tests/test_mirror.sh` gains behavioral cases for the preflight
  (absent / too-old / under-scoped `gh` ⇒ non-zero, names `gh`, no board mutation), gh-only /
  no-MCP dispatch, single `github-projects` code path, idempotent reconcile, `--dry-run`
  mutates nothing, the one-way invariant (fixture-local `tasks.json` snapshot), and the docs +
  no-new-config-key checks. Assertions are behavior/shape only — no exact-VERSION pin and no
  diff of DO-NOT-TOUCH files against `main`.
- **Scope note** — F01 projects **status** only; the pre-existing `mirror.board.assignee`
  behavior is preserved untouched (no `owner → assignee` expansion — that is E10-F03).

## [0.28.0] — 2026-07-10

### Added — ✨ Ownership primitive: `owner` field in TaskStore + scoped `/sdd-next --mine` (E10-F01)
- **Optional `owner` field on epics and features** — `store/tasks.schema.json` now defines an
  optional string `owner` on both epic objects and feature objects. It is **additive and
  backward-compatible**: `owner` is not in any `required` array, so existing owner-free
  `state/tasks.json` files validate unchanged and no migration is needed.
- **Effective owner (feature wins)** — a feature's effective owner is its own `owner` when set,
  else its parent epic's `owner`, else unowned. Documented in `agents/orchestrator.md`,
  `docs/WORKFLOW.md`, and `store/local.md`.
- **Scoped `/sdd-next --mine`** — the Orchestrator contract adds an "Ownership & scoped
  selection" subsection: `--mine` selects only features whose effective owner equals the
  identity resolved from `workflow.identity` (`@me`/`self` → authed `gh` user via `gh api
  user`; else literal). Scoping is a filter layered on top of the existing `next()` gates —
  it never relaxes a gate. It is **owned-only** (no claim-on-select — that is E10-F02) and
  **fails closed** (unresolved identity or no owned actionable work ⇒ report + no state change,
  never widen to board-wide). Bare `/sdd-next` is unchanged board-wide selection.
- **`workflow.identity` config key** — new optional key in `harness.config.yaml` (empty default
  ⇒ solo/board-wide, today's behavior).
- **Installer wiring** — `harness-install.sh` generates the `--mine` scoped-selection front-end
  into every selected target's `/sdd-next` glue (Claude/OpenCode/Antigravity/Codex), byte
  identical; `tests/test_install.sh` asserts the wiring. New `tests/test_ownership.sh` behavior
  suite added to `verification.test_command`.
- The board mirror stays **one-way** — no agent reads the board for ownership; `state/tasks.json`
  is the single source of truth (invariant preserved).
- `VERSION` bumped 0.27.3 → 0.28.0 (installed body changed; **MINOR** per the versioning policy —
  additive/backward-compatible).

## [0.27.3] — 2026-07-10

### Fixed — 📝 Align draft-epic docs + re-validate after driller approval mutation (E09)
- **Driller re-validates after the approval mutation** — `agents/driller.md` R10 now states
  re-validation of `state/tasks.json` runs both **after seeding AND after the approval-branch
  mutation** (the `draft → planned` flip + `autonomous` stamp). That final post-mutation
  validation gates the completion report: a malformed state flip/stamp can no longer be
  reported as a successful drill. `tests/test_sdd_drill.sh` R10 asserts the post-mutation
  re-validation requirement.
- **WORKFLOW draft definition realigned to the drillable-minimum contract** — the epic
  lifecycle `draft` bullet in `docs/WORKFLOW.md` replaced the stale "title + business brief
  only" wording with the drillable-minimum five elements (matching `agents/planner.md`), so
  role files and workflow docs give coherent canonical guidance. `tests/test_sdd_plan.sh` R21
  asserts the coherence (drillable-minimum present, no stale "brief only").
- `VERSION` bumped 0.27.2 → 0.27.3 (installed body changed; PATCH per the versioning policy).
  Fixes Codex #39 r3 P2/P2.

## [0.27.2] — 2026-07-10

### Fixed — 🔒 Harden doc-critic write access + exact-line gitignore seeding (E09)
- **doc-critic granted `Write`** — the emitted `.claude/agents/doc-critic.md` shim now
  carries `Read, Grep, Glob, Write` (was read-only). The role writes an auditable
  `progress/<run>/doc-critic-<checkpoint>.md` note (R7); without `Write` the checkpoint
  left no file-based handoff. `Write` is the minimal, most-scoped grant (no Edit/Bash).
- **exact-line matching for seeded root `.gitignore` ignores** — the append-only loop now
  uses `grep -qxF` (whole-line) instead of `grep -qF` (substring), so a pre-existing
  `.gitignore` that mentions `AGENTS.local.md`/`CLAUDE.local.md`/`AGENTS.override.md`
  (or `.claude/settings.local.json`) only in a comment or negation still gets the real
  ignore line appended — a personal override can no longer slip through uncommitted.
- **Regression assertions** added to `tests/test_install.sh` for the doc-critic `Write`
  grant and the exact-line gitignore seeding (a comment-only mention still gets the real
  ignore added). `VERSION` bumped 0.27.1 → 0.27.2 (installed body changed; PATCH per the
  versioning policy). Fixes Codex #39 r2 P2/P3.

## [0.27.1] — 2026-07-10

### Fixed — 🔧 Wire the doc-critic checkpoint into the installer-generated glue (E09)
- **doc-critic spawnable in the installed Claude workflow** — `harness-install.sh` now
  emits a `.claude/agents/doc-critic.md` subagent shim (pointing at the canonical
  `.harness/agents/doc-critic.md`) and adds the `Task` tool to the emitted `architect`
  shim, so the advertised pre-`spec-ready` `target-type=feature-spec` checkpoint is
  actually executable on the primary `/sdd-next` path. `doc-critic` is added to
  `HARNESS_CLAUDE_SHIMS` so it participates in scoped deselect removal.
- **doc-critic mirrored into every front-end registry** — the OpenCode `opencode.json`
  agent set and the Antigravity `.agents/agents/` persona set now include `doc-critic`,
  keeping all front-ends consistent with the Claude shims.
- **`/sdd-plan` glue mirrors the drillable-minimum + checkpoint** — the installed
  `/sdd-plan` command body now requires the five drillable-minimum `epic.md` elements
  (business brief, epic-level success criteria, technical considerations/non-goals,
  cross-epic dependencies and boundaries, pointers to relevant shared ADRs) and runs the
  `target-type=plan-output` doc-critic checkpoint before re-validation; `/sdd-drill`
  likewise runs its `target-type=epic-decomposition` checkpoint.
- **Regression assertions** added to `tests/test_install.sh` for the doc-critic shim,
  the architect `Task` tool, the antigravity `doc-critic` persona, and the `/sdd-plan` +
  `/sdd-drill` drillable-minimum + checkpoint glue. `VERSION` bumped 0.27.0 → 0.27.1
  (installed body changed; PATCH per the versioning policy). Fixes Codex #39 r1 P1/P2.

## [0.27.0] — 2026-07-10

### Added — ✨ Per-developer local prompt override convention (E09-F02)
- **Generated entrypoint guidance** — `AGENTS.md`, `CLAUDE.md`, and `GEMINI.md` managed
  marker blocks now mention the optional `AGENTS.local.md` local prompt override. The
  guidance is conditional, additive, and states that committed instructions remain
  authoritative on conflict.
- **Installer ignore seeding** — project-root `.gitignore` seeding now includes
  `AGENTS.local.md`, `CLAUDE.local.md`, and `AGENTS.override.md` through the existing
  append-only/idempotent seed path, preserving user-authored ignore entries.
- **Docs and examples** — `docs/CONFIG-LAYERING.md` documents the personal prompt layer,
  native local files for Claude Code and Codex, fresh worktree caveats, and per-tool
  local-file differences. `umbrella.gitignore.example` includes the same local prompt
  ignore entries for shared-spec repository roots.
- **Verification** — `tests/test_install.sh` covers local prompt ignore seeding,
  idempotence, generated entrypoint wording, docs coverage, umbrella example parity, and
  this SemVer MINOR bump. `VERSION` bumped 0.26.0 → 0.27.0.

## [0.26.0] — 2026-07-10

### Added — ✨ Doc-critic: advisory review pass over harness-generated docs (E09-F01)
- **New portable Doc-critic role (`agents/doc-critic.md`)** — an automated, advisory
  sub-agent that reviews harness-generated planning documents and specs at three defined
  checkpoints. It accepts a `target-type` argument (`plan-output`, `epic-decomposition`,
  `feature-spec`) and flags only issues that would cause real downstream problems across
  completeness, consistency, clarity, scope, and YAGNI. Findings are advisory only: the
  generating agent applies fixes inline and proceeds, with a short note to `progress/<run>/`.
  On error or timeout the agent proceeds best-effort and records the skipped pass.
- **Planner checkpoint (`/sdd-plan`)** — after writing vision, architecture, ADRs, and
  seeded `epic.md` files, the Planner spawns the Doc-critic with `target-type=plan-output`
  and applies inline fixes. Each seeded `epic.md` must carry the drillable-minimum:
  business brief, epic-level success criteria, technical considerations / restrictions /
  non-goals, cross-epic dependencies and boundaries, and pointers to relevant shared ADRs.
- **Driller checkpoint (`/sdd-drill`)** — after decomposing the epic (feature entries,
  `epic.md` feature table, inbox briefs, ADR deltas), the Driller spawns the Doc-critic
  with `target-type=epic-decomposition` and applies inline fixes.
- **Architect checkpoint (before `spec-ready`)** — after drafting a feature's four-file
  spec, the Architect spawns the Doc-critic with `target-type=feature-spec` and applies
  inline fixes before handing off to the human gate.
- **Installer wiring** — `agents/doc-critic.md` is copied into `.harness/agents/` on every
  install/upgrade via the existing `copy agents` step.
- **Verification** — `tests/test_doc_critic.sh` covers R1–R18 (static grep contract
  assertions over the role and checkpoint wiring); `tests/test_install.sh` asserts the
  role is installed and the Planner/Driller/Architect contracts reference it. Wired into
  `verification.test_command`.
- **Docs** — `docs/WORKFLOW.md` gains a distinct `## Doc-critic checkpoints` section
  documenting the three checkpoints and the advisory/inline-fix/best-effort nature.
- Purely additive: no change to `store/tasks.schema.json`, no new status value, no new
  human gate, and no retro-fit of existing specs. `VERSION` bumped 0.25.0 → 0.26.0.

## [0.25.0] — 2026-07-01

### Added — ✨ Codex CLI front-end (`codex` agent key)
- **`codex` is now a selectable front-end (`harness-install.sh`).** Added to `AGENT_KEYS`
  (`claude gemini opencode antigravity codex`), so it appears in the interactive picker,
  is individually selectable via `--agents=codex` / `HARNESS_AGENTS`, and persists to
  `.harness/.agents` like every other agent.
- **GLOBAL `/sdd-*` prompts (§5d).** Codex CLI has no project-local custom-command
  mechanism, so its only slash-command surface is the machine-global prompts dir
  `${CODEX_HOME:-$HOME/.codex}/prompts/`. When `codex` is selected the installer stamps
  the five `sdd-next`, `sdd-new`, `sdd-plan`, `sdd-drill`, `sdd-fix` prompt bodies
  there — byte-identical to the Claude/OpenCode/Antigravity copies (same `CMDDIR` source).
  Codex surfaces each `<name>.md` as the slash command **`/prompts:<name>`** (namespaced
  under `/prompts:`, not top-level `/<name>`). This is the one front-end whose glue lands
  **outside** `$TARGET`; the bodies resolve their paths against `.harness/` of whatever
  repo Codex launches in, so a single global copy drives every target. Honors `$CODEX_HOME`,
  and when neither `CODEX_HOME` nor `HOME` is set (minimal CI) the Codex step is skipped
  with a warning instead of aborting the install under `set -u`.
- **No new entrypoint pointer.** Codex reads the always-written `AGENTS.md` from the repo
  root natively, so a `codex`-only install needs no dedicated entry file.
- **Non-destructive install.** The global prompts dir is a user-owned namespace, so a
  same-named file that differs from the harness body — an original OR a later user edit —
  is backed up to `<name>.md.pre-harness.bak` and warned about before the harness copy is
  written. The backup refreshes whenever the current contents change, so a post-install
  edit is captured too (never silently lost); a routine re-install where the file is
  already the identical harness body neither warns nor churns the backup.
- **Pristine-only deselect (§7).** Dropping `codex` reclaims only byte-pristine global
  prompts (a user-edited `/prompts:sdd-*` prompt survives), mirroring the `opencode.json` /
  Antigravity `cmp -s` contract, and prunes the prompts dir only when empty.
- **Tests (`tests/test_install.sh`).** Sandboxes `CODEX_HOME` for the whole suite (never
  touches the real `~/.codex`); adds `--agents=codex` (global-prompts-only + byte-identical
  to peers) and codex-deselect (pristine reclaim, edit-preserving, warns) cases; extends the
  ALL-default and registry-key coverage to include `codex`.

## [0.24.0] — 2026-07-01

### Added — ✨ Board mirror: status-gated issue assignee (`mirror.board.assignee`)
- **`assignee` config key (`tools/sync-board.mjs`)** — the board mirror can now fill the
  provider's assignee/owner field from a new, provider-neutral `mirror.board.assignee` key.
  Assignment is **status-gated**: when `assignee` is set the mirror **owns** the Assignees
  field for its items and reconciles it to the exact desired set every sync — a started item
  (`in-progress`/`in-review`/`done`) ends up with *exactly* the configured login (any other
  assignee removed), a not-started one (`pending`/`spec-ready`) with none — so the board
  reflects who owns each item *right now* and a teammate's stale assignment from a shared
  `@me` sync is cleared whether the item is in flight or regressed. Empty (the default) ⇒ the
  mirror never touches assignees, so a preserved config behaves exactly as before. Implemented
  for the `github-projects` provider; the `jira`/`azure-boards` stubs ignore it until wired.
- **Dynamic `"@me"` resolution** — `assignee: "@me"` (or `"self"`) resolves at sync time to
  the authed `gh` user via `gh api user`, so a shared-repo config reflects whoever runs the
  sync instead of hard-coding one login. Resolution failure degrades to "skip assignment this
  run" rather than erroring, and assignment is idempotent (the API call is skipped when the
  item already has the right assignee).
- **Docs + template parity** — `store/board-mirror.md` documents the key as provider-neutral
  (each tracker maps it to its own assignee/owner field) and the stub-provider guide tells
  new providers to honor it; `harness.config.yaml` and the installer's `migrate_config` mirror
  template both gain the commented `assignee: ""` default (append-only, existing configs
  preserved). `tests/test_mirror.sh` gains coverage: `@me` resolution + status-gated
  assign/unassign, and the assignee-unset back-compat no-op. **`VERSION` 0.23.1 → 0.24.0**
  (MINOR: new backward-compatible capability). Upstreamed from a downstream install so the
  canonical body now owns it and future upgrades no longer clobber a hand-carried copy.

## [0.23.1] — 2026-07-01

### Added — ✨ claude-mem-context block
- **Memory context block (`AGENTS.md`)** — adds `claude-mem-context` to the orchestrator documentation to maintain memory of recent context.

## [0.23.0] — 2026-06-12

### Added — ✨ Installer agent picker: arrow-key + spacebar checkbox UI (E99-F01)
- **Cursor-driven checkbox picker (`harness-install.sh` `tui_select`)** — on a raw-capable
  interactive TTY the agent front-end selector now renders the four agent keys
  (`claude gemini opencode antigravity`) as a checkbox list: ↑/↓ (or `k`/`j`) move a `>`
  cursor, **Space** toggles the highlighted row's `[x]`/`[ ]`, **Enter** confirms (`q`/Esc
  also confirm the current selection). This replaces the awkward type-a-number toggle model
  as the preferred interactive path. Pre-check state still seeds from the saved
  `.harness/.agents` set (or ALL on a fresh install), and only the resolved sorted keys
  (one per line) reach stdout, so the captured `SELECTED` contract is unchanged.
- **Graceful fallback (`tui_capable`)** — a capability probe detects whether `stty` can save +
  enter + restore raw mode on an interactive TTY. When raw mode is unavailable (no `stty`,
  non-interactive / piped stdin, sandboxed), `resolve_agents` falls back to the existing
  numbered `toggle_select`. The install never hard-fails on a terminal that can't do raw mode.
- **Guaranteed terminal restore** — raw mode is entered with `stty` and UNCONDITIONALLY
  restored via an `EXIT`/`INT`/`TERM` trap (plus an explicit restore on the normal completion
  path), so Ctrl-C or quitting never leaves the user's terminal stuck in raw mode; the cursor
  is re-shown too. All prompts/UI go to **stderr**.
- **No behavior change off the interactive path** — the no-TTY "ALL agents" default and the
  `--agents=` / `HARNESS_AGENTS=` override path are untouched; the picker only changes the
  interactive presentation. Portable POSIX sh, **no new binary dependencies**. `VERSION`
  bumped 0.22.0 → 0.23.0 (MINOR). `tests/test_install.sh` gains an E99-F01 group asserting the
  picker + capability probe + fallback wiring (the numbered fallback is what the suite
  exercises non-interactively). `tests/test_sdd_fix.sh` R17 now checks the installer-SEEDED
  store (throwaway target) for "no pre-seeded E99" instead of the mutable live
  `state/tasks.json`, which this repo legitimately populates while dogfooding its own
  `/sdd-fix` lane (permanent-suite anti-pattern fix). No canonical `agents/*.md` role file is
  touched.

## [0.22.0] — 2026-06-12

### Added — ✨ Antigravity native support
- **Antigravity glue (`harness-install.sh` §5c)** — Google Antigravity (a Gemini-based
  agentic IDE) is now a first-class, selectable harness target. On every run (gated on the
  `antigravity` agent key), the installer stamps a workspace-local `.agents/` tree that POINTS
  at the canonical `.harness/agents/*.md` roles — it never forks, copies, or redefines a role
  body. Antigravity natively reads `<root>/.agents/{rules,agents,workflows}/*.md` (plural —
  the dir its current build scans).
- **Entrypoint rule (`.agents/rules/harness.md`)** — a thin rule that loads the harness for an
  Antigravity session (Antigravity does not auto-load `AGENTS.md`): it points at
  `.harness/AGENTS.md` (source of truth) and `.harness/agents/orchestrator.md` (entry role),
  mandates `.harness/init.sh` first, and documents the working model. The root `GEMINI.md`
  pointer block (already written by §4) also serves Antigravity as the in-repo entrypoint.
- **Personas (`.agents/agents/{orchestrator,architect,builder,reviewer,scout}.md`) —
  best-effort** — one per harness role, each carrying a `description` and a body that
  defers to `.harness/agents/<role>.md`, runs `.harness/init.sh` first (halt on non-zero), and
  hands off via `.harness/progress/` files — no copied role body. Bare-file persona discovery
  is unconfirmed, so the personas are written (cheap, possibly honored) but the harness does
  NOT claim they register as Antigravity subagents.
- **Workflows (`.agents/workflows/{sdd-next,sdd-new,sdd-plan,sdd-drill,sdd-fix}.md`)** — the
  same five SDD slash commands, COPIED from the shared command bodies (mirroring the OpenCode
  block) so they stay byte-identical to the Claude/OpenCode copies and never drift. Each
  already carries the `description` frontmatter Antigravity needs to register `/<name>`.
- **Durable working model** — the confirmed primitives are the `.agents/rules/` entrypoint rule
  + the `description`-gated `.agents/workflows/` slash commands + `.harness/progress/` files as
  the hand-off / isolation boundary (not a Task-tool-style spawn, not an asserted bare-file
  subagent registration); the personas above are a best-effort layer on top.
- **No new dependencies; harness-owned + idempotent** — the `.agents/` glue is regenerated each
  run (like `.claude/` / `.opencode/`); deselecting `antigravity` removes ONLY harness-owned
  files that are byte-identical to a freshly-generated stamp (pristine) — never a user file that
  merely shares a standard name, and never `rm -rf` of a user `.agents/` dir. `VERSION`
  bumped 0.21.0 → 0.22.0 (MINOR). `tests/test_install.sh` gains an Antigravity assertion group
  covering R1–R13; no canonical `agents/*.md` role file is touched.

## [0.21.0] — 2026-06-11

### Added — ✨ Selectable agent targets (interactive selection + re-prompt on update)
- **Declarative agent registry (`harness-install.sh`)** — the four selectable coding-agent
  front-ends (`claude`, `gemini`, `opencode`, `antigravity`) are modeled as a small registry
  (`AGENT_KEYS`); each EXISTING per-agent stamp block is now **gated** on selection rather than
  always running. The shared portable entrypoint `AGENTS.md` is never gated — it is always
  written and never removed.
- **Interactive selection (zero new deps)** — on an interactive TTY with no override, the
  installer presents a pure-`read` numbered toggle list pre-checked from the saved selection
  (or ALL on a fresh install) and stamps only the chosen agents.
- **Non-interactive override + back-compat** — `--agents=<csv>` / `HARNESS_AGENTS=<csv>` resolve
  the set without prompting (the override always wins; an unknown key aborts non-zero, naming the
  token, with no changes). No-TTY + no override still stamps **ALL** agents, preserving the
  historical behavior so existing CI is unchanged.
- **Persistence + re-prompt-on-update** — the resolved set is persisted to `.harness/.agents`
  (one sorted key per line; dot-prefixed to avoid colliding with the `.harness/agents/` role-bodies
  dir), beside `.harness/.harness-version`. Every re-run re-resolves and reconciles **decoupled
  from VERSION/upgrade detection**: an **added** agent is stamped, a **deselected** agent's
  harness-owned regenerated glue is deleted — **scoped to the specific generated files**
  (its pointer block, the `orchestrator/architect/builder/reviewer/scout` shims, the `sdd-*`
  commands, a generated `opencode.json`); user-authored files sharing `.claude/`/`.opencode/`
  are preserved and those dirs are pruned only when left empty. `opencode.json` is removed only
  when **byte-identical** to the generated stamp — any user edit (e.g. an added `model`/providers
  key) leaves it in place with a warning — and each removed path is warned about. `AGENTS.md` and the
  `.harness/` body are never removed. Deselecting `antigravity` is a **no-op** while its stamp
  is a placeholder (E07-F01), so a user-authored `.agent/` directory is never deleted.
  An existing install with **no** persisted `.harness/.agents` (a pre-0.21 install that stamped
  all front-ends) is treated as the **all-agents baseline**, so the first selective upgrade can
  actually remove the now-deselected glue instead of leaving it stale.
- **Docs + tests** — `tests/test_install.sh` gains an assertion group covering R1–R15 (selected-only
  stamping, no-TTY ALL default, explicit override + precedence, unknown-key rejection, persistence
  round-trip, an add+remove re-run at the same VERSION, and the legacy-upgrade baseline removal).

## [0.20.0] — 2026-06-11

### Added — ✨ Drift check on epic rollup (Scout re-validates remaining draft/planned epics)
- **Epic-done rollup formalized (`store/local.md`, `agents/orchestrator.md`)** — when every
  feature of an epic is `done`, the Orchestrator now **derives and persists** the epic's `done`
  status and **re-validates** `state/tasks.json` — additively, beside the existing
  feature-level rollup, mirroring its "derive, then persist" discipline. No new status value,
  no schema change (`done` was already an epic enum value).
- **Scout drift-check mode (`agents/scout.md`)** — on that epic rollup the read-only Scout
  re-validates the remaining `draft`/`planned`/`pending` epics against what the completed epic
  produced and writes a per-epic still-valid/stale findings file to
  `progress/<run>/scout-drift-<epic>.md`. Staleness uses concrete signals only — **(S1)** a new
  ADR contradicts the brief, **(S2)** the brief references a removed/renamed thing, **(S3)** an
  explicit `supersedes E0X` / `obsoletes E0X` marker — stale only when ≥1 fires. The Scout's
  **read-only** contract is preserved: it writes only to `progress/`, never `state/tasks.json`.
- **Orchestrator-applied demotion (`agents/orchestrator.md`)** — the Orchestrator (not the
  Scout) demotes a stale `planned`/`pending` epic to `draft` via `set_status` and re-validates.
  Demotion only ever moves an epic **backward**; `in-progress`/`done` epics are never demoted;
  re-drilling a demoted epic back to `planned` stays a manual `/sdd-drill` step, reported as a
  pointer with an optional flag-only `demoted on drift:` `epic.md` note. The no-op paths (no
  remaining planning-tier epics, or no architecture) emit a clear "nothing to re-validate" note
  and change nothing — this drift check never fails silently.
- **Docs + tests** — `docs/WORKFLOW.md` gains a distinct "Drift check on epic rollup" section;
  `tests/test_drift_check.sh` (POSIX sh + python3, zero new deps) is wired into
  `verification.test_command`.

## [0.19.0] — 2026-06-10

### Added — ✨ Architect ADR-citation contract (architecture.md mandatory-when-present input; specs cite the ADRs they touch)
- **Amended Architect contract (`agents/architect.md`)** — the Architect now **consumes**
  the planning tier's durable design. When `specs/architecture.md` + `specs/adr/NNNN-*.md`
  are **present**, they are a **mandatory input** alongside the inbox brief, and the
  Architect reuses the **F03-D7 hook** (the touched `ADR-NNNN` ids the Driller already
  recorded in the brief) as the seed. Every feature `.spec.md` it writes carries a
  **`## Architecture alignment`** section citing each touched `ADR-NNNN` + a one-line "how
  this honors it"; **`ADRs touched: none`** is the explicit, legitimate no-touch state; a
  divergence is **stated in the section** (never an authored ADR delta — that stays F03's
  job).
- **Graceful degradation** — `present` means the file exists **and** carries real content
  (a bare/template-stub counts as **absent**). When architecture is absent (legacy repo or
  `/sdd-new` altitude-3), the Architect records the absence and proceeds from the brief
  alone — no fabricated citation, no failure, section not required. Existing pre-contract
  specs stay valid (no retro-fit). The rule also applies to umbrella shared specs,
  orthogonal to the contract-artifact reference.
- **`## Architecture alignment` template section** — `specs/_templates/feature.spec.md`
  gains the section (between `## Business rules` and `## Acceptance criteria (EARS)`) with
  the `ADRs touched: none` fallback, so every new spec has a consistent, checkable slot.
- **Additive Reviewer clause (`agents/reviewer.md`)** — a new
  `## ADR-citation check (architecture-aligned specs)` section that fires **only where**
  `specs/architecture.md` + ≥1 ADR exist **and** the feature is `sdd: true`; it confirms
  the `.spec.md` has a `## Architecture alignment` section citing ≥1 `ADR-NNNN` or stating
  `ADRs touched: none`. A missing/empty section is a **soft flag**, not a hard reject; the
  clause does not fire for legacy/no-architecture features or `sdd: false` brief-only items.
- **Docs** — `docs/SPEC-FORMAT.md` documents the section + cite-your-ADRs rule;
  `docs/WORKFLOW.md` gains a distinct "Architecture-aligned specs (the Architect cites
  ADRs)" section placing the contract relative to `/sdd-plan` + `/sdd-drill`; `README.md`
  gains a one-line note that feature specs cite the ADRs they touch.
- **Verification** — `tests/test_architect_adr.sh` (wired into
  `verification.test_command`): grep contract assertions over the role/reviewer/template/docs,
  a temp-dir markdown fixture proving the `## Architecture alignment` shape (both citing an
  ADR and `ADRs touched: none`) is internally consistent, and a temp JSON store fixture
  proving the citation needs **no** `store/tasks.schema.json` change.
- Purely additive / consume-only: F02 `/sdd-plan`, F03 `/sdd-drill`, the ADR
  format/numbering, the architecture/adr templates, `store/tasks.schema.json`, and every
  `/sdd-*` command are unchanged; a repo with no `specs/architecture.md` behaves exactly as
  today.

## [0.18.0] — 2026-06-10

### Added — ✨ `/sdd-fix` lightweight fix lane (maintenance epic, brief-only `sdd: false` intake)
- **New portable Fixer role (`agents/fixer.md`)** — a sibling of Inception / Planner /
  Driller that is the **brief-only intake** for the lightweight fix lane. It seeds **one**
  `sdd: false` fix under a single reserved maintenance epic, carrying only a one-paragraph
  inbox brief, and **hands it off to the existing `sdd: false → Builder → Reviewer` loop**.
  It is a thin front-end over the existing F01 primitive: **no new Orchestrator routing, no
  new TaskStore status, and no `store/tasks.schema.json` change**. It seeds and hands off —
  it never specs and writes no production code itself.
- **Reserved maintenance epic convention (`E99`)** — `/sdd-fix` creates the maintenance
  epic on first use (`id: "E99"`, slug `maintenance`, title "Maintenance (hotfixes & minor
  fixes)", `status: "planned"`, `features: []`, plus `specs/epics/E99-maintenance/epic.md`)
  and re-identifies the **same** epic **by id `E99`** on every later run (never a second
  bucket, never a renumber). `E99` is a deliberately high reserved number that already
  satisfies the `^E[0-9]+$` schema pattern (no schema change); `planned` is a selectable,
  non-`draft` status so the `next()` gate returns its fixes.
- **Brief-only `sdd: false` fix seeding** — each fix is appended as the next-sequential
  `F##` strictly above the epic's max (append-only, no reuse) with `sdd: false`,
  `status: "pending"`, a one-line title, and a recorded `spec_path` (directory **not**
  created), stamped **`autonomous: true` by default** (runs end-to-end) with a `--gated`
  opt-out that stamps `autonomous: false`. Exactly one fix-oriented inbox brief is written
  at `progress/inbox/<id>.md` from `specs/_templates/inbox-brief.md` — never a feature
  `.spec/.plan/.tasks/.tests`, never a `spec_path` directory, never the Architect. The
  Fixer re-validates `state/tasks.json` against `store/tasks.schema.json` after each write
  and fail-stops on an invalid store.
- **New `/sdd-fix` slash command (`.claude/commands/sdd-fix.md`)** — the interactive
  wrapper that acts as Fixer, reads the description from `$ARGUMENTS` (STOP if empty),
  offers ≤3 text-only options (never images), seeds the `E99` fix, re-validates, and hands
  off to the existing `sdd: false` loop in-session. Generated by `harness-install.sh` into
  `.claude/commands/sdd-fix.md` (resolving `.harness/agents/fixer.md`) and mirrored to
  `.opencode/command/sdd-fix.md`.
- **Additive Builder/Reviewer clarifications (`sdd: false` only)** — `agents/builder.md`
  now states that for an `sdd: false` item with no `tasks.md` the Builder works from the
  inbox brief as its worklist and still writes a test proving the fix; `agents/reviewer.md`
  now states that for an `sdd: false` item the Reviewer verifies behaviourally + the fix's
  test and that its R-id traceability check does not apply when there are no R-ids. Both
  edits are strictly additive — the `sdd: true` four-file path is unchanged.
- **`sdd: false` routing split by `autonomous` (coherence fix)** — the Orchestrator's
  `pending + sdd: false` route is split in two: `autonomous: true` **sets the feature to
  `in-progress`** (so the Builder's Loop A `in-progress` precondition holds) then spawns
  the Builder directly → `in-review`; `autonomous: false` (e.g. `/sdd-fix --gated`)
  **parks at the human gate** (not actionable until a human approves), so `--gated` is a
  real opt-out instead of a no-op. `agents/builder.md`, `agents/fixer.md`,
  `store/local.md`, and `docs/WORKFLOW.md` are aligned to this split.
- **Docs + tests** — `docs/WORKFLOW.md` documents the lightweight fix lane alongside
  "Selective SDD" (adds no new status, no new routing); `README.md` carries a one-line
  `/sdd-fix` mention beside the existing `/sdd-new` / `/sdd-plan` / `/sdd-drill` /
  `/sdd-next` command family; `tests/test_sdd_fix.sh` (wired into
  `verification.test_command`) covers the role/command/builder/reviewer/docs contract plus
  a schema fixture for the seeded `sdd: false`/`autonomous: true` fix inside a `planned`
  `E99` epic; R15/R16 installer assertions live in `tests/test_install.sh`. `/sdd-fix` is
  a lighter sibling of the heavier `/sdd-plan` and `/sdd-drill` planning skills — it never
  writes a feature spec or runs a drill.

## [0.17.0] — 2026-06-10

### Added — ✨ `/sdd-drill` per-epic drill-down skill (decompose draft epic, ADR deltas, epic-level approval)
- **New portable Driller role (`agents/driller.md`)** — a sibling of the Planner and the
  Architect that operates at the per-epic altitude. It is the **consumer that decomposes,
  never specs**: it takes exactly one `draft` epic, seeds `pending` feature entries (ids,
  one-line intents, `depends_on`, `sdd: true`, `spec_path`) into the epic's `features`
  array, fills the `epic.md` feature table, and writes a per-feature inbox brief under
  `progress/inbox/` (recording the `ADR-NNNN` ids each feature must honor). It allocates
  feature ids as a next-sequential block strictly above the epic's max `F##` (append-only,
  no reuse) and never writes a feature `.spec/.plan/.tasks/.tests` or spawns the Architect.
- **ADR deltas** — the Driller appends per-epic design decisions as one-decision ADRs at
  `specs/adr/NNNN-<title>.md` (4-digit, above the max existing ADR number, no reuse),
  scoped one level below F02's whole-system upfront ADRs, and never rewrites or renumbers
  F02's existing ADRs.
- **Single epic-level approval (approve / keep-gated branches)** — the drill ends in
  exactly one human decision at the epic granularity, realized solely through F01's
  `planned` state and the existing `autonomous` flag (no new status, no new approval
  mechanism, no schema change). **Approve** flips the epic `draft → planned` and stamps
  `autonomous: true` on every seeded feature (all-or-nothing); **keep gated** flips the
  epic `draft → planned` while leaving every feature `autonomous: false` so each parks at
  the per-feature spec-approval gate. `/sdd-drill` is the only step that flips an epic
  `draft → planned`.
- **New `/sdd-drill` slash command (`.claude/commands/sdd-drill.md`)** — the interactive
  wrapper that acts as Driller, reads the `<epic-id>` from `$ARGUMENTS`, STOPs on an
  empty/missing/non-`draft` target, runs the ≤3 text-only adaptive Q&A, and presents the
  single approve / keep-gated decision.
- **Docs** — `docs/WORKFLOW.md` gains a "Per-epic drill-down (`/sdd-drill`)" note placing
  it between `/sdd-plan` and `/sdd-next`; `README.md` gains a one-line `/sdd-drill` mention.
- **Verification** — `tests/test_sdd_drill.sh` (wired into `verification.test_command`):
  grep contract assertions over the role/command/docs plus one python fixture proving the
  decomposed shape (a `pending` feature inside a `planned` epic, stamped `autonomous: true`,
  with the required root `project` field) validates against `store/tasks.schema.json`.
- Purely additive: `/sdd-new`, `/sdd-plan`, `/sdd-next`, Inception, and the Planner are
  behaviorally unchanged; no schema change. MINOR `VERSION` bump → `0.17.0`.

## [0.16.0] — 2026-06-10

### Added — ✨ `/sdd-plan` whole-project inception skill (vision + architecture + draft epics)
- **New portable Planner role (`agents/planner.md`)** — a sibling of Inception that
  operates at the whole-roadmap altitude. It is a **producer that never specs**: it
  writes `specs/vision.md`, `specs/architecture.md` + one-decision ADRs at
  `specs/adr/NNNN-<title>.md`, and seeds a block of `draft` epics — and it never writes
  a feature `.spec/.plan/.tasks/.tests`, never spawns the Architect, and never advances
  an epic past `draft` (F03 `/sdd-drill` owns the `draft → planned` flip).
- **New `/sdd-plan` slash command (`.claude/commands/sdd-plan.md`)** — the interactive
  wrapper that acts as Planner, reads the idea from `$ARGUMENTS`, runs the ≤3 text-only
  adaptive Q&A, and reports the seeded epics + artifact paths.
- **New artifact templates** — `specs/_templates/vision.md` (problem/users/outcomes/
  non-goals; complements `product.md`/`glossary.md`), `specs/_templates/architecture.md`
  (system shape + stable upfront decisions + ADR index by `ADR-NNNN` id), and
  `specs/_templates/adr.md` (one-decision context/decision/consequences).
- **Draft-epic seeding** writes each epic with `status: "draft"` and `features: []` —
  the schema-valid empty-features shape (no placeholder `F01`, the deliberate difference
  from `/sdd-new`'s new-epic altitude) — allocating ids as a next-sequential block above
  the current maximum, append-only, no reuse.
- Purely **additive / backward-compatible**: `/sdd-new`, `/sdd-next`, and Inception are
  unchanged; a repo that never runs `/sdd-plan` validates and behaves exactly as before.
  `docs/WORKFLOW.md` + `README.md` updated; new suite `tests/test_sdd_plan.sh` wired into
  `verification.test_command`.

## [0.15.0] — 2026-06-10

### Added — ✨ Human-readable telemetry durations (`HH:MM:SS`) + table total row
- **`tools/telemetry-report.py` renders every duration as `HH:MM:SS`** instead of
  raw seconds (e.g. `00:13:11` not `791s`), across the session view and all calendar
  rollups — per-phase durations and human-gate latency alike. Hours are not capped at
  24 (a multi-day gate latency shows e.g. `48:00:00`), keeping the format unambiguous.
- **Per-phase breakdown tables gain a `**total**` row** (count + summed duration) so
  the session total lives in the table itself, not only the prose bullet below it.
- The change is output-only and backward-compatible: the JSONL telemetry record format
  (`duration_s`/`human_latency_s` in seconds) is unchanged; only the rendered report
  differs. Suite `tests/test_telemetry.sh` updated (R4/R9/R10 expectations) with a new
  `R4b` covering the `HH:MM:SS` format and the total row.

## [0.14.0] — 2026-06-10

### Added — ✨ Epic lifecycle: `draft`/`planned` states + `next()` draft gate
- **Epic `status` enum gains `draft` and `planned`** (`store/tasks.schema.json`,
  purely additive): canonical lifecycle is now `draft → planned → in-progress → done`,
  with epic-level `pending` kept indefinitely as a **legacy alias of `planned`**
  (gating-equivalent). Feature/slice status enums are unchanged; existing consumer
  `tasks.json` files validate as-is — no migration.
- **`next()` draft gate** (normative in `store/local.md` + `agents/orchestrator.md`,
  the portable contract files): features of a `draft` epic are **never actionable** —
  the Orchestrator never selects them, regardless of the feature's own
  `status`/`sdd`/`autonomous`/`depends_on` (`autonomous: true` skips the *human
  approval* gate, not this *planning* gate). `pending`/`planned`/`in-progress`/`done`
  epics impose no new gate.
- **Warn-only `init.sh` invariant**: a `draft` epic containing a feature whose status
  is not `pending` prints a ⚠️ warning naming the epic and feature, and still exits 0
  (the gate already neutralizes it; schema validation does not reject it). The
  zero-dependency fallback validator accepts the new epic statuses.
- Docs/template updates: epic-lifecycle section in `docs/WORKFLOW.md`, lifecycle
  status comment in `specs/_templates/epic.md`, and a `store/board-mirror.md` note
  that epic statuses (including `draft`/`planned`) never map to board columns.
- New test suite `tests/test_epic_lifecycle.sh` (R1–R14), wired into
  `verification.test_command`.

## [0.13.0] — 2026-06-08

### Added — ✨ `mirror.board.status_map` — keep existing board columns via config
- **`tools/sync-board.mjs` now reads an optional `mirror.board.status_map`** mapping each
  harness status to a board **column name** (e.g. `pending: "Todo"`, `done: "Done"`).
  Omitted ⇒ identity columns (unchanged default). This lets a team whose board already has
  custom columns adopt the shipped mirror **without editing `sync-board.mjs`** — so a
  `harness-install.sh` upgrade never clobbers the customization. Backed by a new
  dependency-free nested-map YAML reader (`yamlGetMap`). Config migration seeds a commented
  `status_map` example into the `mirror:` block.

## [0.12.0] — 2026-06-08

### Added — ✨ Pluggable board mirror + generic post-write sync hook
- **`tools/sync-board.mjs`** — a generic, provider-pluggable one-way **mirror** that
  projects `state/tasks.json` onto an external project board (issue/work-item per feature,
  Status + Epic fields, closes done / reopens regressed). `tasks.json` stays the source of
  truth; the board is a downstream projection agents never read. **Inert by default.**
  - Provider chosen by `mirror.board.provider`: `""`/`none` ⇒ no-op exit 0;
    **`github-projects`** implemented (config-driven `owner`/`project_number`/`repo`, needs
    `gh`); **`jira`** + **`azure-boards`** recognized as no-op **stubs**. No org/repo/tool is
    hard-coded; status columns default to the harness status names verbatim (identity map).
- **`store.on_write_command`** — a generic, **VCS/PM-neutral** post-write hook. When
  non-empty the Orchestrator runs it after any persisted store write
  (`<cmd> "<feature-id>" "<op>"`, cwd = `HARNESS_DIR`); empty (default) ⇒ no hook. Best-effort:
  a non-zero exit never rolls back `tasks.json` and never blocks the loop. The harness never
  learns what the command does (git push, board mirror, both). A team wires `sync-board.mjs`
  into it via config — the mirror tool is never hard-coded into the loop.
- Config migration seeds both `store.on_write_command` and the `mirror:` block on upgrade
  (append-only, value-preserving); `sync-board.mjs` is installed + `chmod +x` like the
  telemetry tool.

### Docs
- **New `store/board-mirror.md`** — the mirror contract, provider table, and the
  **mirror-vs-backend** distinction (one-way projection vs where state lives).
- **`store/README.md`** gains a "Mirrors vs backends" section; **`store/jira.md`** gets a
  backend-not-mirror cross-link; **`store/local.md`** documents "Post-write sync";
  **`agents/orchestrator.md`** gains the best-effort post-write-sync step.

## [0.11.0] — 2026-06-08

### Added — ✨ `--shared-repo`: version-control the umbrella as a shared spec repository
- **`harness-install.sh --umbrella <dir> --shared-repo`** makes the umbrella ROOT its own
  git repo — a *shared spec repository* that tracks `.harness/` (specs, `state/tasks.json`,
  progress) + the umbrella docs and **git-ignores the product child repos** (each stays its
  own repo, never a gitlink). Solves the "planning state stranded on one laptop" gap a team
  hits when several developers work the same umbrella. **Opt-in and inert by default**:
  without the flag the umbrella stays a non-git parent dir, byte-for-byte as before.
  - `git init` runs **only if the umbrella root has no `.git`** — an existing repo is never
    re-initialized; if `git` is absent the install continues and seeds the `.gitignore`.
  - The umbrella-root `.gitignore` is **append-seeded** with exactly the child repos the
    cascade discovered (never a blanket rule; never clobbers an existing file).
  - Works with `--dry-run` to preview the `git init` + ignore plan. Umbrella-mode only
    (`--shared-repo` without `--umbrella` is rejected).
- **New `umbrella.gitignore.example`** (shipped at the harness root, beside
  `umbrella.manifest.example.yaml`) documents the intended shared-spec-repo `.gitignore`
  shape: product repos ignored, `.harness/` + docs tracked, personal state ignored.

### Docs
- **`docs/UMBRELLA.md`** softens the absolute "No new git repo is introduced" claim into a
  default-vs-opt-in statement and gains a **"Shared spec repository (opt-in)"** section.
- **`docs/INSTALL.md`** gains a `--shared-repo` subsection under umbrella mode.

## [0.10.0] — 2026-06-08

### Added — ✨ Seed a project-root `.gitignore` for personal/runtime agent state
- **`harness-install.sh` now append-seeds the project-root `.gitignore`** with per-developer
  agent state — `.claude/settings.local.json`, `.claude/scheduled_tasks.lock`, and a
  commented `.playwright-mcp/` — so a **shared** spec/umbrella repo (a team clones the
  install) never carries one developer's local config. The seed is **append-only and
  idempotent**: it never clobbers an existing root `.gitignore` and only adds an entry that
  is missing, mirroring the existing `.harness/.gitignore` telemetry seeding. It ignores
  **specific files** under `.claude/`, never the whole dir, so the harness-generated
  `.claude/agents` and `.claude/commands` stay tracked and shared.

### Docs
- **New `docs/CONFIG-LAYERING.md`** — the shared-vs-personal config model (project layer =
  committed `CLAUDE.md`/`.harness`/`.claude` glue; personal layer = gitignored
  `settings.local.json`; user-global = `~/.claude/CLAUDE.md`). Directly answers "should every
  developer share the same `CLAUDE.md`?" (yes — keep it shared; push personal prefs to the
  user-global layer).
- **INSTALL.md** ownership table gains the project-root `.gitignore` under runtime/local and a
  pointer to `CONFIG-LAYERING.md`.

## [0.9.0] — 2026-06-07

### Added — ✨ Install `/sdd-next` + `/sdd-new` as OpenCode commands too
- **`harness-install.sh` now emits the slash commands to `.opencode/command/` as well as
  `.claude/commands/`.** Previously the commands were written only to the Claude Code
  command dir, so targets driven through OpenCode saw the agents but had no `/sdd-next`
  or `/sdd-new`. The command bodies are now authored once and written to both locations
  (identical content; no `agent:` frontmatter, so they run under the primary
  orchestrator agent defined in the generated `opencode.json`). Regenerated on every
  install/upgrade. Manifest updated to list `.opencode/command/*` as harness-owned.

## [0.8.0] — 2026-06-06

### Added
- **Config migration seeds the `telemetry:` block on upgrade.** `harness-install.sh`'s
  append-only `migrate_config` now adds the `telemetry:` block (`enabled` kill-switch +
  `log:` path) to a preserved pre-telemetry config, so an upgraded consumer gains the
  same discoverable config surface as a fresh install (a config without the block already
  worked — it defaults to enabled + `telemetry.jsonl`). Covered by `tests/test_cascade.sh`.

### Docs
- **README** gains an **Observability (telemetry)** section (report commands, local-only
  gitignored storage, the `telemetry:` config + `enabled` kill-switch, cost-out scope), a
  note on the Reviewer's cross-file consistency check + multi-round build↔review loop, and
  `tools/` in the layout.
- **INSTALL.md** documents the installed `tools/`, the seeded `.harness/.gitignore` + local-only
  `telemetry.jsonl`, the telemetry config migration, and a pre-v0.7.0 upgrade note; adds a
  `runtime/local` row to the ownership table.

## [0.7.0] — 2026-06-06

### Added — ✨ Sub-agent & human-gate telemetry with rollup reports (E05-F02)
- **Telemetry contract (`agents/orchestrator.md` "## Telemetry").** The Orchestrator —
  the single writer — now appends structured, best-effort, append-only JSONL records at
  every delegation boundary and gate transition: a `phase` record per sub-agent span
  (`architect`/`builder`/`reviewer`/`scout`/`inception`/`slice-dispatch`) with
  `start`/`end`/`duration_s`/`outcome`/`round`/`slice`, a two-line `gate` open/close pair
  carrying `human_latency_s` (the human spec-approval interval, with an `autonomous` flag),
  and a `session-start` marker delimiting each session. Timestamps are ISO-8601 UTC via
  `date -u`. Capture is **never on the critical path** — a failed/absent write never
  blocks a gate or build. Token/USD accounting is **out of scope**; a reserved `cost`
  field (null today) lets a future instrumented runtime populate it without a format
  migration.
- **Storage = local-only runtime data.** The log resolves to `<HARNESS_DIR>/telemetry.jsonl`
  (overridable via the new optional `telemetry:` block in `harness.config.yaml`;
  `enabled: false` is the kill-switch). It is **gitignored / never committed**: the source
  `.gitignore` ignores `/telemetry.jsonl`, and `harness-install.sh` seeds a targeted
  `.harness/.gitignore` (containing `telemetry.jsonl`, seed-once / never clobbered) so a
  consumer's committed harness body coexists with a local-only log.
- **Report script (`tools/telemetry-report.py`, python3 stdlib only).** Reads the JSONL
  log and emits text/markdown rollup tables at `daily`/`weekly`/`monthly`/`quarterly`/
  `semester`/`annual` granularity (default: an all-granularity summary), plus a `session`
  view scoped to the latest `session-start` marker that reproduces the Orchestrator's
  end-of-session summary (per-phase durations, build↔review round count, mean/median
  human-gate latency excluding autonomous transitions). Malformed lines are skipped; an
  absent/empty log exits 0 with a "no telemetry yet" notice.
- **Portable end-of-session summary.** The summary instruction lives in
  `agents/orchestrator.md` (plain prose + `python3 tools/telemetry-report.py session`,
  no Claude-Code-specific dependency) with a one-line pointer in `AGENTS.md`, so every
  AGENTS.md-compatible CLI surfaces the same text-only table.
- **Tests:** `tests/test_telemetry.sh` covering R1–R27 (fixture-driven rollups, best-
  effort/empty no-op, schema/format, the two gitignores, the AGENTS.md pointer), wired
  into `verification.test_command`.

## [0.6.0] — 2026-06-06

### Added — Reviewer cross-file consistency + explicit build↔review rounds
- **Cross-file consistency check (`agents/reviewer.md`).** The in-loop Reviewer now
  has a named "What you check" item for cross-file consistency: for any change to a
  role/contract/prose file it loads the **collaborators the diff references** (the
  unchanged files the change invokes), scoped to those references
  (curate-don't-dump, never a whole-repo dump), and verifies the change's
  preconditions are satisfied by — and do not contradict — the contracts it invokes.
  A **provably violated** precondition is a **hard reject**; a suspected-but-unproven
  inconsistency is **flagged for the Builder to justify** rather than blocked. Ships
  the canonical **PR #10 worked example** (an `orchestrator.md` dispatch step telling
  the Builder to open a child PR vs. `builder.md` Loop A's "Builder never opens a PR")
  — a contradiction with no failing test, exactly what this check catches. Rejects
  emit specific, actionable, **file-based** feedback (contradicting files + expected
  vs. actual) to `progress/<run>/review.md`.
- **Explicit multi-round build↔review loop (`agents/orchestrator.md`).** The
  build↔review handoff is now documented as an explicit loop that repeats **until
  green**: reject → actionable file feedback → `in-progress` → Builder addresses →
  re-review. **Each round is recorded** (one line per round in `progress/history.md`).
  No new status value and no schema change — the round counter lives only in
  `progress/` history. `docs/WORKFLOW.md` aligned to the multi-round loop.

## [0.5.0] — 2026-06-06

### Added — umbrella mode hardening (feedback pass)
- **`in-session` umbrella dispatch is now a first-class, documented mode.** The
  coordinator loop previously documented slice dispatch *only* via an external
  `delegate_cmd` — but the shipped default is `execution.builder.backend: in-session`,
  which has no executor, so the documented path dead-ended on a fresh install.
  `agents/orchestrator.md` and `docs/UMBRELLA.md` now branch dispatch on
  `execution.builder.backend`: under `in-session` (default) the Orchestrator spawns the
  Builder sub-agent `cd`'d into each child repo (zero-dependency, the natural
  single-session path); under `delegate` it uses the `delegate_cmd` seam. `delegate_cmd`
  is now documented as optional and ships empty in `umbrella.manifest.example.yaml`.
- **Contract artifact is now prompted and enforced.** `agents/architect.md` gained an
  Umbrella-mode section making the single pinned inter-repo contract artifact
  **mandatory** for any feature with `slices[]`, with every slice required to reference
  it (prevents inter-repo field drift). `agents/reviewer.md` gained a matching check:
  a sliced feature is rejected unless the pinned contract exists and the slice under
  review traces its wire fields/shapes to it.
- **Cascade preview: `harness-install.sh --umbrella … --dry-run` (alias `--list`).**
  Lists the coordinator + every git child that would be installed (with skip reasons),
  writing nothing — so the cascade no longer surprises you by scaffolding untouched
  repos. The activation message now states explicitly that pointing `umbrella.manifest`
  ENGAGES umbrella mode.

### Changed
- Documented the two manifest path bases (the `umbrella.manifest` value resolves
  relative to `.harness/`; each entry's `path:` resolves relative to the manifest's own
  dir) in `harness.config.yaml`, `umbrella.manifest.example.yaml`, and `docs/UMBRELLA.md`.
- Clarified in `init.sh` that `.harness/init.project.sh` is for FAST structural/presence
  checks only — the heavy test suite belongs in `verification.test_command` (Reviewer-run,
  once at the `in-review` gate), not in the per-step gate.

## [0.4.0] — 2026-06-01

### Added — Inception role + /sdd-new intake (E04-F01)
- **Inception role (`agents/inception.md`):** the portable, model-interchangeable
  front door *before* `pending`. Takes a raw idea, triages it to exactly one altitude
  (new task on an existing not-`done` feature / new feature under an existing epic /
  new epic + `epic.md` + first `F01`), allocates a **next-sequential** id (no reuse of
  vacated ids), writes a `pending` TaskStore entry, re-validates `state/tasks.json`
  against `store/tasks.schema.json` (fail-stop: a failed validation is never a
  success), and writes an intent brief to `progress/inbox/<feature-id>.md`. It
  **seeds; it never specs** — it never writes the four spec files, never advances
  status past `pending`, and never spawns the Architect.
- **`/sdd-new` slash command (`.claude/commands/sdd-new.md`):** thin Claude wrapper
  that carries the interactive adaptive Q&A and ≤3 **text-only** mockup options,
  taking the idea via `$ARGUMENTS` and deferring the durable contract to the role
  file. Ends by reporting the seed + "run `/sdd-next`".
- **Installer ships `/sdd-new`:** `harness-install.sh` now emits an installed
  `.claude/commands/sdd-new.md` wrapper (with all paths rewritten to `.harness/…`)
  alongside `/sdd-next`, so consumer repos get the Inception intake command too.
  The installed wrapper mirrors the source's altitude-dependent write step (the
  altitude-1 reuse-and-append branch keyed on the existing feature's status) and
  copies its inbox brief from the shipped `.harness/specs/_templates/inbox-brief.md`
  template instead of the un-shipped `E04-F01.md` example; `tests/test_install.sh`
  asserts the template path, the absence of `E04-F01`, and the altitude-1 branch.
- **Docs:** `AGENTS.md` role list + flow now name Inception; `docs/WORKFLOW.md`
  documents the pre-`pending` intake step feeding the unchanged state machine.
- **Tests:** `tests/test_inception.sh` covering R1–R16 (static file/format/grep +
  schema validation), wired into `verification.test_command`.
- **Purely additive:** no change to `store/tasks.schema.json`, no new status value,
  and no change to the Orchestrator or Architect contracts.

## [0.3.0] — 2026-05-31

### Added — Cascade installer (E03-F02)
- **Umbrella install mode:** `harness-install.sh --umbrella <dir>` installs a
  coordinator profile in the umbrella directory, scans its immediate children, and
  installs the normal `.harness/` into each child that is a git repo (`.git` as a
  directory **or** a file). `--recursive` opt-in for deeper scans. Bare
  `harness-install.sh <target>` is byte-for-behavior unchanged (hard non-regression).
- **Manifest auto-population:** discovered repos are upserted into
  `umbrella.manifest.yaml` (path discovered; `init`/`test_command`/`delegate_cmd` as
  bootstrap TODOs). Idempotent — re-runs append new repos and never clobber
  project-owned entry fields. Repo-key grammar `^[a-z0-9-]+$` validated; violators are
  skipped with a message rather than written as undispatchable entries.
- **Non-destructive config migration:** on upgrade, missing umbrella keys
  (`umbrella.manifest`, `verification.integration_command`) are appended to a preserved
  `harness.config.yaml` without altering existing values/comments — fixes the case
  where a pre-0.2.0 install could never opt into the coordinator. Append-only and
  idempotent.
- **Tests:** `tests/test_cascade.sh` covering R1–R24, wired into
  `verification.test_command`.

## [0.2.0] — 2026-05-30

### Added — Multi-repo coordination (E03-F01: Umbrella coordinator)
- **TaskStore schema:** optional `slices[]` on a feature (`id`, `repo`, `status`,
  `merged`, `spec_path`, cross-repo `depends_on`). Pure superset — single-repo
  stores validate unchanged.
- **Umbrella manifest:** `umbrella.manifest.example.yaml` mapping each child repo to
  its `path` / `init` / `test_command` / `delegate_cmd`. Manifest presence is the
  opt-in switch for umbrella mode.
- **Config:** additive `verification.integration_command` (feature-level stack-up
  check) and `umbrella.manifest` keys. No existing key changes meaning.
- **Orchestrator "Umbrella mode"** (additive section, no role fork): topological
  slice select, dispatch via the existing `execution.builder.delegate` seam, gate
  downstream slices on upstream `done`+`merged`, fail-stop, and a derived feature
  `done` rolled up behind the integration gate.
- **Docs:** `docs/UMBRELLA.md` describing the coordinator model.
- **Tests:** `tests/test_umbrella.sh` covering R1–R19, wired into
  `verification.test_command`.

## [0.1.0]

### Added
- Initial harness body: installer (`harness-install.sh`), `init.sh` gate, the
  Orchestrator/Architect/Builder/Reviewer/Scout roles, the 4-file spec format, and
  the local/obsidian/jira store contract.
