# Earned lessons (append-only)

> One entry per lesson that cost a review round, a rejection, or a debugging session to
> learn. Every role reads this file at session start; any lane may append. Never rewrite
> or delete an entry — supersede it with a newer one. Format:
>
>     - [YYYY-MM-DD <lane>] <the lesson, one or two lines, imperative>

- [2026-09-04 product-queue] `command -v missing-tool` exits 1 under macOS `sh` but 127
  under CI's dash — never assert on the exact exit code of a lookup miss; assert on ≠0.
- [2026-09-04 product-queue] An `onTaskUpdate` timeout usually means a blocked event
  loop, not load — profile the loop before raising the timeout.
- [2026-09-04 product-queue] `mkdtempSync` is not a safety signal — a unique dir name
  proves nothing about who else can write inside it.
- [2026-09-04 product-queue] Account for stray processes with a pid diff (before/after
  set difference), never a global `ps | grep -c` — the global count races every other
  lane on the box.
- [2026-09-04 product-queue] A timeout cap can hide a missing cache: when a step's time
  is capped, the cap firing looks identical to the step being fast. Verify the cache
  exists, don't infer it from elapsed time.
- [2026-09-05 builder] This repo's root `harness.config.yaml` is the SEED TEMPLATE fresh
  installs copy verbatim — a repo-local choice written there silently changes the shipped
  default for every future consumer (6 suites red). Repo-local model tiering lives in the
  `.claude/agents/*.md` shim `model:` keys instead; same pattern as the pr-loop
  severities (repo raises P2 locally, seed stays P0,P1).
- [2026-09-05 builder] `run-tests.sh --jobs 8` occasionally fails 2-3 unrelated suites
  under heavy box load; each passes standalone. Before chasing a "failure" in a suite
  your diff never touched, re-run it alone — and only debug if it fails solo.
- [2026-09-05 builder] Never invoke a bash-shebang script via `sh` inside a test suite —
  under the strict runner the suite runs in dash, and `set -o pipefail` (or any bashism)
  aborts the script at startup, making the test flake by host shell. Run it through its
  own shebang (`./script`).
- [2026-09-04 pr-loop] A hand-rolled severity classifier tested `nit` before defaulting
  — substring matches inside longer words mis-tag severities. First match wins **by
  position**, and matches must be word-boundary anchored. (Now enforced in
  `tools/wait-for-codex.sh classify` — use it, never re-implement.)
- [2026-09-05 builder] A board chore that rolls an epic/feature `done` without syncing the spec frontmatter breaks ./init.sh for EVERY later lane (E25-F01: board `done`, spec `in-review`) — the transition write path must update both, and a red init.sh at session start is worth checking against main before blaming your own diff.
