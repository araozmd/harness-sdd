# Epic lifecycle: draft/planned states + next() gating — Technical Plan

> Translates the .spec.md intent into design. Every decision cites the R-id(s) it
> serves. This feature is schema + prose + one warn-only shell/python check — there
> is no application code.

## Stack & dependencies
- Language: JSON Schema draft-07 (`store/tasks.schema.json`), POSIX sh + embedded
  python3 (`init.sh`, tests), markdown prose (role files, docs, template).
- New dependencies: **none** (the zero-dependency pillar holds; `jsonschema` stays
  optional, exactly as today).

## Data model  (serves: R1, R2, R3)
| Entity | Field | Type | Notes |
|---|---|---|---|
| epic | `status` | enum | becomes `["draft", "planned", "pending", "in-progress", "done"]` — purely additive; `pending` retained as legacy alias of `planned` (D1) |
| feature | `status` | enum | **unchanged** (`pending`, `spec-ready`, `in-progress`, `in-review`, `done`) |
| slice | `status` | enum | **unchanged** (feature set + `failed`) |

No new fields, no new required keys, no layout change ⇒ existing consumer
`tasks.json` files validate as-is (R3).

## Interface — the `next()` contract  (serves: R5, R6, R7, R8)
`next()` is prose executed by the Orchestrator, defined in `store/local.md` and
enforced by `agents/orchestrator.md`. New rule, stated in both places:

> **Epic gate:** a feature is only eligible for `next()` if its parent epic's
> status is **not `draft`**. Features of `pending`, `planned`, `in-progress`, or
> `done` epics are evaluated by the existing per-feature rules unchanged.
> `autonomous: true` does **not** override the epic gate (it skips the human
> approval gate only).

This is deliberately a *filter added in front of* the existing actionability rules,
not a rewrite of them — `planned` ≡ `pending` for selection (R6, R11).

## Files to change  (serves: all R-ids)
| File | Change | R-id |
|---|---|---|
| `store/tasks.schema.json` | modify: epic `status` enum → add `"draft"`, `"planned"`; add a `$comment` naming the lifecycle and the `pending`≡`planned` alias | R1, R2, R3 |
| `init.sh` | modify: (a) fallback validator `EPIC_STATUS` set gains `draft`, `planned`; (b) add warn-only draft-invariant check (see Approach notes) that runs on **both** validation paths and never fails the gate | R4, R12 |
| `agents/orchestrator.md` | modify: step 3 ("Read state") — add the epic gate sentence; one-line note near the routing table that `draft`-epic features are skipped entirely | R5, R6, R8 |
| `store/local.md` | modify: `next()` bullet — add the epic gate; add a short "Epic lifecycle" note (`draft → planned → in-progress → done`, `pending` legacy alias, gating-equivalent to `planned`) | R5, R6, R7, R11 |
| `docs/WORKFLOW.md` | modify: add a short "Epic lifecycle" section (above or beside the feature state machine) documenting the canonical chain + legacy alias + the draft gate | R9 |
| `specs/_templates/epic.md` | modify: frontmatter status comment → `# draft → planned → in-progress → done (pending = legacy alias of planned)` | R10 |
| `store/board-mirror.md` | modify: one short note — epic statuses never map to board columns; `draft`/`planned` need no `status_map` entries | R13 |
| `tests/test_epic_lifecycle.sh` | create: static + fixture test suite (see `.tests.md`) | R1–R14 |
| `harness.config.yaml` | modify: append `&& sh tests/test_epic_lifecycle.sh` to `verification.test_command` (and extend the trailing comment) | R1–R14 (wiring) |
| `VERSION` | modify: one MINOR bump (e.g. `0.13.0` → `0.14.0`; use whatever the current value is at merge time + MINOR) | R14 |
| `CHANGELOG.md` | modify: new `## [<new version>]` entry describing `draft`/`planned` + the `next()` gate + the warn-only init check | R14 |

## DO NOT TOUCH
- `agents/inception.md` — intake keeps seeding `pending` epics (D1 / out of scope).
- `.claude/` glue (`.claude/agents/`, `.claude/commands/`) — gating must live in
  the portable role files, not here (R8); no edit is needed or allowed.
- `tools/sync-board.mjs` — D3: no provider work; the mirror already ignores epic
  status for columns.
- `harness-install.sh` — no layout change; the installer copies the edited body
  as-is.
- Feature/slice status enums and the slices `allOf` cross-field rule in
  `store/tasks.schema.json` — explicitly unchanged (R2).
- `state/tasks.json` statuses — the Orchestrator owns status transitions; the
  Builder does not flip any epic/feature status as part of this feature.
- Existing test suites (`tests/test_*.sh`) — additive only; do not edit them.

## Approach notes
- **Schema edit is one line plus a comment.** Keep draft-07; keep enum order
  readable (`draft`, `planned` first or appended — Builder's choice; tests assert
  membership, not order).
- **init.sh warn placement (R12).** The existing python block `sys.exit()`s inside
  the `jsonschema` branch, so a warn appended after the fallback would never run
  when `jsonschema` is installed. Run the draft-invariant scan **before** the
  branch (right after `json.load`, on the raw `data`), printing to stderr with the
  existing `⚠️` convention and **never** adding to `errors`. Keep it a few lines:
  for each epic with `status == "draft"`, warn for any feature whose
  `status != "pending"`. Also update the fallback `EPIC_STATUS` set (R4). Mirror
  the same parity in the inline fallback used by tests if the Builder reuses it.
- **Prose edits are surgical.** One or two sentences each in
  `agents/orchestrator.md` step 3 and `store/local.md` `next()`; do not restructure
  either file. Use the exact words "draft" and "not actionable"/"never selects" so
  the grep-based tests bind to normative text, mirroring `test_inception.sh` style.
- **Docs wording for D1:** call `pending` a "legacy alias of `planned`" — that
  exact phrase (or "legacy alias") in `docs/WORKFLOW.md` and `store/local.md` keeps
  the tests simple and the stance unambiguous.
- **Tests are static + fixture-based** (house style: POSIX sh, grep, python3
  here-docs; sandbox copy for the init.sh behavioral check). They must read
  `VERSION` dynamically (never hard-code it) and never `git diff` against `main`.
- **Sequencing:** schema → init.sh → prose/docs → tests → config wiring → VERSION +
  CHANGELOG last (so the CHANGELOG heading matches the final VERSION).
