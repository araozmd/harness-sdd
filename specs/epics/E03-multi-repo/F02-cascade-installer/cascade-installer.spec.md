---
id: E03-F02
title: Cascade installer
epic: E03
status: pending          # pending → spec-ready → in-progress → in-review → done
sdd: true                # false = quick task, skip full SDD
autonomous: false        # true = may bypass the human approval gate
depends_on: ["E03-F01"]
owner: araozmd
---

# Cascade installer — Functional Spec

## Context
F01 delivered the umbrella **coordinator model** — the `slices[]` schema, the
`umbrella.manifest.yaml` shape, the `umbrella.manifest` + `verification.integration_command`
config keys, and `docs/UMBRELLA.md`. But there is no way to *install* it: the current
`harness-install.sh` is single-target with no git detection. To stand up the motivating
`viernes/` case (a non-git umbrella over five sibling repos) an operator must run the
installer once per child by hand, hand-write `umbrella.manifest.yaml`, and — because the
installer deliberately preserves an existing `.harness/harness.config.yaml` on upgrade —
the F01 config keys never reach a harness that was installed before F01.

This feature extends `harness-install.sh` so a single invocation can **cascade** across an
umbrella: write a coordinator profile in the umbrella dir, discover and install the normal
child profile into each immediate git child, and auto-populate the manifest. It also adds a
**non-destructive config migration** so the F01 keys (and any future additive defaults)
reach already-installed harnesses without clobbering bootstrap-set values.

This is a **harness feature** — it changes the installer, `init.sh`, the example manifest
and docs. No application code is produced. The hard constraint: the existing single-target
behavior (no `--umbrella` flag) must be **byte-for-byte behaviorally unchanged**.

## Business rules
- **Two install profiles.** The **coordinator profile** (umbrella dir, typically non-git)
  gets the full harness body, the manifest, and `verification.integration_command`
  configured; it is NOT expected to run per-repo unit tests. The **child profile** is the
  existing normal `.harness/` install, unchanged.
- **Cascade in three steps.** Installing into the umbrella dir (a) writes the coordinator
  profile there, (b) scans its immediate children and installs the child profile into each
  child that is a git repo, then (c) auto-populates `umbrella.manifest.yaml`.
- **One level deep, git-gated.** Scan IMMEDIATE children only by default (deeper scan is an
  explicit opt-in flag). A child qualifies iff it contains `.git` as a **directory OR a
  file** (covering worktrees/submodules). Hidden/dotfile dirs and the umbrella's own
  `.harness` are skipped.
- **Manifest keys obey the slice-id grammar.** Each discovered repo's manifest key must
  match `^[a-z0-9-]+$` (the same grammar `init.sh` enforces and the slice-id `@<repo>`
  segment requires). A child whose directory name violates it is surfaced and skipped, not
  written as an undispatchable entry.
- **Idempotent + additive.** Re-running rediscovers newly-added repos and appends them
  WITHOUT clobbering project-owned content (the same per-repo guarantee the installer gives
  today). A manifest entry's project-owned fields are never overwritten on upgrade.
- **Non-destructive config migration.** On upgrade the installer preserves the existing
  `.harness/harness.config.yaml`; this feature appends any missing default keys to that
  preserved file while retaining every project-owned value (and surrounding comments). This
  applies to both coordinator and child installs.
- **Single-target is sacred.** With `--umbrella` absent, the installer behaves exactly as
  today — only the additive config migration (an explicit, value-preserving step) is layered
  in, and it must not change any existing value.

## Definitions
- **Umbrella dir** — the (typically non-git) parent directory passed with `--umbrella`,
  hosting the coordinator harness and sibling child repos.
- **Coordinator profile** — the install variant written to the umbrella dir: full body +
  manifest + `integration_command`, no per-repo test wiring expected.
- **Child profile** — the existing single-target `.harness/` install, unchanged.
- **Immediate child** — a direct subdirectory of the umbrella dir (depth 1).
- **Git child** — an immediate child containing `.git` (a directory or a file).
- **Config migration** — appending missing default top-level/nested keys to a preserved
  `harness.config.yaml` without altering existing values or comments.

## Acceptance criteria (EARS)
> Each is one testable behavior with a stable id. See docs/SPEC-FORMAT.md.
> "the installer" = `harness-install.sh`.

### CLI surface
- **R1** — The installer shall accept an umbrella mode invoked as
  `harness-install.sh --umbrella <umbrella-dir>`, in addition to the existing
  `harness-install.sh <target>` single-target form.
- **R2** — Where `--umbrella` is absent, the installer shall treat its positional argument
  exactly as today (single-target install into `<target>`), with no discovery, no cascade,
  and no manifest writes.
- **R3** — If the installer is invoked with neither a positional `<target>` nor
  `--umbrella <dir>` (or with an `--umbrella` value that is not an existing directory),
  then the installer shall print a usage error and exit non-zero, making no filesystem
  changes.
- **R4** — Where the `--recursive` (deeper-scan) flag is absent, the installer shall scan
  only the umbrella's immediate children (depth 1).

### Cascade — coordinator profile
- **R5** — When invoked in umbrella mode, the installer shall write the coordinator profile
  (the full harness body, identical to a normal install) into `<umbrella-dir>/.harness/`.
- **R6** — When writing the coordinator profile on a fresh install, the installer shall set
  `umbrella.manifest` in the coordinator's `harness.config.yaml` to the path of the
  auto-populated `umbrella.manifest.yaml`.
- **R7** — When writing the coordinator profile, the installer shall ensure the coordinator
  config carries a `verification.integration_command` key (left blank for bootstrap to fill
  if not already set), and shall NOT set a per-repo `test_command` for the coordinator
  beyond the existing single-target seeding behavior.

### Discovery
- **R8** — When scanning the umbrella, the installer shall select an immediate child as a
  git child iff it contains `.git` as either a directory or a regular file.
- **R9** — While scanning, the installer shall skip any immediate child whose name begins
  with `.` (hidden/dotfile dirs), and shall skip the umbrella's own `.harness` directory.
- **R10** — For each discovered git child, the installer shall install the child profile
  (the normal single-target `.harness/`) into that child, applying the same fresh-vs-upgrade
  rules a direct single-target install would apply to that child.

### Manifest auto-population
- **R11** — When in umbrella mode, the installer shall create
  `<umbrella-dir>/umbrella.manifest.yaml` if it does not exist, with a top-level `repos:`
  mapping.
- **R12** — For each discovered git child, the installer shall add a manifest entry keyed by
  the child's directory name, with `path` set to the child's location relative to the
  umbrella dir, and `init`, `test_command`, `delegate_cmd` set to TODO placeholders (or to a
  trivially-detected value).
- **R13** — If a discovered child's directory name does not match `^[a-z0-9-]+$`, then the
  installer shall skip that child (write no manifest entry and perform no child install for
  it) and print a clear message naming the child and the grammar it violates.
- **R14** — When re-run, the installer shall add manifest entries for newly-discovered git
  children and shall NOT overwrite the project-owned fields (`path`, `init`, `test_command`,
  `delegate_cmd`) of any manifest entry that already exists.
- **R15** — The manifest the installer writes shall be readable by `init.sh`'s existing
  umbrella manifest check (same `repos:` / two-space key / `path:` grammar) and shall use
  repo keys that satisfy `init.sh`'s `^[a-z0-9-]+$` validation.

### Idempotency & project-file preservation (per repo)
- **R16** — When re-run in umbrella mode, the installer shall preserve every child's
  project-owned content (`specs/product.md`, `state/tasks.json`, `specs/epics/`, `progress/`,
  `init.project.sh`) exactly as the single-target upgrade does today.
- **R17** — When re-run in umbrella mode, the installer shall not duplicate the entrypoint
  harness block in any child's `CLAUDE.md`/`AGENTS.md`/`GEMINI.md`, matching today's in-place
  replacement guarantee.

### Config migration (non-destructive)
- **R18** — When upgrading a target whose preserved `harness.config.yaml` is missing one or
  more default keys present in the shipped config (e.g. `umbrella.manifest`,
  `verification.integration_command`), the installer shall append the missing keys with
  their shipped default values.
- **R19** — While migrating a preserved config, the installer shall retain every
  already-present key's value byte-for-byte (it shall change no existing value and remove no
  existing key or comment).
- **R20** — Where a preserved config already contains all default keys, the config-migration
  step shall make no change to that file (idempotent: a second run produces an identical
  file).
- **R21** — The config migration shall apply to both the coordinator install and each child
  install, using only POSIX `sh` and zero external dependencies.

### Version stamp & manifest.txt
- **R22** — When in umbrella mode, the installer shall stamp `.harness/.harness-version` and
  regenerate `.harness/manifest.txt` for the coordinator and for every child it installs,
  exactly as a single-target install does.
- **R23** — The coordinator's `manifest.txt` shall list `umbrella.manifest.yaml` as a
  project-owned artifact (seeded once, never clobbered).

### Non-regression (hard requirement)
- **R24** — Where `--umbrella` is absent, a single-target install and any existing
  single-repo target shall be behaviorally unchanged from the pre-F02 installer, except for
  the additive, value-preserving config migration of R18–R20 (which changes no existing
  value).

## Out of scope
- Editing or generating any application source code in child repos (each child runs its own
  SDD loop via the delegate seam).
- Detecting or filling real `delegate_cmd` / `test_command` values beyond trivial detection —
  bootstrap fills these (placeholders are acceptable).
- Wiring or running the `integration_command` (that is the coordinator's runtime concern,
  F01) — F02 only ensures the key is present/seeded.
- Removing or de-registering manifest entries for repos that disappear (prune is not
  required; only additive discovery).
- Nested / multi-level umbrellas as a default (deeper scan is gated behind `--recursive` and
  its full semantics beyond "depth > 1, still git-gated" are deferred — see open questions).
- Converting the umbrella directory into a git repo.

## Open questions
- **`--recursive` depth semantics.** R4 fixes depth-1 as default and `--recursive` as the
  opt-in. Should `--recursive` mean "unbounded depth, git-gated, still skip dotfiles and
  nested `.harness`", or take an explicit `--depth N`? Proposed: a boolean `--recursive`
  meaning "descend into non-git children looking for git children, stop descending once a
  git child is found." Confirm before locking, or defer `--recursive` to a follow-up and
  ship depth-1 only.
- **Manifest key collision.** Two children could normalize to the same valid key only if the
  grammar allowed normalization; since R13 skips (not normalizes) invalid names, collisions
  can only arise from identical directory names (impossible as siblings). Confirm no
  normalization is wanted (keep keys = literal dir name).
- **Coordinator `test_command`.** R7 leaves the coordinator's per-repo `test_command` at the
  existing blanked-on-seed default. Confirm the coordinator should rely solely on
  `integration_command` and have no unit `test_command`, rather than a sentinel that makes
  the Reviewer skip per-repo tests for a coordinator.
