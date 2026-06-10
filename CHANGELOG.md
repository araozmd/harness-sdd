# Changelog

All notable changes to the harness body are recorded here. Versions follow
[SemVer](https://semver.org/) and are stamped into every install's
`.harness/.harness-version` (see `CLAUDE.md` → Versioning).

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
