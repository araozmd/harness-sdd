# Architect — E20-F02 (`pr_loop.enabled` prompt in the installer picker)

Spec written to `specs/epics/E20-workflow-toggles/F02-pr-loop-prompt/` (4 files, R1–R15).
Board: E20-F02 → `spec-ready`.

## Doc-critic checkpoint (agents/architect.md R12)
**SKIPPED — no sub-agent spawn available in this session** (the Architect ran without a
Task tool). Recorded here per the role file's best-effort clause. A self-review pass was
run instead and caught one real defect before hand-off: an early draft asked the suite to
assert "no `gh`/`jq` in `harness-install.sh`" by grep, which is impossible — the installer
GENERATES the `/sdd-pr-loop` body (~:2640), which is full of `gh`/`jq` calls. Replaced with
a behavioral `no_install_time_preflight` check (PATH stubs + sentinel).

## Rulings recorded in the spec
1. **No install-time preflight** — the installer must never invoke `gh`/`jq`; the prompt
   states the Codex-App/`gh` precondition and E18-F01's exit-5 fail-fast diagnoses it at the
   one moment it can be accurate.
2. **`--pr-loop=<true|false>` flag, NO env twin** — `HARNESS_PR_LOOP_ENABLED` keeps its
   E18-F01 per-run semantics. Repurposing it would rewrite target configs underneath
   `tests/test_install.sh:24` (exports it suite-wide) and `tests/test_pr_loop.sh`'s
   `install_on`, both of which must stay out of this feature's diff.

## Note for the Orchestrator (not part of this feature)
`specs/epics/E20-workflow-toggles/epic.md`'s feature table still lists F01 as `pending`
while the board says `done`. Left untouched deliberately — out of this feature's scope.
