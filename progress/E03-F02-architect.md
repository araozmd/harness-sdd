# E03-F02 Cascade installer — Architect handoff

Status: spec drafted, ready for the `spec-ready` gate.

## Output (4 files)
- specs/epics/E03-multi-repo/F02-cascade-installer/cascade-installer.spec.md
- specs/epics/E03-multi-repo/F02-cascade-installer/cascade-installer.plan.md
- specs/epics/E03-multi-repo/F02-cascade-installer/cascade-installer.tasks.md
- specs/epics/E03-multi-repo/F02-cascade-installer/cascade-installer.tests.md

Frontmatter: id E03-F02, epic E03, status pending, sdd true, depends_on ["E03-F01"].

## Scope captured (locked design, specified not re-litigated)
- CLI surface: `harness-install.sh --umbrella <dir>` (+ optional `--recursive`), bare
  `<target>` 100% unchanged (R1–R4, R24).
- Cascade: coordinator profile in umbrella + child profile in each git child + manifest
  auto-populate (R5–R15).
- Discovery: depth-1, `.git` as dir OR file (`-e` test), skip dotfiles + own `.harness`,
  key-grammar `^[a-z0-9-]+$` validation with skip+message on violation (R8, R9, R13).
- Coordinator vs child profile difference (R5–R7, R10).
- Manifest create + idempotent upsert, never clobber project-owned entry fields (R11–R14).
- Non-destructive config migration `migrate_config` — append-only, value/comment-preserving,
  idempotent, POSIX sh zero-dep, both profiles (R18–R21). This is the Codex-flagged carryover.
- Version stamp + manifest.txt per target (R22, R23).
- HARD non-regression as explicit R24 with a dedicated test plus the full existing
  `tests/test_install.sh` suite.

## Key design decisions
- Refactor existing install body into `install_one <target>`, call once (single-target) or
  per repo (cascade) — reuse over a new script, protects byte-for-byte single-target output.
- `migrate_config` runs only on the upgrade branch (fresh seed already ships current keys).
- Manifest `path` written as `./<name>` so init.sh's relative-path join resolves it.
- Tests in new `tests/test_cascade.sh`; `verification.test_command` extended to run it.

## Open questions for the human gate
1. `--recursive` depth semantics — boolean "descend non-git, stop at git child" vs explicit
   `--depth N` vs defer `--recursive` entirely and ship depth-1 only. Proposed: ship depth-1,
   keep `--recursive` minimal or defer.
2. Manifest key on invalid name — confirm SKIP (current spec, R13) vs normalize. Skipping is
   specified to avoid undispatchable entries.
3. Coordinator `test_command` — confirm coordinator relies solely on `integration_command`
   with no per-repo unit `test_command` (current R7), vs a sentinel that makes the Reviewer
   skip per-repo tests.

No production code written. state/tasks.json not modified.
