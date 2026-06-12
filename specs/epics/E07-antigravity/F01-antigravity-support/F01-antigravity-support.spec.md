---
id: E07-F01
title: Antigravity native support (entrypoint + installer wiring + role/command glue)
epic: E07-antigravity
status: done             # pending → spec-ready → in-progress → in-review → done
sdd: true                # full SDD — installer body change
autonomous: false        # parks at the human spec-approval gate
depends_on: []
owner: araozmd
---

# Antigravity native support — Functional Spec

## Context
The harness is model-agnostic: `AGENTS.md` is the source of truth, and the installer
already fronts Claude Code (`CLAUDE.md` + `.claude/`), Gemini CLI (`GEMINI.md`), and
OpenCode (`opencode.json` + `.opencode/command/`) over the **same** canonical
`agents/*.md` roles. Google **Antigravity** — a Gemini-based agentic IDE — is a new
target with its own context convention and its own agent/workflow model. Today an
Antigravity user can read `AGENTS.md` and drive the roles by hand, but gets none of the
one-command orchestration (role isolation, `/sdd-*` commands) that the `.claude/` glue
gives Claude Code users. This feature makes Antigravity a first-class harness target —
an entrypoint, installer wiring that stamps it into target repos with a
`tests/test_install.sh` assertion, and a native glue layer mapping the harness roles
onto Antigravity's primitives — forking no canonical role file.

## Architecture-artifact absence (graceful degradation)
This repo has **no `specs/architecture.md`, no `specs/vision.md`, and no `specs/adr/`**
— it never ran `/sdd-plan`. Per the Architect's graceful-degradation rule and
`docs/SPEC-FORMAT.md`, the architecture/ADR input is **absent**, so this spec records
that absence deliberately, is written from the inbox brief alone, fabricates no ADR
citation, and carries **no `## Architecture alignment` section**. This is not a defect.

## Antigravity integration surface — researched facts vs. open questions
The brief's central unknown was Antigravity's actual integration surface. Grounded
against current Antigravity documentation and corroborating community sources
(antigravity.google/docs/rules-workflows; Mete Atamel, Google DevRel,
atamel.dev 2025-11-25; aiengineerguide.com TIL on AGENTS.md; community `.agent/`
workflow repos), the following are treated as **confirmed** and drive the design:

- **Context convention.** Antigravity natively loads a **global** rules file
  `~/.gemini/GEMINI.md` and **per-workspace** files under `<workspace>/.agent/`. It
  does **not** reliably auto-load a project-root `AGENTS.md` (symlinking `GEMINI.md`
  to it is reported not to work); the documented way to make Antigravity honor
  `AGENTS.md` is a **rule** that instructs the agent to read it. A project-root
  `GEMINI.md` pointer is therefore the portable, in-repo entrypoint (the installer
  already writes `GEMINI.md`).
- **Workspace config dir.** Antigravity natively reads `<workspace>/.agent/` for
  **agents** (`.agent/agents/*.md`), **skills** (`.agent/skills/*.md`), and
  **workflows** (`.agent/workflows/*.md`). New `.agent/` content is picked up on
  application **restart**.
- **Commands.** A workflow file under `.agent/workflows/<name>.md` becomes a
  user-invokable **slash command** (`/<name>`), but **only when it carries a
  `description` field in its frontmatter** — otherwise the IDE does not register it.
- **Sub-agents / personas.** `.agent/agents/*.md` define named personas (with a
  `description`) the Orchestrator agent can reference and delegate to.

**Left open (flagged for the human gate):** whether Antigravity exposes a *first-party,
isolated-context sub-agent spawn* equivalent to Claude Code's Task tool. Current
evidence shows native **personas + delegation by reference**, while strict per-agent
**context isolation** (separate CLI process, blocked global config) is provided by a
**third-party VS Code extension**, not confirmed as a built-in API. Accordingly the
glue is specced to the **confirmed** primitives (personas + `description`-gated slash
workflows pointing at the canonical roles, with `progress/`-file hand-off as the
portable isolation boundary), and the "first-party isolated spawn" path is recorded as
an open question rather than fabricated (R12, Open questions).

## Business rules
- `AGENTS.md` stays the single source of truth. The Antigravity front-end is a pointer
  + glue that **points at** the canonical `agents/*.md` roles; it never duplicates,
  forks, or redefines a role.
- Mirror the existing per-tool pattern (how `.claude/` and `GEMINI.md` front the same
  roles). Do not invent a parallel role system.
- The Antigravity glue lives at the **target/workspace root** (`.agent/`) and is
  **regenerated each install run**, exactly like `.claude/` and `.opencode/` — it is
  harness-owned, not project-owned.
- All glue resolves relative harness paths against `.harness/` (e.g.
  `.harness/agents/orchestrator.md`, `.harness/init.sh`, `.harness/progress/`),
  matching the installed-consumer layout the other front-ends use.
- This touches the installed body (`harness-install.sh` + new glue paths), so it
  requires a **MINOR `VERSION` bump** (new backward-compatible capability) and a
  `CHANGELOG.md` entry. Every new command must be **generated by `harness-install.sh`
  AND asserted in `tests/test_install.sh`**.
- Keep the harness lean: add only the glue Antigravity needs; change none of the
  portable core (`init.sh`, the markdown TaskStore, `progress/` hand-offs, the 4-file
  spec format, `store/tasks.schema.json`, status values).
- Antigravity command coverage matches the brief's stated parity target: at minimum
  `/sdd-next` and `/sdd-new`. The installer already generates five Claude/OpenCode
  commands (`sdd-next`, `sdd-new`, `sdd-plan`, `sdd-drill`, `sdd-fix`); the Antigravity
  set mirrors **the same five** so parity is uniform and future-proof (R6).

## Acceptance criteria (EARS)
> Each is one testable behavior with a stable id. "The installer" = `harness-install.sh`
> run in single-target mode against a target repo `<T>`. Relative paths below are under
> `<T>` unless prefixed `.harness/`.

### Entrypoint
- **R1** — When the installer runs against a target, it shall ensure the target has a
  root `GEMINI.md` entrypoint whose harness-managed block (between the `harness:begin`
  / `harness:end` markers) instructs an Antigravity session to act as the Orchestrator
  and to read `.harness/AGENTS.md` as the source of truth. *(The installer already
  writes `GEMINI.md`; this requirement makes its content explicitly cover Antigravity —
  Antigravity natively loads `GEMINI.md`-style rules.)*
- **R2** — The installer shall, on every run, write/refresh an Antigravity workspace
  rule at `.agent/rules/harness.md` that points the agent at `.harness/AGENTS.md`
  (the source of truth) and `.harness/agents/orchestrator.md` (the entry role), so an
  Antigravity session loads the harness even though Antigravity does not auto-load
  `AGENTS.md`.
- **R3** — The Antigravity entrypoint rule (`.agent/rules/harness.md`) shall reference
  the canonical role files **by their `.harness/agents/*.md` paths** and shall contain
  no copied role body — i.e. it points at the canonical roles, it does not fork them.

### Native glue — personas (role isolation)
- **R4** — On every run, the installer shall generate one Antigravity agent/persona
  file per harness role under `.agent/agents/` — at minimum `orchestrator`,
  `architect`, `builder`, `reviewer`, and `scout` — each carrying a `description`
  field in its frontmatter and a body that defers to the canonical
  `.harness/agents/<role>.md` for that role's full definition.
- **R5** — Each generated `.agent/agents/<role>.md` shall instruct the persona to run
  `.harness/init.sh` before any work, to halt on its non-zero exit, and to hand off
  through `.harness/progress/` files rather than by forwarding chat history (the
  portable role-isolation contract), and shall contain no copied role body.

### Native glue — commands (slash workflows)
- **R6** — On every run, the installer shall generate Antigravity workflow files under
  `.agent/workflows/` for the same five SDD commands the other front-ends ship:
  `sdd-next`, `sdd-new`, `sdd-plan`, `sdd-drill`, and `sdd-fix`.
- **R7** — Each generated `.agent/workflows/<name>.md` shall carry a `description`
  field in its frontmatter (Antigravity registers a workflow as the slash command
  `/<name>` only when `description` is present).
- **R8** — Each generated `.agent/workflows/<name>.md` shall act as the corresponding
  role for that command (e.g. `sdd-next` → Orchestrator, `sdd-new` → Inception,
  `sdd-plan` → Planner, `sdd-drill` → Driller, `sdd-fix` → Fixer), resolve that role
  against its `.harness/agents/<role>.md` path, and forward the user's free-text
  argument to the workflow.
- **R9** — The body of each generated Antigravity workflow shall be content-equivalent
  to the already-generated Claude/OpenCode command of the same name (same role, same
  `.harness/`-resolved steps), so the three front-ends drive identical behavior and do
  not drift. *(The `.claude/commands/*.md` bodies are the single source the Antigravity
  workflows mirror — like `.opencode/command/*` already does.)*

### Installer contract & verification
- **R10** — When the installer finishes a run, the manifest/version-stamp behavior
  shall be unchanged and `.harness/.harness-version` shall equal the source `VERSION`;
  the source `VERSION` shall be bumped by a MINOR increment for this capability and a
  matching `CHANGELOG.md` entry shall be present.
- **R11** — `tests/test_install.sh` shall assert, after a fresh install, that the
  Antigravity entrypoint rule (R2), every persona file (R4), and every workflow file
  (R6) exist, that each workflow carries a `description` (R7) and resolves its role
  against `.harness/agents/*.md` (R8/R3), and that no Antigravity glue file embeds a
  copied canonical role body (R3/R5) — extending the existing `R7`-style assertions
  for the other front-ends. The full `verification.test_command` suite shall pass.

### Graceful fallback (isolation primitive uncertain)
- **R12** — Where Antigravity does not provide a first-party isolated-context
  sub-agent spawn, the glue shall still deliver native orchestration using the
  confirmed primitives — personas (R4) plus `description`-gated slash workflows (R6/R7)
  that drive the canonical roles — with `.harness/progress/` files as the hand-off /
  isolation boundary, and the installed entrypoint (R1/R2) shall document this as the
  Antigravity working model rather than asserting a Task-tool-style spawn that may not
  exist. *(This is the "graceful fallback" the brief asks for; it is the default path
  until/unless a first-party isolation API is confirmed — see Open questions.)*

## Out of scope
- Forking, rewriting, or duplicating any canonical `agents/*.md` role body.
- Any change to the portable core: `init.sh`, the markdown TaskStore, `progress/`
  hand-offs, the 4-file spec format.
- Any change to `store/tasks.schema.json` or any new status value.
- Global (`~/.gemini/`) installation; this feature stamps **workspace-local** glue
  into the target, matching how `.claude/` / `.opencode/` are installed per-repo.
- A first-party isolated sub-agent spawn integration (e.g. wiring a third-party
  Antigravity-subagents extension or `execution.builder.delegate_cmd`) — out of scope
  here and recorded as a follow-up open question.
- Umbrella/cross-repo concerns: this feature has no `slices[]` and is single-repo.

## Open questions (for the human spec-approval gate)
1. **Isolation primitive.** Confirm whether Antigravity exposes a first-party
   isolated-context sub-agent spawn (Task-tool equivalent). If yes, a follow-up feature
   can upgrade the glue from "personas + workflows + `progress/` hand-off" (R12) to
   true per-role process isolation. If no, R12's model is the durable answer.
2. **Entrypoint duplication.** `GEMINI.md` already serves Gemini CLI. Is reusing the
   same `GEMINI.md` block for Antigravity (R1) acceptable, or does the human want a
   distinct, additive Antigravity note appended within the same managed block? The spec
   currently reuses `GEMINI.md` + adds the `.agent/rules/harness.md` rule (R2) as the
   Antigravity-specific hook.
3. **Glue dir name.** The spec uses Antigravity's documented `.agent/` convention
   (`.agent/rules`, `.agent/agents`, `.agent/workflows`). Confirm no objection to a new
   top-level `.agent/` dir in target repos (it sits beside `.claude/` and `.opencode/`).
4. **Command breadth.** The spec ships all five SDD workflows for uniform parity (R6).
   Confirm this over a narrower "`/sdd-next` + `/sdd-new` only" set if a smaller surface
   is preferred.
