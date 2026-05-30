# harness-sdd

A portable **agent harness** for **Spec-Driven Development**. It runs primarily on
**Claude Code** and is portable to **Codex**, **Gemini CLI**, and **OpenCode** —
because the harness is just files in the repo, and the model/CLI is interchangeable.

> The model is the engine; the harness is the chassis. Models change every few
> months — your harness doesn't. See `docs/HARNESS.md`.

## How it works

Four roles move work through files, each in a clean context:

```
Orchestrator → Architect → Builder → Reviewer        (Scout = read-only recon)
   state         specs       code      verify
```

Specs follow a **Product → Epic → Feature** hierarchy, where each feature is a
4-file spec (`.spec` / `.plan` / `.tasks` / `.tests`) with **EARS** acceptance
criteria and full requirement→test **traceability**. See `docs/SPEC-FORMAT.md`.

## Quick start (Claude Code)

```bash
cd harness-sdd
./init.sh                 # environment gate — must pass
claude                    # CLAUDE.md → AGENTS.md auto-loads
# then:  /sdd-next        # runs the Orchestrator on the next task
```

The Orchestrator spawns `architect` → (human approves) → `builder` → `reviewer`.

## Using other CLIs

| CLI | Entry file | Sub-agents |
|---|---|---|
| **Claude Code** | `CLAUDE.md` → `AGENTS.md` | `.claude/agents/*` + `/sdd-next` |
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

## Layout

```
AGENTS.md              entrypoint (open standard)
CLAUDE.md GEMINI.md    thin per-CLI pointers
opencode.json          OpenCode agents + AGENTS.md instruction
harness.config.yaml    store backends + settings
init.sh                environment verification gate
agents/                role prompts (canonical)
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
3. Add epics/features (copy `specs/_templates/`), or run the Architect to generate them.

After install, steps 1–2 are done for you by the first-run bootstrap (`/sdd-next`).

Derived from the *Harnessing Engineering* research (harness-engineering + SDD videos,
Anthropic's long-running-development post, the Harness Engineering knowledge graph).
