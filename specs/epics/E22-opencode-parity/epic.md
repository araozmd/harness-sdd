---
id: E22
title: "OpenCode parity: parallel-fix opt-in & model tier pins"
status: done          # draft → planned → in-progress → done (pending = legacy alias of planned; rollup of its features)
---

# Epic E22 — OpenCode parity: parallel-fix opt-in & model tier pins

> **Retrospective record.** This epic is reconstructed from the work that actually
> shipped, not written ahead of it. `E22-F01` landed in merged PR #85 (commit
> `3faa24c`, 2026-07-29, VERSION 0.47.0) while the board carried no `E22` entry at
> all, so `state/tasks.json` under-reported what was installed for four days. The
> gap was found by the `/sdd-next` audit on 2026-08-02 and backfilled then. The
> feature is recorded `sdd: false` because that is how it was built — through the
> quick-fix lane, with no `.spec`/`.plan`/`.tasks`/`.tests` set. Nothing here is a
> reconstructed specification; see `F01-parallel-optin-model-helper/NOTES.md`.

## Problem

OpenCode is a selectable front-end, but two parts of the harness assumed a
capability it does not uniformly have.

1. **`/sdd-fix-parallel` was installed unconditionally.** The lane runs several
   isolated fix workers concurrently. On an OpenCode build without working
   concurrent sub-sessions that produces a command which appears installed and
   then misbehaves — the worst of the two failure modes, because the operator has
   no signal until a batch is already in flight.
2. **Model routing had no usable path on OpenCode.** `models.pin.opencode.<tier>`
   must be a concrete `provider/model` pair, since OpenCode has no floating tier
   alias — but nothing in the harness could tell you which pairs your install
   actually offers, so the pin was a value you had to already know.

## Success criteria

- `/sdd-fix-parallel` is **opt-in** for OpenCode: skipped unless a probe marks the
  install as supporting concurrency, or the operator overrides explicitly. Every
  other front-end is unaffected.
- The operator can discover valid `provider/model` values for their own OpenCode
  install rather than guessing at a pin.
- No change to any other front-end's generated glue.

## Features

| id | title | status | sdd | autonomous | depends_on |
|---|---|---|---|---|---|
| E22-F01 | OpenCode `/sdd-fix-parallel` opt-in + model tier helper | done | false | true | — |

## What shipped (PR #85, VERSION 0.47.0)

- **`/sdd-test-concurrency` probe** installed for OpenCode; it writes the
  `.harness/.opencode-parallel` marker recording the result.
- **`/sdd-fix-parallel` is skipped for OpenCode** unless that marker says the
  install supports it, or `--with-opencode-parallel=true` overrides.
- **`tools/opencode-model-helper.sh`** lists the models an OpenCode install
  exposes and suggests tier pins, so `models.pin.opencode.<tier>` becomes a value
  you can look up instead of guess.
- **A `set -e` regression fixed** in `remove_owned` on macOS `/bin/sh`, where
  `rmdir` left non-harness files behind and aborted the run.
- `docs/INSTALL.md`, `README.md` and the manifest wiring updated to match.
