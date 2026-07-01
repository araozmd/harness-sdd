# harness-sdd

A portable **agent harness** for **Spec-Driven Development**. It runs primarily on
**Claude Code** and is portable to **Codex**, **Gemini CLI**, **OpenCode**, and
**Antigravity** — because the harness is just files in the repo, and the model/CLI is
interchangeable.

> The model is the engine; the harness is the chassis. Models change every few
> months — your harness doesn't. See `docs/HARNESS.md`.

## How it works

An interactive **intake** (Inception) turns a raw idea into a seeded `pending` task;
from there the roles move it through files, each in a clean context:

```mermaid
flowchart LR
    project(["whole project"]) -->|/sdd-plan| Planner["Planner<br/>(vision + ADRs)"]
    Planner --> draft["draft epics"]
    draft -->|/sdd-drill| Driller["Driller<br/>(epic → features)"]
    Driller --> pending

    idea(["raw idea"]) -->|/sdd-new| Inception["Inception<br/>(intake)"]
    Inception --> pending["pending<br/>(task)"]

    pending -->|/sdd-next| Orchestrator["Orchestrator<br/>(state)"]
    Orchestrator --> Architect["Architect<br/>(specs)"]
    Architect --> Builder["Builder<br/>(code)"]
    Builder --> Reviewer["Reviewer<br/>(verify)"]
    Scout["Scout<br/>(read-only recon)"] -.assists.-> Orchestrator

    fix(["quick fix"]) -->|/sdd-fix| Builder
```

Specs follow a **Product → Epic → Feature** hierarchy, where each feature is a
4-file spec (`.spec` / `.plan` / `.tasks` / `.tests`) with **EARS** acceptance
criteria and full requirement→test **traceability**. When the project has an
architecture (`/sdd-plan`), each feature spec also **cites the architecture decisions
(ADRs) it touches** in a `## Architecture alignment` section. See `docs/SPEC-FORMAT.md`.

Epics carry their own lifecycle — `draft → planned → in-progress → done` (epic-level
`pending` stays valid as a legacy alias of `planned`). A `draft` epic is an inception
sketch: the Orchestrator **never selects features from a `draft` epic**, no matter
what the feature itself says — the foundation for rolling-wave planning (epic
roadmap: `specs/epics/E06-planning-tier/epic.md`). See `docs/WORKFLOW.md`.

The Reviewer runs a **cross-file consistency** check (a change must not contradict the
contracts it invokes) and the build↔review loop is **multi-round until green** — see
`agents/reviewer.md`.

## Quick start (Claude Code)

```bash
cd harness-sdd
./init.sh                 # environment gate — must pass
claude                    # CLAUDE.md → AGENTS.md auto-loads
# new idea? /sdd-new "<idea>"   # Inception triages it → seeds a pending task
# whole project? /sdd-plan "<idea>"  # the whole-project inception skill: writes vision/architecture + ADRs and seeds draft epics
# deepen one? /sdd-drill <epic-id>  # the per-epic drill-down skill: decomposes a draft epic into features + ADR deltas, then one epic-level approval (draft → planned)
# quick fix? /sdd-fix "<desc>"   # the lightweight fix lane: seeds an sdd:false fix under the reserved maintenance epic (brief only, no spec) and runs Builder → Reviewer
# then:     /sdd-next            # runs the Orchestrator on the next task
```

`/sdd-new` is the front door: it asks a few questions, decides whether the idea is a
new epic / feature / task, and writes a `pending` entry plus an intent brief — without
hand-editing `state/tasks.json`. Then the Orchestrator spawns `architect` → (human
approves) → `builder` → `reviewer`.

## Using other CLIs

| CLI | Entry file | Sub-agents |
|---|---|---|
| **Claude Code** | `CLAUDE.md` → `AGENTS.md` | `.claude/agents/*` + `/sdd-new`, `/sdd-plan`, `/sdd-drill`, `/sdd-fix`, `/sdd-next` |
| **Codex** | `AGENTS.md` (native) | run roles sequentially; **global** `/prompts:sdd-new`, `/prompts:sdd-plan`, `/prompts:sdd-drill`, `/prompts:sdd-fix`, `/prompts:sdd-next` prompts in `${CODEX_HOME:-~/.codex}/prompts/` |
| **Gemini CLI** | `GEMINI.md` → `AGENTS.md` | run roles sequentially |
| **OpenCode** | `AGENTS.md` (native) + `opencode.json` | `opencode.json` agents + `.opencode/command/*` (`/sdd-new`, `/sdd-plan`, `/sdd-drill`, `/sdd-fix`, `/sdd-next`) |
| **Antigravity** | `GEMINI.md` + `.agents/rules/` → `AGENTS.md` | `.agents/agents/*` personas + `.agents/workflows/*` slash commands (`/sdd-new`, `/sdd-plan`, `/sdd-drill`, `/sdd-fix`, `/sdd-next`) |

The harness body — `AGENTS.md`, `agents/`, `specs/`, `progress/`, `init.sh`, the
stores — is **identical** across all of them. Only the entry filename and the
sub-agent mechanism differ. Which of these front-ends gets installed is your choice —
the installer lets you select the agents to support and re-prompts on every upgrade
(see [Installing into an existing project](#installing-into-an-existing-project)).

## Configuring the knowledge base / state

`harness.config.yaml` picks the store backend (no prompt changes when you swap):

| Backend | Status | Notes |
|---|---|---|
| `local` | ✅ default | `state/tasks.json` + markdown; zero deps |
| `obsidian` | ✅ | point a vault at the repo; frontmatter + `[[wikilinks]]` |
| `jira` | ⏳ stub | contract defined in `store/jira.md`; wire MCP in a follow-up |

A **backend** is *where state lives*. Two optional, **VCS/PM-neutral** seams sit beside it
(both empty/off by default, so nothing changes unless you opt in):

- **`store.on_write_command`** — a command the Orchestrator runs after every persisted
  store write (best-effort, never blocks the loop). Point it at a `git push`, a board
  mirror, or a wrapper doing both. The harness never learns what it does. See
  `store/local.md` → "Post-write sync".
- **Project board mirror** — a one-way projection of `state/tasks.json` onto a Kanban
  board (see below).

## Delegating implementation (execution backend)

By default the **Builder writes code itself**, in whatever CLI you're running — no
extra dependencies, works for everyone. That's `execution.builder.backend: in-session`.

If you have an external executor (a multi-agent orchestrator, a remote build
service, anything that takes a spec and produces an implementation), you can hand
the **Builder phase** off to it without forking any role file:

```yaml
# harness.config.yaml
execution:
  builder:
    backend: delegate
    delegate_cmd: "bash path/to/your-executor.sh"
```

In `delegate` mode the Builder does not write code — it invokes
`delegate_cmd <feature-id> <abs-spec-path>` and surfaces the result. The executor
owns implementation (and may own PR creation / review too). On non-zero exit the
Builder records the failure and hands back to the Orchestrator.

Scope is deliberate and structural:

- **Only the Builder is delegatable.** The Orchestrator is *never* a key here — it
  is the loop that reads this config and calls `delegate_cmd`, so it always runs in
  the host code-agent. Architect / Reviewer / Scout also stay in-session.
- To make a new role delegatable later, add a sibling key (e.g. `architect:`) — the
  Orchestrator can never be one.

This is the seam that lets a heavier orchestrator *consume* the harness while the
harness stays standalone: the harness never learns what the executor is, and a
single-CLI user is unaffected (they keep the `in-session` default). For a worked
example, see the multi-cli-orchestrator project, which wires its CLI-routing +
Codex-PR pipeline in as one such executor.

## Observability (telemetry)

The harness records its own work — per-sub-agent **durations**, build↔review **round
counts**, and **human spec-approval latency** (the gap between `spec-ready` and a human
moving it to `in-progress`) — to a zero-dependency JSONL log, and rolls it up into
reports. It is **on by default** and **best-effort** (a telemetry write never blocks a
gate or build).

```bash
python3 tools/telemetry-report.py            # all-granularity summary
python3 tools/telemetry-report.py weekly      # daily|weekly|monthly|quarterly|semester|annual
python3 tools/telemetry-report.py session     # this session (also printed at session end)
```

The log is **local-only / gitignored** runtime data at `<HARNESS_DIR>/telemetry.jsonl`
(`.harness/telemetry.jsonl` in an installed consumer; the installer seeds a targeted
`.harness/.gitignore`), configurable via the `telemetry:` block (incl. an `enabled`
kill-switch) in `harness.config.yaml`. Token/USD cost is out of scope for the portable
markdown-prompt runtime (a reserved `cost` slot is left for an instrumented SDK runtime).
See `agents/orchestrator.md` → "## Telemetry".

## Project board mirror

Optionally **mirror** `state/tasks.json` onto an external project board so humans get a
Kanban view — one issue/work-item per feature, with Status + Epic fields, closing done /
reopening regressed. It is a **one-way projection**: `tasks.json` stays the source of
truth and the agents never read the board, so unlike a store backend it never has to be
reachable for the loop to run. **Opt-in and inert by default.**

```yaml
# harness.config.yaml
mirror:
  board:
    provider: github-projects   # ""/none (default) · github-projects · jira · azure-boards
    owner: my-org
    project_number: 1
    repo: my-org/specs
```

```bash
node tools/sync-board.mjs            # sync the configured provider
node tools/sync-board.mjs --dry-run  # preview, mutate nothing
```

`github-projects` is implemented (needs `gh`); `jira` and `azure-boards` are recognized
no-op **stubs**. Run it automatically after each status change by wiring it into
`store.on_write_command`. **Mirror ≠ backend**: a mirror projects local truth outward; a
backend (`tasks: jira`) *is* the truth. Full contract, the provider table, and column
configuration: `store/board-mirror.md`.

## Layout

```
AGENTS.md                    entrypoint (open standard)
CLAUDE.md GEMINI.md          thin per-CLI pointers
opencode.json                OpenCode agents + AGENTS.md instruction
harness.config.yaml          store backends, hooks, mirror, telemetry, umbrella
harness-install.sh           install/upgrade into a target (+ --umbrella, --shared-repo)
init.sh                      environment verification gate
agents/                      role prompts (canonical)
tools/                       zero-dep utilities (telemetry-report.py, sync-board.mjs)
specs/                       product.md, glossary.md, _templates/, epics/<E>/<F>/*.md
state/                       tasks.json (local TaskStore) + schema
progress/                    run output + history.md
store/                       store contract + adapters (local, obsidian, jira) + board-mirror
docs/                        SPEC-FORMAT, WORKFLOW, HARNESS, INSTALL, UMBRELLA, CONFIG-LAYERING
umbrella.manifest.example.yaml   cross-repo coordinator manifest template
umbrella.gitignore.example       shared-spec-repo .gitignore reference
.claude/                     Claude Code sub-agents + commands
.opencode/command/           OpenCode slash commands (/sdd-new, /sdd-plan, /sdd-drill, /sdd-fix, /sdd-next)
.agents/                     Antigravity glue — rules + agent personas + workflows (/sdd-new, /sdd-plan, /sdd-drill, /sdd-fix, /sdd-next)
${CODEX_HOME:-~/.codex}/prompts/  Codex CLI slash-command prompts (GLOBAL, not in-repo — /prompts:sdd-new, /prompts:sdd-plan, /prompts:sdd-drill, /prompts:sdd-fix, /prompts:sdd-next)
```

## Installing into an existing project

```bash
./harness-install.sh /path/to/your-project
```

Idempotent install/upgrade: drops the harness body into `<project>/.harness/`, appends
a marked pointer block to any existing `CLAUDE.md`/`AGENTS.md`/`GEMINI.md` (your prose
is preserved), generates the glue for the selected agents, and seeds a runnable
workspace. Re-run to upgrade — project-authored specs/state are never clobbered. See
`docs/INSTALL.md`.

**Choosing which agents to support.** The shared portable entrypoint `AGENTS.md` is
always written, but each coding agent's front-end is **opt-in**. On an interactive
terminal the installer shows a checkbox-style toggle list — `claude`, `gemini`,
`opencode`, `antigravity`, `codex` — and stamps only the ones you pick. The choice is
saved to `.harness/.agents`, so **every re-run re-prompts with your current selection
pre-checked** — add or drop an agent any time, even when the harness version hasn't
changed. Deselecting an agent removes only the harness-generated glue (your own
`.claude/`/`.opencode/`/`.agents/` files and a hand-edited `opencode.json` are left
untouched — Antigravity and Codex glue are removed only when byte-identical to a freshly
generated stamp, never your edited files).

> **Note — Codex is GLOBAL.** Codex CLI has no project-local custom-command
> mechanism, so its only slash-command surface is the machine-global prompts dir
> `${CODEX_HOME:-~/.codex}/prompts/`. Selecting `codex` therefore writes the prompt
> files *outside* the target repo, into that shared dir (honoring `$CODEX_HOME`; if
> neither `CODEX_HOME` nor `HOME` is set — e.g. minimal CI — the Codex step is
> skipped with a warning rather than failing the install). Codex surfaces a file
> `sdd-next.md` as **`/prompts:sdd-next`** (namespaced under `/prompts:`, not
> top-level `/sdd-next`). The bodies resolve their paths against `.harness/` of
> whatever repo Codex is launched in, so one global copy drives every target — but
> the prompts are shared across all harness installs on the machine (later installs
> overwrite them), and Codex's in-repo entrypoint remains the always-written
> `AGENTS.md`.

```bash
# Non-interactive / CI — pick explicitly (no prompt):
./harness-install.sh --agents=claude,opencode /path/to/your-project
HARNESS_AGENTS=claude ./harness-install.sh /path/to/your-project
# No TTY and no override ⇒ all agents are stamped (back-compatible default).
```

**Shared vs personal config.** The install is meant to be *committed and shared* — one
`CLAUDE.md`, the `.harness/` body, the `.claude/` glue. Per-developer state stays local:
the installer append-seeds the project-root `.gitignore` with `.claude/settings.local.json`
and friends, and personal model/prompt preferences belong in your user-global
`~/.claude/CLAUDE.md`. So yes — the same `CLAUDE.md` for the whole team is the intended
setup. See `docs/CONFIG-LAYERING.md`.

**Cross-repo products (umbrella).** One invocation can cascade the harness across an
umbrella directory of sibling repos (`--umbrella`), and `--shared-repo` makes the umbrella
root its own git repo — a **shared spec repository** that versions `.harness/` (specs,
task state) for the team while git-ignoring the product repos cloned into it. Both opt-in;
single-repo use is unaffected. See `docs/UMBRELLA.md`.

## Adapting to a real project
1. Rewrite `specs/product.md` for your product.
2. Set the test/lint/typecheck commands in `harness.config.yaml` and the
   project-specific section of `init.sh`.
3. Add work by running `/sdd-new "<idea>"` (the Inception intake seeds it for you), or
   hand-author entries from `specs/_templates/`.

After install, steps 1–2 are done for you by the first-run bootstrap (`/sdd-next`).

Derived from the *Harnessing Engineering* research (harness-engineering + SDD videos,
Anthropic's long-running-development post, the Harness Engineering knowledge graph).
