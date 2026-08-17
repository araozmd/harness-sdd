# Store backend: `local` (default)

Zero dependencies. State is plain files in the repo — this *is* the "harness lives
in the repo" pillar. Use this unless you have a reason not to.

## TaskStore → `state/tasks.json`
Validated by `store/tasks.schema.json` (and by `init.sh`).

- **list()** — read `state/tasks.json`, return `epics[].features[]`.
- **next()** — first feature whose `status` is actionable and whose `depends_on`
  are all `done`. Prefer lower epic/feature ids. Actionable means `pending`,
  `in-progress`, `in-review`, **or** `spec-ready` when the feature has
  `autonomous: true` (that flag skips the human gate, so the Orchestrator may move
  it straight to `in-progress` for Builder work). A `spec-ready` feature *without*
  `autonomous: true` is **not** actionable — it is parked at the human gate.
  The same gate applies to a `pending` + `sdd: false` fix: with `autonomous: true`
  it **is** actionable (the Orchestrator sets it `in-progress` and sends the Builder
  straight at it — there is no spec to gate); with `autonomous: false` (e.g.
  `/sdd-fix --gated`) it is **not** actionable — it is parked at the human gate until
  a human moves it to `in-progress` or re-stamps `autonomous: true`.
  **Epic gate:** features of a `draft` epic are **never actionable** — `next()`
  never selects them, regardless of the feature's own `status`, `sdd`,
  `autonomous`, or `depends_on` (`autonomous: true` does **not** override this
  gate; it skips the human approval gate only). Epics in `pending`, `planned`,
  `in-progress`, or `done` impose **no new gate** — their features are evaluated
  by the per-feature rules above, unchanged.

### Deterministic read-only selector (E16-F03)

`node tools/next-task.mjs --json` executes the `next()` and optional
`next_slice()` policy against the local TaskStore. Installed consumers use
`node .harness/tools/next-task.mjs --json`. Add `--mine` for the existing owner
filter or `--feature E##-F##` for an exact target. It emits one compact
schema-version-1 JSON object with fixed fields `schema_version`, `mode`,
`outcome`, `selected`, `reason`, `blocked`, and `summary`; it never writes state.

The Orchestrator treats a valid successful result as authoritative. Missing Node,
a nonzero invocation, invalid JSON, or an unsupported schema version is reported
and falls back to the preserved behavioral prose oracle in
`agents/orchestrator.md`. This changes neither the gates above nor the
Orchestrator's exclusive ownership of state writes.

- **get(id)** — find the feature object by `id`.
- **set_status(id, status)** — set the `status` of the **object the id addresses**.
  The whole persist is run **under an advisory lock** so concurrent writers (E15
  parallel fix chains) can never lose an update. Do **not** hand-edit
  `state/tasks.json` and re-validate inline; instead run the write through the lock
  helper, which owns the entire critical section in one process:

  ```
  # installed layout (consumer repo): helper at .harness/tools/, board at .harness/state/
  python3 .harness/tools/tasks-lock.py set-status <id> <status>
  # source layout (this repo): helper at tools/, board at state/
  python3 tools/tasks-lock.py set-status <id> <status>
  ```

  Run it from **any** cwd — the helper resolves the harness directory with this
  precedence: (1) an explicit `HARNESS_DIR=<dir>` env var wins as a
  highest-precedence escape hatch; else (2) when invoked from a **linked git
  worktree** (the E15 F02/F03 parallel-fix flow) it resolves the **single canonical
  board root in the MAIN working tree** via `git rev-parse --git-common-dir` (whose
  parent is the main worktree root), re-applying the source-vs-installed subpath
  under that root — **accepted only if the board actually exists there**; else (3)
  it falls back to its **own path** (`<HARNESS_DIR>/tools/tasks-lock.py`, so
  `HARNESS_DIR` = parent-of-parent of the script). A **primary** checkout is never
  remapped — it already *is* the main working tree, so it always takes (3).
  Because of (2), every worker in every worktree reads/writes the **same**
  `state/tasks.json` and contends on the **same** `state/tasks.json.lock` inode, so
  the no-lost-update guarantee holds across parallel worktrees, not only within one
  directory. Any git failure (not a repo, git absent, timeout) degrades to (3) —
  never crashes, never blocks.

  **One case exits non-zero instead of guessing.** From a **linked worktree** whose
  main working tree is unrecoverable from git — `git init --separate-git-dir` and
  submodule-style layouts, where `--git-common-dir` reports a separate metadata dir
  that is not the main worktree — step (2) cannot find the canonical board, and
  falling back to (3) would write the linked worktree's **own** checked-out board,
  silently defeating the shared-board guarantee. The helper therefore **fails loudly**
  and asks for an explicit override:

  ```
  HARNESS_DIR=/path/to/main/harness python3 tools/tasks-lock.py set-status <id> <status>
  ```

  The `/sdd-fix-parallel` coordinator sets `HARNESS_DIR` for every worktree worker
  automatically, so this is only visible when driving the helper by hand from a
  linked worktree in one of those layouts. Everywhere else — any cwd, a primary
  checkout in any layout, or a linked worktree of an ordinary repo — the plain
  command above is correct in both layouts with no override required.

  The helper acquires an advisory `fcntl.flock` on the sibling lockfile
  `state/tasks.json.lock` (resolved under the canonical `HARNESS_DIR`) → **re-reads
  `state/tasks.json` from disk inside the lock** (never a copy read before the lock)
  → applies the single status mutation to that fresh content → validates it (`json`
  parse **and** `store/tasks.schema.json` schema check) → atomically replaces the
  file (write-temp-then-`os.replace`, so a failure never leaves a torn file) →
  releases the lock. On validation failure it aborts non-zero, releases the lock,
  and leaves the original `state/tasks.json` untouched (fail-stop). Lock acquisition
  is **bounded by a timeout** (default ~10s): if the lock cannot be taken it aborts
  non-zero with an error naming the lockfile and the timeout — it never blocks
  forever and never writes unlocked. For a **serial (uncontended) caller** the lock
  is taken immediately and the resulting file is byte-for-byte what the old
  read-modify-write produced, so `/sdd-next` and existing tests are unchanged. Scope
  is **single-host** (a `flock`-family advisory lock; cross-machine coordination is
  out of scope). This adds **no new status value and no `store/tasks.schema.json`
  change** — only the concurrency discipline around the write. The best-effort
  `store.on_write_command` hook (see "Post-write sync" below) fires **after** the
  lock is released — never inside the critical section, so it can never hold the
  board lock.

  The id selects the object kind:
  - a **feature id** (`E06-F06`) edits that feature's `status` in `epics[].features[]`;
    keep the feature's `.spec.md` frontmatter `status` in sync.
  - an **epic id** (`E06`) edits that **epic's** `status` in `epics[]`; keep the epic's
    `epic.md` frontmatter `status` in sync. Epic-status writes are required by the
    epic-done rollup and the drift-check demotion (below) — `set_status` is the **one**
    write path for both feature and epic status; backends MUST implement the epic case.

  Since **v0.59.0** both "keep in sync" clauses above are **maintained and enforced**,
  not merely asked for.

  **Since v0.64.0 a `done` transition on a feature requires a landing record** (E99-F102):

  ```
  # single-repo feature
  python3 .harness/tools/tasks-lock.py set-status <id> done --evidence <ref|none:why>
  # SLICED feature — one binding per slice repository
  python3 .harness/tools/tasks-lock.py set-status <id> done \
      --evidence <repo-a>=<ref> --evidence <repo-b>=none:<why>
  ```

  `done` is what stops the selector routing an item, so a feature marked `done` whose work
  never merged is both unshipped **and** unreachable — an audit of 148 `done` features
  across seven repos found **four** (E99-F58, E99-F59 on never-pushed local branches;
  E09-F02, E99-F29 on closed, unmerged PRs), each found by accident rather than by any
  check. E99-F32's board entry cites E99-F29 as landed, which is the harm this exists to
  stop, already in the corpus.

  **Write it only once the work has LANDED.** An approve verdict says the work is correct,
  not that it merged. The order is: approve → open the PR (the feature stays `in-review`) →
  observe the merge → then `set_status(<id>, done, evidence=<merge commit>)`. Writing `done`
  on the approval re-creates the failure this record exists to prevent (an abandoned PR
  leaves a `done`, unselectable feature whose work never shipped) and makes the record
  itself unusable, since the only ref that exists then is an unmerged branch tip. There is
  no board state for "approved, awaiting merge" yet, and `in-review` is not inert — the
  selector routes it to a Reviewer — so **park** the feature while the PR is open and unpark
  it before the `done` write. `none:<why>` stays the one legitimate `done` with nothing to
  merge; it is not a way to close work that has simply not merged **yet**.

  ⚠️ **Recorded, NOT verified.** This helper does not check the reference. It runs no git,
  opens no connection, resolves no repository, and never decides whether a commit reached a
  default branch — so every ref is stored as `landed.verified: "unchecked"` (or `"declared"`
  for `none:<why>`), with a warning saying exactly that, and `repo`/`base` are absent. It
  **cannot** write `verified: "ancestor"`. Verification is a separate, later change; what
  you get today is that the claim is **on the board and greppable** instead of nowhere, so
  re-auditing is a scan rather than commit archaeology across four colliding id namespaces.

  **Every feature, sliced or not.** A sliced feature *looks* attested — the schema refuses
  `done` unless every slice is `done` **and** `merged` — but **nothing in the harness ever
  writes `slice.merged`**: every occurrence in `tools/` is a read or a type assertion, and
  the `set_slice_merged` contract below has the agent set it through `apply --mutator`. It
  is hand-typed, i.e. the say-so `--evidence` replaces. **E09-F02 is the proof**: three
  slices all `merged: true`, whose first slice's own `pr` points at `viernes-infra#24` —
  closed, unmerged. So a sliced feature satisfies **both** invariants.

  **A sliced feature's evidence is BOUND PER SLICE REPOSITORY** — `--evidence <repo>=<ref>`,
  repeated once per slice repo. One feature-level value names no repository, so it attests
  no particular slice: one slice's merge commit would carry the whole feature to `done`
  while another sat unmerged. A bare ref on a sliced feature is **REFUSED** (naming the form
  and the repos), as are a binding for a repo the feature has no slice in, a repeated
  binding, and a missing one (naming the repos still owed). `none:<why>` is expressible per
  slice. The record carries one entry per repository under `landed.slices`, and the
  feature-level `verified` rolls up to the **weakest** slice.

  What the helper does with the value:
  - **`none:<why>`** records `verified: "declared"` — work with no commit at all (a console
    action, a supersession). The reason after the colon is required.
  - **anything else** (a sha, a PR URL, a tag) is transcribed verbatim and recorded
    `verified: "unchecked"`, with a warning: nothing was proved. It is deliberately not
    classified further — "does this look like a commit id?" is a question only the code that
    resolves objects can answer, and that code does not exist here yet.
  - `--evidence` on any **non-`done`** transition is **REFUSED**: the record means one thing.

  **`set_status` does the syncing itself.** A feature transition rewrites the `status:` in
  that feature's `*.spec.md`, and an epic transition rewrites its `epic.md`, in the same
  locked critical section as the board write — so the two records move together or not at
  all. If a document cannot be read, the write **aborts and the board does not move**,
  because a board that advanced without its document is exactly the divergence the gate
  fail-stops on. The sync is deliberately narrow: it updates a `status:` that is **already
  declared**, never adds a frontmatter block, never creates a file, and never touches a spec
  declaring a different feature's `id`. `apply --mutator` is not synced — it may rewrite
  arbitrary structure, so there is no single (id, status) to follow.

  **`init.sh` verifies it** by running `tools/validate-board.py … --spec-root .`, which fails the gate when a
  spec's or `epic.md`'s frontmatter `status` disagrees with the board, naming the file and
  both values. The same pass resolves `spec_path` — an `sdd: true` feature past `pending`
  must point at a directory holding a readable `*.spec.md` **that declares that feature's
  `id`**, because a path pointing at a sibling feature's directory otherwise satisfies every
  other rule while handing the Reviewer the wrong spec. A spec that cannot be read or
  decoded is reported as such, never treated as one that simply declares nothing, and a
  `spec_path` that is absolute or escapes the repository via `..` is rejected outright
  (containment is to the harness root, not to `specs/` — the schema has never required
  that layout). Containment is not a property of `spec_path` alone: **every** read of a
  spec or `epic.md` resolves the path and checks it before opening, so a directory, a
  matched `*.spec.md`, or a `specs/epics/<id>-*` directory that is a symlink out of the
  repository is an escape too — in-repo by spelling, external in fact. One helper in
  `tools/validate-board.py` does the resolve-contain-open, and the writer in
  `tools/tasks-lock.py` reads through it and re-checks containment before writing, so a
  new read or write site cannot arrive without the rule. It does
  **not** fire for the
  `sdd: false` quick-fix lane (no Architect runs, so there is no spec by construction), for a
  feature still at `pending`, or for a feature inside a `draft` epic (already warn-only). A
  spec that declares no `status` is skipped — the contract is "keep in sync", not "must
  declare". The check runs only at the gate, never inside the `set_status` write path, which
  stays a pure function of the board data.

### Ownership & scoped selection (optional `owner` — E10-F01)
Both **epic** objects and **feature** objects carry an **optional** string `owner`
field in the schema. It is **additive and backward-compatible**: it is not in any
`required` array, so an owner-free `state/tasks.json` validates unchanged and no
migration is needed. With **no `owner` anywhere** and no `workflow.identity`,
selection is **exactly today's** board-wide `next()` — `owner` is ignored.

- **Effective owner.** A feature's effective owner = its own `owner` when set, else its
  parent epic's `owner`, else **unowned** (feature-level wins). Comparison is literal.
- **Identity.** The current developer's identity is `workflow.identity` in
  `harness.config.yaml`: empty ⇒ board-wide; `"@me"`/`"self"` ⇒ resolve to the authed
  `gh` user login (`gh api user`); any other value ⇒ literal string.
- **Scoped `next()` (`/sdd-next --mine`).** A **filter layered on top of** the ordinary
  `next()` above — it never relaxes any gate. It runs every existing gate (epic gate,
  `depends_on`-done, actionable status, human gate), then keeps only candidates whose
  effective owner equals the resolved identity, and picks the first by the usual lower
  epic/feature ordering. It is **owned-only**: it never selects an unowned feature and
  **never writes or claims** an `owner` (claim-on-select is E10-F02). If the identity is
  unresolved, or no owned actionable feature exists, it **fails closed** — selects
  nothing, reports, changes no state — and does **not** widen to board-wide.

### `next()` no-result diagnostic contract — E16-F01

The Orchestrator activates this contract when `next()` or scoped `next()` selects
nothing, explaining the existing gates across the board without changing
actionability. It also activates when top-level selection returns a sliced feature
but `next_slice(feature)` returns no slice while unfinished slices remain; that path
emits records only for unfinished slices of the selected parent feature. Do not run
whole-board top-level diagnostics for the sliced-parent path, and do not emit records
for any other feature or slice. Both paths use the same stable records, reason order,
and final summary below. Diagnostics are informational, successful, read-only
records; selection changes no state. E16-F03 must reuse this vocabulary and both
no-result activation paths **verbatim** in the future deterministic selector.

Candidate records have the exact shape
`blocked <id> [<reason-code>]: <human text>`. Sort candidates by numeric epic and
feature id, feature before slice, and lexical slice suffix. Emit all applicable
non-owner reasons for a subject in this order: `dependency-cycle`, `gated-epic`,
`parked`/`gated-owner`, `unmet-dependency`, `human-gate`; then scoped owner reasons
`owner-excluded`, `owner-unresolved`.

- `dependency-cycle`: `dependency cycle (<kind>): <id> -> ... -> <id>`, using the
  canonical closed feature or slice witness.
- `gated-epic`: `epic <id> is draft`.
- `parked`: `<reason> [(unblocked by: <text>)] [route when unparked: <route>]`, for a
  `parked` object with no `gate` — externally blocked, not workable *yet* (E06-F07).
- `gated-owner`: `owner gate: <reason> [(unblocked by: <text>)] [a person must act, not
  an agent; route when released: <route>]`, for `parked.gate: "owner"` — the automatable
  work is finished and every remaining requirement is a person's (E99-F77). Do not route
  an agent at it; the two codes are mutually exclusive and occupy the same position.
- `unmet-dependency`: `blocking dependencies: <id>=missing,
  <id>=<status>, <id>=done-but-unmerged`; name every blocker in canonical order.
  Missing and cross-kind ids use `missing` and never become cycle nodes.
- `human-gate`: exactly `spec-ready requires approval` or
  `gated quick fix requires approval`.
- `owner-excluded`: only in resolved `--mine`, only for an otherwise actionable
  candidate; exactly `effective owner=<literal>` or `effective owner=unowned`.
- `owner-unresolved`: subject `--mine`; exactly
  `workflow.identity=<empty>`, `workflow.identity=@me lookup failed`, or
  `workflow.identity=self lookup failed`.
- `no-candidates`: no subject and no blocked record; exactly
  `no actionable work [no-candidates]: board has no features` or
  `no actionable work [no-candidates]: all features are done`.

Bare `/sdd-next` emits neither ownership reason. A cycle does not hide other
dependency blockers: emit both applicable records. After one or more candidate
records, emit exactly
`no actionable work: selection blocked; see reasons above`.

### Epic lifecycle
The canonical epic lifecycle is `draft → planned → in-progress → done`. A `draft`
epic is an inception sketch (title + business brief only) whose features are never
selectable; a `planned` epic is drilled down and human-approved. Epic-level
`pending` is a **legacy alias of `planned`**, kept indefinitely for backward
compatibility: `pending` and `planned` are **gating-equivalent** — selection
treats them identically.

## Cross-repo features → `slices[]` (umbrella mode)
A feature may optionally carry a `slices` array — one entry per child repo for a
cross-repo (umbrella) feature. Each slice has `id` (`<feature-id>@<repo>`, e.g.
`E03-F01@viernes-bff`), `repo`, `status`, optional `merged` (true once its PR is
merged in that repo), optional `spec_path` (the slice's emitted `.tasks`/`.tests`),
optional `pr` (the PR URL the child SDD loop opened — the selector used to poll the
merge, since the short `repo` key is not a `gh` repo slug), and optional cross-repo
`depends_on` (slice ids). A feature with **no** `slices`
behaves exactly as a single-repo feature does today — the field is purely additive.

- **slices(id)** — read the feature's `slices[]` (empty/absent ⇒ single-repo).
- **next_slice(feature)** — the lowest-id slice that is actionable and whose every
  `depends_on` upstream slice is `done` **and** `merged` (topological order).
- **set_slice_status(feature, slice_id, status)** / **set_slice_merged(...)** —
  these are structural slice mutations, so express each as a temporary Python
  mutator exposing `mutate(data) -> data` and run it through the same guarded
  persist primitive:

  ⚠️ **`merged` is hand-typed and nothing verifies it.** No harness tool writes it — every
  occurrence in `tools/` reads it (`next-task.mjs`, `validate-board.py`, the schema
  cross-field) — so the boolean is only ever as true as the agent that typed it. E09-F02
  carries `merged: true` on a slice whose own `pr` is a closed, unmerged PR. That is why a
  sliced feature's `done` still needs `--evidence` **bound to each slice repository** (see
  `set_status` above), and why the record keeps the repositories apart.

  ```
  # installed layout; use tools/tasks-lock.py in this source repository
  python3 .harness/tools/tasks-lock.py apply --mutator <temporary-mutator.py>
  ```

  The mutator locates the feature and slice by id from the fresh board passed to
  it. The helper acquires the canonical lock, re-reads inside it, applies the
  mutation, validates, and atomically replaces the board. Do not hand-edit the
  slice or validate inline.

### Rollup rule (feature `done` is derived, then persisted)
For a sliced feature the coordinator **derives** the feature's status from its slices
rather than declaring `done` by fiat — but it **does persist** the derived result:

- While **any** slice is not `done`+`merged`, the feature's rolled-up status is **not**
  `done`, and the coordinator must NOT write `done` onto the feature.
- A feature becomes `done` **only when every slice is `done` and `merged`** **and** the
  feature-level integration check (`verification.integration_command`) has passed.
- **When those conditions hold, the coordinator writes the derived `done` onto the
  feature** through `tasks-lock.py set-status <feature-id> done --evidence <repo>=<ref> …`,
  once per slice repository — the rollup does **not** exempt it from the evidence
  requirement, because the per-slice `merged` flags it checks are hand-typed and unverified
  (see `set_status` above). This persistence is required:
  feature-level `next()` gates `depends_on` on the *stored* feature status, so a
  dependent feature (e.g. `E03-F02` depends_on `E03-F01`) stays blocked until the
  upstream feature's `done` is actually written.
- On each slice **advance** (a slice reaching `done`+`merged`), re-evaluate which
  downstream slices have become dispatchable, then re-check the rollup condition.

"Derived, never set directly" therefore means *never set `done` prematurely* (while a
slice or the integration gate is red) — not "never written". This guarantees there is
no path to a green feature with a red slice, while still unblocking dependents. The umbrella
dispatch/gating loop that consumes these semantics is specified in
`docs/UMBRELLA.md` and the "Umbrella mode" section of `agents/orchestrator.md`.

### Epic-done rollup (all features `done` ⇒ epic `done`, derived then persisted)
Beside the sliced-feature rollup above — and **additively**, not inside it — the same
"derive, then persist" discipline rolls an **epic** up. **When every feature of an epic is
`done`, the epic's `done` status is derived and persisted** by the Orchestrator (the owner
of `set_status`): it derives `done` from the fact that **all features are `done`**, writes it
onto the epic through `tasks-lock.py set-status <epic-id> done`. The helper performs
the validation before persisting. This
mirrors the feature rollup exactly — `done` is never set by fiat while any feature is still
open, but it **is persisted** once every feature is `done`. This introduces **no new status
value** and **no schema change**: `done` is already an epic-enum value (`store/tasks.schema.json`).

### Drift check on epic rollup (Scout re-validates, Orchestrator demotes)
Immediately **after** an epic rolls up to `done`, the Orchestrator triggers a **drift check**
to guard against stale rolling-wave plans. It spawns the **read-only Scout** in a drift-check
mode (see `agents/scout.md`) to re-validate the remaining `draft`/`planned`/`pending` epics
against what the just-completed epic produced (new/changed ADRs + architecture deltas + what
its features changed). The **Scout flags, the Orchestrator acts**:

- The Scout writes a per-epic still-valid/stale findings file under `progress/` and makes
  **no** state change (its read-only contract is preserved — it never writes `state/tasks.json`).
- The **Orchestrator demotes** a stale `planned`/`pending` epic to `draft` via `set_status`,
  then re-validates `state/tasks.json`. A stale `draft` epic **stays `draft`** (already the
  lowest planning state) but is **flagged** in the findings.
- **`in-progress` and `done` epics are never demoted** — the check concerns *future* planned
  work only. Demotion only ever moves an epic **backward**; re-drilling a demoted epic back to
  `planned` stays a manual `/sdd-drill` (F03) step.

The demoted epic's features become non-selectable behind `next()`'s epic gate until it is
re-drilled. This adds **no new status value** and **no schema change** — demotion reuses the
existing `draft` state.

## DocStore → markdown
- **read_spec(feature_id)** — read the 4 files under the feature's `spec_path`.
- **write_spec** — Architect writes `<feature>.spec.md|plan.md|tasks.md|tests.md`
  from `specs/_templates/`.
- **append_progress(run, note)** — write/append under `progress/<run>/`.
- **append_history(line)** — append one line to `progress/history.md`.

## Post-write sync (opt-in)
After **any persisted write** — `set_status`, `set_slice_status`, `write_spec`, and the
done rollup — the Orchestrator runs `store.on_write_command` (from `harness.config.yaml`)
**when it is non-empty**, invoked as `<cmd> "<feature-id>" "<op>"` with cwd = `HARNESS_DIR`.
This is the harness's generic, **VCS/PM-neutral** sync seam: the harness never learns what
the command does. A team might point it at a `git push` of `state/tasks.json` + `specs/`,
at a board mirror (`node tools/sync-board.mjs` — see [`board-mirror.md`](./board-mirror.md)),
or at a wrapper doing both.

- **Empty (default) ⇒ no hook** — exactly today's behavior.
- **Best-effort, never-blocking** — a non-zero exit NEVER rolls back `tasks.json` and never
  stalls `next()`. Do the local write regardless, then report the sync gap; never block
  feature work on it. (Same discipline as telemetry.)
- **Runs AFTER the board-write lock is released** — for a `set_status` persist the hook
  fires once the lock helper (see `set_status` above) has returned, i.e. *after* the
  advisory lock is released. The hook is never invoked inside the critical section, so it
  can never hold the board lock (E15-F01).
- `tasks.json` stays the **source of truth**; anything the hook pushes to is downstream.

## Notes
- Commit `state/tasks.json` and `specs/` so state is versioned with the code.
- This backend is fully compatible with `obsidian` — pointing a vault at the repo
  needs no migration.
