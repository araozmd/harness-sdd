# E99-F16 — Builder note

**Feature:** the harness cannot spawn its own mandatory doc-critic checkpoint
**Status at start:** `in-progress` (confirmed in `state/tasks.json`; `sdd: false`, so the
worklist was the inbox brief `progress/inbox/E99-F16.md`, not a `tasks.md`).
**Branch:** `fix/E99-F16-source-doc-critic-shim`

## What changed

Three registrations, all in the **source** checkout, none in the installed body:

1. **`.claude/agents/doc-critic.md`** (new). Frontmatter `name` / `description` / `tools`
   matching the sibling source shims; body points at the canonical `agents/doc-critic.md`
   and resolves against the **source** tree (no `.harness/` prefix — that is the installed
   variant's body). Tools: `Read, Grep, Glob, Write`, copied exactly from the installer's
   grant at `harness-install.sh:3481`. `Write` is the one the role file forces: it records
   `progress/<run>/doc-critic-<checkpoint>.md` ("Output summary"), and
   `tests/test_install.sh:587` asserts it on the installed shim. Nothing beyond that grant.

2. **`.claude/agents/architect.md`** — added `Task` to the tools list, and one sentence to
   the body naming the R12 checkpoint as what `Task` is for.

3. **`opencode.json`** — registered `doc-critic` as a `subagent` whose prompt is
   `{file:./agents/doc-critic.md}` (source path; the installer's generated file uses
   `./.harness/agents/doc-critic.md`).

4. **`tests/test_source_shims.sh`** (new) — auto-discovered by `tools/run-tests.sh`.

Not touched: `agents/doc-critic.md`, `harness-install.sh`, `state/tasks.json` (beyond the
status line the Orchestrator had already written), `VERSION`, `CHANGELOG.md`.

### No VERSION bump, no CHANGELOG entry — deliberate

Per the brief's Constraints section, which records this as a review finding already
disagreed-with-and-recorded. Re-verified rather than taken on faith:
`HARNESS_BODY_PROSE='AGENTS.md agents docs specs/_templates specs/glossary.md'` and
`HARNESS_BODY_LOCAL='init.sh store tools umbrella.manifest.example.yaml
umbrella.gitignore.example'` (`harness-install.sh:668-669`) — neither includes `.claude/`,
`opencode.json`, or `tests/`. **No heredoc was modified**, so the obligation the brief
attaches to that case does not trigger: every installed target receives byte-identical
output before and after this change.

## Decision 1 — does granting the source Architect `Task` widen anything?

**Yes, and it is the same widening every consumer already receives. Granted.**

- **The installer's grant is not scoped.** `harness-install.sh:3463` emits
  `emit_agent architect "Read, Write, Edit, Grep, Glob, Bash, Task"`, with the comment
  "architect carries `Task` so it can spawn the doc-critic sub-agent". That is a *comment*,
  not a mechanism — Claude Code's `tools:` frontmatter is a flat allowlist with no
  per-callee restriction, so there is no narrower grant available in either tree. The
  source shim now mirrors the installed one exactly.
- **So what widens:** the Architect can spawn *any* registered sub-agent, not only the
  doc-critic. It is constrained by prose (`agents/architect.md`) exactly as it is in every
  installed target.
- **What does not widen:** `Task` confers delegation, not new authority over the
  filesystem. The Architect already holds `Write`, `Edit` and `Bash`; anything it could
  reach through a sub-agent it could already do directly, in one fewer step.
- **The brief's premise here is wrong, and worth correcting for the record.** It says "no
  other source shim carries `Task` today". `.claude/agents/orchestrator.md` carries
  `tools: Read, Bash, Edit, Grep, Glob, Task` and always has. `Task` is not novel in this
  checkout; the Architect is the second holder, not the first.

Net: before this change the source repo was strictly *less* capable than every target it
ships to, in the one respect its own mandatory checkpoint depends on.

## Decision 2 — specific fact, or general rule?

**The general rule, with the "spawned" set as a *maintained list* whose completeness is
machine-checked.**

The general rule is only as good as its set of spawned roles, and that set is **not
reliably derivable**:

- `agents/architect.md`, `agents/driller.md` and `agents/planner.md` name their callee in
  prose with its path (``spawn the **Doc-critic** (`agents/doc-critic.md`) as a
  sub-agent``) — so a path-citing pattern finds `doc-critic` and **nothing else**.
- `agents/orchestrator.md` spawns builder / reviewer / scout **without ever citing their
  file paths** ("Spawn the **Builder** sub-agent with a clean context", line 417).
- `pr-fixer` is spawned from a slash-command body (`.claude/commands/sdd-pr-loop.md:416`),
  not from any role file at all.
- `agents/orchestrator.md` also contains generic sentences — "Spawn each sub-agent with a
  clean context" (line 353) — that any looser pattern swallows as a false positive.

A regex loosened until it reproduces the answer I already knew would not be a derivation;
it would be the answer, laundered, and its failure message would name a guarantee it cannot
detect. **A maintained list is the honest answer.** What the suite machine-checks instead is
the list's *rot*: `SPAWNED` + `NOT_SPAWNED` must together account for every `agents/*.md`,
and neither may name a file that does not exist. Adding or renaming a role file fails the
suite until someone classifies it — at the moment the knowledge is present and the
classification is cheap.

The suite therefore asserts, all against `$SRC`:

1. The source registers roles in **exactly two** front-ends (`.claude/agents/`,
   `opencode.json`), and `.codex/`, `.gemini/`, `.agents/`, `.opencode/` are **absent**. A
   new front-end appearing fails the suite rather than silently escaping its loop — the
   brief flags "assumed the enumeration was complete" as a three-round recurring failure
   here, so it is checked, not assumed.
2. The classification accounts for every role file (above).
3. Every spawned role is registered in every front-end. For `opencode` this accepts
   **either** an `agent:` entry in `opencode.json` **or** a file-based
   `.opencode/agent/<role>.md`, because the installer genuinely uses both mechanisms.
4. The doc-critic's three preconditions asserted **separately**, since any one alone leaves
   R12 unrunnable: shim exists; shim grants `Write`; shim resolves against `agents/` and
   **not** `.harness/`; architect shim grants `Task`; `opencode.json` names it as a
   `subagent` pointing at the source path.
5. `agents/architect.md` still *mandates* the checkpoint — extracted by named section with
   the `awk` heading helper, then grepped, so an unrelated mention of "doc-critic" elsewhere
   in the file cannot satisfy it. If the mandate is ever dropped, the suite says so rather
   than quietly enforcing a dead requirement.

Deliberately **not** asserted: that a source shim is byte-identical to (or a superset of)
the installed one — they resolve against different roots by design, so that comparison
would be wrong rather than strict. Also no exact `VERSION` string and no diff of
DO-NOT-TOUCH files against `main`.

### The out-of-scope gaps are asserted as *still broken*, not exempted

`builder-heavy` (missing from both front-ends) and `pr-fixer` (missing from OpenCode) stay
out of scope per the brief. They are listed in `KNOWN_GAPS` and asserted to **still be
gaps**. An entry that is merely skipped outlives its reason silently; an entry asserted
broken fails the moment someone fixes it, with a message saying to delete the line. Mutation
M8 below proves that self-expiry works.

## Mutation check

Run against a copy of `agents/`, `.claude/`, `opencode.json` and the suite in a scratch
tree, so the working checkout was never mutated. Baseline green, then each mutation applied
and reverted individually. **All eleven fail, each with the message that names the real
symptom:**

| # | Mutation | Suite result |
|---|---|---|
| M1 | delete `.claude/agents/doc-critic.md` | FAIL — "'doc-critic' is spawned as a sub-agent but is NOT registered for claude in the source checkout" |
| M2 | drop `Task` from the architect shim | FAIL — "source architect shim lacks the Task tool — … the shim exists but is unreachable" |
| M3 | drop `doc-critic` from `opencode.json` | FAIL — "… NOT registered for opencode in the source checkout" |
| M4 | drop `Write` from the doc-critic shim | FAIL — "lacks the Write tool — cannot record its progress/… note" |
| M5 | point the shim body at `.harness/` | FAIL — "resolves against .harness/ — that is the INSTALLED shim's body" |
| M6 | `opencode.json` prompt → `.harness/` path | FAIL — prompt mismatch, with expected/actual on stderr |
| M7 | add an unclassified `agents/widget.md` | FAIL — "role file(s) not classified by this suite: widget" |
| M8 | add a `builder-heavy` shim (fix a known gap) | FAIL — "the KNOWN_GAPS exemption 'builder-heavy:claude' is obsolete; DELETE that line" |
| M9 | create a `.gemini/` front-end | FAIL — "source now registers roles in .gemini/ — that front-end is not covered" |
| M10 | rename `agents/scout.md` | FAIL — stale-classification guard |
| M11 | delete the R12 section from `agents/architect.md` | FAIL — "no longer has a '## Doc-critic checkpoint before `spec-ready` (R12)' section" |

Each of M1/M2/M3 alone is enough to break the checkpoint, and each is caught alone —
which is the point of asserting the three preconditions separately.

## Verification

- `./init.sh` — green ("environment ready — agents may proceed").
- `sh tools/run-tests.sh` — **34 of 35 suites pass, including `test_source_shims.sh`.**
- `dash tests/test_source_shims.sh` — green (POSIX-clean, not just `sh`-on-macOS-clean).

### One pre-existing failure, NOT caused by this change

`test_feature_park.sh` fails on `R7 precondition: the repo board already carries a parked
key, so this is not a no-parks board`. Reproduced on a pristine `git archive HEAD` export,
where it fails identically — so it predates this branch. Cause: `E21-F06` is parked in the
live board (`state/tasks.json`), and `tests/test_feature_park.sh:263-269` requires the
repo's own board to contain **zero** parked features as a precondition for its R7 case.
That is a permanent-suite assertion coupled to live board *content*: the first legitimate
park makes it unsatisfiable forever, which is what happened. It needs its own fix (build the
no-parks board as a fixture rather than borrowing the repo's), and is out of scope here.

## Findings the brief did not anticipate

1. **"No other source shim carries `Task`" is false** — `.claude/agents/orchestrator.md`
   already does. Detailed under Decision 1.
2. **`pr-fixer` in `opencode.json` is mis-classified in the brief's enumeration table.**
   The installer *deliberately never* registers `pr-fixer` in `opencode.json`:
   `gen_opencode_json` is documented as independent of `pr_loop`, and
   `tests/test_pr_loop.sh:482-483` asserts `opencode.json must not gain a pr-fixer entry`.
   Its OpenCode registration site is the file-based `.opencode/agent/pr-fixer.md`
   (`harness-install.sh:4679`). So the source gap is a missing `.opencode/agent/` tree, not
   a missing JSON key — a different fix from the one the table implies. Still out of scope;
   `register_ok()` models both mechanisms so the distinction survives in the suite.
3. **`test_feature_park.sh` is already red on `main`** — see above.
