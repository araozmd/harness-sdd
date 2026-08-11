---
feature: E17-F04
agent: scout
date: 2026-08-11
---
# E17-F04 recon — what the installer actually knows before the spec was written

## The brief's premise is half wrong — say so in the spec

> "The installer already probes the environment to pick front-ends."

It does not probe for **invocable CLIs**. `grep -n "command -v" harness-install.sh` returns
four hits and **none of them is a front-end CLI**: `stty` (TTY picker), `node` (inside a
commented example), and `git` twice. There is no `command -v claude|codex|opencode|agy|gemini`
anywhere in the installer.

What the installer actually has is two different things:

1. **`detect_host` + `HOST_MARKERS`** (harness-install.sh:880–960) — detects the ONE front-end
   the installer session is *running inside*, from **session env markers only**
   (`CLAUDECODE`, `CODEX_THREAD_ID`, `OPENCODE`/`OPENCODE_PID`,
   `ANTIGRAVITY_AGENT`/`ANTIGRAVITY_CONVERSATION_ID`; `gemini` has **no row** and is
   undetectable). This answers "who launched me", never "what is installed".
2. **The picker** — a human toggles which front-ends to stamp. `AGENT_KEYS="claude gemini
   opencode antigravity codex"`. Selection is *intent*, not presence.

**Consequence for the spec:** roster presence-detection is NEW code, not a reuse of existing
probing. It is also a **different evidence class** from `HOST_MARKERS`, and the distinction is
load-bearing: R6 forbids ambient env vars as host evidence precisely because "a variable a
human exports in a shell profile proves they use that tool *somewhere*; it never proves THIS
installer run was launched from it." For a roster the question IS "can this machine invoke it",
so `command -v` is exactly the right evidence — the thing R6 rules out for host detection is
the thing the roster wants. Say this explicitly or a reviewer will read the new probe as an R6
violation.

## Precedents the three open questions should be answered against

- **Where it lives.** `telemetry.jsonl` is the closest analogue: machine-written, local-only,
  resolved under `HARNESS_DIR`, and seeded into `.harness/.gitignore` by the installer
  (harness-install.sh:2483–2568, `_ignores='telemetry.jsonl…'`). The roster describes *this
  machine*, so the same treatment (`.harness/workers.json`, gitignored) is the defensible
  default — and the brief's constraint already gestures at it.
- **Absent configuration reproduces today's behaviour.** Same shape as `.gemini/agents/` /
  `.codex/agents/`: only created when something asks. So the roster needs an opt-in key.
- **Re-run on upgrade.** The harness already has a vocabulary for this: **pristine-only
  reclaim** (regenerate only what the installer itself wrote, byte-identical; never clobber a
  human edit). Whatever the spec decides, it should state the ownership rule in those terms.

## Boundaries to keep loud

- **The harness never executes a rostered CLI** — `command -v` is a PATH lookup, not an
  execution, which is what keeps presence-detection inside the epic's boundary. A version
  probe would mean *running* the CLI (`--version`), which the brief explicitly rules out
  ("do not quietly start") — and that boundary is the reason `agy >= 1.1.5` is documented
  rather than checked in `harness.config.yaml`.
- `schema: 1` from the first write.
- Installed body ⇒ **MINOR** VERSION bump + CHANGELOG.
- Budget: `change_size.max_requirements: 12`.

## Central design question, unresolved by the drill

The **capability vocabulary**. Free-form tags are unmatchable; a closed set needs extending per
CLI feature. Note the harness already carries one closed vocabulary in this space that the
spec can lean on or deliberately diverge from: the model tiers / role names in the
`models:` block and `escalation_verdict`. Worth at least citing.
