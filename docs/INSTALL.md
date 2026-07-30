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
├── .agents/{rules,skills}/           # Antigravity glue → resolves to .harness/ (regenerated each run)
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
> `/sdd-pr-loop` glue at all. The installer **asks** — see
> [The third question](#the-third-question--pr_loopenabled) — so answer `2` at the prompt,
> pass `--pr-loop=true`, or set the key in `.harness/harness.config.yaml` and re-run the
> installer to turn the loop on. Only the literal `true` enables it — an absent block,
> an absent key, an empty or malformed value all mean off.

The installer also generates **`/sdd-pr-loop`** — the Codex review loop — from one
byte-identical body into `.claude/commands/`, `.opencode/command/`,
`.agents/skills/sdd-pr-loop/SKILL.md` (Antigravity, with an injected `name:` line) and
the GLOBAL `${CODEX_HOME:-~/.codex}/prompts/`, plus a `pr-fixer` sub-agent for Claude
(`.claude/agents/pr-fixer.md`), OpenCode (`.opencode/agent/pr-fixer.md`) and Antigravity
(`.agents/skills/pr-fixer/SKILL.md`). All of it points at the canonical
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

## Host detection — `--agents=host` (opt-in)

If you work in exactly one coding-agent CLI, you can ask the installer to stamp *that*
front-end's glue and nothing else, without naming it:

```bash
./harness-install.sh --agents=host /path/to/your-project
HARNESS_AGENTS=host ./harness-install.sh /path/to/your-project
```

`host` is a **resolution mode, not a sixth agent key**. It never appears in the toggle
list, it is never written to `.harness/.agents` (that file holds concrete keys only), and
it must be the **entire** value — `--agents=host,gemini` is rejected with a non-zero exit
and changes nothing.

Nothing about a **scripted** install that does not pass `host` changes: a no-override
non-interactive run still stamps every front-end and an explicit `--agents=<csv>` still
wins. The **interactive first install** now starts from the detected host — see
[The fresh-install default](#the-fresh-install-default) below.

### Which markers are trusted

Detection reads **session markers** only — variables a CLI *injects into the environment
of the processes it launches*. It deliberately ignores ambient configuration and
credentials: `CODEX_HOME`, `HOME`, `TERM_PROGRAM` and anything ending `_API_KEY`
(`GEMINI_API_KEY`, `OPENCODE_API_KEY`, `ANTHROPIC_API_KEY`) are forbidden by rule. Those
prove you *use* a tool somewhere; they never prove this install was launched from it.

| Front-end | Marker(s) | Verified on |
|---|---|---|
| `claude` | `CLAUDECODE`, `CLAUDE_CODE_ENTRYPOINT` | Claude Code 2.1.220 |
| `codex` | `CODEX_THREAD_ID` | codex-cli 0.145.0 (`codex exec`, sandboxed and not) |
| `opencode` | `OPENCODE`, `OPENCODE_PID` | opencode 1.18.5 (`opencode run`) |
| `antigravity` | `ANTIGRAVITY_AGENT`, `ANTIGRAVITY_CONVERSATION_ID` | agy 1.1.8 (`agy -p`) |
| `gemini` | *(none — undetectable)* | no marker verified |

Every row above was observed empirically in the delta between a plain login shell and a
shell the CLI itself spawned. A front-end with no verified marker carries **no row** and
is simply undetectable — that is an accepted outcome, not a bug, and it degrades to the
fallback below. **A miss is normal operation and never fails the install.**

Two more rules keep detection honest:

- A marker set to the **empty string** does not count as present.
- If markers for **two or more** front-ends are present at once — which is exactly what
  nesting looks like, one CLI shelling out to another — the host is **undetected**, with a
  diagnostic on stderr naming the candidates. There is no way to tell inner from outer
  from the environment, so the installer refuses to guess rather than picking a winner.

### Declaring the host yourself — `HARNESS_HOST_AGENT`

If your front-end is undetectable (or you simply prefer to be explicit), declare it once,
e.g. in your shell profile:

```bash
export HARNESS_HOST_AGENT=gemini
```

It takes exactly one known agent key and wins over the marker table. Any other value — an
unknown token, several tokens, or the literal `host` — prints one warning naming the value
and is then ignored; it never aborts the install. On its own it changes nothing: it only
feeds `host` resolution, so a run that never passes `host` is unaffected.

### What happens when the host is undetected — and why the two cases differ

| Situation | Resolved set |
|---|---|
| Detected | that front-end alone |
| Undetected, **no existing install** in the target | **ALL** front-ends |
| Undetected, target **already carries an install** | its **persisted `.harness/.agents`** set (ALL if a pre-E08 install persisted none) |

The asymmetry is deliberate. On a target with no existing install there is nothing to
preserve, so `host` falls back to exactly today's no-override behavior — it can never
stamp *less* than a plain install would. On a target that already carries an install
there *is* something to preserve: re-stamping four front-ends onto a claude-only repo
because detection happened to miss is a user-visible regression. So the rule is
*detected ⇒ narrow to the one key you asked for; undetected ⇒ never change the shape of
the install*. Either way the run prints one line saying which it did.

### The fresh-install default

You do not have to pass `host` on a **first, interactive install**. When you run the
installer from a terminal inside a CLI it can detect, the picker opens with **that
front-end pre-checked and the others unchecked**:

```
[x] claude
[ ] gemini
[ ] opencode
[ ] antigravity
[ ] codex
```

It is a **pre-check, not a restriction**: the list is already on screen, so spacebar adds
any other front-end before you confirm. Confirming as-is stamps the detected front-end's
glue (plus the always-written `AGENTS.md`) and nothing else.

Exactly three cases, and only the first is new:

| Target | Interactive pre-check |
|---|---|
| **No existing install**, host detected | **that front-end alone** |
| **No existing install**, host undetected | **all** front-ends (unchanged) |
| **Existing install** (any `.harness/.harness-version`) | its persisted `.harness/.agents` selection — **all** front-ends if it predates that file |

Three limits are deliberate:

- **An upgrade is never narrowed by detection.** "Existing install" means the target
  carries `.harness/.harness-version`. A pre-E08 install has every front-end stamped and
  no persisted selection, so it pre-checks everything: pressing Enter on an upgrade can
  never delete glue you are using.
- **Undetected still means everything.** A miss is normal operation, so a front-end with
  no verified marker keeps the historical behavior exactly.
- **Nothing changes without a TTY.** A piped or CI run with no override still stamps every
  front-end (pass `--agents=host` or `--agents=<csv>` to narrow a scripted install) — a
  best-effort guess is only acceptable where a human can correct it before it applies.

The pre-check is the detected front-end **alone**, never unioned with `claude`: a Gemini
CLI or OpenCode user should not have to delete `CLAUDE.md` they never asked for.

### Seeing what it would do — `--print-agents`

```bash
./harness-install.sh --print-agents /path/to/your-project
host=claude
baseline=claude
```

Two lines on stdout, exit 0, **nothing written anywhere**. `host=` is the detected key
(empty when undetected) and `baseline=` is the set that would be **pre-checked** for that
target — the same helper the picker seeds from, so the preview cannot disagree with what
the picker will offer you. On an undetected fresh target it prints all five; on an
installed target it prints that target's persisted selection. It is single-target only:
combined with `--umbrella` it exits non-zero with a usage message.

`baseline=` answers "what will the picker check?", which is the same set an **undetected**
`--agents=host` run falls back to — but on an *existing* install it is not what a
**detected** `--agents=host` run would select. Reading a `gemini` install from inside
Claude Code, `host=claude` and `baseline=gemini`: the picker would offer `gemini`, while
`--agents=host` would narrow the install to `claude`. The two lines are separate answers on
purpose.

### Changing the selection later

**Re-running the installer is the supported way to change which front-ends are stamped.**
There is no separate reconfiguration command — the installer *is* the config UI:

```bash
cd harness-sdd            # your harness checkout
./harness-install.sh /path/to/your-project
```

Run interactively, it re-opens the picker **pre-checked from the project's saved
`.harness/.agents`** and applies the diff both ways:

- **Added** front-ends get their glue stamped on the spot.
- **Removed** (deselected) front-ends have their harness-owned, regenerated glue
  **deleted**, with a warning naming each file. The shared `AGENTS.md` entrypoint and the
  `.harness/` body are never touched, and hand-edited files (e.g. an `opencode.json` you
  changed) are left in place with a warning instead of being destroyed.

The same thing works non-interactively when you already know the answer — the override
always wins, and it is the form to use in a script:

```bash
./harness-install.sh --agents=claude,gemini /path/to/your-project   # exactly these two
./harness-install.sh --agents=host /path/to/your-project            # just this session's CLI
```

Either way the resolved set is persisted back to `.harness/.agents`, so the next re-run
starts from what you chose.

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
| `true` | `/sdd-pr-loop` and the `pr-fixer` sub-agent are stamped into every selected front-end. Answering `1` on a later re-run **reclaims** all of it in that same run. |

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
`/sdd-pr-loop`'s own preflight fails fast (exit `5`) naming the failed check and its
remedy at the one moment that diagnosis can be accurate.

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
| `antigravity` | `.agents/skills/<role>/SKILL.md` | `model:` frontmatter key |
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
