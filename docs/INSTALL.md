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
├── .claude/agents/*  .claude/commands/{sdd-next,sdd-new,sdd-plan,sdd-drill,sdd-fix,sdd-fix-parallel}.md
├── .claude/commands/sdd-pr-loop.md  .claude/agents/pr-fixer.md   # only while pr_loop.enabled (opt-in, seeded false)
├── .opencode/agent/pr-fixer.md         # only while pr_loop.enabled (OpenCode file-based sub-agent)
├── opencode.json                       # created only if absent (re-stamped only while pristine)
├── .agents/{rules,agents,workflows}/   # Antigravity glue → resolves to .harness/ (regenerated each run)
├── .gemini/agents/*.md                 # per-role model routing only — created ONLY when a tier resolves
├── .codex/agents/*.toml                # per-role model routing only — project-local, never ~/.codex
└── .harness/                           # the whole harness body
    ├── .harness-version  manifest.txt
    ├── .opencode.stamp                  # byte copy of the last generated opencode.json (model routing only)
    ├── .model-agents/                   # byte copies of the last .gemini/.codex per-role files (model routing only)
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

The installer also generates `/sdd-fix-parallel` from one byte-identical command body
for Claude, OpenCode, Antigravity, and global Codex prompts. It resolves the portable
Fixer and targeted Orchestrator contracts from `.harness/`, and its filename is
registry-owned for safe front-end cleanup. Fresh config includes
`fix_lane.max_parallel: 3` and extension-only `fix_lane.shared_paths: []`. The
parallel command requires the default `execution.builder.backend: in-session`; a
delegate backend fails before manifest/provision/claim and points to serial
`/sdd-fix`, because delegates may own PR/review timing.

### `/sdd-pr-loop` (opt-in, gated on `pr_loop.enabled`)

> **Opt-in.** A fresh install seeds `pr_loop.enabled: false` and stamps **no**
> `/sdd-pr-loop` glue at all. Set it to `true` in `.harness/harness.config.yaml` and re-run
> the installer to turn the loop on. Only the literal `true` enables it — an absent block,
> an absent key, an empty or malformed value all mean off.

The installer also generates **`/sdd-pr-loop`** — the Codex review loop — from one
byte-identical body into `.claude/commands/`, `.opencode/command/`, `.agents/workflows/`
and the GLOBAL `${CODEX_HOME:-~/.codex}/prompts/`, plus a `pr-fixer` sub-agent for Claude
(`.claude/agents/pr-fixer.md`), OpenCode (`.opencode/agent/pr-fixer.md`) and Antigravity
(`.agents/agents/pr-fixer.md`). All of it points at the canonical
`.harness/agents/pr-fixer.md`; no role body is duplicated, and **no** `pr-fixer` artifact
is created for the codex or gemini front-ends (those apply fixes in-session).

**Preconditions — the loop only works with all three:** the **Codex GitHub App** installed
on the target repository, an **authed `gh`**, and **`jq`** on `PATH`. The watcher's
`preflight` mode checks each one before anything is posted and fails fast (exit `5`) with
a one-line diagnostic naming the failed check and its remedy. These are **loop-runtime**
dependencies only: `init.sh` gains no new gate, so a target with neither `gh` nor `jq`
still passes the environment gate.

Fresh config seeds:

```yaml
pr_loop:
  enabled: false                 # opt-in master gate; ONLY `true` stamps /sdd-pr-loop glue
  auto_merge: true               # merge once every gate is green and threads are Codex-only
  max_rounds: 4                  # round cap; the cap round labels the PR needs-human
  blocking_severities: "P0,P1"   # comma-separated severities that block a merge
  merge_strategy: "merge"        # merge | squash
```

An upgrade appends the same block byte-for-byte; an absent block (or key) behaves exactly
as the defaults above, so an existing config that predates the block stays **off** until
you add it. Each policy key takes a per-run env override —
`HARNESS_PR_LOOP_ENABLED`, `HARNESS_AUTO_MERGE`, `HARNESS_MAX_ROUNDS`,
`HARNESS_BLOCKING_SEVERITIES`, `HARNESS_MERGE_STRATEGY` (env wins over config, config wins
over the default). Execution knobs are **env-only**: `HARNESS_POLL_INTERVAL` (60),
`HARNESS_POLL_CEILING` (900), `HARNESS_FIRST_RESPONSE` (180, `0` disables the probe) and
`HARNESS_DRY_RUN`.

Flipping `pr_loop.enabled` back to `false` and re-running the installer **reclaims** the
command and every `pr-fixer` artifact from each still-selected front-end
(pristine-only in the user-owned `$CODEX_HOME/prompts` dir and the `.agents/` tree), and
empty dirs are pruned. Flipping it back to `true` restores byte-identical glue. The round
cache lives at `.harness/.pr-loop/<pr>/round-<n>/` and is gitignored by the seeded
`.harness/.gitignore`.

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

## Per-role model routing (`models:`) — opt-in

Every sub-agent normally inherits whatever model the host CLI session runs, so the
Architect's design work and the Builder's mechanical execution of an approved `tasks.md`
cost the same per token. The `models:` block in `.harness/harness.config.yaml` lets you
put each SDD role on the tier that fits its job. It is **opt-in and inert by default**:
the seeded block puts every role on `inherit`, and an absent block, an empty block and an
all-`inherit` block are all byte-for-byte identical to a harness without this feature.

```yaml
models:
  default: inherit        # tier for any role not listed below
  orchestrator: inherit
  architect: reasoning
  builder: standard
  reviewer: standard
  scout: cheap
  doc-critic: cheap
  # pin.opencode.standard: "anthropic/claude-sonnet-4-5"
  # pin.codex.cheap: "gpt-5-mini"
```

**Tier vocabulary: `reasoning | standard | cheap | inherit`.** A role's tier is
`models.<role>`, else `models.default`, else `inherit`. An **unrecognized** tier is a
warning on stderr, resolves as `inherit`, and never fails the install — so a config
written for a newer harness can never block an upgrade on an older installer.

`inherit` compiles to **key omission** on every front-end. The literal string `inherit`
is never written anywhere: it is unknown on Codex and a hard error on OpenCode, while an
absent key means "use the session model" on all five.

### What each tier stamps

| tier | claude | antigravity | gemini | codex | opencode |
|---|---|---|---|---|---|
| `reasoning` | `opus` | `pro` | `pro` | *(pin required)* | *(pin required)* |
| `standard` | `sonnet` | `pro` | `pro` | *(pin required)* | *(pin required)* |
| `cheap` | `haiku` | `flash` | `flash` | *(pin required)* | *(pin required)* |
| `inherit` | *omitted* | *omitted* | *omitted* | *omitted* | *omitted* |

Every built-in value is a **floating vendor alias**, never a version-pinned model id, so
a new model release is picked up without a harness change. Antigravity and Gemini expose
only two tiers upstream, so `reasoning` and `standard` both map to `pro`.

### Pinning an exact model — `models.pin.<front-end>.<tier>`

A pin is written **verbatim** in that front-end's own vocabulary and overrides the
built-in alias for every role on that tier. It is **required** for `codex` and `opencode`,
which have no floating alias — an unpinned tier there stamps nothing and the installer
prints one advisory line naming the exact `pin.` key to set.

- `opencode` **must** be `provider/model`. A value without a `/` would abort your OpenCode
  runs, so it is warned about and dropped.
- `codex` **must** be a bare model id; the provider comes from your `model_provider`.
- A pin of `"inherit"` is a **tier name, not a model id**. It is warned about and dropped
  on every front-end, stamping nothing — exactly like the `inherit` tier. The literal
  string `inherit` is never written into a generated artifact.

Those are the only two value checks the installer makes; it cannot know any vendor's
model list, so every other pin value is passed through untouched.
- `antigravity` accepts only tier aliases and needs **`agy` >= 1.1.5**; below that the
  `model:` frontmatter key is inert, never an error. The installer does not probe your
  CLI version.

### Where the values land

| front-end | artifact | form |
|---|---|---|
| `claude` | `.claude/agents/<role>.md` | `model:` frontmatter key |
| `antigravity` | `.agents/agents/<role>.md` | `model:` frontmatter key |
| `opencode` | `opencode.json` | `"model"` member in `agent.<role>` |
| `gemini` | `.gemini/agents/<role>.md` | `model:` frontmatter key (**new file**) |
| `codex` | `.codex/agents/<role>.toml` | `model = "…"` (**new file**, project-local) |

`.gemini/agents/` and `.codex/agents/` are created **only** when at least one role
resolves to a concrete value for that front-end. Only **selected** front-ends
(`--agents`) are ever stamped. The Codex artifact is deliberately project-local: unlike
the target-independent global `/prompts:sdd-*` bodies, a model stamp is target-dependent,
so writing it to `~/.codex` would let one repo silently retune every other repo on the
machine.

> **Codex precondition — the project must be trusted.** Codex discovers agent files by
> directory convention (`$CODEX_HOME/agents/` and the project-local `<repo>/.codex/agents/`),
> so the generated files need no registration. But Codex only reads a project's local
> `.codex/` config at all when that project is **trusted** — i.e. `~/.codex/config.toml`
> carries `[projects."<absolute path to your repo>"]` with `trust_level = "trusted"`.
> On an untrusted clone the generated role files are silently ignored and every role keeps
> the session model. Each file defines the required trio `name` / `description` /
> `developer_instructions`; `codex doctor` reports any role file Codex rejected.

`opencode.json` is the one config file the harness does not regenerate on a plain re-run.
It is re-stamped **only** when it is byte-identical to `.harness/.opencode.stamp` (the
last body the installer wrote) or to a freshly generated model-free body; anything else
is treated as yours, left untouched, and reported. `.harness/.model-agents/` is the same
device for the `.gemini/agents/` and `.codex/agents/` trees: it remembers the exact bytes
last written there, so putting every role back on `inherit` (or deselecting the front-end)
reclaims those files instead of orphaning them with their old `model` keys. Both stamps
exist only while the artifacts they describe do.
Deselecting a front-end reclaims its
stamped artifacts through the same pristine byte-comparison every other generated file
uses — an edited file survives with a warning.

> **`models.orchestrator` does not choose your session's model.** The Orchestrator drives
> the session *you* launched, and how you launched it decides its model. This key applies
> only where the orchestrator is a spawned sub-agent (Claude) or the configured primary
> agent (OpenCode).

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
