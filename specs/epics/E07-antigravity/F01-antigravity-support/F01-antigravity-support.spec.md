---
id: E07-F01
title: Antigravity native support (entrypoint + installer wiring + role/command glue)
epic: E07-antigravity
status: in-progress      # pending → spec-ready → in-progress → in-review → done (re-spec: corrected Antigravity surface — .agents/ plural + honest persona model)
sdd: true                # full SDD — installer body change
autonomous: false        # parks at the human spec-approval gate
depends_on: []
owner: araozmd
---

# Antigravity native support — Functional Spec

> **Re-spec note (2026-06-12).** The original spec (and the implementation already
> landed on `feat/E07-F01-antigravity-support`, PR #31, HELD) targeted the workspace
> dir `.agent/` (singular) and asserted bare-file persona registration on a
> file-existence-only test. Codex r3 P2 (#3404422700) and the Orchestrator's research
> (`progress/research-E07-F01-antigravity-surface.md`) show the current (June 2026)
> convention has drifted. This re-spec makes two corrections: (1) the workspace dir is
> **`.agents/` (plural)**, and (2) the durable working model is the **confirmed
> primitives** — the `.agents/rules/` entrypoint rule + `description`-gated
> `.agents/workflows/` slash commands + `.harness/progress/` hand-off — with bare-file
> personas demoted to a **conditional** requirement, not a hard one tested only by file
> presence. R-ids whose *behavior* is unchanged keep their numbers; the dir-rename moves
> their target path. See `progress/architect-E07-F01-respec.md` for the full R-id diff.

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
against the Orchestrator's June-2026 research (`progress/research-E07-F01-antigravity-surface.md`,
the authoritative input — the Architect has no web access), the evidence is
**conflicting on the workspace dir name** and **unconfirmed on bare-file persona
registration**. The re-spec resolves both explicitly:

- **Workspace config dir is `.agents/` (plural) — CONFIRMED-LEANING, gate-confirmed.**
  The strongest current signal is **Google's own June-2026 codelab** ("Getting Started"
  and "Autonomous Pipelines"), which places project skills at
  `<project-root>/.agents/skills/`, plus a 2026 search snippet stating "workspace rules
  live in the `.agents/rules` folder … `.agents/` is a special directory natively
  recognized by Antigravity." The singular `.agent/` of the original spec traces to
  Nov-2025-era tutorials (Romin Irani; agentpedia, which itself mixes both) and appears
  to be an **early-version path that was renamed**. **Decision:** the glue installs under
  `.agents/{rules,agents,workflows}/`. This is the central change. (Open question 1 asks
  the human to confirm the plural before merge.)
- **Context convention / entrypoint.** Antigravity natively loads `GEMINI.md`-style
  rules. The original r1 fix (write `GEMINI.md` for `gemini || antigravity`) stands
  regardless of the dir rename. Antigravity does **not** reliably auto-load a project-root
  `AGENTS.md`; the documented way to make it honor `AGENTS.md` is a **rule** that
  instructs the agent to read it. `AGENTS.md` is also read directly on Antigravity
  v1.20.3+ (Mar 2026), which reinforces the source-of-truth pointer.
- **Rules + workflows are well-attested; bare-file personas are NOT.** The research is
  explicit: the `.agents/{rules,skills,workflows}/` paths are well-attested, but the
  *subagents-as-bare-`.agents/agents/*.md`-files* path is **not confirmed discoverable**.
  Codex (#3404422700) cites a competing model in which discoverable subagents are packaged
  inside a **plugin bundle** staged under the **global** `~/.gemini/...plugins/<name>/`
  path — not as workspace-local bare files. Mirroring how the original spec refused to
  fabricate an isolated-spawn primitive, this re-spec does **not** assert that bare
  `.agents/agents/*.md` files register as Antigravity subagents.
- **Commands.** A workflow file under `.agents/workflows/<name>.md` becomes a
  user-invokable **slash command** (`/<name>`) **only when it carries a `description:`
  field** in its frontmatter — otherwise the IDE does not register it. This is not in
  doubt and drives R7.
- **Skills (`.agents/skills/`)** are newly attested in the research but are **additive**;
  this re-spec keeps them **out of scope** (Open question 3) to avoid scope creep.

**The durable working model (decision).** The glue is specced to the **confirmed
primitives**: the `.agents/rules/harness.md` entrypoint rule (R2/R3), the
`description`-gated `.agents/workflows/` slash commands that drive the canonical roles
(R6–R9), and `.harness/progress/` files as the hand-off / isolation boundary (R12). The
bare-file personas under `.agents/agents/` are retained as a **best-effort, conditional**
artifact (R4/R5) — written because they cost nothing and *may* be read by some
Antigravity versions, but the acceptance criteria do **not** claim they register as
subagents, and the install test does **not** fatten a registration claim with a mere
file-existence check (the original R11 defect Codex flagged). Whether bare-file personas
are discoverable, or whether plugin-bundle packaging is needed, is **Open question 2** for
the human gate.

## Business rules
- `AGENTS.md` stays the single source of truth. The Antigravity front-end is a pointer
  + glue that **points at** the canonical `agents/*.md` roles; it never duplicates,
  forks, or redefines a role.
- Mirror the existing per-tool pattern (how `.claude/` and `GEMINI.md` front the same
  roles). Do not invent a parallel role system.
- The Antigravity glue lives at the **target/workspace root** (`.agents/`, plural) and is
  **regenerated each install run**, exactly like `.claude/` and `.opencode/` — it is
  harness-owned, not project-owned.
- All glue resolves relative harness paths against `.harness/` (e.g.
  `.harness/agents/orchestrator.md`, `.harness/init.sh`, `.harness/progress/`),
  matching the installed-consumer layout the other front-ends use.
- This touches the installed body (`harness-install.sh` + the glue paths), so it
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
- The deselect-safety contract is mandatory: deselecting `antigravity` removes **only
  harness-generated files that are byte-identical to a freshly-generated stamp**
  (pristine), never a user file that merely shares a standard name, and never `rm -rf`
  of a user `.agents/` dir (R13, the r2 P1 contract — re-pointed at the plural dir).

## Acceptance criteria (EARS)
> Each is one testable behavior with a stable id. "The installer" = `harness-install.sh`
> run in single-target mode against a target repo `<T>`. Relative paths below are under
> `<T>` unless prefixed `.harness/`. Behavior unchanged from the original spec keeps the
> same R-id; only the target path moves `.agent/` → `.agents/`.

### Entrypoint
- **R1** — When the installer runs against a target with `antigravity` selected, it
  shall ensure the target has a root `GEMINI.md` entrypoint whose harness-managed block
  (between the `harness:begin` / `harness:end` markers) instructs an Antigravity session
  to act as the Orchestrator and to read `.harness/AGENTS.md` as the source of truth.
  *(Antigravity natively loads `GEMINI.md`-style rules; `GEMINI.md` is written when
  EITHER `gemini` OR `antigravity` is selected — it is the shared in-repo entrypoint.)*
- **R2** — On every run with `antigravity` selected, the installer shall write/refresh an
  Antigravity workspace rule at **`.agents/rules/harness.md`** that points the agent at
  `.harness/AGENTS.md` (the source of truth) and `.harness/agents/orchestrator.md` (the
  entry role), so an Antigravity session loads the harness even though Antigravity does
  not auto-load `AGENTS.md`.
- **R3** — The Antigravity entrypoint rule (`.agents/rules/harness.md`) shall reference
  the canonical role files **by their `.harness/agents/*.md` paths** and shall contain
  no copied role body — i.e. it points at the canonical roles, it does not fork them.

### Native glue — personas (best-effort, conditional)
> The two persona requirements are **conditional/best-effort**: the personas are written
> because they are cheap and *may* be honored by some Antigravity versions, but no
> requirement here claims they **register as subagents** — see Open question 2 and R12.
> Their tests verify **shape** (correct dir, `description`, defers to the canonical role,
> no forked body), never registration.
- **R4** — On every run with `antigravity` selected, the installer shall generate one
  Antigravity persona file per harness role under **`.agents/agents/`** — at minimum
  `orchestrator`, `architect`, `builder`, `reviewer`, and `scout` — each carrying a
  `description` field in its frontmatter and a body that defers to the canonical
  `.harness/agents/<role>.md` for that role's full definition. *(Best-effort: discovery
  of bare-file personas is unconfirmed — Open question 2.)*
- **R5** — Each generated `.agents/agents/<role>.md` shall instruct the persona to run
  `.harness/init.sh` before any work, to halt on its non-zero exit, and to hand off
  through `.harness/progress/` files rather than by forwarding chat history (the
  portable role-isolation contract), and shall contain no copied role body.

### Native glue — commands (slash workflows) — the durable primitive
- **R6** — On every run with `antigravity` selected, the installer shall generate
  Antigravity workflow files under **`.agents/workflows/`** for the same five SDD commands
  the other front-ends ship: `sdd-next`, `sdd-new`, `sdd-plan`, `sdd-drill`, and
  `sdd-fix`.
- **R7** — Each generated `.agents/workflows/<name>.md` shall carry a `description`
  field in its frontmatter (Antigravity registers a workflow as the slash command
  `/<name>` only when `description` is present).
- **R8** — Each generated `.agents/workflows/<name>.md` shall act as the corresponding
  role for that command (`sdd-next` → Orchestrator, `sdd-new` → Inception, `sdd-plan`
  → Planner, `sdd-drill` → Driller, `sdd-fix` → Fixer), resolve that role against its
  `.harness/agents/<role>.md` path, and forward the user's free-text argument
  (`$ARGUMENTS`) to the workflow.
- **R9** — The body of each generated Antigravity workflow shall be byte-identical to the
  already-generated Claude command of the same name (same role, same `.harness/`-resolved
  steps), so the three front-ends drive identical behavior and do not drift. *(The shared
  command bodies are the single source the Antigravity workflows mirror — like
  `.opencode/command/*` already does.)*

### Installer contract & verification
- **R10** — When the installer finishes a run, the manifest/version-stamp behavior
  shall be unchanged and `.harness/.harness-version` shall equal the source `VERSION`;
  because this re-spec changes the installed body, the source `VERSION` shall remain at a
  MINOR increment for this capability and a matching `CHANGELOG.md` entry shall be present
  and reflect the `.agents/` (plural) path. The manifest's HARNESS-OWNED list shall name
  the `.agents/{rules,agents,workflows}/*` glue.
- **R11** — `tests/test_install.sh` shall assert, after a fresh install, that: the
  Antigravity entrypoint rule exists under `.agents/rules/` and points at the harness
  (R2); every persona exists under `.agents/agents/` with a `description` and defers to
  its `.harness/agents/<role>.md` with no forked body (R4/R5); every workflow exists under
  `.agents/workflows/`, carries a `description`, resolves its role against
  `.harness/agents/*.md`, carries `$ARGUMENTS`, and is byte-identical to the Claude
  command of the same name (R6–R9); and **no glue file embeds a copied canonical role
  body** (R3/R5, via an absent-sentinel check, not mere file existence). The full
  `verification.test_command` suite shall pass.
- **R13** — When `antigravity` is deselected on a re-run, the installer shall remove a
  generated `.agents/` glue file **only when it is byte-identical to a freshly-generated
  stamp** (pristine); **if** a standard-named `.agents/` file differs from the stamp
  (user-authored/edited), **then** the installer shall leave it in place, shall never
  `rm -rf` the user's `.agents/` dir, and shall prune an emptied `.agents/` subdir only
  when it is empty. *(The r2 P1 byte-compare contract, re-pointed from `.agent/` to
  `.agents/`. GEMINI.md, being shared with `gemini`, is removed only when neither owner
  remains selected.)*

### Graceful fallback (isolation primitive uncertain)
- **R12** — Where Antigravity does not provide a first-party isolated-context sub-agent
  spawn **and where bare-file persona discovery is not confirmed**, the glue shall still
  deliver native orchestration using the **confirmed** primitives — the
  `.agents/rules/harness.md` entrypoint rule (R2) plus the `description`-gated
  `.agents/workflows/` slash commands (R6/R7) that drive the canonical roles — with
  `.harness/progress/` files as the hand-off / isolation boundary, and the installed
  entrypoint (R1/R2) shall document this as the Antigravity working model rather than
  asserting a Task-tool-style spawn **or** a bare-file persona registration that may not
  exist. *(This is the durable default until/unless a first-party isolation API or
  bare-file persona discovery is confirmed — see Open questions 1 and 2.)*

## Out of scope
- Forking, rewriting, or duplicating any canonical `agents/*.md` role body.
- Any change to the portable core: `init.sh`, the markdown TaskStore, `progress/`
  hand-offs, the 4-file spec format.
- Any change to `store/tasks.schema.json` or any new status value.
- Global (`~/.gemini/`) installation, **including the plugin-bundle subagent packaging
  model** Codex cited — this feature stamps **workspace-local** glue into the target,
  matching how `.claude/` / `.opencode/` are installed per-repo. If the gate decides
  plugin-bundle packaging is the only way personas register, that is a **follow-up
  feature**, not in this scope.
- A `.agents/skills/` harness skill — newly attested but additive; deferred (Open
  question 3).
- A first-party isolated sub-agent spawn integration (e.g. a third-party
  Antigravity-subagents extension or `execution.builder.delegate_cmd`) — recorded as a
  follow-up open question.
- Umbrella/cross-repo concerns: this feature has no `slices[]` and is single-repo.

## Open questions (for the human spec-approval gate)
1. **Confirm `.agents/` (plural).** This re-spec moves the entire glue tree from the
   original `.agent/` (singular) to **`.agents/` (plural)** — the dir Google's own
   June-2026 codelab and current snippets attest as natively recognized. The singular
   appears to be an early-version path. **Confirm the plural is correct before merge.**
   (If the human knows the live IDE still scans `.agent/`, the rename is reverted and
   only the persona-model change applies.)
2. **Persona-registration model.** The `.agents/{rules,workflows}/` paths are
   well-attested; **bare `.agents/agents/*.md` personas are NOT confirmed discoverable** —
   Codex cites a global plugin-bundle model instead. This re-spec's recommendation is the
   **confirmed-primitives fallback**: rely on the `.agents/rules/` entrypoint +
   `description`-gated `.agents/workflows/` + `.harness/progress/` hand-off (R12) as the
   durable working model, and keep the bare-file personas (R4/R5) only as a cheap
   best-effort artifact tested for **shape**, not registration. Choose: (a) accept the
   fallback as-is; (b) confirm bare-file personas DO register (then R4/R5 can be promoted
   to hard registration requirements with a real registration test); or (c) require
   plugin-bundle packaging (a follow-up feature — out of scope here).
3. **`.agents/skills/` harness skill.** Newly attested surface. Add an additive harness
   skill there now, or defer? Recommended: **defer** (keeps the change a path-rename +
   honest-model fix, no scope creep).
4. **Entrypoint duplication.** `GEMINI.md` already serves Gemini CLI. Reusing the same
   `GEMINI.md` block for Antigravity (R1) — acceptable, or does the human want a distinct
   additive Antigravity note within the same managed block? The spec currently reuses
   `GEMINI.md` + adds the `.agents/rules/harness.md` rule (R2) as the Antigravity hook.
5. **Command breadth.** The spec ships all five SDD workflows for uniform parity (R6).
   Confirm this over a narrower "`/sdd-next` + `/sdd-new` only" set if preferred.
