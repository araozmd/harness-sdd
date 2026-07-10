# Ownership primitive: `owner` field + scoped `/sdd-next` — Tasks

> Atomic, sequential, independent steps. The Builder works these top to bottom,
> one at a time. Each task names the R-id(s) it satisfies. Check off when done.
> Order: schema → orchestrator contract → config → /sdd-next glue → installer wiring →
> docs → tests → VERSION bump → green gate.

- [x] **T1** (R1, R2, R3) — In `store/tasks.schema.json`, add an optional
  `"owner": { "type": "string" }` property to the **epic** object's `properties` and
  to the **feature** object's `properties`. Do **not** add `owner` to any `required`
  array; do **not** touch the `status` enums, the `slices` subschema, or the `allOf`
  sliced-`done` cross-field rule.

- [x] **T2** (R4, R5, R6, R7, R8, R9, R10, R11) — In `agents/orchestrator.md`, add an
  "Ownership & scoped selection" subsection to the loop that defines, in
  **tool-agnostic** (AGENTS.md-compatible) wording: that **unscoped** `/sdd-next`
  ignores `owner` and behaves exactly as today (R4); the **effective owner** rule
  (feature `owner` else parent epic `owner` else unowned — R6); the `--mine` filter
  applied **on top of** the existing `next()` gates, never relaxing them (R5, R7);
  identity resolution (`workflow.identity`; `@me`/`self` → `gh api user`; else literal
  — R8); **fail-closed** when identity is unresolved (R9); and **no-widen** when scoped
  selection yields nothing (R10). Preserve the board-mirror-one-way note.

- [x] **T3** (R8, R9) — In `harness.config.yaml`, add `identity: ""` under the
  `workflow:` block with a comment documenting: empty ⇒ board-wide (today's behavior);
  `"@me"`/`"self"` ⇒ resolve to the authed `gh` user; any other value ⇒ literal
  identity string.

- [x] **T4** (R11, R12, R13) — In `harness-install.sh`, edit the single
  `CMDDIR/sdd-next.md` heredoc (≈ line 1023) so the generated `/sdd-next` command
  documents and forwards **`--mine`** scoped selection via `$ARGUMENTS`, delegating the
  actual scoping semantics to `.harness/agents/orchestrator.md`. Do not add per-target
  branches — the existing copy loops propagate the one body to Claude/OpenCode/
  Antigravity/Codex byte-identically.

- [x] **T5** (R11, R13) — Update the source repo's committed
  `.claude/commands/sdd-next.md` to mirror the new generated body (this repo ships the
  command directly, not only via the installer). Keep it consistent with the CMDDIR
  body from T4.

- [x] **T6** (R14) — In `docs/WORKFLOW.md`, add an "Ownership & scoped selection"
  subsection documenting the optional `owner` field (epic + feature), the effective-owner
  rule, the `workflow.identity` key and its `@me`/`self`/literal resolution, and
  `/sdd-next --mine` — explicitly stating "no `owner` anywhere ⇒ exactly today's
  board-wide behavior".

- [x] **T7** (R14) — In `store/local.md`, extend the TaskStore / `next()` description
  with the optional `owner` field (epic + feature), the effective-owner resolution, and
  the scoped `--mine` filter (owned-only, no claim-on-select, fail-closed, no-widen).

- [x] **T8** (R1, R2, R3, R4, R5, R6, R7, R8, R9, R10, R14, R15) — Add a new
  `tests/test_ownership.sh` behavior suite (shell,
  same style as `tests/test_mirror.sh`) covering: schema validation of an owner-free
  doc (R2), an owner-present doc (R1/R3), and rejection of a non-string owner (R3);
  presence of the effective-owner + `--mine` + fail-closed + no-widen contract wording
  in `agents/orchestrator.md` (R5–R10); `workflow.identity` present in
  `harness.config.yaml` (R8); ownership + `--mine` documented in `docs/WORKFLOW.md` and
  `store/local.md` (R14); and the board-mirror one-way invariant note still intact.
  Assert **behavior**, never pin the exact VERSION and never diff DO-NOT-TOUCH files
  against `main`.

- [x] **T9** (R12, R13) — In `tests/test_install.sh`, add assertions that the generated
  `/sdd-next` body (for each selected target) carries the `--mine` scoped-selection
  wiring and forwards `$ARGUMENTS`.

- [x] **T10** (R13) — In `harness.config.yaml`, append `&& sh tests/test_ownership.sh`
  to `verification.test_command` (and update its trailing comment) so the new suite runs
  in the Reviewer's gate.

- [x] **T11** (R15) — Bump `VERSION` one **MINOR** step (e.g. `0.27.3` → `0.28.0`).
  Additive/backward-compatible — SemVer MINOR, not MAJOR. Add a matching `CHANGELOG.md`
  entry.

- [x] **T12** — Write/finish the tests per `F01-owner-field.tests.md`; ensure every
  R-id maps to a passing test.

- [x] **T13** — Run `./init.sh` + the full `verification.test_command` (now including
  `tests/test_ownership.sh`); ensure green before hand-off.
