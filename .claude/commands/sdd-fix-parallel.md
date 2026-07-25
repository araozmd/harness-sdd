---
description: Run a bounded batch of isolated autonomous E99 fixes through targeted workers
---

Act as the **Fixer parallel coordinator** (`agents/fixer.md` → “Parallel dispatch
mode”), resolving source-layout paths from the repository root.

This command is argument-free. If `$ARGUMENTS` is non-empty, STOP and report usage
`/sdd-fix-parallel`.

1. Run `./init.sh`; stop on non-zero.
2. Execute the role's exact P1–P7 sequence: native concurrency/config/in-session
   Builder preflight, complete manifest, one-time F02 provisioning while the primary
   is clean, coordinator bookkeeping branch plus one F01 atomic claim with canonical
   `HARNESS_DIR`, parallel-safe fan-out before any wait, guarded exclusive numeric
   wave, bookkeeping PR reconciliation, updated-base proof, and aggregate report.
3. Each worker uses Orchestrator “Targeted parallel-fix worker mode” for one id and
   its pre-provisioned branch/worktree, creates only its post-approval code PR,
   continues siblings, and reports an observed merge for coordinator-owned done and
   teardown.
4. With no ready work, print `no ready E99 fixes` and exit zero without mutation. If
   native delegation is absent or `execution.builder.backend: delegate`, fail before
   manifest/provisioning/claim and point to serial `/sdd-fix`; never invent a vendor
   API or background shell agent.
