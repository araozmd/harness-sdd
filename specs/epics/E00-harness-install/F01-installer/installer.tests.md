# Installer script — Test Contract

> Every R-id maps to an executable assertion in `tests/test_install.sh`. The
> Reviewer fails the feature if any R-id lacks a passing test. Run with
> `sh tests/test_install.sh` (also wired as `test_command` in `harness.config.yaml`).

| R-id | Behavior | Test (file::assertion) | Type | Status |
|---|---|---|---|---|
| R1 | Harness body copied into `.harness/` | `tests/test_install.sh` :: "fresh install layout correct" | integration | ✅ |
| R2 | Version stamp matches source `VERSION` | `tests/test_install.sh` :: "version stamped" | integration | ✅ |
| R3 | Existing entrypoint prose preserved + block added | `tests/test_install.sh` :: "entrypoint merge preserves prose + adds block" | integration | ✅ |
| R4 | Re-run does not duplicate the block | `tests/test_install.sh` :: "upgrade preserves project files + is idempotent" (block count == 1) | integration | ✅ |
| R5 | Upgrade preserves project-authored files | `tests/test_install.sh` :: "upgrade preserves project files + is idempotent" (product/tasks sentinels) | integration | ✅ |
| R6 | Fresh install seeds runnable project stubs | `tests/test_install.sh` :: "fresh install layout correct" (product.md, tasks.json) | integration | ✅ |
| R7 | Claude Code glue resolves against `.harness/` | `tests/test_install.sh` :: "Claude Code glue generated" | integration | ✅ |
| R8 | Fresh-install verification commands reset to blank | `tests/test_install.sh` :: "target verification commands reset" | integration | ✅ |
| R9 | Bad invocations exit non-zero, no changes | `tests/test_install.sh` :: "arg guards reject bad invocations" | integration | ✅ |
| R10 | Installed `init.sh` passes from target root | `tests/test_install.sh` :: "installed init.sh passes" | integration | ✅ |
| R11 | Upgrade preserves bootstrap-set verification commands | `tests/test_install.sh` :: "upgrade preserves bootstrap-configured verification commands" | integration | ✅ |

## Behavioral / end-to-end checks
- Install into a scratch dir that already has a `CLAUDE.md`; confirm the original
  text is still present above the `<!-- harness:begin -->` block.
- Run `( cd <target> && sh .harness/init.sh )` → exits 0 (proves the seeded
  `tasks.json` is schema-valid and the body is structurally intact).
- Upgrade twice; confirm a single pointer block and unchanged project files.

## Non-functional checks
- Lint: installer is POSIX `sh` (`set -eu`; no bash-only constructs). `sh tests/test_install.sh` runs under `/bin/sh`.
- Types: n/a (shell).
