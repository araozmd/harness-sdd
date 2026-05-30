---
id: E00
title: Harness installer
status: in-progress
owner: araozmd
---

# Epic E00 — Harness installer

## Business brief
The harness is only useful if it can be dropped into *other* repos without manual
surgery. This epic delivers a deterministic, idempotent installer that copies the
harness body into a target's `.harness/` directory, merges pointer blocks into any
pre-existing `CLAUDE.md` / `AGENTS.md` / `GEMINI.md`, and seeds a runnable project
workspace — leaving the intelligent project-specific adaptation to a first-run
bootstrap through the harness itself. This makes the harness portable and
upgradable, which is the whole "the harness is the stable chassis" thesis.

## Success criteria (epic level)
- A single command installs the harness into any repo without clobbering existing files.
- Re-running the command upgrades the harness body without touching project-authored content.
- The installed harness is immediately runnable (`/sdd-next` works out of the box).

## Features
| id | title | status | sdd | depends_on |
|---|---|---|---|---|
| F01 | Installer script | in-review | true | — |

## Notes
- Layout decision: harness body lives in `.harness/` (namespaced, zero collisions);
  product/source code stays at the repo root. See `docs/INSTALL.md`.
- Distribution: idempotent copy + version stamp (`.harness/.harness-version`), not a
  git submodule — so project-owned files (`product.md`, `tasks.json`) can live inside
  `.harness/` and still survive upgrades.
- AI-driven "adopt this repo" is the documented fallback, not the default path,
  because it is non-reproducible and unupgradable.
