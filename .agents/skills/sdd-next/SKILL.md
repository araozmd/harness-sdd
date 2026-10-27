---
name: sdd-next
description: Run the Orchestrator loop on the next actionable task (init → route → delegate)
---

## Invocation adapter

In Antigravity or OpenCode, invoke `/sdd-next`; in Codex, invoke `$sdd-next` and write arguments after the skill mention. In all hosts, treat all accompanying text as `$ARGUMENTS` in the workflow below. Wherever that workflow writes a portable `/sdd-<name>` reference, the Codex invocation is `$sdd-<name>` and the Antigravity or OpenCode invocation is `/sdd-<name>`.
In pi, invoke `/sdd-next` (the harness prompt template) or `/skill:sdd-next`; pi loads project prompt templates and skills only after the project is trusted (`/trust`, or `-a` on a headless run).

## Canonical workflow
Act as the **Orchestrator** (`agents/orchestrator.md`).

1. Run `./init.sh`. If it exits non-zero, STOP and report — do not work on a broken
   environment.
2. Read `harness.config.yaml` and the TaskStore (per `store/local.md`).
3. Find the next actionable feature and route it by status per `docs/WORKFLOW.md`:
   - `pending` + sdd:true → spawn **architect**, then set `spec-ready` and PAUSE for
     the human gate (unless `autonomous`). When spawning the Architect, pass the
     feature's intent brief `progress/inbox/<feature-id>.md` (when it exists) as a
     primary input alongside the spec templates, so Inception's captured intent,
     constraints, and open questions reach spec generation.
   - `spec-ready` + `autonomous:true` → human gate is skipped: set `in-progress`,
     spawn **builder** with the specs, then `in-review`. (A `spec-ready` feature
     *without* `autonomous:true` is parked at the human gate — not actionable.)
   - `in-progress` → spawn **builder** with the approved specs only, then `in-review`.
   - `in-review` → spawn **reviewer**; approve → open the PR and LEAVE it `in-review`
     (`done` is written only after the work merges — see `agents/orchestrator.md`
     “Writing `done`”), reject → back to `in-progress`.
   (In Antigravity, define role subagents dynamically with `define_subagent` using canonical `agents/<role>.md` prompts and `enable_write_tools=True`, dispatching via `invoke_subagent` to maintain role context hygiene.)
   (In pi, delegate each role in a fresh context with the `subagent` tool when the `pi-subagents` package is loaded, otherwise run `tools/pi-dispatch.sh <role> <task-file>`; if neither works, stop and report the limitation and the handoff file path.)
4. Append what happened to `progress/history.md`.

Map `$ARGUMENTS` to the selector's closed scope flags:
- no argument → `node tools/next-task.mjs --json`.
- the exact token `--mine` → `node tools/next-task.mjs --json --mine`.
- one valid positional feature id `E##-F##` → translate it to
  `node tools/next-task.mjs --json --feature E##-F##`; never forward the feature
  id as a selector positional token.
- `--wave`, optionally followed by `--max N` and/or `--epic E##` in either order → **wave
  coordinator mode** (below): the coordinator reads
  `node tools/next-task.mjs --waves --json`, forwarding `--epic E##` to it, and
  `--max N` is the coordinator's own worker cap (never a selector flag).
- anything else is invalid and selects or changes nothing.

`--wave` is a closed-scope token beside `--mine` and `E##-F##`: it cannot be combined with
either. `--max` and `--epic` are valid only after `--wave`, each at most once; `N` must match
`^[1-9][0-9]*$` and `E##` must match `^E[0-9]+$`. Any other argument shape (`--wave --mine`,
`--wave E##-F##`, `--max N` or `--epic E##` without `--wave`, `--max 0`, `--epic E36-F01`,
a repeated token) selects nothing, changes no state, and prints
`usage: /sdd-next [--mine | E##-F## | --wave [--max N] [--epic E##]]`.

Under `--wave`, act as the wave coordinator in `agents/orchestrator.md` →
"## Wave coordinator mode (/sdd-next --wave)"; that section is the contract and this
command only maps the scope. Its preflight stops before any mutation — naming the cause,
pointing to `/sdd-next <id>` and exiting non-zero — on a missing native concurrent sub-agent
capability, on an `execution.builder.backend` other than `in-session` (`delegate` or any
unknown value), or on a non-empty `umbrella.manifest`.

Under `--mine`, use **scoped selection**: consider only features whose **effective owner**
  (feature `owner` else parent epic `owner`) equals the identity resolved from
  `workflow.identity` in `harness.config.yaml` (`@me`/`self` → authed `gh` user via
  `gh api user`; else literal). This is **owned-only** — it never claims unassigned work
  and never writes an `owner`; if the identity is unresolved or no owned actionable
  feature exists, it **fails closed** (selects nothing, reports, changes no state) and
  does **not** widen to board-wide selection. Bare `/sdd-next` (no `--mine`) is unchanged
  board-wide selection and ignores `owner`. The scoping semantics live in the
  **Orchestrator contract** (`agents/orchestrator.md` → "Ownership & scoped selection");
  this command only maps the scope.
