# Implemented baseline — 0.78.1

Documentation baseline recorded on 2026-09-14, before the next front-end changes.
`VERSION` remains `0.78.1`: this audit corrects documentation without changing the
installer, execution contracts, tools, or generated glue.

## Current implementation and validation

The installer still accepts all five front-end keys. Claude-first defaults park
other front-ends until selected on fresh installs; their emitters remain present.
See [installation and selection rules](INSTALL.md) for interactive, unattended,
and explicit-host behavior.

| Front-end | Implemented integration surface | Validation confidence at this baseline |
|---|---|---|
| Claude Code (`claude`) | `CLAUDE.md`, `.claude/agents/`, `.claude/commands/` | Primary workflow, validated through maintainer-reported use |
| Codex (`codex`) | Native `AGENTS.md`, shared `.agents/skills/` workflows, seven `.codex/agents/*.toml` roles | Tested less deeply end to end than Claude Code, per the maintainer |
| OpenCode (`opencode`) | `AGENTS.md`, `opencode.json`, `.opencode/command/`; parallel-fix capability gate | Implementation retained; no equivalent live-use validation claim in this audit |
| Gemini CLI (`gemini`) | `GEMINI.md`; sequential roles, with role files when model routing resolves | Implementation retained; no equivalent live-use validation claim in this audit |
| Antigravity (`antigravity`) | `GEMINI.md`, `.agents/{rules,agents,workflows}/`, shared `.agents/skills/` | Implementation retained; no equivalent live-use validation claim in this audit |

Generated artifacts and regression tests establish implementation coverage.
They do not establish that every workflow works end to end in every live CLI.
Claude's stronger confidence comes from the maintainer's experience, rather than
an exhaustive test claim. The unmerged PR #183 Codex delegate trial is separate
from this shipped baseline.

## Source checkout and installed projects

The source checkout keeps the body at repository root and includes `.claude/`,
`CLAUDE.md`, `GEMINI.md`, and `opencode.json`. It has no installed `.harness/` body
or generated `.codex/`, `.agents/`, or `.opencode/` directories. Source `--self`
regenerates Claude glue only; it does not verify all five integrations.

An installed project keeps its body under `.harness/`, with selected and enabled
front-end glue at project root. Edit `.harness/specs/product.md`, configuration,
and the durable `.harness/init.project.sh` hook for project adaptation. The
installer refreshes `.harness/init.sh`. See [layout and ownership](INSTALL.md#layout--ownership).

The default local TaskStore requires Unix Python 3 with stdlib `fcntl`, with no
third-party Python packages. Node is optional for task selection with a prose
fallback, and required for board mirrors. GitHub Projects and Jira Server/Data
Center mirrors are implemented; the Jira TaskStore and Azure Boards mirror remain
stubs. See the [store overview](../store/README.md) and [mirror contract](../store/board-mirror.md).

## Future direction — separate implementation work

The intended priority is **Claude Code first, Codex second, OpenCode third**.
Removing Gemini and Antigravity integration support is planned follow-up work.
Codex integration work comes next after this documentation baseline is reviewed
and recorded. Neither the removal nor the Codex trial is delivered by this audit.
