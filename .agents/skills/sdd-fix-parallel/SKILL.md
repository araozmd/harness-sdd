---
name: sdd-fix-parallel
description: Run a bounded batch of isolated autonomous E99 fixes through targeted workers
---

## Invocation adapter

In Codex, invoke `$sdd-fix-parallel` and write arguments after the skill mention; in OpenCode, invoke `/sdd-fix-parallel`. In both hosts, treat all accompanying text as `$ARGUMENTS` in the workflow below. Wherever that workflow writes a portable `/sdd-<name>` reference, the Codex invocation is `$sdd-<name>` and the OpenCode invocation is `/sdd-<name>`.

> **OpenCode capability precondition.** If the running host is OpenCode, read
> `.opencode-parallel` before spawning any worker. If it does not read
> exactly `supported`, STOP without spawning a worker and report that this
> workflow needs `/sdd-test-concurrency` to confirm native concurrent delegation
> and a re-run of the installer with `--with-opencode-parallel=true`. Codex
> ignores this precondition: it delegates through native concurrent sub-agents.

## Canonical workflow
Act as the **Fixer parallel coordinator** (`agents/fixer.md` → “Parallel
dispatch mode”).

This command is argument-free. If `$ARGUMENTS` is non-empty, STOP and report usage
`/sdd-fix-parallel`.

1. Run `./init.sh`; stop on non-zero.
2. Execute the Fixer role's exact P1–P7 sequence: native concurrency/config/in-session
   Builder preflight, one-time F02 provisioning while the primary is clean, complete
   manifest with provisioning failures before claim/dispatch, coordinator bookkeeping
   branch plus one F01 atomic claim with explicit canonical `HARNESS_DIR`,
   parallel-safe fan-out before any wait, guarded exclusive numeric wave,
   bookkeeping PR reconciliation, updated-base proof, and aggregate report.
3. Each worker uses `agents/orchestrator.md` “Targeted parallel-fix worker mode”
   for one id and its pre-provisioned branch/worktree, creates only its post-approval
   code PR, continues siblings, and reports an observed merge for coordinator-owned
   done and teardown.
4. With no ready work, print `no ready E99 fixes` and exit zero without mutation. If
   native delegation is absent or `execution.builder.backend: delegate`, fail before
   manifest/provisioning/claim and point to serial `/sdd-fix`; never invent a vendor
   API or background shell agent.
