# Cascade installer — Test Contract

> The traceability matrix: every R-id in cascade-installer.spec.md maps to a concrete,
> executable check. The Reviewer fails the feature if any R-id lacks a passing test. Tests
> are zero-dependency POSIX `sh` in `tests/test_cascade.sh`, matching the house style of
> `tests/test_install.sh` (self-cleaning `mktemp` tree, `fail`/`pass` helpers). The
> single-target non-regression suite `tests/test_install.sh` must also stay green.

## Fixture setup (built by `tests/test_cascade.sh`)
- A temp umbrella dir with immediate children:
  - `viernes-bff/` containing `.git` as a **directory** (git child).
  - `lia-api/` containing `.git` as a **regular file** (worktree/submodule gitlink).
  - `not_a_repo/` with no `.git` (non-git; skipped).
  - `bad_Name/` containing `.git` (valid git child, INVALID key grammar → skipped + warned).
  - `.hidden/` and an `.harness/` dir (skipped by the dotfile/own-harness rule).
- A separate temp target with a **pre-F01** `harness.config.yaml` (no `umbrella:` block, a
  bootstrap-set `test_command`) for the migration tests.

## Traceability matrix
| R-id | Behavior | Test (file::name) | Type | Status |
|---|---|---|---|---|
| R1 | `--umbrella <dir>` mode accepted | `tests/test_cascade.sh::umbrella_mode_runs` | integration | ⬜ |
| R2 | no `--umbrella` ⇒ single-target only, no manifest/discovery | `tests/test_cascade.sh::single_target_no_cascade` | integration | ⬜ |
| R3 | no target / bad `--umbrella` dir ⇒ usage error, non-zero, no writes | `tests/test_cascade.sh::arg_guards_no_writes` | unit | ⬜ |
| R4 | default scan is depth-1 only | `tests/test_cascade.sh::depth_one_default` | integration | ⬜ |
| R5 | coordinator profile written to `<umbrella>/.harness/` | `tests/test_cascade.sh::coordinator_body_installed` | integration | ⬜ |
| R6 | coordinator `umbrella.manifest` set to manifest path (fresh) | `tests/test_cascade.sh::coordinator_manifest_key_set` | integration | ⬜ |
| R7 | coordinator has `integration_command` key, no extra `test_command` | `tests/test_cascade.sh::coordinator_integration_key` | integration | ⬜ |
| R8 | `.git` as dir OR file both selected | `tests/test_cascade.sh::git_dir_or_file_selected` | integration | ⬜ |
| R9 | dotfile dirs and own `.harness` skipped | `tests/test_cascade.sh::hidden_and_harness_skipped` | integration | ⬜ |
| R10 | each git child gets the normal child profile | `tests/test_cascade.sh::child_profile_installed` | integration | ⬜ |
| R11 | `umbrella.manifest.yaml` created with `repos:` | `tests/test_cascade.sh::manifest_created` | integration | ⬜ |
| R12 | each child gets entry (key, relative `path`, TODO placeholders) | `tests/test_cascade.sh::manifest_entries_populated` | integration | ⬜ |
| R13 | invalid-named child skipped + clear message, no entry/install | `tests/test_cascade.sh::invalid_name_skipped` | integration | ⬜ |
| R14 | re-run adds new repos, never overwrites existing entry fields | `tests/test_cascade.sh::manifest_upsert_preserves` | integration | ⬜ |
| R15 | written manifest passes `init.sh` repo-key + path grammar | `tests/test_cascade.sh::manifest_init_compatible` | integration | ⬜ |
| R16 | re-run preserves each child's project-owned files | `tests/test_cascade.sh::child_project_files_preserved` | integration | ⬜ |
| R17 | re-run does not duplicate entrypoint block in children | `tests/test_cascade.sh::child_pointer_not_duplicated` | integration | ⬜ |
| R18 | upgrade appends missing default keys to preserved config | `tests/test_cascade.sh::migrate_appends_missing_keys` | unit | ⬜ |
| R19 | migration preserves existing values/comments byte-for-byte | `tests/test_cascade.sh::migrate_preserves_values` | unit | ⬜ |
| R20 | migration is a no-op on a complete config (idempotent) | `tests/test_cascade.sh::migrate_idempotent` | unit | ⬜ |
| R21 | migration runs on both coordinator and child, zero-dep | `tests/test_cascade.sh::migrate_both_profiles` | integration | ⬜ |
| R22 | version stamp + `manifest.txt` for coordinator and each child | `tests/test_cascade.sh::stamp_and_manifest_each` | integration | ⬜ |
| R23 | coordinator `manifest.txt` lists `umbrella.manifest.yaml` as project-owned | `tests/test_cascade.sh::coordinator_manifest_txt_lists_manifest` | integration | ⬜ |
| R24 | single-target unchanged (pre-F02 behavior) except value-preserving migration | `tests/test_install.sh` (whole suite) + `tests/test_cascade.sh::single_target_unchanged` | regression | ⬜ |

## Behavioral / end-to-end checks (Reviewer)
- Run `sh tests/test_install.sh` — the entire pre-F02 single-target contract must pass
  unchanged (hard non-regression, R24).
- Run `sh tests/test_cascade.sh` once (fresh), assert: coordinator `.harness/` present with
  `umbrella.manifest` set; both git children installed; `not_a_repo`, `.hidden`, `.harness`,
  and `bad_Name` absent from the manifest; a warning printed for `bad_Name`.
- Edit a child's `state/tasks.json` and a manifest entry's `test_command`; re-run; assert the
  child file and the manifest field are unchanged, and no entry/block is duplicated (R14,
  R16, R17).
- Build a pre-F01 config (no `umbrella:` block, `test_command: "pytest -q"`), upgrade, assert
  `umbrella:`/`manifest:` and `verification.integration_command` now present AND
  `test_command: "pytest -q"` retained; run again and assert the file is byte-identical
  (R18, R19, R20).
- Run `( cd <coordinator> && ./.harness/init.sh )` against the populated manifest and assert
  it reports umbrella mode without a repo-key grammar warning (R15).

## Non-functional checks
- Lint: installer remains POSIX `sh`, zero external dependencies (no `yq`, `jq`, `python`
  required for the cascade or migration paths).
- `./init.sh` green in the harness source repo after the change.
