---
id: E08-F01
title: Interactive agent-target selection (checkbox + re-prompt on update)
epic: E08-installer-selection
status: done             # pending → spec-ready → in-progress → in-review → done
sdd: true                # full SDD — installer body change
autonomous: false        # parks at the human spec-approval gate
depends_on: []
owner: araozmd
---

# Interactive agent-target selection — Functional Spec

## Context
`harness-install.sh` today stamps **every** supported coding-agent front-end
unconditionally: Claude Code (`CLAUDE.md` + `.claude/`), Gemini CLI (`GEMINI.md`),
OpenCode (`opencode.json` + `.opencode/command/`), and — once E07-F01 builds — an
Antigravity `.agent/` tree. An engineer installing the harness into a repo may use
only one or two of these agents, yet gets all of them littered into the repo, with no
supported way to add or drop a target on a later run. This feature lets the installer
**present an interactive selection** of which agents to stamp, write only the chosen
ones, **persist** that choice, and **re-prompt with the previous set pre-checked on
every re-run** — applying both adds and removes — so the target set is a deliberate,
revisable choice. It must stay CI-safe: non-interactive runs honor an explicit
override and otherwise default to **all** agents, preserving today's behavior.

## Architecture-artifact absence (graceful degradation)
This repo has **no `specs/architecture.md`, no `specs/vision.md`, and no `specs/adr/`**
— it never ran `/sdd-plan`. Per the Architect's graceful-degradation rule and
`docs/SPEC-FORMAT.md`, the architecture/ADR input is **absent**, so this spec records
that absence deliberately, is written from the inbox brief alone, fabricates no ADR
citation, and carries **no `## Architecture alignment` section**. This is not a defect.

## Decisions on the brief's four open questions
These are the Architect's decisions; each is reflected in the acceptance criteria and
the plan. They are flagged for the human gate (see *Open questions*).

1. **Selection UI mechanism — pure-`read` numbered toggle list, zero new dependencies.**
   No `whiptail`/`dialog`. A numbered list of the agents is printed with each agent's
   pre-check state shown; the user types space/comma-separated numbers to **toggle**
   entries, then confirms. This honors the harness leanness rule (AGENTS.md rule 5,
   "POSIX sh, zero dependencies") and matches `init.sh`'s ethos. It is only ever invoked
   on an interactive TTY (R5/R6 cover the non-interactive path).
2. **Persistence — a dedicated state file `.harness/agents` (newline-separated agent
   keys) under the harness metadata, beside `.harness/.harness-version`.** A real state
   file is chosen over *deriving* the set from which front-end files exist, because
   derivation **cannot distinguish "deliberately deselected" from "never installed"**,
   which would make remove-on-reconcile and the pre-check baseline ambiguous. The file
   is harness-owned metadata (like `.harness-version`), written each run.
3. **Remove semantics — delete the deselected agent's stamped front-end files/glue,
   with a printed warning naming each removed path.** Deletion is chosen (over
   stop-updating-and-warn) so the repo reflects the current selection exactly and a
   removed agent leaves no stale glue. The risk to hand-edited files is mitigated by
   scoping deletion to **only the harness-owned, regenerated-each-run glue** for that
   agent (the dirs/files the installer itself writes), and **never** to the shared
   portable entrypoint `AGENTS.md` or to `.harness/` body content (R12, R13).
4. **Agent registry — a small declarative table in the installer, one row per agent.**
   Each agent is one entry (`key`, the stamp action, and the list of glue paths it owns
   for removal), so each existing stamp block is gated by the same mechanism and a future
   agent (or E07's Antigravity row) is one entry. The selectable keys are exactly:
   `claude`, `gemini`, `opencode`, `antigravity` (R10).

## Business rules
- The selectable target set is exactly four agents — **claude, gemini, opencode,
  antigravity** — modeled as a declarative registry (one row per agent) in the installer.
- Each agent's stamp action is the **existing** stamp block in `harness-install.sh`
  (Claude → the `CLAUDE.md` pointer + `.claude/` glue; Gemini → the `GEMINI.md` pointer;
  OpenCode → `opencode.json` + `.opencode/command/`; Antigravity → the E07 `.agent/`
  tree). This feature **gates** those existing blocks on selection — it does **not**
  invent a parallel install path.
- `AGENTS.md` is the portable, source-of-truth entrypoint shared by all front-ends; it
  is **not** an agent-specific front-end and is **never** part of any agent's selectable
  glue — it is always written and never removed, independent of selection.
- Selection is **decoupled from version-bump / upgrade detection**: the re-prompt and
  the add/remove reconciliation run on **every** re-run, whether or not `VERSION`
  changed.
- Back-compatibility is non-negotiable: a non-interactive run with no override stamps
  **ALL** agents, exactly as today.
- This touches the installed body (`harness-install.sh` + the new state file +
  `tests/test_install.sh`), so it requires a **MINOR `VERSION` bump** and a
  `CHANGELOG.md` entry; every new behavior must be **generated by `harness-install.sh`
  AND asserted in `tests/test_install.sh`** (repo `CLAUDE.md` installer contract).
- Keep the harness lean: no new runtime dependency; the selection UI is pure `read`.

## Acceptance criteria (EARS)
> Each is one testable behavior with a stable id. "The installer" = `harness-install.sh`
> run in single-target mode against a target repo `<T>`. An "agent key" is one of
> `claude`, `gemini`, `opencode`, `antigravity`. Relative paths below are under `<T>`
> unless prefixed `.harness/`. "Selected set" = the agent keys resolved for this run.

### Interactive selection (fresh install, TTY)
- **R1** — While standard input is an interactive TTY and no override is supplied, when
  the installer runs against a target that has **no** persisted selection
  (`.harness/agents` absent), the installer shall present a numbered toggle list of all
  four agent keys and let the user choose a subset, defaulting the pre-checked set to
  **ALL** agents.
- **R2** — When the user confirms an interactive selection, the installer shall stamp
  **only** the selected agents' front-ends/glue and shall **not** write any deselected
  agent's front-end files (e.g. selecting only `claude` writes `CLAUDE.md` + `.claude/`
  and does **not** create `GEMINI.md`, `opencode.json`, `.opencode/command/`, or
  `.agent/`).

### Conditional stamping (per agent)
- **R3** — Where an agent key is in the selected set, the installer shall execute that
  agent's existing stamp action (claude → `CLAUDE.md` pointer + `.claude/agents` +
  `.claude/commands`; gemini → `GEMINI.md` pointer; opencode → `opencode.json` +
  `.opencode/command`; antigravity → the `.agent/` tree once E07-F01 supplies it).
- **R4** — Where an agent key is **not** in the selected set, the installer shall skip
  that agent's stamp action, leaving its front-end files unwritten on a fresh install.

### Non-interactive override + no-TTY default (CI safety, back-compat)
- **R5** — When the installer is invoked with `--agents=<csv>` or with the environment
  variable `HARNESS_AGENTS=<csv>` set, the installer shall resolve the selected set from
  that comma-separated list of agent keys, **without** prompting, on both interactive and
  non-interactive runs (the explicit override always wins over the prompt and over any
  persisted selection).
- **R6** — While standard input is **not** an interactive TTY and **no** override
  (`--agents` / `HARNESS_AGENTS`) is supplied, the installer shall default the selected
  set to **ALL** agents and stamp all of them without prompting (preserving today's
  unconditional-stamp behavior so existing CI is unchanged).
- **R7** — If an override (`--agents` / `HARNESS_AGENTS`) contains a token that is not a
  known agent key, then the installer shall exit non-zero with an error naming the
  unknown token and shall make no changes.

### Persistence
- **R8** — When the installer finishes resolving the selected set for a run, it shall
  persist that set to `.harness/agents` (one agent key per line) as harness-owned
  metadata, written/overwritten on every run beside `.harness/.harness-version`.
- **R9** — When the installer runs and `.harness/agents` already records a previous
  selection, while standard input is an interactive TTY and no override is supplied, the
  installer shall present the toggle list with the **previously-persisted** set
  pre-checked (the prior selection is the reconciliation baseline, not ALL).

### Registry
- **R10** — The installer shall define the selectable agents as a declarative registry
  whose entries are exactly the keys `claude`, `gemini`, `opencode`, `antigravity`, each
  carrying its stamp action and the list of glue paths it owns; adding a future agent
  shall be expressible as one new registry entry.

### Re-prompt-on-update + add/remove reconciliation (decoupled from VERSION)
- **R11** — When the installer re-runs against an already-installed target, it shall
  offer selection reconciliation **regardless of whether the source `VERSION` differs**
  from the installed `.harness/.harness-version` (selection is decoupled from
  upgrade/version-bump detection).
- **R12** — When a re-run resolves a selected set that **adds** an agent not in the
  previously-persisted set, the installer shall stamp that newly-added agent's
  front-end/glue on that run (an add is applied).
- **R13** — When a re-run resolves a selected set that **removes** an agent that was in
  the previously-persisted set, the installer shall delete that agent's harness-owned,
  regenerated glue files/dirs (per its registry entry) and print a warning naming each
  removed path; it shall **not** delete the shared portable entrypoint `AGENTS.md` and
  shall **not** delete any `.harness/` body content.

### Installer contract & verification
- **R14** — When the installer finishes a run, the version-stamp/manifest behavior shall
  be unchanged and `.harness/.harness-version` shall equal the source `VERSION`; the
  source `VERSION` shall be bumped by a **MINOR** increment for this capability and a
  matching `CHANGELOG.md` entry shall be present.
- **R15** — `tests/test_install.sh` shall assert, mirroring its existing stamping-
  assertion structure: selected-only stamping under an explicit `--agents` override
  (R2/R4), the no-TTY ALL default (R6), the explicit override path (R5), an unknown-key
  override rejection (R7), the `.harness/agents` persistence round-trip (R8), and a
  re-run that both **adds** and **removes** an agent with the persisted set as baseline
  (R9/R12/R13). The full `verification.test_command` suite shall pass.

## Out of scope
- The Antigravity glue **itself** — that is E07-F01. This feature only makes Antigravity
  one selectable registry row + gates a stamp action; E07-F01 supplies what is stamped
  when Antigravity is selected. (See *E07-F01 coordination* below.)
- Forking, rewriting, or duplicating any canonical `agents/*.md` role body.
- Any change to the portable core: `init.sh`, the markdown TaskStore, `progress/`
  hand-offs, the 4-file spec format, `store/tasks.schema.json`, or any status value.
- The shared portable entrypoint `AGENTS.md` is never gated, removed, or made
  selectable — it is always written.
- Umbrella/cross-repo concerns: this feature has **no `slices[]`** and is single-repo.
  (The selection prompt is interactive and TTY-gated; an umbrella cascade is
  non-interactive per child, so each child resolves via the override/ALL path — no new
  umbrella behavior is specced here.)

## E07-F01 coordination (flag for the human gate — do NOT act on it here)
`E07-F01` is `spec-ready` and now carries `depends_on: ["E08-F01"]`, but its approved
spec predates this selection model: it specifies "**always** stamp the Antigravity
`.agent/` tree on every run" (E07-F01 R2/R4/R6 — *"on every run, the installer shall…"*).
Under E08-F01, Antigravity becomes **stamp-if-selected** (one registry row, gated by
R3/R4). **E07-F01 must therefore be re-specced by the Architect** (always-stamp →
stamp-if-selected) **before it builds**, so its installer wiring slots into this
feature's registry/gating rather than re-introducing an unconditional stamp. This spec
does **not** edit E07-F01 — it only records the dependency for the human to weigh at the
gate. Until E07-F01 builds, the `antigravity` registry row's stamp action is a no-op
placeholder (its glue does not yet exist); the row, selection, persistence, and removal
plumbing are still specced now so E07-F01 only has to fill in the stamp body.

## Open questions (for the human spec-approval gate)
1. **Selection UI mechanism.** Decided: pure-`read` numbered toggle list, zero deps.
   Confirm no preference for a `whiptail`/`dialog`-with-fallback richer UI.
2. **Persistence location/format.** Decided: dedicated `.harness/agents` file
   (newline-separated keys), chosen over deriving from existing files. Confirm over a
   key inside the version sidecar / `harness.config.yaml`.
3. **Remove semantics.** Decided: **delete** the deselected agent's regenerated glue
   (scoped to harness-owned paths) + warn. Confirm acceptance of deletion over the
   safer "stop-updating-and-warn" — note the residual risk if a user hand-edited a
   generated glue file (e.g. a `.claude/commands/*.md`).
4. **E07-F01 re-spec dependency.** The human must decide to send E07-F01 back to the
   Architect (always-stamp → stamp-if-selected) before E07-F01 builds.
