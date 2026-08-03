# ADR-0004 — A child resolves the harness body through pointer stubs at the same paths

- **Status:** accepted (E24-F03, 2026-08-03)
- **Date:** 2026-08-03

## Context

Every child in an umbrella carries a full copy of the harness body. In the `~/repos/viernes`
cascade that is 26–29 files per child, five times over, byte-identical, each able to diverge
independently and each producing its own diff on every upgrade.

The obvious fix — *stop copying* — does not survive contact with how the body is read.
**The generated front-end glue resolves body paths inside the child's own `.harness/`**, and
some of those readers are programs, not agents:

| Reader | What it resolves | Can it follow a prose pointer? |
|---|---|---|
| `opencode.json` | `{file:./.harness/agents/<role>.md}` — interpolated by OpenCode | the file's *text* becomes the prompt, so yes, indirectly |
| `.codex/agents/*.toml` | `developer_instructions = "Read .harness/agents/<role>.md …"` | yes — an agent reads it |
| `.claude/agents/*`, `.agents/agents/*` | pointer prose at `.harness/agents/<role>.md` | yes |
| `init.sh` | `store/tasks.schema.json`, `tools/validate-board.py`, `tools/harness-owned-paths.sh` | **no** — it `exec`s and parses them |
| CI / the verification gate | `harness.config.yaml`'s `test_command` | **no** |

So a body file can never simply be **absent** from a child; it can only be **redirected**.
And redirection only works for files whose consumer is a *reader of prose*. That is the
line, and it is a property of the consumer, not of how duplicated the file looks.

Three mechanisms were considered:

1. **Pointer stubs at the same paths.** Every path a child has today still exists; in an
   umbrella install the prose-tier files hold a short redirect instead of the full body.
2. **Gitignore the resolvable tier and materialise it as a local cache.** The strongest
   de-duplication — zero upgrade diffs, nothing tracked twice. It also inverts E24-F01 and
   E24-F02, which exist precisely to prove the installed body is *committed*: a cached body
   is deliberately not. A PR reviewer's checkout and a CI clone would contain no body at all.
3. **Narrow dedup** — vendor everything, de-duplicate only what a child-rooted session
   provably never reads. Safe by construction, and it removes almost nothing: the table
   above shows a child-rooted session reads essentially the whole body.

The competing invariant is **standalone entry**: `init.sh` works, the verification gate
works, the PR loop works, for a child entered on its own — CI, a lone clone, a reviewer's
checkout, a fresh worktree. None of those can `cd` to anyone's umbrella.

## Decision

**In an umbrella install, a child keeps every body path; the prose tier holds a pointer stub
that redirects to the umbrella's copy. The program-read tier stays a full local copy.**

- **Tier by consumer, not by duplication.**
  - *Resolvable (stub):* `AGENTS.md`, `agents/*.md`, `docs/*`, `specs/_templates/*`,
    `specs/glossary.md`. Every consumer is something that reads prose and follows a
    reference.
  - *Standalone (full copy, unchanged):* `init.sh`, `tools/`, `store/`,
    `harness.config.yaml`, `.harness-version`, the root entrypoint blocks, and **all**
    generated front-end glue. Every consumer is a program that parses or executes the file.
- **The umbrella is located explicitly, not searched for.** The cascade writes
  `umbrella.root` into the child's `harness.config.yaml` — it is the one component that
  already knows the answer. An upward filesystem search for `umbrella.manifest.yaml` is
  zero-config but binds a child to whatever ancestor happens to match, which in CI or a
  developer's home directory is a silent, wrong answer. An explicit key is boring,
  greppable, and diffable.
- **No umbrella is not a broken environment.** With `umbrella.root` absent — every
  single-repo install — nothing changes: the child gets the full body it gets today. This
  is additive.
- **The stub is a contract, not a comment.** It names the resolved path, states that the
  umbrella copy is authoritative, and names the recovery step when the umbrella is
  unreachable. An agent that reads it knows what to do; `init.sh` never reads it at all.
- **Symlinks are not used.** They break on Windows checkouts, get committed by accident,
  resolve unpredictably inside git worktrees (`tools/fix-worktree.sh` already carries that
  scar tissue), and `harness-owned-paths.sh` refuses to trust symlinked components for
  ownership. A stub is an ordinary tracked file with none of those properties.

## Consequences

- **Easier.** Upgrading the umbrella stops producing N identical child diffs: a stub's text
  depends on the umbrella path, not on the body version, so it is stable across upgrades.
  One source of truth for prompt bodies, docs, and role definitions.
- **Easier.** E24-F01's drift guard and E24-F02's landing audit keep working *unchanged*.
  Stubs are tracked, committed files under the same pathspecs; nothing about ownership,
  the `local-only` subtraction, or "is the body committed?" changes.
- **Harder — a lone clone of a thin child gets prose that points somewhere it cannot see.**
  This is the real cost, and it is bounded: `init.sh` still passes, the verification gate
  still runs, CI is unaffected, and the PR-review path that reads root `AGENTS.md` still
  resolves. What degrades is an *agent session started inside a thin child that has been
  separated from its umbrella* — it reads a stub naming a path it cannot open. The stub
  says so explicitly rather than failing mysteriously, and re-materialising a full local
  copy is a follow-up capability (see below), not a manual repair.
- **Harder — the tier line must be defended per file.** "Which tier is this?" is now a
  question every new body file must answer, and the wrong answer fails asymmetrically: a
  program-read file placed in the resolvable tier breaks a standalone child *at parse time*,
  while a prose file left in the standalone tier merely fails to save a copy. When unsure,
  put it in the standalone tier.
- **Harder — `umbrella.root` is a path recorded in a committed file.** Moving or renaming
  the umbrella directory invalidates every child's key at once. That is visible and
  greppable rather than silent, but it is a new coupling that did not exist before.
- **Deliberately out of scope here.** Two things this decision *enables* but does not do:
  migrating already-installed full-copy children to the thin layout (a destructive
  pristine-only replacement), and a `--standalone` flag that re-materialises a full body in
  a thin child. Both are follow-up work with their own review surface; until then, an
  existing target keeps its full copy and `manifest.txt` says which layout it is in.
