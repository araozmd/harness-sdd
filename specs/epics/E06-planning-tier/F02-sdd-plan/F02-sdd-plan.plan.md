# /sdd-plan inception skill (vision + architecture + draft epics) — Technical Plan

> Translates the .spec.md intent into design. Every decision cites the R-id(s) it
> serves. This feature ships **prose + templates + docs + one test suite** — there is
> no application code. The "skill" is a portable role file plus a Claude slash-command
> wrapper, mirroring exactly how Inception (E04-F01) is built.

## Stack & dependencies
- Markdown prose: a new portable role file (`agents/planner.md`), a Claude command
  (`.claude/commands/sdd-plan.md`), three new templates under `specs/_templates/`, and
  two doc edits (`docs/WORKFLOW.md`, `README.md`).
- Verification: POSIX sh + grep + python3 here-docs (`tests/test_sdd_plan.sh`), wired
  into `verification.test_command`. One sandboxed seed→validate fixture exercises the
  `features: []` draft-epic shape against the live schema.
- New dependencies: **none** (zero-dependency pillar holds; `jsonschema` stays
  optional, exactly as today).

## Data model  (serves: R11, R13)
No schema change. F02 only *uses* the F01-extended schema. The canonical seeded-epic
shape is:

| Entity | Field | Value | Notes |
|---|---|---|---|
| epic | `id` | `E##` | next-sequential block, strictly above max existing (D5/R11) |
| epic | `title` | string | from the idea |
| epic | `status` | `"draft"` | always — F01 enum value, gated by `next()` (R11, R15, R16) |
| epic | `features` | `[]` | empty array — schema-valid (`features` required, no `minItems`) (R11) |

`features: []` validates against `store/tasks.schema.json` as-is — confirmed: the
`features` array has no `minItems`. **No schema edit is permitted by this feature.**

## Artifacts produced by a `/sdd-plan` run  (serves: R7, R8, R9, R12)
> These are written by the *running skill*, not by the Builder. The Builder ships the
> templates + the contract that mandates them; the fixtures below assert the shapes are
> valid, not that a session ran.

| Path | Produced by skill | From template | R-id |
|---|---|---|---|
| `specs/vision.md` | greenfield run | `specs/_templates/vision.md` | R7 |
| `specs/architecture.md` | greenfield run | `specs/_templates/architecture.md` | R8 |
| `specs/adr/NNNN-<title>.md` | per recorded decision | `specs/_templates/adr.md` | R9 |
| `state/tasks.json` rows | per seeded epic | — (`status: draft`, `features: []`) | R11, R13 |
| `specs/epics/<id>-<slug>/epic.md` | per seeded epic | `specs/_templates/epic.md` (existing) | R12 |

## Files to change  (serves: R#)
| File | Change | R-id |
|---|---|---|
| `agents/planner.md` | **create**: portable Planner role contract — producer of vision/architecture/ADRs + `draft` epics; Q&A front-end (≤3 text-only options); the seeds-never-specs + never-past-draft guardrails; reuse of F01 `draft` gate; ADR location/numbering (D4); id-block allocation (D5); re-run behavior (D2); `vision.md` complements `product.md` (D3); depth boundary vs F03 (D6); portable for any AGENTS.md CLI | R1, R3, R9, R10, R11, R12, R13, R14, R15, R16, R17, R18, R20 |
| `.claude/commands/sdd-plan.md` | **create**: slash-command wrapper that acts as Planner, points at `agents/planner.md`, reads `$ARGUMENTS`, runs `./init.sh` first, carries the ≤3 text-only-options rule, and reports without spawning the Architect / advancing status | R2, R3 |
| `specs/_templates/vision.md` | **create**: vision template (problem, users, outcomes, non-goals; note it complements `product.md`/`glossary.md`) | R4, R18 |
| `specs/_templates/architecture.md` | **create**: architecture template (system shape, stable upfront decisions, ADR index referencing `ADR-NNNN` ids) | R5 |
| `specs/_templates/adr.md` | **create**: one-decision ADR template (context / decision / consequences) | R6 |
| `docs/WORKFLOW.md` | **modify**: add a short "Whole-project inception (`/sdd-plan`)" note placing it upstream of `/sdd-drill` (F03) and the `/sdd-next` loop; producer-only, never past `draft` | R21 |
| `README.md` | **modify**: one-line `/sdd-plan` description beside `/sdd-new` / `/sdd-next` | R22 |
| `tests/test_sdd_plan.sh` | **create**: static + fixture suite per `.tests.md` (grep contract assertions + a python seed→validate fixture + an `./init.sh` exit-0 run) | R1–R23 |
| `harness.config.yaml` | **modify**: append `&& sh tests/test_sdd_plan.sh` to `verification.test_command` and extend its trailing comment | R1–R23 (wiring) |
| `VERSION` | **modify**: one MINOR bump (current value + MINOR — read at build time, do not hard-code) | R23 |
| `CHANGELOG.md` | **modify**: new `## [<new version>]` entry describing `/sdd-plan`, the vision/architecture/ADR artifacts, and draft-epic seeding | R23 |

## DO NOT TOUCH
- `agents/inception.md` — D1: Planner is a **sibling** role; Inception keeps triaging
  one idea to one altitude and seeding `pending`. Not extended, not edited.
- `.claude/commands/sdd-new.md`, `.claude/commands/sdd-next.md` — R19: existing intake
  and loop are behaviorally unchanged. Only a **new** `sdd-plan.md` command is added.
- `store/tasks.schema.json` — R11/R19: no schema change; `features: []` already
  validates. Adding `minItems` or any new status would break backward compatibility.
- `agents/orchestrator.md`, `store/local.md` — the F01 `next()` draft gate is reused
  as-is; F02 adds no gating rule.
- `specs/product.md`, `specs/glossary.md` — D3/R18: `vision.md` complements them; they
  are not rewritten, absorbed, or deleted.
- Existing test suites (`tests/test_*.sh`) — additive only; do not edit them.
- `state/tasks.json` epic/feature statuses — the Orchestrator owns transitions; the
  Builder flips no status while implementing this feature.

## Approach notes
- **Mirror the Inception build exactly** (E04-F01). The role file is the portable,
  durable contract; the Claude command is the thin interactive wrapper that points at
  it. Tests are static greps over the role + command + templates + docs (house style,
  cf. `tests/test_inception.sh`), plus one python fixture that proves the seeded shape
  is schema-valid. Use the exact phrases the spec pins (`draft`, `features: []`,
  `never`, `complement`, `legacy`/`producer`) so the grep tests bind to normative text.
- **`features: []` is the load-bearing difference from `/sdd-new`.** The new-epic
  altitude of Inception seeds a first `F01`; the Planner deliberately seeds an empty
  `features` array and no `F01`. The fixture must construct a synthetic epic with
  `features: []` and assert it validates (jsonschema if installed, else the structural
  fallback that mirrors `init.sh`). Keep the fixture in a temp file — never mutate the
  live `state/tasks.json`.
- **ADR path + numbering (D4/R9).** `specs/adr/NNNN-<title>.md`, 4-digit zero-padded,
  allocated above the current max ADR number. The role states the format; the
  architecture template's ADR-index section references `ADR-NNNN` ids so F04 can later
  pin feature specs to the same ids.
- **Re-run guard (D2/R17).** The role states the default-refuse behavior (vision.md /
  architecture.md already present ⇒ stop + point at `/sdd-drill` or amend) and the
  explicit append-only amend mode. No destructive overwrite, no renumber. This is prose
  the test greps for; there is no runtime guard to implement beyond the role contract.
- **Re-validation (R13).** The role mandates the same zero-dependency re-validate step
  Inception uses (`python3 -c "import json; json.load(...)"` + schema check) and the
  same fail-stop wording ("must not claim a successful plan"). The test greps the role
  for that fail-stop, mirroring `test_inception.sh::R7`.
- **Docs wording.** Use "`/sdd-plan`" verbatim and the phrase "draft" in
  `docs/WORKFLOW.md` and `README.md` so greps are simple; place the WORKFLOW note in/near
  the existing "Epic lifecycle" / intake section so the flow reads `/sdd-plan` (sketch)
  → `/sdd-drill` (deepen one epic) → `/sdd-next` (execute).
- **Sequencing:** templates → role file → command → docs → tests → config wiring →
  VERSION + CHANGELOG last (so the CHANGELOG heading matches the final VERSION).
- **Portability (R20).** Do not add an `agents.inception`-style opencode entry as a
  hard requirement — `opencode.json` today lists no Inception agent; portability is
  satisfied by the normative contract living in `agents/planner.md` + AGENTS.md. The
  test asserts the rule's *presence in the portable role file*, never anything about
  `.claude/` contents.
