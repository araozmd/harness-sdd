---
id: E24
title: "Upgrade integrity: an unlanded upgrade must not run silently"
status: done             # draft → planned → in-progress → done (pending = legacy alias of planned; rollup of its features)
owner: araozmd
---

# Epic E24 — Upgrade integrity: an unlanded upgrade must not run silently

## Business brief
`harness-install.sh` writes an upgrade into a target. Nothing anywhere checks that the
upgrade was ever **landed** — committed, on the branch the target actually runs from.
The installer's job ends at `write`; `init.sh`'s job starts at `read`; between them sits
a gap no gate covers.

The gap is observable today. In a five-child umbrella (`~/repos/viernes`) the v0.50.x
cascade wrote 26–29 files into every child and **none of it was committed**. The
consequences were invisible for days:

- Three children's committed `harness.config.yaml` still predated the `change_size`
  block, so the change-size classifier ran against a config that has no budget — while
  `migrate_config()` (`harness-install.sh:396-414`) had *already appended* that block on
  disk. Present in the working tree, absent from the branch.
- Every Builder and Reviewer sub-agent spawned in those repos read agent prompts that are
  not the prompts the repo ships. Each session ran on a body no reviewer had approved and
  no commit records.
- One stray `git add -A` away from being swept into an unrelated feature's PR, where it
  would land unreviewed under someone else's diff.

Nothing failed. That is the defect. A half-applied upgrade is byte-for-byte
indistinguishable from a clean one at runtime, because **`init.sh` never reads
`.harness/.harness-version`** — the stamp the installer writes at
`harness-install.sh:2194` is consumed only by the *next installer run*
(`harness-install.sh:1794`) for upgrade detection. At runtime it is dead metadata.

The diagnosis that matters: **the cascade is not broken.** `--umbrella` discovers every
depth-1 git child and re-installs idempotently, and `migrate_config()` append-seeds the
missing keys into project-owned config. Distribution works. *Landing* has no owner, and
*drift* has no detector. Both of those are this epic.

## Why "one copy at the umbrella" is not the fix
The tempting response to N drifting copies is to keep a single harness at the umbrella
root, reduce each child to a pointer, and require every session to start at the umbrella.
It halves the right problem and creates a worse one.

It is right that the **source of truth** should be single — specs, board, and prompt
bodies genuinely should not be forked N ways, and `docs/CONFIG-LAYERING.md` already argues
exactly that for `CLAUDE.md`.

It is wrong that the **runtime** should be single. The child repo is entered by callers
that cannot `cd` to anyone's umbrella: the Codex GitHub App reviewing that child's PR, CI,
a teammate who cloned only that repo, a cloud agent, a fresh worktree. A manifest that says
"start at the root" is a note to a human and unreadable by every one of them — and the
`/sdd-pr-loop` lane runs against child PRs specifically. Worse, it is unenforceable: every
violation degrades **silently**, which is the exact failure class this epic exists to end.

And it would relocate the version problem rather than remove it. The umbrella `.harness/`
is still a vendored copy that must be upgraded and committed, with no runtime guard. Blast
radius drops from N to 1 — real, and worth having — but the mechanism that bit us (write →
never land → nothing checks) survives untouched at N=1.

So: fix the guard (F01) and the landing (F02) first, because they fix the actual defect
under *either* layout. Then take the single-source-of-truth win properly (F03) — by
thinning the child to what it needs to stand alone and resolving the rest from the umbrella
when one is present, rather than by emptying the child and hoping nobody enters it.

## Success criteria (epic level)
- A target whose installed body differs from what its branch records **stops**, with a
  message naming the drift, instead of running on unapproved prompts.
- `harness-install.sh` cannot report a successful upgrade while that upgrade is unlanded.
- A child repo entered on its own — by CI, a PR reviewer, or a fresh clone — still works.
- The prompt bodies, docs, and role definitions have exactly one source of truth per
  umbrella, without a second copy per child drifting away from it.

## Features
| id | title | status | sdd | depends_on |
|---|---|---|---|---|
| F01 | `init.sh` drift guard: refuse to run on an unlanded harness | pending | true | — |
| F02 | The cascade lands the upgrade (or reports that it did not) | pending | true | F01 |
| F03 | Thin the child: umbrella-resolved body with local fallback | pending | true | F01, F02 |
| F04 | Migrate existing children to the thin layout (+ `--standalone`) | pending | true | F03 |

## Notes
**Sequencing is deliberate.** F01 is the cheapest change and the only one that fixes
today's live defect on its own — it converts silent drift into a stop, under the current
layout, with no migration. F02 closes the producing side so the guard is rarely tripped in
anger. F03 is the layout change, and it is last because it is the only one that needs a
migration path for already-installed targets — and because F01's guard is what will make
F03's rollout safe to observe.

**F01 must not become a fourth kind of flaky gate.** `init.sh` is run before every single
piece of agent work; a guard that misfires halts the whole harness. The failure mode to
design against is a false positive on a legitimately-customized target — project-owned
files (`harness.config.yaml`, `init.project.sh`, `specs/`, `state/`, `progress/`) are
*expected* to differ and must never trip it. Only the HARNESS-OWNED set
(the `manifest.txt` list at `harness-install.sh:2199`) is in scope.

**F03 split into F03 + F04 at spec time (E21).** The decision is recorded as `ADR-0004`:
a child keeps every body path, and in an umbrella install the *prose* tier (`AGENTS.md`,
`agents/`, `docs/`, `specs/_templates/`, `glossary.md`) holds a pointer stub while the
*program-read* tier (`init.sh`, `store/`, `tools/`) stays a full local copy. The tier line
is drawn by **what reads the file** — a program cannot follow a prose pointer — which is
also why "delete the child's copy" was never available: the generated front-end glue
resolves body paths inside the child's own `.harness/`.

F03 carries the mechanism and changes only what a *fresh* child install writes. Migrating
already-installed full-copy children — a destructive, pristine-only replacement — plus a
`--standalone` flag to re-materialise a full body in a thin child, is **F04**. Specifying
both together exceeded what one review pass covers, so the split is declared here rather
than discovered at PR time.

**F03 needs an ADR.** How a child locates its umbrella (env var, upward search, an explicit
path in `harness.config.yaml`), and what happens when it finds none, is a durable
architectural commitment with a real fallback story. It gets a decision record, not an
implementation detail buried in a `.plan.md`.

**Related prior art.** E16 (harness robustness) and E21 (change-size discipline) both
address "a gate that stopped meaning anything". This epic is the same shape applied to the
install path: a signal that was never wired up, rather than one that degraded.
