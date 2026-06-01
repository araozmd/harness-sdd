# Changelog

All notable changes to the harness body are recorded here. Versions follow
[SemVer](https://semver.org/) and are stamped into every install's
`.harness/.harness-version` (see `CLAUDE.md` → Versioning).

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
