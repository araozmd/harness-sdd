# Inception role + /sdd-new intake — Technical Plan

> Translates the .spec.md intent into design. Every decision cites the R-id(s) it
> serves. Start high-level; don't over-specify internals that might be wrong.

## Stack & dependencies
- Language/framework: **none — this is prose, not runtime code.** The deliverables are
  a portable markdown role file (`agents/inception.md`) and a Claude slash-command
  markdown file (`.claude/commands/sdd-new.md`), plus two small doc edits. House style
  matches the existing roles in `agents/*.md` and the existing command in
  `.claude/commands/sdd-next.md`. (Serves: R1, R2, R16.)
- New dependencies: **none.** Validation reuses the already-present `python3` +
  `store/tasks.schema.json` toolchain that `init.sh` and `store/local.md` already use.
  (Serves: R6, R7.)
- No new structural artifact except the `progress/inbox/<feature-id>.md` brief file
  type, which already exists by example (`progress/inbox/E04-F01.md`). (Serves: R4, R5.)

## Data model  (serves: R3, R4, R5, R9)
No schema change. Inception writes only data shapes already defined by
`store/tasks.schema.json` and the existing inbox-brief convention.

| Entity | Field | Type | Notes |
|---|---|---|---|
| TaskStore feature entry | `id` | string `^E[0-9]+-F[0-9]+$` | next-sequential within epic (R10) |
| (in `state/tasks.json`) | `title` | string | from the idea |
| | `status` | enum | always `"pending"` (R12) |
| | `sdd` | boolean | Inception decides; default `true` |
| | `autonomous` | boolean | Inception decides; default `false` |
| | `depends_on` | string[] | wired during triage |
| | `spec_path` | string | `specs/epics/<epic-slug>/F<NN>-<slug>/` |
| TaskStore epic entry | `id` | string `^E[0-9]+$` | next-sequential project-wide (R10); only on "new epic" (R9) |
| | `title` / `status` / `features` | — | `status: "pending"`, `features` seeded with first F01 (R9) |
| Intent brief | frontmatter | YAML | `feature`, `seeded_by: inception`, `date` (R5) |
| `progress/inbox/<id>.md` | body sections | markdown | problem/who, success outcome, scope/boundaries, chosen options, constraints, open questions (R5) |

The brief shape is the existing `progress/inbox/E04-F01.md` (this very feature's own
brief) — Inception's role file should reference it as the canonical template. (R5.)

## API / interface  (serves: R2, R15)
The only "interface" is the slash command contract. No HTTP/runtime endpoints.

| Surface | Form | Behavior | R-id |
|---|---|---|---|
| `/sdd-new "<idea>"` | Claude slash command | takes free-text idea via `$ARGUMENTS`, runs Inception interactively | R2 |
| Inception completion report | chat output | reports new id + tasks.json entry + inbox path + "run /sdd-next next" | R15 |

## Files to change  (serves: R#)
| File | Change | R-id |
|---|---|---|
| `agents/inception.md` | **create** — portable role contract: intake loop (triage altitude → allocate id → wire deps/flags → write pending entry → re-validate → write inbox brief → report). Encode every guardrail (seeds-not-specs, never-past-pending, additive, text-only mockups ≤3, next-sequential ids). | R1, R3, R4, R5, R6, R7, R8, R9, R10, R11, R12, R13, R14, R15 |
| `.claude/commands/sdd-new.md` | **create** — thin Claude wrapper: frontmatter `description:`, "Act as **Inception** (`agents/inception.md`)", accept `$ARGUMENTS` as the idea, carry the interactive Q&A, defer the contract to the role file. Mirror `.claude/commands/sdd-next.md` style. | R2, R14, R15 |
| `AGENTS.md` | **modify** — add Inception to the role list / `agents/*.md` row so the entrypoint names the intake role. Single-line, additive. | R16 |
| `docs/WORKFLOW.md` | **modify** — add a short pre-`pending` intake step showing `/sdd-new` (raw idea → `pending` entry + inbox brief) feeding the existing state machine. Additive; do not restructure the existing diagram's states. | R16 |

A Claude sub-agent shim under `.claude/agents/inception.md` (mirroring the existing
`.claude/agents/architect.md`) MAY be added by the Builder for parity, but it is **not
required by any R-id** — the spawn path for intake is the `/sdd-new` slash command, not
the Orchestrator's Task tool. Leave it out unless trivially consistent; it is not in
the touch-list above.

## DO NOT TOUCH
- `store/tasks.schema.json` — no schema change, no new status value. (R13)
- `agents/orchestrator.md` — the routing table and loop are unchanged; intake is
  pre-`pending` and the Orchestrator already starts at `pending`. (R13)
- `agents/architect.md` — the Architect contract is unchanged; Inception hands off via
  the inbox brief the Architect already reads. (R13)
- Any `*.spec.md` / `*.plan.md` / `*.tasks.md` / `*.tests.md` under `specs/epics/**`
  other than this feature's own four files — Inception seeds, it never specs. (R11)
- `.claude/commands/sdd-next.md` — the downstream loop is unchanged. (additive scope)

## Approach notes
- **No runtime code ⇒ verification is by inspection + a sample walkthrough.** Because
  the deliverables are role/command prose, "testable" means: (a) static assertions on
  the produced files (existence, required phrases/guardrails present, the slash command
  points at the role file) — scriptable with grep/file checks; and (b) a documented
  manual `/sdd-new` walkthrough on a sample idea that must yield a schema-valid
  `pending` entry plus a well-formed inbox brief. See `inception.tests.md` for the
  exact mapping; lean on `python3 -c json.load` + schema validation for R3/R6/R7 and
  file/format assertions for the rest, in the style of `tests/test_install.sh`.
- **Re-validation is mandatory and load-bearing (R6/R7).** The role file must instruct
  Inception to run the schema check after writing `state/tasks.json` and to treat a
  validation failure as a non-success (report, do not claim a seed). This mirrors
  `set_status` in `store/local.md`.
- **Triage decision tree (R8/R9/R10).** Inception inspects `state/tasks.json`: if the
  idea extends an existing not-`done` feature → add a task-level note/dependency under
  it; else if it fits an existing epic → allocate the next `F##` in that epic; else →
  allocate the next `E##` project-wide, create `epic.md`, and seed `F01`. Ids are
  always next-sequential; never reuse a vacated id.
- **Interactivity boundary (R2/R14).** All Q&A and option presentation lives in the
  `/sdd-new` wrapper prose; the role file states the contract (what must end up on
  disk) so a non-Claude CLI can implement its own front-end against the same role.
  Options are text-only, capped at 3.
- **Versioning (process note, not a spec requirement).** Merging this feature touches
  `agents/` and the `.claude/` glue, so per `CLAUDE.md` it warrants a **MINOR** VERSION
  bump (✨) with a `CHANGELOG.md` entry and a `vX.Y.Z` tag on merge. These are listed
  as Builder/PR tasks in `inception.tasks.md`, not as acceptance criteria.
