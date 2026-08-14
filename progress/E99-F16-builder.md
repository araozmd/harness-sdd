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

---

# Round 4 — `register_ok` rewritten as record + shared validator (Codex #3786832831)

## Why a rewrite and not a fourth patch

Three consecutive review rounds found the **same defect class in three different branches
of one function** — an assertion that named something stronger than it checked:

| round | branch | what it actually checked | what it claimed |
|---|---|---|---|
| 1 | `claude` | file exists | "the role is spawnable" |
| 2 | `opencode` JSON | key is present | ditto — and round 1's patch left a **comment saying the OpenCode branch already checked mode and prompt**, false about the code two lines below it |
| 3 | `.opencode/agent/<role>.md` | file exists | ditto — a **zero-byte file** would have satisfied the whole suite the moment `pr-fixer:opencode` was retired |

Patching one branch at a time reproduced the bug once per branch, because the branches had
no shared contract: each one decided for itself how much to check. Three instances is this
repo's stated threshold for rewriting the rule. So the branches are gone.

## The structure

`registration_probe <role> <front-end>` (python3, invoked from the shell wrapper
`register_ok`, which keeps the reasons in `REGISTER_WHY` for the failure message):

- **Every mechanism extracts the same record.** `Rec = namedtuple("Rec", "present name
  targets harness_rooted mode described")`. Three extractors — `claude-shim`,
  `opencode-json`, `opencode-file` — and nothing else. A namedtuple was chosen over a dict
  on purpose: a mechanism that forgets a field **raises**, it does not answer fewer
  questions than its siblings.
- **One validator asks the record five questions**: Present, Identity, Target, Mode,
  Described. There is no per-mechanism branch in the validator at all.
- **A record field that nothing asks about is a hard error.** `CHECKS` declares, per entry,
  which `Rec` fields it consumes, and the union is asserted equal to `Rec._fields`. Adding
  a field without adding a check exits 2 → `fail`, not a silent pass. (Mutation **S1**.)
- **Adding a front-end is a table edit**: `MECHANISMS` (front-end → mechanisms),
  `EXTRACTORS` (mechanism → extractor), `SITES` (mechanism → path for messages). A
  mechanism named in `MECHANISMS` with no extractor is a `KeyError`, not a skip.
- **Exit codes are three-valued**: 0 spawnable, 1 not (with per-mechanism reasons), **2 the
  suite itself is misconfigured** — unknown front-end, unasked field, non-record. Two is a
  hard `fail`, so a broken probe can never read as "not registered".

### The two traps that survived the rewrite, explicitly

1. **Containment vs equality.** `{file:./.harness/agents/x.md}` *contains* `agents/x.md`, so
   a containment test accepts the installed prompt verbatim. `targets` is therefore a list
   of **normalized, delimited** references compared for **equality**, and the reference
   regex carries two trailing lookaheads so `agents/x.md.bak` extracts as *no reference*
   rather than as `agents/x.md` (mutation **C4**). `harness_rooted` is kept as a separate,
   broader field — true if `.harness/` appears anywhere in the registration text — so an
   installed-style body is rejected even when its stray `.harness/` path is not a role file
   (this is what the old `! grep -qF ".harness/"` did; it was not weakened).
2. **The orchestrator.** `expected_mode()` encodes the mode **the installer actually emits
   per site** — `primary` for `orchestrator` in `opencode.json` (harness-install.sh's
   `agent:` map), `subagent` everywhere else, including every file-based agent
   (`gen_oc_agent` hardcodes it). An earlier tightening demanded `subagent` universally and
   **failed the correct orchestrator config**; that is the defect this suite exists to
   prevent, so the reasoning is inline at `expected_mode()`.

### Fields fixed BY THE MECHANISM, said out loud

The brief's rule — *comments must not claim more than the code does* — cuts both ways, so
each such field says so at its assignment:

- `claude-shim.mode` is `"subagent"` **by construction**: `.claude/agents/` has no mode key;
  every file there *is* a spawnable sub-agent. The Mode check is a **tautology** for this
  mechanism and detects nothing in the claude tree. It is filled rather than skipped so the
  coverage assertion can force the *next* mechanism to answer the question.
- `opencode-json.name` and `opencode-file.name` are the role **by construction** (the JSON
  key / the filename is the identity, and the lookup was keyed on it), so Identity cannot
  fail there; it is the **Target** check that ties those registrations to the role.
  Identity is a real check for exactly one mechanism — `claude-shim`, where Claude Code
  addresses the sub-agent by a frontmatter `name` that can disagree with the filename.

**Fifth question added: Described.** `tests/test_pr_loop.sh:481` requires a file-based
OpenCode agent to carry a `description`. All three mechanisms already carry one, so asking
it uniformly costs nothing and removes one more thing a stub registration can fake.

## Mutation matrix

Applied in a throwaway `git worktree add --detach`, one at a time, restored between each;
the working checkout was never mutated and the worktree was removed clean.
**Baseline green; 18 of 18 behaved as intended, none needed a second mutation to fail.**

| # | mechanism | mutation | result |
|---|---|---|---|
| C1 | claude-shim | delete `.claude/agents/doc-critic.md` | FAIL — `Present: no registration at .claude/agents/doc-critic.md` |
| C2 | claude-shim | frontmatter `name: doccritic` | FAIL — `Identity: declares name 'doccritic', expected 'doc-critic'` |
| C3 | claude-shim | body repointed at `.harness/agents/doc-critic.md` | FAIL — `Target: resolves against .harness/` |
| C4 | claude-shim | body target `agents/doc-critic.md.bak` (containment would accept) | FAIL — `Target: points at no well-formed role-file reference` |
| C5 | claude-shim | drop `description:` from the scout shim | FAIL — `Described: carries no description` |
| J1 | opencode-json | delete the `doc-critic` entry | FAIL — `Present` (both mechanisms reported) |
| J2 | opencode-json | `mode: primary` on `builder` | FAIL — `Mode: mode is 'primary', expected 'subagent'` |
| J3 | opencode-json | doc-critic prompt → `{file:./agents/scout.md}` | FAIL — `Target: points at ['agents/scout.md']` |
| J4 | opencode-json | prompt in the INSTALLED form `{file:./.harness/agents/doc-critic.md}` | FAIL — `Target: resolves against .harness/` |
| J5 | opencode-json | empty `description` on `builder` | FAIL — `Described` |
| J6 | opencode-json | **orchestrator flipped to `subagent`** | FAIL — `Mode: mode is 'subagent', expected 'primary'` |
| **F1** | **opencode-file** | **zero-byte `.opencode/agent/pr-fixer.md`, `pr-fixer:opencode` exemption AND the `.opencode` absence guard removed** | **FAIL** — `Target` + `Mode` + `Described`, all three |
| F2 | opencode-file | **well-formed** file-based agent, same two removals | **PASS** |
| F3 | opencode-file | well-formed but `mode: primary` | FAIL — `Mode` |
| F4 | opencode-file | body points at `.harness/agents/pr-fixer.md` | FAIL — `Target: resolves against .harness/` |
| F5 | opencode-file | no `description` | FAIL — `Described` |
| F6 | opencode-file | body points at `agents/reviewer.md` | FAIL — `Target: points at ['agents/reviewer.md']` |
| F7 | xfail machinery | well-formed file **but `KNOWN_GAPS` line left in place** | FAIL — `the KNOWN_GAPS exemption 'pr-fixer:opencode' is obsolete; DELETE that line` |
| S1 | structure | add a `model` field to `Rec` with no `CHECKS` entry | FAIL (exit 2) — `registration record fields unasked/unknown: ['model']` |

**F1 is round 3's finding, proved closed**; F2 proves the fix does not merely reject
everything. **F7 proves the xfail self-expiry still fires** at the exact moment the gap is
retired. The `orchestrator` control **passes at baseline** with its legitimate
`mode: primary`, and J6 proves that pass is a real assertion rather than a permissive one.

## Verification

- `./init.sh` — green.
- `sh tools/run-tests.sh` — **all 36 suites passed**.
- `dash tests/test_source_shims.sh` — green (POSIX-clean, not just `sh`-on-macOS-clean).
- `harness-install.sh`, `agents/*.md`, `state/tasks.json`, `VERSION`, `CHANGELOG.md`
  untouched — one file changed, `tests/test_source_shims.sh`.

## Findings this round that the brief did not anticipate

1. **The over-claiming was in a failure MESSAGE too, not only in comments.** The first cut
   of `check_mode` printed *"a caller cannot spawn what is not a subagent"* for every mode
   mismatch — including `orchestrator`, where the expected mode is `primary` and that
   sentence is the exact opposite of the truth. Caught by mutation J6 reading its own
   output. `check_mode` now branches its reason on which mode was wanted. Same defect
   class as rounds 1–3, one layer out: the diagnostic asserting more than the check knows.
2. **The `.opencode` absence guard and the `pr-fixer:opencode` xfail must be retired
   TOGETHER, and only one of them says so.** Creating `.opencode/agent/pr-fixer.md` trips
   the section-1 absence check ~70 lines before the xfail fires (mutations F1–F6 had to
   remove both to reach the code under test). The absence-check message already names both
   deletions; the `KNOWN_GAPS` comment does not. Left as is — the message the author will
   actually hit first is the complete one — but noted because it is invisible from the
   `KNOWN_GAPS` side.
3. **`mode` is not uniformly meaningful, and pretending otherwise would have been the next
   round's finding.** Claude's mechanism has no mode concept at all. The honest options
   were "skip the question for that mechanism" (which is what rounds 1–3 kept doing, one
   question at a time) or "answer it by construction and label it a tautology". The second
   keeps the record shape uniform — which is what makes the coverage assertion able to
   force a *future* mechanism to answer — at the cost of one check that provably detects
   nothing in one tree. That trade-off is stated at the assignment rather than hidden.
