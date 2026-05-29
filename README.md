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

## Adapting to a real project
1. Rewrite `specs/product.md` for your product.
2. Set the test/lint/typecheck commands in `harness.config.yaml` and the
   project-specific section of `init.sh`.
3. Add epics/features (copy `specs/_templates/`), or run the Architect to generate them.

Derived from the *Harnessing Engineering* research (harness-engineering + SDD videos,
Anthropic's long-running-development post, the Harness Engineering knowledge graph).
