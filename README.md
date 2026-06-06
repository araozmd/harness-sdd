# harness-sdd

A portable **agent harness** for **Spec-Driven Development**. It runs primarily on
**Claude Code** and is portable to **Codex**, **Gemini CLI**, and **OpenCode** —
because the harness is just files in the repo, and the model/CLI is interchangeable.

> The model is the engine; the harness is the chassis. Models change every few
> months — your harness doesn't. See `docs/HARNESS.md`.

## How it works

An interactive **intake** (Inception) turns a raw idea into a seeded `pending` task;
from there the roles move it through files, each in a clean context:

```
 /sdd-new                       /sdd-next
  idea → Inception → pending → Orchestrator → Architect → Builder → Reviewer
         (intake)                  state         specs       code      verify
                                              (Scout = read-only recon)
```

Specs follow a **Product → Epic → Feature** hierarchy, where each feature is a
4-file spec (`.spec` / `.plan` / `.tasks` / `.tests`) with **EARS** acceptance
criteria and full requirement→test **traceability**. See `docs/SPEC-FORMAT.md`.

The Reviewer runs a **cross-file consistency** check (a change must not contradict the
contracts it invokes) and the build↔review loop is **multi-round until green** — see
`agents/reviewer.md`.

## Quick start (Claude Code)

```bash
cd harness-sdd
./init.sh                 # environment gate — must pass
claude                    # CLAUDE.md → AGENTS.md auto-loads
# new idea? /sdd-new "<idea>"   # Inception triages it → seeds a pending task
# then:     /sdd-next            # runs the Orchestrator on the next task
```

`/sdd-new` is the front door: it asks a few questions, decides whether the idea is a
new epic / feature / task, and writes a `pending` entry plus an intent brief — without
hand-editing `state/tasks.json`. Then the Orchestrator spawns `architect` → (human
approves) → `builder` → `reviewer`.

## Using other CLIs

| CLI | Entry file | Sub-agents |
|---|---|---|
| **Claude Code** | `CLAUDE.md` → `AGENTS.md` | `.claude/agents/*` + `/sdd-new`, `/sdd-next` |
| **Codex** | `AGENTS.md` (native) | run roles sequentially; hand off via files |
| **Gemini CLI** | `GEMINI.md` → `AGENTS.md` | run roles sequentially |
| **OpenCode** | `AGENTS.md` (native) + `opencode.json` | `opencode.json` agents |

The harness body — `AGENTS.md`, `agents/`, `specs/`, `progress/`, `init.sh`, the
stores — is **identical** across all of them. Only the entry filename and the
sub-agent mechanism differ.

## Configuring the knowledge base / state

`harness.config.yaml` picks the store backend (no prompt changes when you swap):

| Backend | Status | Notes |
|---|---|---|
| `local` | ✅ default | `state/tasks.json` + markdown; zero deps |
| `obsidian` | ✅ | point a vault at the repo; frontmatter + `[[wikilinks]]` |
| `jira` | ⏳ stub | contract defined in `store/jira.md`; wire MCP in a follow-up |

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

## Layout

```
AGENTS.md              entrypoint (open standard)
CLAUDE.md GEMINI.md    thin per-CLI pointers
opencode.json          OpenCode agents + AGENTS.md instruction
harness.config.yaml    store backends + settings
init.sh                environment verification gate
agents/                role prompts (canonical)
tools/                 zero-dep utilities (telemetry-report.py)
specs/                 product.md, glossary.md, _templates/, epics/<E>/<F>/*.md
state/                 tasks.json (local TaskStore) + schema
progress/              run output + history.md
store/                 store contract + adapters (local, obsidian, jira)
docs/                  SPEC-FORMAT.md, WORKFLOW.md, HARNESS.md
.claude/               Claude Code sub-agents + commands
```

## Installing into an existing project

```bash
./harness-install.sh /path/to/your-project
```

Idempotent install/upgrade: drops the harness body into `<project>/.harness/`, appends
a marked pointer block to any existing `CLAUDE.md`/`AGENTS.md`/`GEMINI.md` (your prose
is preserved), generates the Claude Code glue, and seeds a runnable workspace. Re-run
to upgrade — project-authored specs/state are never clobbered. See `docs/INSTALL.md`.

## Adapting to a real project
1. Rewrite `specs/product.md` for your product.
2. Set the test/lint/typecheck commands in `harness.config.yaml` and the
   project-specific section of `init.sh`.
3. Add work by running `/sdd-new "<idea>"` (the Inception intake seeds it for you), or
   hand-author entries from `specs/_templates/`.

After install, steps 1–2 are done for you by the first-run bootstrap (`/sdd-next`).

Derived from the *Harnessing Engineering* research (harness-engineering + SDD videos,
Anthropic's long-running-development post, the Harness Engineering knowledge graph).
