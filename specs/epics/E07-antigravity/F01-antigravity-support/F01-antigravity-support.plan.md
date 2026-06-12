# Antigravity native support — Technical Plan

> Translates the `.spec.md` intent into design. Every decision cites the R-id(s) it
> serves. The implementation mirrors, almost line-for-line, the existing per-tool
> stamping in `harness-install.sh` (the Claude `.claude/` block and the OpenCode
> `.opencode/command/` block) — that is the proven pattern this feature extends.

## Stack & dependencies
- Language/framework: POSIX `sh` (the installer is `/bin/sh`, zero dependencies).
  Tests are POSIX `sh` (`tests/test_install.sh`). No new runtime deps.
- New dependencies: none.
- Antigravity integration surface relied upon (all confirmed; see `.spec.md`
  "Antigravity integration surface"):
  - native load of root `GEMINI.md` rules,
  - native read of `<workspace>/.agent/{rules,agents,workflows}/*.md`,
  - a workflow is registered as a `/<name>` slash command **iff** its frontmatter
    carries a `description`.

## Design overview
Add **one new generation block** inside `install_one()` in `harness-install.sh`,
placed immediately AFTER the OpenCode block (§5b) and BEFORE the `opencode.json`
block (§6), producing the workspace-local `.agent/` tree. It reuses the **already
generated** `.claude/commands/*.md` bodies as the single source for the workflow
bodies (exactly as the OpenCode block `cp`s them), so the three front-ends never
drift (serves R9). Antigravity-specific framing (the `description`-bearing
frontmatter the IDE needs, and the persona/rule wrappers) is added around that
shared body. The root `GEMINI.md` pointer is already written by §4 `write_pointer`;
R1 only requires its managed block to read as Orchestrator-bootstrap against
`.harness/AGENTS.md` (it already does — confirm + keep).

## Files to change  (serves: R1–R12)
| File | Change | R-id |
|---|---|---|
| `harness-install.sh` | In `install_one()`, after §5b (OpenCode), add §5c **Antigravity glue**: `mkdir -p "$TARGET/.agent/rules" "$TARGET/.agent/agents" "$TARGET/.agent/workflows"`. | R2,R4,R6 |
| `harness-install.sh` | §5c: write `.agent/rules/harness.md` — a short rule pointing the agent at `.harness/AGENTS.md` (source of truth) + `.harness/agents/orchestrator.md` (entry role); no copied role body. | R2,R3 |
| `harness-install.sh` | §5c: for each of `orchestrator architect builder reviewer scout`, write `.agent/agents/<role>.md` with `---\ndescription: …\n---` frontmatter + a body that defers to `.harness/agents/<role>.md`, mandates `.harness/init.sh` first + halt-on-fail, and `progress/`-file hand-off; no copied role body. Reuse the same descriptions as the `.claude/agents` `emit_agent` calls for consistency. | R4,R5 |
| `harness-install.sh` | §5c: for each of `sdd-next sdd-new sdd-plan sdd-drill sdd-fix`, write `.agent/workflows/<name>.md` = a `description:` frontmatter line + the body copied from the just-written `$TARGET/.claude/commands/<name>.md` (mirror, do not re-author), so role/`.harness/`-resolution/args match. | R6,R7,R8,R9 |
| `harness-install.sh` | §5c: emit an `ok "Antigravity glue … installed (.agent/)"` line (parity with the existing `ok` lines). | R12 |
| `harness-install.sh` | §4 `write_pointer`/`GEMINI.md`: confirm the managed `GEMINI.md` block reads as "act as Orchestrator, read `.harness/AGENTS.md`". If already satisfied, no code change beyond a comment noting it also serves Antigravity. | R1,R12 |
| `harness-install.sh` | §3 manifest.txt: add `.agent/rules/*  .agent/agents/*  .agent/workflows/*  (repo root, regenerated)` to the HARNESS-OWNED list so the manifest documents the new regenerated glue. | R10 |
| `tests/test_install.sh` | After the OpenCode assertions, add an **Antigravity glue** assertion group (R-tagged) — see `.tests.md` for the exact checks. | R11 |
| `VERSION` | Bump MINOR: `0.20.0` → `0.21.0` (new backward-compatible capability). | R10 |
| `CHANGELOG.md` | Add a `## [0.21.0]` section under a `### Added — ✨ Antigravity native support` heading describing the entrypoint rule, personas, and workflows. | R10 |

## Generation details (Builder guidance, not pinned internals)
- **Placement.** Put §5c between the existing §5b (`ok "OpenCode commands …"`) and §6
  (`opencode.json`). The `.claude/commands/*.md` files exist by then (written in §5),
  so the workflow bodies can be sourced from them.
- **Workflow file shape (R7/R9).** Each `.agent/workflows/<name>.md` must START with a
  YAML frontmatter block containing a `description:` line (the Claude command bodies
  already begin with their own `---\ndescription: …\n---` frontmatter — reusing that
  verbatim satisfies R7 directly; the simplest correct implementation is therefore a
  plain `cp` of the Claude command file, mirroring the OpenCode block). Keep the
  description ≤ ~120 chars so the IDE menu renders it.
- **Persona file shape (R4/R5).** Model on `.claude/agents/<role>.md`: `description`
  frontmatter + a body of the form "You are the **<role>** … your canonical definition
  is `.harness/agents/<role>.md` — read it and follow it … run `.harness/init.sh`
  first, halt on failure … hand off through `.harness/progress/`." No role body copied.
- **Rule file shape (R2/R3).** A few lines: "This workspace uses the SDD harness in
  `.harness/`. Source of truth: `.harness/AGENTS.md`. Start as the Orchestrator
  (`.harness/agents/orchestrator.md`); run `.harness/init.sh` first." No role body.
- **No-drift guarantee (R9).** Because the workflow bodies are sourced from the Claude
  command files (a `cp`, like OpenCode), a future change to any `/sdd-*` command body
  propagates to Antigravity automatically — do not hand-maintain a second copy.

## DO NOT TOUCH
- `agents/*.md` — the **canonical** role definitions. The Antigravity glue points at
  them via `.harness/agents/*.md`; it must never fork, copy, or edit a role body.
  (Business rule; R3, R5.)
- `store/tasks.schema.json` and the set of status values — no schema/status change.
- `init.sh`, the markdown TaskStore (`store/`), `progress/` hand-off mechanics, and the
  4-file spec format / `specs/_templates/` — the portable core stays as-is.
- The existing `.claude/` (§5), OpenCode (§5b), and `opencode.json` (§6) blocks and the
  `write_pointer` logic (§4) beyond the additive comment in R1 — do not refactor them;
  add the Antigravity block alongside, do not restructure the proven stamping.
- The umbrella/cascade machinery (`manifest_upsert`, arg parsing, `--umbrella` flow) —
  unrelated to this single-repo feature.
- Existing assertions in `tests/test_install.sh` — append the new group; do not modify
  the existing R1–R11 checks.

## Approach notes
- **Idempotency / upgrade safety.** The `.agent/` glue is regenerated every run (like
  `.claude/` and `.opencode/`), so it is harness-owned and overwrite-on-upgrade — it
  must NOT be added to the "seed once / never clobber" project-owned set. No
  `tasks.json`/`product.md`-style preservation applies. The existing idempotency test
  (re-run install, no duplication) will naturally cover it once the assertions are
  added.
- **Single source of truth for command bodies.** Reusing the `.claude/commands/*.md`
  bodies (R9) is the key anti-drift decision: it mirrors the existing OpenCode block
  and prevents a second hand-maintained copy of the SDD command prose.
- **VERSION bump timing.** Per repo `CLAUDE.md`, bump `VERSION` + add the `CHANGELOG.md`
  entry in this same change, before the PR is ready to merge, because the installed
  body changes. MINOR (`0.21.0`) — new backward-compatible capability.
- **Open-question dependency (R12).** If the human gate decides Antigravity does expose
  a first-party isolated spawn, that is a *follow-up* feature, not a change to this
  plan — this plan delivers the confirmed-primitive glue and documents the working
  model. Nothing here is invalidated by that later upgrade.
