---
id: E08
title: "Installer: selectable agent targets"
status: done             # pending → in-progress → done (rollup of its features)
owner: araozmd
---

# Epic E08 — Installer: selectable agent targets

## Business brief
`harness-install.sh` today stamps **every** supported coding-agent front-end
unconditionally — `CLAUDE.md` + `.claude/`, `GEMINI.md`, `opencode.json` (and, via
E07, an Antigravity `.agent/` tree). A user who only works in one agent still gets
all the others' glue littered into their repo, and there is no way to add or drop a
target later without hand-editing.

This epic makes agent targets **a deliberate choice**: the installer presents an
interactive selection of which agents to support, stamps only those, and — crucially
— **re-prompts on every re-run/update with the current selection pre-checked**, so a
user who first picked only Claude can later add Antigravity (or remove Gemini)
**even when `VERSION` did not change**. Selection is decoupled from the upgrade-detection
path: a re-run is always an opportunity to reconcile the target set, not only a
version bump.

It stays CI-safe: a non-interactive run honors an explicit override and otherwise
defaults to **all** agents, preserving today's unconditional-stamp behavior so no
existing automation breaks.

## Success criteria (epic level)
- A fresh install lets the human pick which agents to stamp; only the chosen targets'
  front-ends/glue are written.
- A re-run/update re-prompts with the previously-chosen set pre-checked, and applies
  adds **and** removes — independent of whether `VERSION` changed.
- Non-interactive runs honor `--agents` / `HARNESS_AGENTS`, and with neither override
  nor a TTY default to **all** agents (back-compatible with current CI).
- Antigravity (E07) participates as one selectable target rather than an always-on
  stamp; `E07-F01` depends on this feature and reworks its always-stamp accordingly.
- No canonical `agents/*.md` role file is forked; the portable core and
  `store/tasks.schema.json` are untouched.

## Features
- **E08-F01** — Interactive agent-target selection (checkbox + re-prompt on update).
  The full scope above as a single feature; the Architect may recommend decomposing
  it during specification.
