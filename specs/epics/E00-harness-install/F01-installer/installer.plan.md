# Installer script — Technical Plan

> Translates installer.spec.md into design. Each decision cites the R-id(s) it serves.

## Stack & dependencies
- Language: POSIX `sh` (no bash-isms in the installer itself). Matches `init.sh` ethos.
- New dependencies: none (`cp`, `sed`, `awk`, `grep`, `mkdir`, `cat` only).

## Layout decision (serves: R1, R5)
Two physical zones in the target, with different overwrite policies:

| Zone | Location | Upgrade policy |
|---|---|---|
| Harness body | `<target>/.harness/{AGENTS.md,agents,docs,store,specs/_templates,init.sh,config}` | overwrite |
| Project content | `<target>/.harness/{specs/product.md,specs/epics,state/tasks.json,progress}` | seed once, never touch |
| Claude glue | `<target>/.claude/{agents,commands}` | regenerate |
| Entrypoints | `<target>/{CLAUDE.md,AGENTS.md,GEMINI.md}` | replace marked block only |

Putting the whole body under `.harness/` keeps it self-contained, so the copied
files need **no path rewriting** — their existing repo-root-relative paths resolve
correctly when the harness root is `.harness/`.

## Key mechanisms
- **Self-locating `init.sh`** (serves: R10) — `init.sh` cd's to its own script dir on
  startup, so `<target>/.harness/init.sh` works when called from the target root.
- **Idempotent pointer block** (serves: R3, R4) — `awk` strips any existing
  `<!-- harness:begin -->..<!-- harness:end -->` range, then the fresh block is
  appended. Content outside the markers is untouched.
- **Project-file guard** (serves: R5, R6) — each project file is written only behind
  an `if [ ! -f ... ]` guard, so upgrades skip them.
- **Config reset** (serves: R8) — after copying, `sed` blanks the three
  `*_command:` values (the source repo points `test_command` at its own tests).
- **Version stamp** (serves: R2) — `VERSION` file read at the source; written to
  `.harness/.harness-version`; presence of that file is also the install-vs-upgrade signal.
- **Generated glue** (serves: R7) — `.claude/` shims are emitted as heredocs that
  point at `.harness/agents/*` and tell the agent to resolve relative paths against
  `.harness/`. The canonical role bodies are copied verbatim and never rewritten.

## Files to change  (serves: R#)
| File | Change | R-id |
|---|---|---|
| `harness-install.sh` | create — the installer | R1–R9 |
| `VERSION` | create — single source of the version string | R2 |
| `init.sh` | modify — self-locate (cd to script dir) | R10 |
| `harness.config.yaml` | modify — point `test_command` at the install tests | R8 (source side) |
| `tests/test_install.sh` | create — executable test contract | all |
| `docs/INSTALL.md` | create — usage + the bootstrap story | — |

## DO NOT TOUCH
- `agents/*.md`, `docs/*.md`, `store/*.md` — copied verbatim; rewriting them would
  fork the canonical role definitions.

## Approach notes
- `set -eu`; every `[ cond ] && action` guard is written as `if/then/fi` so a false
  test does not abort under `-e`.
- Allowlist copy (not copy-all-then-prune) so source-only files (`.git`, `.mco-cache`,
  the installer, demo epics) never leak into a target.
- AI-adopt remains a documented fallback in `docs/INSTALL.md`, not an installer path.
