---
id: E20
title: "Installer: workflow toggles beyond front-end selection"
status: pending          # draft → planned → in-progress → done (pending = legacy alias of planned; rollup of its features)
owner: araozmd
---

# Epic E20 — Installer: workflow toggles beyond front-end selection

## Business brief
The installer's interactive surface answers exactly one question: *which coding-agent
front-ends should I stamp?* Every other install-shaping choice is a hand-edit of
`.harness/harness.config.yaml` after the fact — including two that materially change how
the harness behaves:

- **`execution.builder.backend`** (`harness.config.yaml:65`) — whether the Builder writes
  code in-session or delegates to an external executor. This is the single seam a heavier
  orchestrator plugs into, and it is invisible at install time.
- **`pr_loop.enabled`** (introduced by E18) — whether the harness's review workflow
  includes the Codex PR cycle at all. This one is not merely a preference: `/sdd-pr-loop`
  only functions on a repo with the Codex GitHub App installed and an authed `gh`, so on
  a repo without that setup the correct answer is *off*, and the human is the only one
  who knows.

This epic generalizes the installer's picker from "front-end selection" into a small
**workflow toggle surface**, so the choices that shape a harness install are made once,
visibly, at install time — and re-toggled the same way, since re-running the installer is
already the harness's post-install reconfiguration path.

The value is discoverability, not new capability: both keys are settable today by editing
YAML. Surfacing them converts tribal knowledge into a prompt.

## Success criteria (epic level)
- The interactive installer prompts for `execution.builder.backend` and
  `pr_loop.enabled` in addition to front-end selection, with current values pre-selected
  on a re-run.
- Defaults are unchanged for anyone who just presses Enter: `in-session`, and whatever
  E18 establishes for `pr_loop`.
- Values are written through the **existing append-only, value-preserving config
  migration** — never by rewriting `harness.config.yaml` wholesale, so a human's comments
  and unrelated hand-edits survive.
- Non-interactive runs are unaffected unless an explicit override is passed; CI keeps
  today's behavior.
- Turning `pr_loop.enabled` off leaves no `/sdd-pr-loop` glue stamped and no dangling
  instruction to run it.
- The picker degrades the same way front-end selection already does: raw-mode TUI when
  the terminal supports it, numbered fallback when it does not, override when
  non-interactive.

## Features
| id | title | status | sdd | depends_on |
|---|---|---|---|---|
| F01 | `execution.builder.backend` prompt in the installer picker | done | true | E19-F02 |
| F02 | `pr_loop.enabled` prompt in the installer picker | done | true | E20-F01 |

## Notes
- **Split into two micro-features (2026-07-28).** The two toggles are independent
  questions with independent failure modes, and a single 30+ R-id feature is what made
  E18-F01 take six Codex review rounds. F01 ships the picker's second-question
  machinery with ONE toggle on it; F02 adds the second toggle to that machinery.
- **Dependency retargeted.** The original entry depended on `E19-F01`, but after the E19
  micro-split it is `E19-F02` that owns the pre-check region this epic extends. E18-F01
  (which creates the `pr_loop` block F02 surfaces) is already merged.
- **These are not agent keys.** They are booleans/enums about *workflow*, not about which
  front-end to stamp. The Architect should decide whether they belong in the same TUI
  screen as the checkbox list or a second prompt after it — the existing `tui_select`
  (:619) is built around a homogeneous list of toggles and may not extend cleanly to a
  mixed list.
- **Override surface is an open question.** `--agents` has `HARNESS_AGENTS` as its env
  twin; whether these toggles need equivalent flags for scripted installs is the
  Architect's call, informed by whether anyone actually scripts them.
