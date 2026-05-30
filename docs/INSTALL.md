# Installing the harness into a project

The harness is portable: it installs into any repo as a self-contained `.harness/`
directory plus a few thin pointers. Install and upgrade are the **same idempotent
command**.

## Install

```bash
git clone <harness-sdd repo>        # or keep a local checkout
cd harness-sdd
./harness-install.sh /path/to/your-project
```

This writes, into your project:

```
your-project/
├── CLAUDE.md / AGENTS.md / GEMINI.md   # your content kept; a marked harness block appended
├── .claude/agents/*  .claude/commands/sdd-next.md   # Claude Code glue → resolves to .harness/
├── opencode.json                       # created only if absent
└── .harness/                           # the whole harness body
    ├── .harness-version  manifest.txt
    ├── AGENTS.md agents/ docs/ store/ specs/_templates/ init.sh harness.config.yaml
    ├── specs/product.md  specs/epics/   # YOURS — seeded once, never overwritten
    ├── state/tasks.json                 # YOURS — bootstrap task seeded
    └── progress/
```

Nothing you authored is destroyed: existing entrypoint prose is preserved (only the
`<!-- harness:begin -->…<!-- harness:end -->` block is managed), and project files
under `.harness/specs|state|progress` are written once and never clobbered.

## Bootstrap (first run)

The installer is deterministic; the *project-specific* adaptation is done through the
harness itself, under the human gate:

1. Edit `.harness/specs/product.md` for your product.
2. Open the project in Claude Code and run **`/sdd-next`**. The Orchestrator runs the
   seeded `E00-F01` bootstrap task — Scout reconnoiters the repo, the Architect drafts
   epics and detects your test/lint/typecheck commands (`.harness/harness.config.yaml`
   + the project section of `.harness/init.sh`).
3. Approve, then keep running `/sdd-next` to build features.

## Upgrade

Re-run the same command after pulling a newer harness:

```bash
cd harness-sdd && git pull
./harness-install.sh /path/to/your-project
```

The harness body and `.claude/` glue are refreshed; the pointer block is replaced in
place (never duplicated); your `product.md`, `tasks.json`, epics and progress are left
untouched. `.harness/.harness-version` records the installed version.

## Layout & ownership

| Class | Files | On upgrade |
|---|---|---|
| harness-owned | `.harness/{AGENTS.md,agents,docs,store,specs/_templates,init.sh,config}`, `.claude/*` | overwritten |
| project-owned | `.harness/{specs/product.md,specs/epics,state/tasks.json,progress}` | never touched |
| merge-region | `CLAUDE.md` / `AGENTS.md` / `GEMINI.md` | only the marked block |

## Fallback: AI-driven adoption

For a repo too unusual for the installer, you can instead open an agent in the target
and say *"here is a harness-sdd checkout — understand it and adapt it for this repo."*
This is the **fallback**, not the default: it is non-reproducible and can't be
cleanly upgraded later. Prefer the installer.
