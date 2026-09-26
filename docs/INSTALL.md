# Installing the harness into a project

The harness is portable: it installs into any repo as a self-contained `.harness/`
directory plus a few thin pointers. Install and upgrade are the **same idempotent
command**. Supported front ends, in priority order, are **Claude Code**,
**Codex**, **OpenCode**, and **Antigravity**. Gemini CLI is retired; see
[legacy upgrades](#retiring-gemini).

## Prerequisites

Use a Unix shell environment. The default local TaskStore requires `python3` with
the stdlib `fcntl` module for validation and locked writes; `init.sh` fails if either
is missing. No third-party Python packages are required. Node is optional for task
selection (which has a prose fallback), and required for board mirrors. PR-loop
requirements (`gh`, authentication, `jq`, and the Codex GitHub App) apply only when
that workflow is enabled.

## Install

```bash
git clone <harness-sdd repo>        # or keep a local checkout
cd harness-sdd
./harness-install.sh /path/to/your-project
```

The available installed layout is below. `AGENTS.md` and `.harness/` are shared;
front-end artifacts are emitted only for the selected integrations and applicable
gates (including OpenCode concurrency and opt-in PR-loop glue).

```
your-project/
├── AGENTS.md / CLAUDE.md              # shared / selected Claude pointer; your content kept
├── .claude/agents/*  .claude/commands/{sdd-next,sdd-new,sdd-plan,sdd-drill,sdd-fix,sdd-fix-parallel}.md
├── .claude/commands/sdd-pr-loop.md  .claude/agents/pr-fixer.md   # only while pr_loop.enabled (opt-in, seeded false)
├── .opencode/command/*.md              # selected OpenCode commands; fix-parallel needs capability/override
├── .opencode/agent/pr-fixer.md         # only while pr_loop.enabled (OpenCode file-based sub-agent)
├── opencode.json                       # created only if absent (re-stamped only while pristine)
├── .agents/skills/sdd-*/                # shared Codex/OpenCode $sdd-*/sdd-* skill units
│   ├── SKILL.md                         # adapter + canonical workflow
│   └── agents/openai.yaml               # explicit-only invocation policy
├── .codex/agents/*.toml                # seven standard Codex roles + gated pr-fixer; model optional
└── .harness/                           # the whole harness body
    ├── .harness-version  manifest.txt
    ├── .opencode.stamp                  # byte copy of the last opencode.json the installer wrote
    ├── .model-agents/                   # last-written Codex role files; historical stamp path retained
    ├── AGENTS.md agents/ docs/ store/ tools/ specs/_templates/ init.sh harness.config.yaml
    ├── init.project.sh                  # YOURS — fast project checks, seeded once
    ├── .gitignore                       # seeded: keeps the local-only telemetry log out of VCS
    ├── telemetry.jsonl                  # created on first run — local-only, gitignored (E05-F02)
    ├── workers.json                     # only while workers.roster — local-only, gitignored (E17-F04)
    ├── specs/product.md  specs/epics/   # YOURS — seeded once; project edits preserved
    ├── state/tasks.json                 # YOURS — bootstrap task seeded
    └── progress/
```

`tools/` ships the zero-dep telemetry reporter (`python3 .harness/tools/telemetry-report.py`);
see [`../README.md`](../README.md) → Observability and `agents/orchestrator.md` → "## Telemetry".

Existing entrypoint prose is preserved outside the managed
`<!-- harness:begin -->…<!-- harness:end -->` block. Project-owned
`.harness/specs/glossary.md`, epic specs, state, progress, configuration, and
`init.project.sh` are preserved on upgrade (configuration also receives missing default
keys); `.harness/specs/product.md` is preserved too, except that a file still
byte-identical to a prior release's shipped stub is refreshed to the current stub, so an
upgraded target does not keep stale seeded guidance. Templates belong to the refreshed
harness body.
Generated glue follows its front-end ownership rules; see [Layout & ownership](#layout--ownership).

### Shared skill units and legacy prompt migration

Selecting **Codex** or **OpenCode** installs `$sdd-next` / `/sdd-next` (and likewise
`$sdd-new` / `/sdd-new`, `sdd-plan`, `sdd-drill`, `sdd-fix`, `sdd-fix-parallel`) under
`.agents/skills/`; `$sdd-pr-loop` follows the opt-in gate. Both hosts read the same
repository-local unit (ADR-0003), so there is **one** `SKILL.md` per command no matter
which claimant is selected. Each is an atomic two-file ownership unit: `SKILL.md`
contains the workflow plus a **host-neutral adapter** that names both the Codex
`$sdd-*` invocation and the OpenCode `/sdd-*` invocation and maps text accompanying
the skill mention to `$ARGUMENTS`, and `agents/openai.yaml` sets
`policy.allow_implicit_invocation: false`. For example, enter
`$sdd-new Add a settings page` in Codex, then `$sdd-next`. In Codex, `/skills` is the
discovery UI; OpenCode exposes the units through its command palette and `skill` tool.

`/sdd-fix-parallel` additionally **self-gates in its shared body**: under OpenCode it
reads `.harness/.opencode-parallel` before spawning any worker and stops unless the
file reads exactly `supported`, reporting the `/sdd-test-concurrency` →
`--with-opencode-parallel=true` path in an installed target. In the harness **source**
checkout no OpenCode command surface is installed, so that probe is unavailable: write
`supported` to `.opencode-parallel` directly after confirming native concurrent
sub-agents, or run the batch sequentially instead. The gate lives in the body because
the unit is one file read by both hosts; on Codex the precondition is a no-op (Codex
delegates through native concurrent sub-agents).

Last-written copies under `.harness/.codex-skills/` protect both files together.
Selected installs, gate-off and deselection preserve foreign, edited or
symlinked units with a diagnostic. Codex role TOMLs use the matching protection
under `.harness/.model-agents/codex/`. Historical stamp directory names remain
unchanged, preserving prior ownership evidence. The claiming set is `{codex, opencode}`
(ADR-0003): the units are installed while **either** is selected and reclaimed only
when the **last** claimant is deselected, so deselecting one front-end leaves the
other's discoverable surface intact. Only proven pristine units are reclaimed, with
edited units and companions preserved.

Current installation does not use `HOME` or `CODEX_HOME` to create workflow glue
and never writes global `${CODEX_HOME:-$HOME/.codex}/prompts/sdd-*.md` files.
The old global resolver remains for migration only. Ungated legacy prompts are
preserved because their cross-target ownership is unknown. Only a byte-pristine
legacy `sdd-pr-loop.md` with a readable ownership ledger proving no live owners
is reclaimable. Missing, unreadable or live-owner evidence preserves the prompt.

### Retiring Gemini

The accepted selectors are `claude`, `codex`, `opencode`, and `antigravity`; `--agents=all`
expands to those four. Explicit `gemini` in `--agents`,
`HARNESS_AGENTS`, or `HARNESS_HOST_AGENT` fails before target writes and names
supported replacements. Ambient retired-host session markers are ignored.

An upgrade without a new explicit selection filters retired keys from the
recorded `.harness/.agents` and preserves the supported survivors with a notice.
For example, `gemini,codex` becomes `codex`. When no supported key
survives, the upgrade stops before mutation; choose the desired replacement:

```bash
./harness-install.sh --agents=codex /path/to/your-project
# Or choose --agents=claude, --agents=opencode, --agents=antigravity, or a supported CSV.
```

A version-stamped legacy install without `.harness/.agents` uses the surviving
historical baseline `claude,opencode`; it does not infer prior Codex or global
prompt ownership. An orphan selection file without a version stamp grants no
legacy removal authority.

Cleanup uses prior ownership evidence before replacing the old body. It removes
only proven pristine Gemini roles and known Antigravity rules/personas/workflows,
including gated legacy PR-loop artifacts, and the exact managed GEMINI pointer
block. Adjacent user text, unrelated siblings, edited or foreign files, symlinks,
and files with missing or ambiguous proof are preserved with path-specific
warnings. It never recursively deletes `.agents/` or `.gemini/`. Preserved
retired glue is excluded from active harness drift ownership. Review the
warnings and decide separately whether to retain your custom legacy integration.
The [v0.78.1 baseline](BASELINE-0.78.1.md) remains the historical support record.

## Starting from nothing (new product)

For a brand-new product the supported front door is **install first, plan second**.
The target may be an empty, non-git directory — that is a first-class path, not a
degraded mode. The installer does not create a git repository.

1. Create an empty directory for the product.
2. Run `./harness-install.sh /path/to/your-product`. An interactive install asks up to
   three questions — the front-end picker, the builder backend
   (`execution.builder.backend`), and the PR-loop opt-in (`pr_loop.enabled`). Each has a
   flag for scripted installs: `--agents=`, `--builder-backend=`, and `--pr-loop=`.
3. Run the version-control step **in the installed target**: `cd /path/to/your-product`
   first, then `git init` and make a `commit`. The installer does not change the
   caller's working directory, so an unqualified `git init` would target the harness
   checkout. Version control is the human's step, and a committed body lets `init.sh`'s
   drift guard verify it: on a non-git tree the guard skips, and on an untracked body it
   warns — it never fails. This is local only: a PR-based flow also needs a remote
   (`gh repo create`, or `git remote add` + push) and one feature branch per feature,
   which is what the harness opens PRs from.
4. Edit the seeded `.harness/specs/product.md` and fill in the project-constitution
   `TODO`s — "what this product is", its audience, its principles. It is Layer 0, and
   `/sdd-plan` plans *around* it rather than rewriting it: `agents/planner.md` defines
   the vision as complementary to the constitution and forbids the Planner from changing
   it, so a `TODO` left here survives planning. The installer's `Next steps` banner
   prints this same edit as its second item, after `git init`.
5. Open the project and run **`/sdd-plan`** — the whole-project inception that writes
   the vision, architecture and ADRs and seeds the project's draft epics.
6. Run **`/sdd-drill <epic-id>`** to decompose the first draft epic into features.
7. Commit and push the planning baseline to the remote from step 3 — the constitution
   edit, the vision, architecture and ADRs, the epic decomposition, the seeded
   `.harness/state/tasks.json`, and, when the plan names more than one deployable, the
   draft `.harness/umbrella.manifest.draft.yaml`. Until this commit those planning
   artifacts are dirty or untracked, so the remote baseline does not describe them.
8. Create the first feature branch before starting feature work with
   `/sdd-next`: features are built on their own branch and their PR opens from it, so
   committing the planning baseline first keeps the vision, ADRs and decomposition out
   of the first feature PR.
9. Keep running **`/sdd-next`** to spec and build that work.

The seeded `E00-F01` bootstrap task is not the front door for a new product; `/sdd-next`
routes it after `/sdd-plan` — see [Bootstrap (first run)](#bootstrap-first-run).

## Bootstrap (first run)

The installer is deterministic; the *project-specific* adaptation is done through the
harness itself, under the human gate. A new product plans before it builds: run
**`/sdd-plan`** first — the front door is
[Starting from nothing](#starting-from-nothing-new-product).

1. Edit `.harness/specs/product.md` for your product.
2. Run **`/sdd-plan`** to brainstorm the vision, architecture and ADRs and seed the
   project's draft epics.
3. Run **`/sdd-drill <epic-id>`** to decompose a draft epic into features.
4. Commit and push the planning baseline — the constitution edit, the vision,
   architecture and ADRs, the epic decomposition, the seeded
   `.harness/state/tasks.json`, and, when the plan names more than one deployable, the
   draft `.harness/umbrella.manifest.draft.yaml` — then create the first feature branch.
   This keeps the planning artifacts out of the first feature PR.
5. Run **`/sdd-next`**. The seeded `E00-F01` bootstrap task is `sdd: true`, so the
   Orchestrator routes it to the Architect (with Scout recon) to detect your
   test/lint/typecheck commands (`.harness/harness.config.yaml` + fast project gates in
   `.harness/init.project.sh`), then **pauses at the human gate** for your approval.
6. Approve, then keep running `/sdd-next` to build features.

To add new work later, run **`/sdd-new "<idea>"`** — the Inception intake triages it
(new epic / feature / task), seeds a `pending` entry plus an intent brief, and tells
you to run `/sdd-next` to spec and build it. The installer ships this command into your
project alongside `/sdd-next`.

The installer also generates `/sdd-fix-parallel` from one canonical command body for
Claude, OpenCode, and the Codex `$sdd-fix-parallel` repository skill. It resolves the portable
Fixer and targeted Orchestrator contracts from `.harness/`, and its filename is
registry-owned for safe front-end cleanup. Fresh config includes
`fix_lane.max_parallel: 3` and extension-only `fix_lane.shared_paths: []`. The
parallel command requires the default `execution.builder.backend: in-session`; a
delegate backend fails before manifest/provision/claim and points to serial
`/sdd-fix`, because delegates may own PR/review timing.

### `/sdd-pr-loop` (opt-in, gated on `pr_loop.enabled`)

> **Opt-in.** A fresh install seeds `pr_loop.enabled: false` and stamps **no**
> `/sdd-pr-loop` glue at all. The installer **asks** — see
> [The third question](#the-third-question--pr_loopenabled) — so answer `2` at the prompt,
> pass `--pr-loop=true`, or set the key in `.harness/harness.config.yaml` and re-run the
> installer to turn the loop on. Only the literal `true` enables it — an absent block,
> an absent key, an empty or malformed value all mean off.

The installer generates **`/sdd-pr-loop`** for Claude/OpenCode and
**`$sdd-pr-loop`** for Codex, plus each selected host’s `pr-fixer` role:
`.claude/agents/pr-fixer.md`, `.opencode/agent/pr-fixer.md`, or
`.codex/agents/pr-fixer.toml`. Each points at the canonical
`.harness/agents/pr-fixer.md`. Codex has seven base roles, or eight while this
gate is on. Each blocking comment is handed to a fresh native PR-fixer context
through files. If the host cannot start that role, it must report the limitation
and handoff path instead of claiming an isolated fix was performed.

**Preconditions — the loop only works with all three:** the **Codex GitHub App** installed
on the target repository, an **authed `gh`**, and **`jq`** on `PATH`. The watcher's
`preflight` mode checks each one before anything is posted and fails fast with a one-line
diagnostic naming the failed check and its remedy — and a distinct exit code per remedy
bucket, never one shared code: `8` (auth/tooling — `gh` missing/unauthenticated, `jq`
missing), `9` (environment — the repo slug is unresolvable, almost always the wrong
directory), `10` (usage — the PR number doesn't resolve, or isn't `OPEN`). These are
**loop-runtime** dependencies only: `init.sh` gains no new gate, so a target with neither
`gh` nor `jq` still passes the environment gate.

Fresh config seeds:

```yaml
pr_loop:
  enabled: false                 # opt-in master gate; ONLY `true` stamps /sdd-pr-loop glue
  auto_merge: true               # merge once every gate is green and threads are Codex-only
  max_rounds: 4                  # round cap; the cap round labels the PR needs-human
  blocking_severities: "P0,P1"   # comma-separated severities that block a merge
  merge_strategy: "merge"        # merge | squash
```

**The seed forces two of these back to the shipped defaults** even though it is otherwise a
copy of the harness's own `harness.config.yaml`: `enabled` (the loop needs the Codex GitHub
App, so defaulting it on would ship a command that can only fail its preflight) and
`blocking_severities`. The harness repo raises the latter to `P0,P1,P2` for itself because
it builds **gates**, where a finding tagged P2 can still mean the gate vouching for
something it never checked, or halting all agent work on a legitimate file. That reasoning
is a property of what that repo builds — for an ordinary product repo, blocking on P2
spends review rounds on findings that never blocked anything. Raise it yourself if your
project has the same shape; nothing stops you.

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
(pristine-only in the user-owned `.agents/` tree), and
empty dirs are pruned. Flipping it back to `true` restores byte-identical glue. The round
cache lives at `.harness/.pr-loop/<pr>/round-<n>/` and is gitignored by the seeded
`.harness/.gitignore`.

## Host detection — `--agents=host` (opt-in)

Use `host` to select the supported coding-agent CLI running the installer:

```bash
./harness-install.sh --agents=host /path/to/your-project
HARNESS_AGENTS=host ./harness-install.sh /path/to/your-project
```

`host` is a resolution mode, not an agent key. It must be the whole value;
`--agents=host,codex` fails before writes. The recorded `.harness/.agents` holds
concrete keys only. Explicit `--agents=<csv>` takes precedence over
`HARNESS_AGENTS`; accepted keys are `claude`, `codex`, and `opencode`.

### Which markers are trusted

Detection uses session markers injected by a supported CLI. Ambient configuration
and credentials such as `CODEX_HOME`, `HOME`, `TERM_PROGRAM` and `*_API_KEY`
variables do not identify the host.

| Front-end | Marker(s) | Observed baseline |
|---|---|---|
| `claude` | `CLAUDECODE`, `CLAUDE_CODE_ENTRYPOINT` | Claude Code 2.1.220 |
| `codex` | `CODEX_THREAD_ID` | codex-cli 0.145.0 |
| `opencode` | `OPENCODE`, `OPENCODE_PID` | opencode 1.18.5 |

Empty markers do not count. Multiple supported hosts produce an ambiguity
warning and an undetected result. Retired-host markers are ignored. A detection
miss uses the baseline below and is normal operation.

### Declaring the host yourself — `HARNESS_HOST_AGENT`

```bash
HARNESS_HOST_AGENT=codex ./harness-install.sh --agents=host /path/to/your-project
```

A supported explicit host wins over markers. An unknown value is warned about
and ignored; explicit retired values `gemini` and `antigravity` are rejected
before target writes. The declaration feeds host resolution rather than
replacing an explicit supported CSV selection.

### What happens when the host is undetected

| Situation | Resolved set |
|---|---|
| Supported host detected with `--agents=host` | That front-end alone |
| Undetected, fresh target | Claude only |
| Undetected, version-stamped target with saved selection | Supported survivors of `.harness/.agents` |
| Undetected, version-stamped target without saved selection | `claude,opencode` |

A detected explicit-host run can narrow an existing install. With no explicit
selection, upgrades preserve supported recorded keys; retired-only recorded
selections stop for an explicit replacement. See [migration](#retiring-gemini).

### The fresh-install default

On a target with no existing install, the interactive picker pre-checks the detected supported
host, or Claude alone when undetected. Its priority order is:

```text
[x] claude
[ ] codex
[ ] opencode
[ ] antigravity
```

You can add or remove selections before confirming. Interactive upgrades start
from the supported saved `.harness/.agents` selection, irrespective of the currently detected host.
Fresh unattended installs with no override select Claude only; unattended
upgrades preserve surviving saved keys. `--agents=all` explicitly selects all
three. A legacy install without a selection file starts from `claude,opencode`.

### Seeing what it would do — `--print-agents`

With no existing install and no detected host, the fallback is Claude only.
An existing install retains its supported persisted selection.

```bash
./harness-install.sh --print-agents /path/to/your-project
# host=claude
# baseline=claude
```

This read-only preview reports the detected host and the picker’s baseline.
They can differ: inside Claude, a saved Codex installation reports `host=claude`
and `baseline=codex`; a detected `--agents=host` would select Claude, while the
picker starts with Codex. The preview is single-target only and rejects
`--umbrella`.

### Changing the selection later

Re-run the installer to add selected glue or remove deselected pristine glue, using
the picker or an explicit selection:

```bash
./harness-install.sh --agents=claude,codex /path/to/your-project
./harness-install.sh --agents=host /path/to/your-project
```

Newly selected integrations are emitted and deselected glue is reclaimed under
its ownership guards. Edited or foreign Codex units/roles and a customized
`opencode.json` survive with warnings. The shared `AGENTS.md` pointer and harness
body remain installed. The resolved selection is saved to `.harness/.agents`.

## OpenCode parallel-fix support (`/sdd-fix-parallel`)

`/sdd-fix-parallel` requires a front-end that can spawn several targeted Orchestrator
workers concurrently. OpenCode support is **not assumed** — it is verified by the
`/sdd-test-concurrency` command that the installer always adds for OpenCode.

1. Run `/sdd-test-concurrency` inside OpenCode. It spawns two trivial subagents,
   measures whether they ran in parallel, and writes the result to
   `.harness/.opencode-parallel` as either `supported` or `sequential`.
2. Re-run the installer. If the marker says `supported`, `/sdd-fix-parallel` is stamped.
3. If the marker says `sequential` (or the file is absent), the installer leaves
   `/sdd-fix-parallel` out. Use the serial `/sdd-fix` lane instead.
4. You can force the decision with `--with-opencode-parallel=true` or
   `--with-opencode-parallel=false`:

```bash
./harness-install.sh --agents=opencode --with-opencode-parallel=true /path/to/your-project
```

**In the harness source checkout** `--self` now generates the OpenCode surface too
(`opencode.json`, `.opencode/command/*.md`, and `.opencode/agent/pr-fixer.md` while the
PR-loop gate is on), including `/sdd-test-concurrency`. The source output is
machine-independent: the capability-gated `/sdd-fix-parallel` command and its
`.opencode-parallel` marker are never emitted or committed. OpenCode still discovers the
committed shared unit `.agents/skills/sdd-fix-parallel/SKILL.md`, which self-gates on
`.opencode-parallel`. When it gates, either confirm the session can spawn native
concurrent sub-agents and write `supported` to `.opencode-parallel` directly, or run the
batch sequentially with `/sdd-fix`.

## Harness feedback (`feedback:`) — on by default

**What it is.** A top-level `feedback:` block that is the one visible switch for E32: when
one of a narrow set of harness defects is detected, the harness may auto-report it as a
scrubbed GitHub issue upstream (allow-listed harness fields only, never project content).
**The report tool ships** (`tools/harness-report.sh`, **E32-F02**): it enforces the
allow-list, the versioned body marker, the duplicate search, the per-session cap, and the
redaction pass. **Reporting is live** (**E32-F03**): a short reporting rule and the
`/sdd-report` command (Codex: `$sdd-report`) call the tool when one of the four harness
defects fires — never for a project failure — at the end of a task or on an early stop. The
switch ships **on**, and the installer tells you so at the moment it becomes possible to
matter.

**Shipped defaults.** A fresh install, and an upgrade of a target that has no `feedback:`
block yet, both seed:

```yaml
feedback:
  enabled: true
  repo: github.com/araozmd/harness-sdd
  max_per_session: 3
```

**The notice.** Whenever the installer seeds this block — fresh install or upgrade — it
prints exactly one line on stdout, for that target, naming the resolved `repo`, the
literal `feedback.enabled: false`, and the config path it just seeded. A run that seeds
nothing (the block already exists) prints no notice.

**Resolution contract** (every consumer of this block, reporter included, resolves it this
way):

- `enabled` — after any trailing `# comment` is stripped, **only** the bare, unquoted,
  lower-case token `true` enables reporting. A missing block, a missing key, an empty
  value, a quoted `"true"`, `True`, or anything else all mean **off**. The default is
  fail-closed because this is a privacy switch.
- `repo` — grammar `[HOST/]OWNER/REPO`: 2 or 3 `/`-separated parts, each non-empty and
  matching `[A-Za-z0-9._-]+`. Two parts mean `OWNER/REPO` on `github.com`; an omitted HOST
  always means `github.com`. A missing or empty value resolves to the shipped default.
  Anything else — a scheme (`https://`), a leading or trailing `/`, an empty part, four or
  more parts, or any other character — is malformed and turns reporting **off**; the
  consumer never guesses a repo.
- `max_per_session` — a non-negative integer (`[0-9]+`). `0` means nothing is filed
  upstream in that session. A missing value, or any value that is not a non-negative
  integer (negatives included), resolves to `3`.

**Opting out means `enabled: false`, not deleting the block.** The documented opt-out is:

```yaml
feedback:
  enabled: false
```

A missing block is **re-seeded on** (with a fresh notice) on the next upgrade — deleting
the block is not an opt-out.

**Umbrella children.** `harness.config.yaml` is a standalone, program-read config (ADR-0004):
each child's **own** `feedback:` block governs sessions rooted in that child, with no
inheritance from the coordinator and no override from it either. The cascade seeds and
prints a notice for each target separately. The local fallback directory the reporter
writes to (`progress/feedback/`) always resolves **under the governing harness dir** —
`<child>/.harness/progress/feedback/` for a child, `.harness/progress/feedback/` for any
other installed target, and `progress/feedback/` in the harness source repo — never the
umbrella's own directory.

**Changing it later.** There is no install-time prompt or `--feedback=` flag. Edit the
value in `.harness/harness.config.yaml` (or the umbrella child's own copy) directly.

## Worker roster (`workers.roster`) — opt-in, local-only

**What it is.** With `workers.roster: true`, every install writes
`.harness/workers.json`: **which of the harness's front-end CLIs this machine can
invoke**, recorded once as versioned data. It exists so an external router — the kind of
kit that farms work out across several coding CLIs — can read one file instead of
re-probing your environment every time. **Nothing inside the harness consumes it.**

**Opt-in and inert by default.** A fresh install seeds `roster: false`, and only the
literal `true` turns it on — an absent block, an absent key, an empty value and any other
value all mean off:

```yaml
workers:
  roster: false   # true ⇒ the installer writes .harness/workers.json
```

Flip it back to `false` and re-run: the installer **removes** the file and says so, so
turning the feature off leaves nothing behind.

**The harness never executes a rostered CLI.** Presence is a `PATH` lookup — `command -v`,
used as a boolean, with its output discarded. That is also why the roster records no
version: asking a CLI its version means running it.

```json
{
  "schema": 1,
  "generated_by": "harness-install.sh",
  "capability_vocabulary": ["harness-selected", "host-detectable", "non-interactive"],
  "workers": [
    {"key": "claude", "command": "claude",
     "capabilities": ["harness-selected", "host-detectable", "non-interactive"]},
    {"key": "codex", "command": "codex",
     "capabilities": ["host-detectable", "non-interactive"]},
    {"key": "opencode", "command": "opencode",
     "capabilities": ["host-detectable", "non-interactive"]}
  ]
}
```

| field | meaning |
|---|---|
| `schema` | the format version. **`1`** here; any change to the entry shape or to the vocabulary below is a bump, so a consumer can detect a format change instead of guessing |
| `capability_vocabulary` | the **closed** set of tags, declared alongside the data. Under `schema: 1` it is exactly these three, always in full — never just the tags this machine happened to produce |
| `workers[]` | one entry per agent key whose command resolved on `PATH`, in the installer's own key order |
| `workers[].key` | the agent key — the same token `--agents` and `.harness/.agents` use |
| `workers[].command` | the supported invocation name that resolved |
| `workers[].capabilities` | a sorted subset of the vocabulary |

| tag | means | the evidence the harness already holds |
|---|---|---|
| `harness-selected` | this install selected the CLI as a harness front-end | the key is in the resolved selection |
| `host-detectable` | `--agents=host` can recognize a session this CLI launched | the key has a host-marker row |
| `non-interactive` | the CLI has a scriptable, prompt-in entrypoint | a recorded, verified entrypoint (`claude -p`, `codex exec`, `opencode run`) |

Every tag points at a fact the harness can show you. There is deliberately **no** taxonomy
of what each CLI is *good at* — that would be the harness asserting things it has not
measured, in a file it stamps as a versioned contract. An entry with an empty capability
list is a meaningful answer, not a bug: *this machine can invoke it, and the harness can
vouch for nothing further.*

Three things to know before you build on it:

- **An entry records no filesystem path.** A consumer that needs the executable's location
  must run its own `command -v` regardless — the roster is a snapshot of one install-time
  moment, and the CLI may have moved, been upgraded or been removed since. Reinstating the
  field would be a `schema` bump, not an additive tweak.
- **Selection is a capability, never a filter.** A CLI you did *not* select still gets an
  entry — telling a router about CLIs this install did not wire up is the whole point —
  carrying whatever it earned, minus `harness-selected`. The tag says *selected*, not
  *stamped*: the installer has refusal branches that leave a selected front-end's glue
  unwritten (a hand-edited `opencode.json`, an edited Codex role), and the roster has no
  ledger that would know.
- **It describes one machine.** The file is per-target, regenerated (overwritten) on every
  install, and **gitignored** — the same local-only treatment `telemetry.jsonl` gets, for
  the same reason. If the path is a symlink the installer writes nothing, removes nothing,
  and warns.

## The second question — `execution.builder.backend`

Front-end selection is not the only question the installer asks. Right after the picker
confirms, an interactive run asks **one** more, as a plain numbered prompt (it is not a row
inside the checkbox picker):

```
Which builder backend should this install use? (E20-F01)
  1) in-session   the Builder writes the code itself, in this CLI session
  2) delegate     the Builder shells out to execution.builder.delegate_cmd
  choose 1/2 [Enter keeps in-session]:
```

The answer is written to `execution.builder.backend` in
`.harness/harness.config.yaml`. The two legal values are:

| Value | Meaning |
|---|---|
| `in-session` | **Default.** The Builder agent implements the code itself, in the CLI session it is already running in. Works with any single coding agent and adds zero dependencies. |
| `delegate` | The Builder does **not** write code. It shells out to `execution.builder.delegate_cmd`, invoked as `<delegate_cmd> <feature-id> <abs-spec-path>`, which owns implementation. |

**Pressing Enter keeps whatever the target already has** — `in-session` on a fresh
install, and on a re-run the value currently in the file. The prompt cannot silently
change your setting, and an unrecognized answer keeps the current value too (the
installer reports the outcome on the next line; re-run to correct it).

### Scripted installs — `--builder-backend=` / `HARNESS_BUILDER_BACKEND`

```bash
./harness-install.sh --builder-backend=delegate /path/to/your-project
HARNESS_BUILDER_BACKEND=in-session ./harness-install.sh /path/to/your-project
```

The flag wins over the environment variable, both suppress the prompt, and an **empty**
value (`--builder-backend=`) means *no override* — exactly like `--agents=`. A value that
is neither `in-session` nor `delegate` aborts non-zero **before anything is created or
modified** in the target.

With **no TTY and no override** the installer asks nothing and leaves the value exactly as
it is, so CI and scripted upgrades behave as they always have.

### Choosing `delegate` before wiring `delegate_cmd`

Allowed, on purpose. The installer writes `delegate` and prints a warning naming
`execution.builder.delegate_cmd` and the config file to edit:

```
⚠️  builder backend is 'delegate' but execution.builder.delegate_cmd is empty — set it in …
```

It does **not** abort and does **not** silently downgrade you to `in-session` — that would
make the installer lie about what you chose. `delegate_cmd` is a free-text command the
installer does not prompt for, so refusing would mean the prompt could never turn
delegation on at all. If the command is still unset when work starts, the Builder role
stops and reports the misconfiguration rather than quietly writing code itself.

## The third question — `pr_loop.enabled`

One more, asked straight after the backend question on an interactive run:

```
Enable the Codex PR review loop on this install? (E20-F02)
  1) false   stamp no /sdd-pr-loop glue — the opt-in default
  2) true    stamp /sdd-pr-loop + the pr-fixer sub-agent
             NEEDS the Codex GitHub App on this repo plus an authed `gh`.
             Nothing is probed now; the first /sdd-pr-loop run reports it.
  choose 1/2 [Enter keeps false]:
```

The answer is written to `pr_loop.enabled` in `.harness/harness.config.yaml`, whose two
legal values are `true` and `false`:

| Value | Meaning |
|---|---|
| `false` | **Default, opt-in.** No `/sdd-pr-loop` glue is stamped anywhere — no command, no `pr-fixer` sub-agent, no global Codex prompt. |
| `true` | Emits PR-loop glue for selected front-ends and their supported fixer surfaces. Codex adds its eighth native `pr-fixer` role with fresh-context dispatch. Answering `1` later reclaims harness-owned gated glue. |

**The prompt does not change the default.** Pressing Enter keeps whatever the target
already has — `false` on a fresh install, and on a re-run the value currently in the file.
A fresh install never inherits the harness source repo's own `pr_loop.enabled`, so the only
way a fresh target ends up at `true` is an explicit `2` or `--pr-loop=true`. An
unrecognized answer keeps the current value too (the installer reports the outcome on the
next line; re-run to correct it).

**Why the question exists.** `/sdd-pr-loop` only functions on a repo with the **Codex
GitHub App** installed plus an authed `gh` (and `jq`). On any other repo the correct value
is `false`, and you are the only one who knows which repo is which.

### Scripted installs — `--pr-loop=`

```bash
./harness-install.sh --pr-loop=true  /path/to/your-project
./harness-install.sh --pr-loop=false /path/to/your-project
```

Both suppress the prompt, and an **empty** value (`--pr-loop=`) means *no override* —
exactly like `--agents=` and `--builder-backend=`. A value that is neither `true` nor
`false` aborts non-zero **before anything is created or modified** in the target.

With **no TTY and no override** the installer asks nothing and leaves the config
**byte-identical**, so CI and scripted upgrades behave as they always have.

### `HARNESS_PR_LOOP_ENABLED` is per-run, and is never persisted

There is deliberately **no** environment twin for `--pr-loop`.
`HARNESS_PR_LOOP_ENABLED` keeps exactly the meaning it has always had: one of the five
**per-run** overrides (with `HARNESS_AUTO_MERGE`, `HARNESS_MAX_ROUNDS`,
`HARNESS_BLOCKING_SEVERITIES`, `HARNESS_MERGE_STRATEGY`) that gate a single run and change
**no byte** of `harness.config.yaml`. It still wins over the config for what that run
stamps. When it disagrees with the value the installer resolved, you get one warning:

```
⚠️  HARNESS_PR_LOOP_ENABLED=true is a PER-RUN override — it gates THIS run only and was NOT persisted; …
```

To persist a value, use the prompt or `--pr-loop=`. Re-running the installer is the
supported way to change it later; there is no `/sdd-config` command, on purpose — two
configuration surfaces would be two things to diverge.

### No install-time preflight

Enabling the loop runs **no** check for the Codex GitHub App, `gh` or `jq`. The installer
is POSIX `sh` with zero dependencies and never invokes either tool — those stay
**loop-runtime** requirements (see the preconditions above), so a target with neither still
installs and still passes `init.sh`. The App can also legitimately be installed *after* the
harness, and a target may not even have a remote yet, so an install-time "missing App"
warning would routinely be wrong. The prompt states the precondition instead, and
`/sdd-pr-loop`'s own preflight fails fast — with a distinct exit code per remedy bucket
(`8` auth/tooling, `9` environment, `10` usage; see above) — naming the failed check and
its remedy at the one moment that diagnosis can be accurate.

### Changing either answer later

Applies to both follow-up questions — `execution.builder.backend` and `pr_loop.enabled`.

**Re-run the installer** — same as front-end selection, and the same reason: the installer
*is* the config UI, so there is no second surface to keep in sync. Only that one scalar is
ever rewritten; the indentation, the trailing comment on the line, and every other comment
and hand-edit in `harness.config.yaml` survive byte-for-byte. (Hand-editing the key
directly works too — the installer reads it back on the next run.)

## Upgrade

Re-run the same command after pulling a newer harness:

```bash
cd harness-sdd && git pull
./harness-install.sh --agents=claude /path/to/your-project  # use your intended selection
```

The harness body and selected front-end glue are refreshed; the pointer block is replaced in
place (never duplicated); your `product.md`, `tasks.json`, epics and progress are left
untouched. `.harness/.harness-version` records the installed version.

### Commit the upgrade — `init.sh` now checks that you did

An upgrade the installer **wrote** is not an upgrade the repo **runs** until it is
committed. Between those two moments, agents read a body no commit describes: the working
tree has the new prompts and the new config keys, the branch has the old ones, and nothing
used to notice. A cascade across five children once left 26–29 uncommitted files in each,
invisibly, for days.

Since **v0.51.0**, `init.sh` verifies that the harness-owned paths match what the branch
records, and **fails the gate** when they do not:

```
❌ init: the installed harness is not committed — 29 harness-owned path(s) differ from
   what this branch records. Agents would run on a body no commit describes.
```

It prints the drifted paths (capped at 10) and the `git status` command that lists the
rest. The fix is normally just to commit the upgrade.

**What counts as harness-owned:** the installed body under `.harness/`, excluding
project-owned config, `init.project.sh`, product/epic specs, state and progress, the
derived Planner draft `.harness/umbrella.manifest.draft.yaml` (a `/sdd-plan` output the
documented flow commits only after `/sdd-drill`, so an untracked draft must not fail the
gate), plus proven active generated glue for the selected supported front ends.
This includes managed Claude files, OpenCode files and stamped Codex roles and
skill units. `.agents/` and `.codex/agents/` are shared namespaces: unrelated
files are not claimed. Codex roles use per-file evidence under
`.harness/.model-agents/codex/`; skill units use `.harness/.codex-skills/`.

After retirement, preserved Gemini or Antigravity glue is excluded from active
drift ownership. A migration preservation warning therefore does not turn a
custom retired file into a mandatory init failure. Your unrelated role files
and siblings remain outside the installer’s ownership claims.

**When the check does not apply**, it stays quiet rather than failing:

| Situation | Behavior |
|---|---|
| No `.harness/.harness-version` (not an installed harness — e.g. the harness source itself) | silent skip |
| The project is not a git work tree | silent skip |
| `.harness/` exists but nothing **in it** is tracked | **warns**, does not fail |

That last row is about the installed **body** specifically. A repo that gitignores
`.harness/` while tracking the root glue still warns — the body is what agents execute, so
its version-control status is asked on its own rather than folded in with the glue.

**Override:** `HARNESS_SKIP_DRIFT_CHECK=1 ./init.sh` proceeds anyway and says that it did.
It is an environment variable, per invocation — deliberately not a `harness.config.yaml`
key, because a config key gets set once during a bad afternoon and silently disables the
guard forever.

The guard only ever reports. It never commits, re-installs, or writes anything.

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

### Promoting a single install to a coordinator

If `/sdd-plan` planned a multi-repo product, it wrote the Planner's draft manifest at
`<umbrella>/.harness/umbrella.manifest.draft.yaml`. Turn the existing single install at
`<umbrella>` into the coordinator with `--from-manifest <file>`:

```bash
./harness-install.sh --umbrella /path/to/umbrella-dir \
  --from-manifest /path/to/umbrella-dir/.harness/umbrella.manifest.draft.yaml
```

Promotion creates each missing child and `git init`s it (local only), runs the entry's
optional opaque `scaffold_cmd`, re-bases each draft `path:` to the umbrella root, seeds
`umbrella.manifest.yaml`, and then reuses the normal cascade. It fails closed on an
invalid draft or an unsafe child path. Preview it with `--dry-run`. The full contract,
including the key-equals-directory rule and the landing-audit gate, is in
[`UMBRELLA.md`](./UMBRELLA.md#promoting-a-single-install-to-a-coordinator).

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

### Body layout — `--thin` and `--standalone`

A child of an umbrella holds its **prose** tier (`AGENTS.md`, `agents/`, `docs/`,
`specs/_templates/`) either as a full local copy or as pointer stubs resolved from
`umbrella.root`. The **program** tier (`init.sh`, `store/`, `tools/`, the example files)
and every generated front-end glue file are always local copies. `specs/glossary.md` is
project-owned (E30-F01) and is never part of either tier: it is a real, local file in
every layout, seeded once and never stubbed. These two flags are the only way to move a
target between the two layouts — neither is ever implied, and no target's layout changes
without one of them.

| Flag | Mode | Effect |
|---|---|---|
| `--thin` | single-target **and** `--umbrella` | one-time consent to **convert** a full-copy child to the thin layout. Pristine-only and all-or-nothing: every prose-tier path must be byte-identical to the umbrella's copy, or nothing in that target converts and every differing path is named. Once a child is thin it stays thin with no flag. Without the flag, a run against a full-copy child **reports** whether it would convert and converts nothing. Inert and silent on a target with no `umbrella.root`; a recorded root that does not resolve warns, keeps the full copy, and does not fail the install. |
| `--standalone` | single-target only | the reverse: re-materialise the full prose body from **this installer's** source over a thin target's stubs, and clear that target's `umbrella.root`. Rejected with `--umbrella` and with `--thin`, before anything is written. Not a permanent opt-out — a later explicit `--thin` converts the target again. |

```bash
./harness-install.sh --umbrella /path/to/umbrella-dir --thin   # migrate every child (re-run until it converges)
./harness-install.sh --thin /path/to/child                     # migrate exactly one child
./harness-install.sh --standalone /path/to/child               # detach one child, full body restored
```

The full procedure, the refusal report and what clearing `umbrella.root` does and does not
buy are in [`UMBRELLA.md`](./UMBRELLA.md#migrating-an-existing-child---thin).

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
  builder-heavy: reasoning   # the escalation tier — see below
  reviewer: standard
  scout: cheap
  doc-critic: cheap
  # pin.opencode.standard: "anthropic/claude-sonnet-4-5"
  # pin.codex.cheap: "gpt-5-mini"
```

**Tier vocabulary: `reasoning | standard | cheap | frontier | inherit`.** A role's tier is
`models.<role>`, else `models.default`, else `inherit`. An **unrecognized** tier is a
warning on stderr, resolves as `inherit`, and never fails the install — so a config
written for a newer harness can never block an upgrade on an older installer.

**Umbrella cascade (E27-F01).** A child whose key resolves to `inherit` (or is absent)
takes the **coordinator's** `models:` value — same role → default order, and absent
child `pin.*` keys fall back to the coordinator's pins — before the built-in default. A
child's own explicit non-`inherit` value always wins. So one edit to the umbrella's
`.harness/harness.config.yaml` re-tiers (and re-arms escalation for) every child on the
next cascade run, and the install output prints one `models cascade:` line per affected
child naming each role's tier and source (`own` | `umbrella`). Single-repo installs and
the coordinator itself are untouched.

`inherit` compiles to **key omission** on every front-end. The literal string `inherit`
is never written anywhere: it is unknown on Codex and a hard error on OpenCode, while an
absent key means "use the session model" on all three supported front ends.

### `builder-heavy` — the escalation tier

There are **two** Builder role names. `builder-heavy` has the *same instruction body* as
`builder` — `agents/builder-heavy.md` is a pointer at `agents/builder.md`, not a second
prompt — and differs only in the tier it resolves to. That lets you retry a task that a
standard Builder is struggling with on a more capable model **without** paying that cost
on every easy task, which is what raising `models.builder` would do.

Escalation selects a role name whose generated definition supplies the model.
Codex and OpenCode use their native model fields; Claude uses model frontmatter.
The two Builder names keep that choice explicit across supported hosts. See
[ADR-0002](../specs/adr/0002-builder-heavy-is-a-tier-not-a-second-prompt.md).

Two things worth knowing:

- **It ships on `inherit`, like every other role — so out of the box it is *not* heavier
  than `builder`.** Give it a tier (`reasoning` is the intended one) before it does
  anything for you. Shipping a heavier default would stamp a model key into every fresh
  target, which is exactly the inertness this block promises.
- **Routing to it IS automatic — once it is armed.** `escalation.after_rejections` ships at
  `2`, so the first build after two Reviewer rejections spawns `builder-heavy` instead of
  `builder`; a spec tagged `complexity: complex` starts heavy on round 1. Set
  `after_rejections: 0` to turn both triggers off.
- **But automatic routing needs a second yes, which the installer computes for you.** While
  `builder-heavy` is on `inherit` — the shipped state described above — escalating would
  hand the build *no model key at all*, abandoning whatever `models.builder` was set to
  exactly when the build is struggling. So `harness-install.sh` asks its own resolvers what
  `builder` and `builder-heavy` resolve to — the whole resolved stamp, `model` plus, on
  Codex, `model_reasoning_effort` — on every front-end it stamps, and records the comparison
  in `.harness/.escalation-arming`. Escalation fires only while that file reads `armed`;
  otherwise the harness declines and names the front-end to fix. **Re-run the installer
  after changing a tier or a pin** — the verdict is computed at install time.
  What it does **not** check: that the **stamp** is *stronger*, or that it exists. The
  harness has no model list and invents none. See `docs/WORKFLOW.md` → "Which Builder runs".

An **upgraded** target keeps whatever `models:` block it already had, so it will not grow
a `builder-heavy:` line. Nothing breaks: an unlisted role falls through to
`models.default`, exactly like any other. Add the key yourself when you want to set it.

### What each tier stamps

| tier | claude | codex `model` | codex `model_reasoning_effort` | opencode |
|---|---|---|---|---|
| `reasoning` | `opus` | *(pin required)* | `high` | *(pin required)* |
| `standard` | `sonnet` | *(pin required)* | `medium` | *(pin required)* |
| `cheap` | `haiku` | *(pin required)* | `low` | *(pin required)* |
| `frontier` | `fable` | *(pin required)* | `xhigh` | *(pin required)* |
| `inherit` | *omitted* | *omitted* | *omitted* | *omitted* |

Claude’s built-in values are floating vendor aliases. Codex and OpenCode require
explicit pins for a concrete `model`; the installer introduces no model default.

### Codex reasoning effort — `model_reasoning_effort` (E99-F161)

Codex's own capability axis is **reasoning effort**, not model identity: your global
`~/.codex/config.toml` typically sets one `model_reasoning_effort` that then applies to
every role. So a `models.<role>` tier stamps a Codex `model_reasoning_effort` too — the
same tier that would pick a floating `claude` alias, applied to Codex's own vocabulary
(`low` / `medium` / `high` / `xhigh`) — with **no separate config key**: an unpinned or
`inherit` tier stamps neither `model` nor `model_reasoning_effort`, exactly the existing
key-omission rule.

This was chosen over a standalone axis (a `models.effort.<role>` map, or a
`pin.codex.effort.<tier>` key) because a tier is already the one dial that varies a
role's capability, and a second, independently-set dial could disagree with it — a
`reasoning`-tier role stamped with `cheap`-tier effort defeats the point of tiering at
all. Riding the existing tier also adds no new vocabulary: only Codex's own accepted
effort values are ever written.

**Escalation counts it (E99-F163).** `escalation_verdict` compares the whole resolved stamp
— `model` plus, on Codex, `model_reasoning_effort` — so a Codex operator who sets
`builder: standard` / `builder-heavy: reasoning` gets genuinely differentiated roles on disk
(`medium` vs `high` effort) **and** an `armed` verdict even when neither tier carries a
`model` pin: an effort difference alone is enough. A distinct `model` pin is needed only when
you also want distinct `model` ids, not to arm. Because the comparison is over the whole
stamp, a role that resolves to nothing on either axis (`inherit` on both, or a tier that
stamps no model and no effort) still reads `neither`/`none` as before, so the downgrade guard
is unchanged. See "Ranking is yours" under `escalation:` in `harness.config.yaml`; the check
still proves change, not strength.

Codex additionally recognizes `max` and, on exactly two models
(`gpt-6-astra`, `gpt-5.6-sol`), `ultra`. Neither is stamped by the built-in ladder above:
the harness has no model list and does not infer which model a role's pin resolves to
(see "Ranking is yours" under `escalation:` in `harness.config.yaml`), so it never
guesses whether the currently pinned model supports `ultra`.

**This value is guarded before it ever reaches a file — but not for the reason the
unknown-key hazard suggests.** Two facts, verified separately against the live CLI
(0.154.0), and not the same fact: an unrecognized **key** in an agent toml does make
Codex discard the *entire* role definition ("Ignoring malformed agent role
definition… unknown field") — but that hazard is triggered by the key name, which this
installer never varies, so no value guard can address it either way. An unrecognized
**value** for the known `model_reasoning_effort` key, by contrast, was **not** observed
to be rejected at role-load time: a deliberately bogus string loaded clean, with no
startup warning and the role kept intact. The guard exists anyway, exactly like the
OpenCode `provider/model` format check, as defence-in-depth: `codex_effort_alias` today
only ever returns a value already in the known-effort allowlist, so the guard currently
has no operator input to reject — it exists against a *future* edit to that built-in
table emitting a value Codex's schema does not accept, not against anything reachable
today.

### Pinning an exact model — `models.pin.<front-end>.<tier>`

A pin is written **verbatim** in that front-end's own vocabulary and overrides the
built-in alias for every role on that tier. It is **required** for `codex` and `opencode`,
which have no floating alias — an unpinned tier there stamps no **model**, and the
installer prints one advisory line naming the exact `pin.` key to set. It is the `model`
key that is omitted, not the role artifact: selecting Codex registers all seven
standard `.codex/agents/*.toml`, plus gated `pr-fixer`, regardless of any pin (see "Where the values land" below).

- `opencode` **must** be `provider/model`. A value without a `/` would abort your OpenCode
  runs, so it is warned about and dropped.
- `codex` **must** be a bare model id; the provider comes from your `model_provider`.
- A pin of `"inherit"` is a **tier name, not a model id**. It is warned about and dropped
  on every front-end, stamping nothing — exactly like the `inherit` tier. The literal
  string `inherit` is never written into a generated artifact.

Those are the only two value checks the installer makes; it cannot know any vendor's
model list, so every other pin value is passed through untouched.

### Where the values land

| front-end | artifact | form |
|---|---|---|
| `claude` | `.claude/agents/<role>.md` | `model:` frontmatter key |
| `codex` | `.codex/agents/<role>.toml` | optional `model = "…"` and optional `model_reasoning_effort = "…"` (role always registered, project-local) |
| `opencode` | `opencode.json` | `"model"` member in `agent.<role>` |

Selecting Codex registers the seven standard roles: `orchestrator`, `architect`,
`builder`, `builder-heavy`, `reviewer`, `scout`, and `doc-critic`, plus `pr-fixer`
only while the PR-loop gate is enabled. Each TOML has `name`, `description`, and
`developer_instructions`. An inherited role or an
unpinned Codex tier omits `model`; a concrete pin adds `model` only to the roles that
resolve to it. `model_reasoning_effort` follows the tier directly (see above) and is
omitted under the identical `inherit` rule — there is nothing to pin for it. Only
selected front-ends (`--agents`) are stamped.

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
last body the installer wrote), to a freshly generated model-free body, or to the body the
previous release generated; anything else is treated as yours, left untouched, and
reported. That third comparison is what lets a role added by a new release reach a target
installed by an older one — without it an already-installed `opencode.json` would be
misreported as edited forever. The stamp is now written on **every** run that writes
`opencode.json`, not only when a role resolves to a concrete model, so future shape changes
are provable from the stamp alone. `.harness/.model-agents/` is the same
device for active `.codex/agents/` roles: it remembers the exact bytes
last written there. Returning Codex roles to `inherit` regenerates stamp-matching TOMLs
without their old `model` keys; a foreign or edited role is preserved and diagnosed.
Deselecting Codex reclaims only roles that still match their last-written stamp.
The historical stamp directory names remain unchanged for migration.
Deselecting a front-end reclaims its
stamped artifacts through the same pristine byte-comparison every other generated file
uses — an edited file survives with a warning.

> **`models.orchestrator` does not choose your session's model.** The Orchestrator drives
> the session *you* launched, and how you launched it decides its model. This key applies
> only where the orchestrator is a spawned sub-agent (Claude) or the configured primary
> agent (OpenCode).

### OpenCode model helper

OpenCode has no floating tier alias, so you must supply a concrete `provider/model` pin.
The installer ships a helper that lists the models OpenCode sees and suggests tier
mappings:

```bash
sh .harness/tools/opencode-model-helper.sh
```

It prints a ready-to-paste snippet like:

```yaml
  pin.opencode.reasoning: "anthropic/claude-opus-4-5"
  pin.opencode.standard: "anthropic/claude-sonnet-4-5"
  pin.opencode.cheap: "anthropic/claude-haiku-4-5"
```

Add the snippet by hand under the `models:` block, or apply it automatically:

```bash
sh .harness/tools/opencode-model-helper.sh --apply
```

`--apply` appends missing `pin.opencode.*` lines to `.harness/harness.config.yaml` and
never overwrites existing values. The mapping is heuristic — review the suggestions before
applying. If a tier has no matching model, no pin is emitted for it and the role stays on
the session model (`inherit`).

## Self mode — `--self` (harness developers only)

`./harness-install.sh --self` regenerates source **Claude + Codex + OpenCode** glue by
running the same emitters against a temporary consumer install and transforming
its references to the repository root. Consumers retain `.harness/` references,
including umbrella children. Self mode takes no target path and writes no
personal/global config.

| Selection | Source output |
|---|---|
| No selector, `--agents=all`, or `--agents=claude,codex,opencode` | Claude, Codex and OpenCode |
| `--agents=claude` | Claude only |
| `--agents=codex` | Codex only |
| `--agents=opencode` | OpenCode only |
| `--agents=host` | Detected Claude, Codex or OpenCode; otherwise an error |
| Retired selectors (`gemini`, `antigravity`) | Error before writes |

CLI selection takes precedence over `HARNESS_AGENTS`. The source output includes
`.claude/agents/`, `.claude/commands/`, `.codex/agents/`, Codex skill units with
policy companions under `.agents/skills/`, `.escalation-arming`, and the generated
OpenCode glue — `opencode.json` plus `.opencode/command/*.md` and
`.opencode/agent/pr-fixer.md` while the PR-loop gate is on. `/sdd-test-concurrency` is
always emitted; the capability-gated `/sdd-fix-parallel` command and its
`.opencode-parallel` marker are never source output. The existing `.claude/.glue-manifest`
tracks every host, policies and the arming verdict, and source init checks this generated
set for drift. Repeated unchanged generation is byte-identical. On deselection or
gate-off, only previously managed pristine artifacts are reclaimed; edited leftovers are
preserved with diagnostics and excluded from the new manifest.

Claude `model:` frontmatter and valid Codex per-role `model = "…"` choices are
harvested separately and preserved. An omitted Codex model remains inherited;
Claude aliases are never translated into Codex pins. A model-only change to a
managed source Codex TOML is a supported override. Other edits, foreign files,
and symlink collisions are preserved with warnings. The seed
`harness.config.yaml` values are not changed by self-generation.

**Combined source escalation is UNARMED when any selected host cannot raise**, even if
the preserved Claude Builder/heavy choices arm Claude alone. The source seed pins no
OpenCode model, so `opencode` resolves `neither` and blocks the combined verdict; Codex
inheritance blocks it the same way. This follows the existing all-selected-host rule; it
does not erase Claude’s models. Explicit
`./harness-install.sh --self --agents=claude` retains the previous Claude-only
verdict. Configure distinct valid Codex Builder/heavy models if you want the
combined set to arm.

Codex Git operations also follow the selected sandbox and approval policy. Run from
an appropriate repository or worktree and arrange permission for required Git writes:
`workspace-write` may protect `.git`, so branch or commit operations can require explicit
permission or a test-driver-created branch. This does not require changing global Codex
settings or making the sandbox unrestricted.

### Optional Codex Builder/heavy model choices

Consumer inheritance remains the default. One optional pairing is
[GPT-5.6 Sol](https://developers.openai.com/api/docs/models/gpt-5.6-sol) for ordinary
Builder work and [GPT-6 Astra](https://developers.openai.com/api/docs/models/gpt-6-astra)
for the heavy role. OpenAI describes Sol as a model for complex professional work
and Astra as its most capable model for difficult end-to-end work. This optional
project choice leaves the harness defaults unchanged.

For an installed consumer, edit its existing `.harness/harness.config.yaml`
`models:` block and re-run the installer:

```yaml
models:
  default: inherit
  builder: standard
  builder-heavy: reasoning
  pin.codex.standard: "gpt-5.6-sol"
  pin.codex.reasoning: "gpt-6-astra"
```

Pins affect every role assigned the corresponding tier. In the **source checkout**,
edit only the model field in each generated role instead, preserving its other
keys and instructions:

```toml
# .codex/agents/builder.toml
model = "gpt-5.6-sol"
```

```toml
# .codex/agents/builder-heavy.toml
model = "gpt-6-astra"
```

Then run `./harness-install.sh --self`. These source choices survive regeneration
and do not become consumer seed defaults. Escalation still requires a distinct resolved
Builder/heavy stamp for every selected host — on Codex, a differing `model` pin or a
differing `model_reasoning_effort` (E99-F163); it does not verify model availability or
compare model quality.

## Config migration on upgrade (non-destructive)

The installer preserves an existing `.harness/harness.config.yaml` on upgrade. To get
newer additive default keys (e.g. the `umbrella.manifest`,
`verification.integration_command`, the `telemetry:` block, and the `feedback:` block
introduced after a target was first installed) into that preserved file, every upgrade
runs an **append-only
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
| harness-owned body | `.harness/{AGENTS.md,agents,docs,store,tools,specs/_templates,init.sh}` | refreshed; thin children retain prose pointers |
| generated glue | managed command/role names for selected front-ends, including `.claude/agents/` and `.claude/commands/` harness files | regenerated subject to each emitter's ownership checks; deselection conservatively reclaims owned files |
| project-owned | `.harness/{harness.config.yaml,init.project.sh,specs/product.md,specs/glossary.md,specs/epics,state/tasks.json,progress}` | preserved (config also append-migrated) |
| derived, project-owned | `.harness/umbrella.manifest.draft.yaml` (only when `specs/architecture.md` names more than one deployable) | never installer-managed; excluded from the drift guard, so an untracked draft does not fail `init.sh`; a collapse amend may remove it |
| runtime/local | `.harness/{telemetry.jsonl,workers.json,.gitignore}`, project-root `.gitignore` | gitignored; both `.gitignore`s append-seeded (never clobbered), logs/personal state never committed. `workers.json` is installer-OWNED derived data: rewritten every run while `workers.roster` is on, removed when it is off |
| merge-region | `AGENTS.md` / selected `CLAUDE.md`; legacy `GEMINI.md` cleanup | only the marked block |

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
