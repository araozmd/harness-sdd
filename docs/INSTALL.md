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
├── .claude/agents/*  .claude/commands/{sdd-next,sdd-new}.md   # Claude Code glue → resolves to .harness/
├── opencode.json                       # created only if absent
├── .agents/{rules,agents,workflows}/   # Antigravity glue → resolves to .harness/ (regenerated each run)
└── .harness/                           # the whole harness body
    ├── .harness-version  manifest.txt
    ├── AGENTS.md agents/ docs/ store/ tools/ specs/_templates/ init.sh harness.config.yaml
    ├── .gitignore                       # seeded: keeps the local-only telemetry log out of VCS
    ├── telemetry.jsonl                  # created on first run — local-only, gitignored (E05-F02)
    ├── specs/product.md  specs/epics/   # YOURS — seeded once, never overwritten
    ├── state/tasks.json                 # YOURS — bootstrap task seeded
    └── progress/
```

`tools/` ships the zero-dep telemetry reporter (`python3 .harness/tools/telemetry-report.py`);
see [`../README.md`](../README.md) → Observability and `agents/orchestrator.md` → "## Telemetry".

Nothing you authored is destroyed: existing entrypoint prose is preserved (only the
`<!-- harness:begin -->…<!-- harness:end -->` block is managed), and project files
under `.harness/specs|state|progress` are written once and never clobbered.

## Bootstrap (first run)

The installer is deterministic; the *project-specific* adaptation is done through the
harness itself, under the human gate:

1. Edit `.harness/specs/product.md` for your product.
2. Open the project in Claude Code and run **`/sdd-next`**. The seeded `E00-F01`
   bootstrap task is `sdd: true`, so the Orchestrator routes it to the Architect
   (with Scout recon) to draft epics and detect your test/lint/typecheck commands
   (`.harness/harness.config.yaml` + the project section of `.harness/init.sh`), then
   **pauses at the human gate** for your approval.
3. Approve, then keep running `/sdd-next` to build features.

To add new work later, run **`/sdd-new "<idea>"`** — the Inception intake triages it
(new epic / feature / task), seeds a `pending` entry plus an intent brief, and tells
you to run `/sdd-next` to spec and build it. The installer ships this command into your
project alongside `/sdd-next`.

## Upgrade

Re-run the same command after pulling a newer harness:

```bash
cd harness-sdd && git pull
./harness-install.sh /path/to/your-project
```

The harness body and `.claude/` glue are refreshed; the pointer block is replaced in
place (never duplicated); your `product.md`, `tasks.json`, epics and progress are left
untouched. `.harness/.harness-version` records the installed version.

## Umbrella mode (cascade install)

For a cross-repo product (see [`UMBRELLA.md`](./UMBRELLA.md)) one invocation can
**cascade** the harness across an umbrella directory that hosts sibling child repos:

```bash
./harness-install.sh --umbrella /path/to/umbrella-dir
```

This is a thin orchestration over the same single-target install (no second harness
body); it does three things:

1. **Coordinator profile** — installs the full harness into `<umbrella>/.harness/`,
   sets `umbrella.manifest` to `../umbrella.manifest.yaml`, and ensures
   `verification.integration_command` exists (left blank for bootstrap to fill). The
   coordinator runs no per-repo unit tests — it relies on the integration command.
2. **Child profile** — scans the umbrella's **immediate children only** (depth 1) and
   installs the normal single-target `.harness/` into every child that is a **git
   repo** (contains `.git` as a directory OR a file). Hidden/dotfile dirs and the
   umbrella's own `.harness` are skipped. A child whose directory name does not match
   `^[a-z0-9-]+$` is **skipped with a warning** (the name cannot form a slice-id repo
   key) — no install, no manifest entry.
3. **Manifest auto-population** — creates `<umbrella>/umbrella.manifest.yaml` (top-level
   `repos:`) and appends one entry per discovered git child (`path: ./<name>` plus
   `init`/`test_command`/`delegate_cmd` TODO placeholders for bootstrap to fill).

`--recursive` is accepted but the deeper-scan semantics are deferred; today it still
scans depth 1 and prints a note.

### Shared spec repository (`--shared-repo`)

By default the umbrella root is **not** a git repo, so the coordinator's `.harness/`
(specs, `state/tasks.json`, progress) lives only on the machine that ran the cascade. To
share that planning state across a team, add `--shared-repo`:

```bash
./harness-install.sh --umbrella /path/to/umbrella-dir --shared-repo
```

After the normal cascade it (a) runs `git init` at the umbrella root **only if it has no
`.git` yet** (an existing repo is never re-initialized), and (b) **append-seeds** the
umbrella-root `.gitignore` to ignore the product child repos it discovered — so they stay
their own repos, never gitlinks — on top of the per-developer state every install ignores.
The umbrella becomes a **spec repository** that tracks `.harness/` + umbrella docs;
teammates clone it for the shared specs/task state, then clone the product repos beside the
harness. Preview it first with `--shared-repo --dry-run`. See
[`UMBRELLA.md`](./UMBRELLA.md#shared-spec-repository-opt-in) and the shipped
`umbrella.gitignore.example`. Omit the flag and nothing about the root changes.

Umbrella mode is **idempotent and additive**: re-running rediscovers newly-added git
children and appends them without ever overwriting an existing manifest entry's fields
or a child's project-owned files. With `--umbrella` absent, the installer behaves
exactly as the single-target form below — only an additive, value-preserving config
**migration** is layered in (see next section).

## Config migration on upgrade (non-destructive)

The installer preserves an existing `.harness/harness.config.yaml` on upgrade. To get
newer additive default keys (e.g. the `umbrella.manifest`,
`verification.integration_command`, and the `telemetry:` block introduced after a target
was first installed) into that preserved file, every upgrade runs an **append-only
migration**: it adds any missing default key (under its section header, or as a new
header+key block at EOF) **without altering any existing value or comment**. It is
idempotent — a config that already has every default key is left byte-for-byte unchanged.
POSIX `sh`, zero deps.

> Upgrading from a pre-telemetry harness (< v0.7.0)? The upgrade refreshes the body
> (so `tools/`, the `## Telemetry` orchestrator section, and the reviewer cross-file
> check arrive), seeds `.harness/.gitignore`, and appends the `telemetry:` block to your
> preserved config. A config *without* the block still works — telemetry defaults to
> enabled with `telemetry.jsonl`.

## Layout & ownership

| Class | Files | On upgrade |
|---|---|---|
| harness-owned | `.harness/{AGENTS.md,agents,docs,store,tools,specs/_templates,init.sh}`, `.claude/*` | overwritten |
| project-owned | `.harness/{harness.config.yaml,specs/product.md,specs/epics,state/tasks.json,progress}` | preserved (config also append-migrated) |
| runtime/local | `.harness/{telemetry.jsonl,.gitignore}`, project-root `.gitignore` | gitignored; both `.gitignore`s append-seeded (never clobbered), logs/personal state never committed |
| merge-region | `CLAUDE.md` / `AGENTS.md` / `GEMINI.md` | only the marked block |

The installer also **append-seeds the project-root `.gitignore`** with per-developer
agent state (`.claude/settings.local.json`, `.claude/scheduled_tasks.lock`, and a commented
example per-tool MCP scratch dir, e.g. `.playwright-mcp/`) so a **shared** spec/umbrella repo never carries one developer's local
config — while the generated `.claude/agents` and `.claude/commands` stay tracked. See
[`CONFIG-LAYERING.md`](./CONFIG-LAYERING.md) for the shared-vs-personal model.

## Fallback: AI-driven adoption

For a repo too unusual for the installer, you can instead open an agent in the target
and say *"here is a harness-sdd checkout — understand it and adapt it for this repo."*
This is the **fallback**, not the default: it is non-reproducible and can't be
cleanly upgraded later. Prefer the installer.
