---
id: E38-F01
title: init.sh update check + consented upgrade with custom-config preservation preview
epic: E38-harness-self-update
status: in-progress      # pending → spec-ready → in-progress → in-review → done
sdd: true
autonomous: false
complexity: complex      # basis stated in Context: 12/12 of change_size.max_requirements, and a
                         # defect class the harness has already paid for (a program that rewrites
                         # the files it is executing from; E24 recorded the half-landed variant)
depends_on: []
owner: araozmd
---

# init.sh update check + consented upgrade — Functional Spec

## Context
A target that installed the harness is never told that a newer release exists. Upgrading
means remembering to pull a separate `harness-sdd` clone and re-running
`harness-install.sh` with the right selection; nothing shows beforehand whether the run
will overwrite a customization. This feature makes the installed `init.sh` check the
harness remote for the highest `vX.Y.Z` tag, print one notice line when it is newer than
`.harness/.harness-version`, and — **only at an interactive terminal** — offer to install
it. A consented upgrade fetches that tag, previews what it will preserve and what it will
replace, backs up locally edited harness-owned files, runs **that tag's own
`harness-install.sh`** (never a re-implementation of it), and then proves that the
project's `harness.config.yaml` values and the user prose in the root entrypoints survived.

`init.sh` is the gate every agent runs non-interactively, so the check is designed to be
unable to hurt it: it never blocks, never prompts, never changes the exit code, and is
bounded in time, off a TTY or offline. The user is a human operator at the terminal of a
single-repo install or of an umbrella coordinator; agents never see the prompt.

**Complexity basis.** The requirement count sits exactly at `change_size.max_requirements`
(12), and the plan names a defect class already paid for in this repo: a shell program that
replaces the body it is executing from (E24 exists because a written-but-unlanded body ran
silently). Both are stated signals, not a feeling.

## Business rules
- **Consent is explicit.** No file is written without a typed `y` at an interactive
  terminal. Interactive means stdin **and** stdout are terminals; the test hook
  `HARNESS_UPDATE_ASSUME_TTY=1` treats the session as interactive and reads answers from
  stdin, so the prompt path is testable without a pseudo-terminal.
- **The gate is never degraded.** Off a TTY, offline, on a failed or slow `ls-remote`, the
  check prints at most one informational line (none when the remote could not be read) and
  leaves `init.sh`'s exit code untouched.
- **Latest version** = the highest tag matching `^v[0-9]+\.[0-9]+\.[0-9]+$` advertised by
  `git ls-remote --tags <remote>`. Peeled refs (`^{}`), pre-release suffixes and any other
  tag name are ignored. Comparison is numeric per component against `.harness-version`
  (which may or may not carry the leading `v`).
- **Remote resolution**, first non-empty wins: `HARNESS_UPDATE_REMOTE` (env, per run) →
  `update.remote` in `harness.config.yaml` → `https://github.com/araozmd/harness-sdd.git`.
  A fork sets the config key. The value is passed to git after `--`; a value beginning with
  `-` is rejected as a misconfiguration (silent in `check`, named in `upgrade`).
- **Opt-out is silent.** `HARNESS_SKIP_UPDATE_CHECK=<non-empty>` (per run) or
  `update.check: false` (durable) skips the check with no output. Unlike E24's drift-guard
  override this is deliberately quiet: the check is a courtesy notice, not a gate, so a
  forgotten opt-out costs a notice, not safety. The test runner exports the env opt-out for
  the whole suite tree so pre-existing suites stay hermetic.
- **Skip where it cannot apply**: no `.harness-version` (the harness source repo, `--self`
  layout); `git` not on `PATH`; an umbrella **child** (`umbrella.root` non-empty — thin or
  full-copy). Children are upgraded by the coordinator's cascade, never independently.
- **Throttle.** The remote is contacted at most once per TTL (default 24 h,
  `HARNESS_UPDATE_TTL` seconds overrides); the verdict — including a failure — is cached under
  `.harness/progress/update-check/`, which every installed target's `.harness/.gitignore`
  already ignores (`progress/*/`). A declined version is remembered there: the notice still
  prints, the prompt does not, until a higher version appears.
- **Bounded.** `ls-remote` is given at most `HARNESS_UPDATE_TIMEOUT` seconds (default 3);
  past that it is abandoned and treated as a failure.
- **Reuse the installer.** The upgrade runs the fetched tag's `harness-install.sh` with
  stdin not a terminal and no selection flags. That is the installer's documented
  non-interactive upgrade path: it keeps the recorded front-end selection
  (`.harness/.agents`), `execution.builder.backend` and `pr_loop.enabled` byte-identical,
  appends only missing config keys (`migrate_config`), and replaces only the pointer block in
  `CLAUDE.md` / `AGENTS.md`. On a coordinator it is invoked with `--umbrella <umbrella-dir>` — the
  **umbrella dir** is the parent directory of the manifest file that `umbrella.manifest`
  names (resolved relative to `.harness/`) — so the cascade reaches every child exactly as a manual upgrade would, and keeps thin
  children thin. The installer's cascade exit `3` ("installed but unlanded", E24-F02) is the
  expected outcome of an upgrade nobody has committed yet and is reported as success.
- **Protected custom configuration** (proved, not promised): every existing line of each
  in-scope `harness.config.yaml` (coordinator and every manifest child that has one,
  including a child's explicit overrides) is still present in order afterwards — appended
  keys allowed, nothing altered or removed; and every byte of `CLAUDE.md` / `AGENTS.md`
  outside the `<!-- harness:begin -->…<!-- harness:end -->` block is identical afterwards.
- **"Locally edited"** = a regular file under one of the body paths the **fetched tag's
  installer will copy** — the entries of `HARNESS_BODY_PROSE` and `HARNESS_BODY_LOCAL` read
  from that `harness-install.sh` (today `AGENTS.md agents docs specs/_templates` and
  `init.sh store tools umbrella.manifest.example.yaml umbrella.gitignore.example`; a fixed
  copy of that list is the fallback when the read yields nothing, and the preview says so) —
  whose bytes differ from the **installed version's own tag** (`v<old>` in the
  fetched repo), or that does not exist in that tag at all (a local addition the body
  refresh will remove, because the installer replaces whole owned directories). When `v<old>`
  is not on the remote the baseline falls back to the incoming tag and the preview says so.
  Children's bodies are not previewed in this feature (see Out of scope).
- **Backups before replacement.** Every listed file is copied, same relative path, to
  `.harness/progress/upgrade-backup/<old-version>/`; the pre-upgrade snapshots used by the
  preservation proof go to `…/upgrade-backup/<old-version>/preservation/<repo-label>/`.
  An existing backup directory is never overwritten.
- **Self-replacement safety.** The upgrade rewrites `init.sh` and the update tool while they
  are the programs running. `init.sh` therefore `exec`s the tool for the write phase (the
  gate process no longer exists when the body changes), and the tool's script body is a set
  of function definitions ending in one `main "$@"` line, so the shell has parsed everything
  before any byte of the body is replaced.
- **Never commits.** The report tells the human that the E24 drift guard will fail `init.sh`
  until the upgrade is committed, and to re-run `init.sh` afterwards.
- **Size.** 12 R-ids = the budget; no override needed.

## Architecture alignment
> `specs/architecture.md` is absent in this repository (no `/sdd-plan` baseline), so this
> section is written on the ADR set alone; the inbox brief recorded no ADR ids.

- ADR-0004 — umbrella-resolved body via pointer stubs: the check is skipped in any target
  that records `umbrella.root` (a child), and a coordinator upgrade goes through the
  installer's `--umbrella` cascade, which is the only path that keeps a thin child thin;
  this feature adds no second body layout rule and never writes into a child itself.
- ADR-0005 — source-only surfaces emit only under `--self`: the update tool is **not**
  source-only — it ships to every target as body under `tools/` — and it goes inert in the
  source layout by the same stamp rule the E24 guard uses (no `.harness-version`), not by a
  `SELF_MODE` branch.

## Acceptance criteria (EARS)
> Each is one testable behavior with a stable id. See docs/SPEC-FORMAT.md. "The gate" is the
> installed `.harness/init.sh`; "the tool" is `.harness/tools/harness-update.sh`.

- **R1 — Notice.** When the gate runs in an installed target whose resolved remote
  advertises a `vX.Y.Z` tag numerically higher than `.harness/.harness-version`, the system
  shall print exactly one line `🔔 harness vX.Y.Z available (installed vA.B.C)` and shall
  leave the gate's exit code and every other gate line unchanged.
- **R2 — Silent skips.** Where any of the following holds — no `.harness/.harness-version`
  (source layout); `HARNESS_SKIP_UPDATE_CHECK` is non-empty; `update.check` is `false` in
  `harness.config.yaml`; `umbrella.root` is non-empty (an umbrella child); `git` is not on
  `PATH` — the system shall neither contact the remote nor print any update line, and the
  gate's output and exit code shall equal those of a run with the check disabled.
- **R3 — Failure is silent and bounded.** If `git ls-remote` exits non-zero or does not
  finish within `HARNESS_UPDATE_TIMEOUT` seconds (default 3), then the system shall print no
  update line, shall leave the gate's exit code unchanged, shall let the gate finish within
  that bound plus the gate's own duration, and shall cache the failed attempt so the remote
  is not contacted again before the TTL elapses.
- **R4 — Same or older is silent.** While the highest matching tag is numerically equal to
  or lower than the installed version, or no tag matches `^v[0-9]+\.[0-9]+\.[0-9]+$`, the
  system shall print no update line; tags that do not match (peeled `^{}` refs, pre-release
  suffixes, two-component versions, other names) shall not take part in the maximum.
- **R5 — Cache and TTL.** The system shall record each check's verdict and time under
  `.harness/progress/update-check/`; while a record younger than the TTL (default 86400 s,
  `HARNESS_UPDATE_TTL` overrides) exists, the system shall not run `ls-remote` and shall
  derive the notice from the record; when the record is older than the TTL or absent, the
  system shall run `ls-remote` once and rewrite the record.
- **R6 — Prompt only when interactive.** When a newer version is found (or cached) and the
  session is interactive (stdin and stdout are terminals, or `HARNESS_UPDATE_ASSUME_TTY` is
  non-empty), the system shall print `Install now? [y/N]` after the notice and read one line;
  on `y`/`Y` it shall start the upgrade (R7), on any other answer it shall record the declined
  version, continue the gate and leave its exit code unchanged. While the recorded declined
  version equals the available version, the system shall print the notice but not the prompt;
  a higher available version shall prompt again. While the session is not interactive, the
  system shall never print the prompt and shall never read stdin, even when stdin holds `y`.
- **R7 — Consented upgrade runs the fetched tag's installer.** When the human consents at
  the preview (R11), the system shall have fetched tag `vX.Y.Z` of the resolved remote into
  `.harness/progress/update-check/repo/`, shall run that checkout's `harness-install.sh
  <project-root>` with stdin not a terminal and no selection flag — so the recorded
  front-end selection, `execution.builder.backend` and `pr_loop.enabled` are reused as the
  installer's non-interactive upgrade path already guarantees — and, when the installer
  succeeds, shall print a report naming the old and new versions, the backup directory, that
  the upgrade must be committed before the E24 drift guard lets `init.sh` pass, and that
  `init.sh` must be re-run; the gate shall then exit `3` (upgrade applied, re-run required)
  with `.harness/.harness-version` equal to the new version. If the fetch or the installer
  fails, then the system shall say so, name the backup directory, and exit `5`.
- **R8 — Config values are proved preserved.** When an upgrade has run, for the target
  and — on a coordinator — every manifest child holding `.harness/harness.config.yaml`, the
  system shall compare the pre-upgrade file with the post-upgrade file and print
  `✅ preserved <label> harness.config.yaml` when every pre-upgrade line is present in the same
  order (appended lines allowed); if any pre-upgrade line is missing or altered, then it shall
  print `❌ changed <label> harness.config.yaml`, name the snapshot path under the backup
  directory, and exit `4`. Explicit child overrides (a child value that differs from the
  coordinator's) are within the comparison.
- **R9 — Entrypoint prose is proved preserved.** When an upgrade has run, for each existing
  `CLAUDE.md` and `AGENTS.md` at every in-scope repo root, the system shall compare the bytes
  outside the `<!-- harness:begin -->`…`<!-- harness:end -->` block (the whole file when no
  block exists) before and after, print `✅ preserved <label> <file>` when identical, and on
  any difference print `❌ changed <label> <file>`, name the snapshot path, and exit `4`.
- **R10 — Coordinator upgrades cascade.** Where the target's `harness.config.yaml` names an
  existing `umbrella.manifest`, the system shall run the fetched installer as
  `harness-install.sh --umbrella <umbrella-dir>` (the manifest file's parent directory) instead of the single-target form, shall
  treat installer exit `3` (installed but unlanded) as success, and afterwards every manifest
  child's `.harness/.harness-version` shall equal the new version while a thin child's prose
  tier remains stubs.
- **R11 — Conflict preview, then consent, before any write.** When the human has answered
  `y` to R6, the system shall, before changing any file in the target, list every body file
  that is locally edited or locally added relative to the installed version's tag (falling
  back to the incoming tag with a stated reason when `v<old>` is absent from the remote), one
  line per file — an edited file with its path and added/removed line counts, a local
  addition with its path and the label `local addition` — name the remote URL and the tag
  whose installer will run, state the preservation guarantees of R8/R9, print `(no local edits to harness-owned files)` when the list is empty,
  and ask `Proceed with the upgrade? [y/N]`; on any answer other than `y`/`Y` the system
  shall record the declined version exactly as R6 does and exit `2` with the target
  byte-identical to before the prompt (stamp, body, config, entrypoints) and no backup
  directory created.
- **R12 — Backups precede replacement.** When the human consents at R11, the system shall,
  before running the installer, copy every file listed by R11 to
  `.harness/progress/upgrade-backup/<old-version>/<relative-path>` and the pre-upgrade
  `harness.config.yaml`, `CLAUDE.md` and `AGENTS.md` of every in-scope repo to
  `…/upgrade-backup/<old-version>/preservation/<label>/`; after the upgrade each backup
  shall be byte-identical to the pre-upgrade original; the system shall not overwrite an
  existing backup directory for the same version; and the backup location shall be ignored
  by the target's VCS through the existing `progress/*/` rule.

## Out of scope
- Installing without consent; committing or staging the upgrade; three-way merging a local
  edit into the new upstream file; release notes / the GitHub Releases API; downgrades.
- Previewing or backing up **children's** body files in a cascade (the cascade replaces them
  exactly as today); R8/R9 do protect children's config and entrypoints. Natural seam for a
  follow-up feature.
- A `/sdd-update` command, an update check inside `harness-install.sh`, or any check in the
  harness source repo itself.
- Pruning old backup directories.

## Decisions (the brief's open questions, resolved)
- **Remote URL**: env → config `update.remote` → hard-coded default (business rules).
- **Cache**: `.harness/progress/update-check/` (ignored by VCS), TTL 24 h, failure cached,
  declined version remembered per version.
- **Umbrella child**: skipped silently; the coordinator's cascade upgrades it.
- **"Locally edited"**: bytes differ from (or file absent in) the installed version's tag,
  resolved from the fetched repo; no hash manifest exists in a consumer install.
- **Where the logic lives**: a new POSIX-sh `tools/harness-update.sh` (`check` / `upgrade`
  subcommands); `init.sh` gains one short hook that runs `check` and `exec`s `upgrade` on
  consent.
- **Split**: not needed at 12 R-ids; if two PRs are preferred, R10 plus the child rows of
  R8/R9 are the seam.

## Open questions
- None blocking. The human may prefer the loud (E24-style) opt-out line; this spec chooses
  silent because the check is a notice, not a gate, and the test runner relies on a quiet
  opt-out to keep ~80 pre-existing suites hermetic.
