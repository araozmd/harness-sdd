# Umbrella coordinator (cross-repo features)

Real products span more than one git repo. The umbrella coordinator is a thin,
**opt-in** layer that lets one product feature — one intent — fan out into N child
repos as **slices**, delegates each slice to that repo's own SDD loop, enforces a
cross-repo merge order, and rolls verification up so the feature is `done` only when
every slice passes **and** an integration check passes.

This is a harness feature. The umbrella **never writes source code**: it specifies
once (the shared spec) and delegates down. **By default** no new git repo is introduced —
the umbrella lives in a non-git parent directory hosting sibling child repos.
**Optionally** (`--shared-repo`, see [below](#shared-spec-repository-opt-in)) the umbrella
root can itself be a git repo that tracks **only** `.harness/` + the umbrella docs and
git-ignores the child product repos — a *shared spec repository* a team clones so epics,
specs, and task state are versioned and shared instead of stranded on one laptop.

## Opt-in switch (single-repo stays inert)
Umbrella mode is engaged **only** when `umbrella.manifest` in `harness.config.yaml`
points at an existing manifest file. Copy the shipped template to start — it lives at
the harness root as `umbrella.manifest.example.yaml`, and an installed harness places
it at `.harness/umbrella.manifest.example.yaml` (the installer copies it with the rest
of the body). With the
key unset or the file absent, the coordinator is inert and the existing single-repo
flow — `init.sh`, `verification.test_command`, the Reviewer's `done` verdict — behaves
exactly as it does today. The presence of the manifest file (not a boolean flag) is
the switch.

## Installing the umbrella (cascade)
Stand up the whole umbrella with a single command (see
[`INSTALL.md`](./INSTALL.md#umbrella-mode-cascade-install)):

```bash
./harness-install.sh --umbrella /path/to/umbrella-dir
```

It installs the coordinator profile into `<umbrella>/.harness/`, installs the normal
child profile into each immediate **git** child (depth 1), and auto-populates
`umbrella.manifest.yaml`.

### The landing audit — "complete" means committed

Writing an upgrade is not landing one. A five-child cascade once printed its green banner
and left 26–29 **uncommitted** files in every child: agents there then read prompts no
commit describes, and three children ran the change-size classifier against a committed
config with no `change_size` block while the installer had already appended it on disk.
Nothing failed.

Since **v0.52.0** the cascade ends by auditing every target it touched:

```
── landing audit ──
   no git    (coordinator)              (not a work tree — cannot verify)
   unlanded  viernes-bff                29 harness-owned path(s)
   landed    viernes-web
❌ install: the cascade wrote an upgrade that is NOT COMMITTED in 1 of 3 target(s).
```

| Outcome | Exit |
|---|---|
| every target committed | `0` |
| at least one target unlanded | **`3`** |
| the install itself failed | `1` |

`3` is deliberately distinct from `1`: *"the install broke"* and *"the install succeeded and
is unlanded"* are different outcomes, and a wrapper or CI job that cannot tell them apart
loses the only information that makes the code actionable. A **fresh** cascade into git
children reports `3` too — correctly, since nothing is committed yet.

A target that is not a git work tree (the default non-git umbrella root, for instance) is
reported and never counted as unlanded: it cannot be unlanded from anything.

**The audit never commits.** No staging, no committing, no branch changes — committing into
N repos the operator did not ask you to commit into is a far larger claim on their working
tree, and the constraints it would need to honour (never stage unrelated work, never touch a
foreign branch) are exactly the accidents this guard exists to prevent. `--dry-run` skips the
audit entirely, as it writes nothing. Re-run any time to pick up newly-added child repos — it is
idempotent and never clobbers a bootstrap-filled manifest entry. Bootstrap then fills
each entry's `test_command`/`delegate_cmd` and the coordinator's `integration_command`.

## The thin child (v0.54.0+)

Every child used to carry a full copy of the harness body — 26–29 files per child,
byte-identical, each able to diverge and each producing its own diff on every upgrade.

**Deleting the copy was never available.** The generated front-end glue resolves body paths
inside the *child's own* `.harness/` — `opencode.json` interpolates
`{file:./.harness/agents/<role>.md}`, the Codex role TOMLs say "Read
`.harness/agents/<role>.md`" — so a body file can only be **redirected**, never removed. And
a redirect only works where the consumer reads prose. `init.sh` `exec`s `tools/` and parses
`store/`; a program cannot follow a pointer.

So the tier line is drawn by **what reads the file**
([`ADR-0004`](../specs/adr/0004-umbrella-resolved-body-via-pointer-stubs.md)):

| Tier | Paths | In a child of an umbrella |
|---|---|---|
| **Prose** — an agent reads it | `AGENTS.md`, `agents/`, `docs/`, `specs/_templates/`, `specs/glossary.md` | a one-screen **pointer stub** at the same path |
| **Program** — `init.sh`/CI parse or exec it | `init.sh`, `store/`, `tools/`, the example files | a full **local copy**, always |

Generated front-end glue (`.claude/`, `.agents/`, `.opencode/`, `.codex/`) is program tier
and always local.

The cascade records the linkage as `umbrella.root` in each child's `harness.config.yaml`
(`../../`), written by the component that already knows the answer. An upward filesystem
search would bind a child to whatever ancestor happens to match — in CI or a home
directory, silently and wrongly.

### Standalone entry still works — that is the acceptance bar

A child entered on its own runs `init.sh`, runs its verification gate, and runs its PR
loop, because all three read the program tier. With the umbrella unreachable `init.sh`
says so and **still exits zero**:

```
ℹ️  umbrella at ../../ is not reachable — the prose body (agent prompts, docs) is remote
   and unavailable here; init.sh, verification and the PR loop are unaffected
```

What degrades is only an *agent session started inside a child that has been separated
from its umbrella*: it reads a stub naming a path it cannot open. The stub says exactly
that, and names the recovery step, rather than dangling.

### What this does and does not change

- A **single-repo** install is untouched: no `umbrella.root`, so the complete body is
  installed locally exactly as before. This is additive.
- An **already-installed child keeps its full copy.** A cascade never silently converts
  one — that is destructive and needs a pristine check. Converting one is an explicit,
  one-time request per child: see *Migrating an existing child* below. `manifest.txt`
  records which layout a target holds, and an ordinary cascade reports what it would have
  converted.
- Upgrading the umbrella no longer rewrites the prose body in N children: a stub's text
  depends on the umbrella path, not the version, so it is byte-identical across upgrades.
  `init.sh`, `store/` and `tools/` are still local copies and do still change.

## Migrating an existing child (`--thin`)

An umbrella that has been running since before the thin layout shipped has children that
each still carry a full local prose body. Converting them is **opt-in per child**, and the
command is:

```bash
./harness-install.sh --umbrella /path/to/umbrella-dir --thin
```

**Run it until it converges** — normally once, twice when the children were behind:

1. The coordinator is upgraded **first**, so it holds the current body. Every child whose
   prose tier already matches that body converts in this same run. A child that was behind
   is named, is upgraded by this run, and does **not** convert.
2. Only if run 1 named anything: those children now match, so a second identical run
   converts them.

`--thin` also works in single-target mode (`./harness-install.sh --thin <child>`) when you
want to convert exactly one child.

**The flag is consent, not ceremony.** It is required for the **first** conversion of a
given child. After that the child *is* thin, and every later cascade maintains the thin
layout with no flag and no prompt. An ordinary run against a *full-copy* child converts
nothing and instead reports whether it would — that report is how the option is
discovered, and it is deliberately not step one of anything. **Never run an unflagged
cascade as a "preview pass" before the migration:** the unflagged path is the ordinary
full-copy branch, which overwrites the whole prose tier from source on every run, so it
*destroys the very differences it just reported*.

### Pristine-only, and all-or-nothing

A prose-tier file is replaced by a stub only when it is **byte-identical to the umbrella's
copy of the same relative path** — the copy the stub will point at. The question a
conversion asks is *if I drop this content and redirect, does the child lose anything?*

A tier converts **whole or not at all**. If any prose-tier path differs — content, or
present on one side only — then **no** file in that child converts, and every differing
path is named:

```
child already holds a full body — NOT converted to the thin layout: these prose-tier
paths differ from the umbrella's copy
  differs: agents/builder.md
  differs: agents/local-note.md
```

A child that is simply **stale** (installed from an older harness version) blocks for
exactly this reason, and that is correct: at the moment of comparison it genuinely holds
content the umbrella does not. The same run upgrades it, so the next run converts it —
that is why the procedure is "run until it converges".

What the refusal guarantees is narrower than it looks, and worth stating plainly: the
installer will not **redirect** a path to content the umbrella does not hold, and it names
every path it refused to redirect. It does **not** preserve a locally edited body file —
the full-copy path has always re-installed the whole prose tier from source on every run,
on both branches. The pre-run content is recoverable from `git diff` in that child, which
is why `init.sh` insists the installed body be committed.

### An unreachable umbrella converts nothing, and is never fatal

If a child records an `umbrella.root` that does not resolve to an installed harness body,
`--thin` **converts nothing, warns, and leaves the full local body in place** — with the
same exit status the run would have had without the flag:

```
⚠️  --thin: umbrella.root is recorded (../../) but does not resolve to an installed
   harness body — nothing converted, this target keeps its full local body
```

This follows from the pristine rule rather than from taste: with nothing to compare
against, byte-identity cannot be **established**, so no deletion can be justified. And it
must not abort, because a child entered on its own — CI, a lone clone, a PR reviewer's
checkout — is a supported state, not a degraded one. A target that records **no**
`umbrella.root` at all is not a child, so `--thin` is inert *and silent* there.

## `--standalone` — the way back

A thin child can be re-materialised into a full local body at any time:

```bash
./harness-install.sh --standalone /path/to/child
```

Every stub in the prose tier is replaced with the real body file **from that installer's
own source** (so a newer installer correctly lands the newer body), and the child's
`umbrella.root` is **cleared**. It is single-target only: `--standalone` with `--umbrella`,
and `--standalone` with `--thin`, are both rejected before anything is written. Applying it
to a target that already holds a full local body is fine — it re-installs the body, clears
the key and exits zero.

**What clearing `umbrella.root` does and does not buy.** `umbrella.root` means exactly one
thing — *resolve my prose body from here* — and after `--standalone` that statement is
false, so leaving it set records a relationship that no longer holds and makes `init.sh`
keep reporting a linkage that governs nothing. Clearing it costs nothing structurally:
umbrella **membership** comes from the cascade's directory discovery and
`umbrella.manifest.yaml`, so a detached child keeps its manifest entry, its slices and its
dispatch.

It is **not a permanent opt-out**. The cascade re-records the key for every child it
installs, and the shipped config seeds `root: ""` — so "cleared" is indistinguishable from
"never set". What actually makes `--standalone` durable is the **layout**: the child is
full-copy again, and every run that does not pass `--thin` leaves a full-copy child alone.
A per-child permanent exclusion would need a new recorded key, and there is not one.

## Shared spec repository (opt-in)
By default the umbrella is a throwaway parent directory — the coordinator's `.harness/`
(specs, `state/tasks.json`, progress) then lives only on whoever ran the cascade. For a
team, that strands the planning state on one laptop and invites duplicated epics/features.

Pass **`--shared-repo`** to version-control the umbrella root instead:

```bash
./harness-install.sh --umbrella /path/to/umbrella-dir --shared-repo
```

After the normal cascade it:
1. **`git init`s the umbrella root** — but **only if it has no `.git` yet**. An existing
   repo is never re-initialized.
2. **Append-seeds the umbrella-root `.gitignore`** to ignore the product child repos it
   just discovered (each stays its **own** repo, never a gitlink), on top of the
   per-developer agent state every install already ignores
   (`.claude/settings.local.json`, …). Append-only — an existing `.gitignore` is never
   clobbered. See [`../umbrella.gitignore.example`](../umbrella.gitignore.example) for the
   intended shape and [`CONFIG-LAYERING.md`](./CONFIG-LAYERING.md) for shared-vs-personal.

The result is a **spec repository**: the umbrella root is a git repo that tracks `.harness/`
+ the umbrella docs (`CLAUDE.md`, `AGENTS.md`, `README.md`) and git-ignores the product
repos cloned into it. Teammates `git clone` it to get the shared specs + task state, then
clone the product repos beside the harness. `--shared-repo` only governs whether the root
is version-controlled; it is orthogonal to the manifest, which still drives slice dispatch.
The local TaskStore is now shared state — commit `.harness/` changes alongside the feature
they describe so others pull a consistent board. Omit the flag and the umbrella behaves
exactly as before (non-git parent dir).

## Concepts
- **Umbrella** — the parent directory hosting the coordinator harness. Non-git by default;
  optionally its own git repo (a *shared spec repository*) under `--shared-repo` (above).
- **Slice** — a per-repo unit of work for one cross-repo feature. In the TaskStore a
  feature carries an optional `slices[]` (see `store/local.md` and
  `store/tasks.schema.json`); each slice has `id` (`<feature-id>@<repo>`, e.g.
  `E03-F01@viernes-bff`), `repo`, `status`, `merged`, `spec_path`, optional `pr` (the
  PR URL the child loop opened — the merge-poll selector), and cross-repo
  `depends_on`. A sliced feature can only be persisted `done` when **every** slice is
  `done`+`merged` (enforced by `tasks.schema.json` cross-field validation and the
  `init.sh` fallback), so a hand-edited store cannot unblock dependents early.
- **Manifest** — `umbrella.manifest.yaml`: maps each `repo` to its `path`, `init`,
  `test_command`, and (only for `backend: delegate`) `delegate_cmd`. The coordinator
  reads it to locate and dispatch each child repo. **Two path bases, by design:** the
  `umbrella.manifest` value in `harness.config.yaml` resolves relative to the harness
  dir (`.harness/`, `init.sh`'s cwd), while each entry's `path:` resolves relative to
  **the manifest file's own directory** (the umbrella root). The cascade installer
  reconciles these by placing the manifest at the umbrella root and pointing
  `umbrella.manifest` at `../umbrella.manifest.yaml`.
- **Contract artifact** — the single pinned inter-repo seam (see below).

## Spec home = umbrella; slices = child repos
The shared `.spec`/`.plan` live in the umbrella harness. Per-repo `.tasks`/`.tests`
**slices** are emitted into each child repo. Each slice maps to one child-repo feature
that runs its own SDD loop.

## Contract artifact (one contract, no drift)
The shared spec pins **exactly one** contract artifact — the inter-repo seam (an
OpenAPI fragment, an event schema, shared types, …) — at a **stable path** in the
umbrella and references it **by a stable id** from the `.spec.md`/`.plan.md`.

- Proposed stable location: `specs/epics/<epic>/<feature>/contract/`.
- The artifact's concrete **format is intentionally unspecified** — only its
  existence, its single-pin location, and its traceability are required. Over-pinning
  the format would cascade errors into every child repo's slice.
- **Every emitted slice's `.tasks`/`.tests` references the pinned contract artifact**
  (by the same path/id), so the traceability matrix links every slice back to the one
  shared seam. Parallel Builders in different repos therefore agree on the wire/shape.

## The coordinator loop (dispatch + gating)
This loop is an **additive** behavior of the Orchestrator (see the "Umbrella mode"
section of `agents/orchestrator.md`); no role file is forked. It is engaged only when
`umbrella.manifest` is set. For each cross-repo feature:

1. **select** — among the feature's slices, pick the lowest-id slice that is
   actionable and whose **every** `depends_on` upstream slice is `done` **and**
   `merged`. Repeatedly applying this rule yields a topological order. If a slice
   names a `repo` that is **not** a key in the manifest, refuse to dispatch it and
   report an error that names the missing repo.
2. **dispatch** — how a slice is dispatched is chosen by `execution.builder.backend`
   in the umbrella's `harness.config.yaml` (the same global Builder switch documented
   in `agents/builder.md`). Both modes run **from that child repo's working directory**
   (`cd` into the manifest `path` first):

   - **`in-session` builder (default, zero-dependency).** The Orchestrator drives the
     child repo's **own SDD loop** from inside it — not a bare Builder. Because Builder
     Loop A refuses to write code unless the *local* feature is `in-progress`, and the
     slice's status lives in the **parent** TaskStore, the Orchestrator first **seeds
     child-local state**: it ensures the child repo's TaskStore has a feature entry for
     the slice (pointing at the emitted slice spec) set to `in-progress`. It then spawns
     the **Builder** sub-agent (clean context, `cd`'d into the manifest `path`, handed
     only that slice's `.spec`/`.plan`/`.tasks`/`.tests` plus the pinned contract
     artifact) to implement via Loop A, lets the child repo's **Reviewer** verify, opens
     the child repo's PR, and **captures its URL** for the slice `pr`. (Builder Loop A
     only reports completion; PR creation is part of the child loop, not the Builder.)
     The per-repo `delegate_cmd` is **not used** here and may be left empty. **This is
     the natural mode for a single code-agent session driving every child repo** — it
     needs no external executor.
   - **`delegate` builder (only when an executor is wired).** Invoke that slice's repo
     `delegate_cmd` from the manifest using the existing seam contract **verbatim**:

     ```
     <delegate_cmd> <feature-id> <abs-spec-path>
     ```

     so a repo-local relative `delegate_cmd` (e.g. `./run-sdd.sh`) resolves correctly.

   In **both** modes the umbrella **never edits source files** in the child repo
   itself — the child repo's own SDD loop owns implementation, its PR, and its review.
3. **gate** — never dispatch a downstream slice's Builder, nor open that downstream
   repo's PR, while any of its upstream `depends_on` slices is not yet `done` **and**
   `merged`.
4. **fail-stop** — if a dispatched slice fails (a `delegate_cmd` non-zero exit, or —
   under `in-session` — the child loop's Builder/Reviewer reporting it cannot complete),
   set that slice's status to `failed`, halt dispatch of its downstream dependents, and
   surface the failure. Do not improvise a fix.
5. **advance** — on a slice's successful completion, record its status as `done` and
   **persist the PR URL** into the slice's `pr` field — under `delegate` the executor
   returns it; under `in-session` it is the URL captured in the dispatch step's
   Review+PR sub-step. `done` alone does not unblock dependents.
6. **observe-merge** — poll the slice's PR to merge with `gh pr view <slice.pr>
   --json state` (a PR **URL** is a valid selector and needs no `-R`; never pass the
   short manifest `repo` key to `-R`). If no `pr` was persisted, fall back to a
   default-branch landing check in the manifest `path` or require an explicit human
   `merged: true`, and surface that the slice awaits merge confirmation — never leave
   the chain silently stuck. On confirmed merge set `merged: true`, then re-run
   **select** so newly-unblocked downstream slices become dispatchable.

The dispatch step is just the existing single-repo Builder, scoped to one slice with
cross-repo gating/ordering around it. Under `in-session` it is the Builder sub-agent
run inside the child repo; under `delegate` it is the `execution.builder.delegate`
seam invoked once per slice. Nothing new is added to the Builder contract — umbrella
mode only adds the slice selection, gating, merge-poll, and rollup around it.

## Integration verification (rollup)
The feature `done` verdict is **derived** from slice state, then **persisted** (never
set `done` prematurely while a slice or the integration gate is red):

- **Gated** — while **any** slice of the feature is not `done`, the coordinator does
  **not** run the integration check.
- **Run** — only when **every** slice is `done` **and** `merged`, the coordinator runs
  the configurable `verification.integration_command` (the stack running together,
  e.g. `viernes-infra/dev.sh ci`). If `integration_command` is empty there is no
  integration gate.
- **Done** — the feature reaches `done` **only when** all per-repo slices pass their
  own verification **and** the integration command exits **zero**. When that holds the
  coordinator **writes** the derived `done` onto the feature (feature-level
  `depends_on` gates on the *stored* status, so a dependent feature stays blocked until
  the upstream `done` is actually persisted). The schema enforces this cross-field
  invariant — a feature cannot be stored `done` while any slice is not `done`+`merged`.
- **Failure** — if the integration command exits **non-zero**, keep the feature out of
  `done` and surface the integration failure.

## Manifest reference
See `umbrella.manifest.example.yaml`. One entry per child repo under `repos:`, each
with `path`, `init`, `test_command`, and `delegate_cmd`. `delegate_cmd` is **required
only under `backend: delegate`**; under the default `backend: in-session` it is unused
and may be left empty. A slice whose `repo` is absent from `repos:` is undispatchable
and must be reported.
