# Antigravity native support — Tasks

> Atomic, sequential steps. The Builder works these top to bottom, one at a time.
> Each task names the R-id(s) it satisfies. The whole change lives in
> `harness-install.sh`, `tests/test_install.sh`, `VERSION`, and `CHANGELOG.md` — no
> canonical `agents/*.md` is touched.

- [x] **T1** (R1) — In `harness-install.sh` §4 (`write_pointer` / `GEMINI.md`), confirm
  the managed `GEMINI.md` block instructs an Antigravity session to act as the
  Orchestrator and read `.harness/AGENTS.md`. If already satisfied, add a one-line
  comment noting the `GEMINI.md` pointer also serves Antigravity (no behavioral change).

- [x] **T2** (R2,R4,R6) — In `install_one()`, immediately after the §5b OpenCode block
  (`ok "OpenCode commands …"`) and before §6 (`opencode.json`), add a new §5c block that
  does `mkdir -p "$TARGET/.agent/rules" "$TARGET/.agent/agents" "$TARGET/.agent/workflows"`.

- [x] **T3** (R2,R3) — In §5c, write `$TARGET/.agent/rules/harness.md`: a short rule that
  points the agent at `.harness/AGENTS.md` (source of truth) and
  `.harness/agents/orchestrator.md` (entry role), mandates `.harness/init.sh` first, and
  contains **no copied role body**.

- [x] **T4** (R4,R5) — In §5c, loop over `orchestrator architect builder reviewer scout`
  and write `$TARGET/.agent/agents/<role>.md` for each: YAML frontmatter with a
  `description:` line + a body that defers to `.harness/agents/<role>.md`, runs
  `.harness/init.sh` first (halt on non-zero), and hands off via `.harness/progress/`.
  Reuse the same role descriptions as the `.claude/agents` `emit_agent` calls. **No
  copied role body.**

- [x] **T5** (R6,R7,R8,R9) — In §5c, loop over `sdd-next sdd-new sdd-plan sdd-drill
  sdd-fix` and write `$TARGET/.agent/workflows/<name>.md` for each by copying the body
  from the already-generated `$TARGET/.claude/commands/<name>.md` (mirror, like the
  OpenCode block — do not re-author). The Claude command files already begin with a
  `description:` frontmatter block, which satisfies the slash-command registration
  requirement; preserve it.

- [x] **T6** (R12) — In §5c, add an `ok "Antigravity glue (rules + agents + workflows)
  installed (.agent/)"` line for parity with the existing front-end `ok` lines.

- [x] **T7** (R10) — In §3, extend the `manifest.txt` HARNESS-OWNED list to mention
  `.agent/rules/*  .agent/agents/*  .agent/workflows/*  (repo root, regenerated)`.

- [x] **T8** (R10) — Bump `VERSION` from `0.20.0` to `0.21.0` (MINOR — new
  backward-compatible capability).

- [x] **T9** (R10) — Add a `## [0.21.0]` section to `CHANGELOG.md` under
  `### Added — ✨ Antigravity native support`, describing the `GEMINI.md`/`.agent/rules`
  entrypoint, the `.agent/agents` personas, and the `.agent/workflows` slash commands,
  and noting no canonical role file is forked.

- [x] **T10** (R11) — In `tests/test_install.sh`, after the OpenCode assertion group,
  add an Antigravity glue assertion group implementing every check in
  `F01-antigravity-support.tests.md` (entrypoint rule exists; all five personas exist;
  all five workflows exist; each workflow has a `description`; each workflow resolves
  its role against `.harness/agents/*.md`; no glue file embeds a copied role body),
  each line tagged with its R-id and ending with `pass "Antigravity glue generated (R11)"`.

- [x] **T11** — Run the full `verification.test_command` suite (`sh tests/test_install.sh
  && …`) plus `./init.sh`; ensure green before hand-off.
