# The Spec Format

This is the standard every spec in this harness follows. It is deliberately
CLI-agnostic and model-agnostic: the same files drive Claude Code, Codex, Gemini
CLI, OpenCode or Antigravity. Specs are also the project's **living documentation**.

## The hierarchy: Product → Epic → Feature

```
specs/
  product.md                         # Layer 0 — constitution: vision, audience,
  glossary.md                        #            domain model, AI features (stable)
  epics/
    E01-example/
      epic.md                        # business brief + feature index + status rollup
      F01-example-feature/
        example-feature.spec.md      # Business / Functional  (EARS acceptance criteria)
        example-feature.plan.md      # Technical / Architecture
        example-feature.tasks.md     # Atomic task checklist
        example-feature.tests.md     # Contract: R-id → verifying test
```

- **Product** = the stable constitution. High-level on purpose — granular detail
  here cascades errors downstream.
- **Epic** = a shippable area of product value (e.g. *Onboarding*, *Settings*). Holds
  one or more features and a status rollup.
- **Feature** = one unit the Builder can implement in a single sprint. It owns the
  four spec files below.

### IDs and traceability

`E01` (epic) → `F01` (feature, numbered within its epic) → `R1, R2…` (requirements,
numbered within the feature's `.spec.md`).

Every entry in `.plan.md`, `.tasks.md` and `.tests.md` cites the `R-id` it serves.
That gives a **traceability matrix**: requirement → design → task → test. The
Orchestrator and Reviewer use it to verify coverage without reading prose.

## The four files

| File | Answers | Owner |
|---|---|---|
| `.spec.md` | *What* and *why* — business rules, EARS acceptance criteria | Architect |
| `.plan.md` | *How* — stack, data models, endpoints, files to change | Architect |
| `.tasks.md` | *In what order* — atomic, sequential steps | Architect → Builder |
| `.tests.md` | *How we know it's done* — R-id → test mapping | Architect → Reviewer |

## EARS — the requirement syntax

Acceptance criteria in `.spec.md` use **EARS (Easy Approach to Requirements
Syntax)**. EARS wins over freeform user stories because **each clause maps 1:1 to a
test**. The five patterns:

| Pattern | Template | Example |
|---|---|---|
| **Ubiquitous** | The `<system>` shall `<response>`. | The profile page shall display the user's display name. |
| **Event-driven** | **When** `<trigger>`, the `<system>` shall `<response>`. | When the user clicks "Save", the system shall persist the form. |
| **State-driven** | **While** `<state>`, the `<system>` shall `<response>`. | While a record is syncing, the system shall show a "Syncing" badge. |
| **Unwanted** | **If** `<condition>`, **then** the `<system>` shall `<response>`. | If the save API returns 5xx, then the system shall show a retry banner and keep the edit queued. |
| **Optional** | **Where** `<feature>`, the `<system>` shall `<response>`. | Where analytics is enabled, the system shall log a `record_saved` event. |

Patterns can be combined: *When `<trigger>`, while `<state>`, the `<system>` shall
`<response>`.*

### Writing good EARS

- One requirement = one observable, testable behavior. Split compound clauses.
- Use **shall** for mandatory behavior; avoid "should/may" in acceptance criteria.
- Name the actor as the `<system>` (or a named component), not "the user" — the
  user is in the trigger, the system is what we verify.
- Quantify: "at most 5 notes", "within 2s", not "a few", "fast".
- Give each a stable id. Never renumber a shipped requirement — append.

## Architecture alignment — cite the ADRs you touch

When the project has been planned (`/sdd-plan` wrote `specs/architecture.md` and ADRs at
`specs/adr/NNNN-*.md`), every feature `.spec.md` carries a dedicated
**`## Architecture alignment`** section (it sits between `## Business rules` and
`## Acceptance criteria (EARS)` — see `specs/_templates/feature.spec.md`). The Architect
**cites** the architecture decisions the feature **touches**, seeded from the `ADR-NNNN`
ids the inbox brief already records (the F03-D7 hook). The rule:

- **Cite each touched ADR.** List each `ADR-NNNN` the feature touches, each with a
  one-line "how this feature honors that decision".
- **`ADRs touched: none`** — when architecture artifacts exist but the feature genuinely
  touches **no** recorded decision, the section still appears and records the explicit line
  `ADRs touched: none` with a one-line why. It is a legitimate state, **not** a silent
  omission — which is what lets the Reviewer tell "touches none" from "forgot".
- **Divergence** — when a feature must intentionally depart from an ADR, state the
  divergence here (which ADR, how it departs, why); the Architect does **not** author an
  ADR delta (that stays the Driller's job).
- **Graceful degradation (absent architecture).** In a legacy repo that never ran
  `/sdd-plan` (or `/sdd-new`'s altitude-3 flow), `specs/architecture.md` is **absent** — a
  bare or template-stub file counts as absent too. Then the section is **not required**:
  the Architect records the absence and proceeds, writing no fabricated citation. Specs
  written before this contract (without the section) remain valid — no retro-fit.

## Frontmatter (machine-readable state)

Every `.spec.md` starts with YAML frontmatter so the Orchestrator reads state
cheaply (and so the `obsidian` store gets graph/backlink support for free):

```yaml
---
id: E01-F01
title: Example feature
epic: E01-example
status: pending          # pending → spec-ready → in-progress → in-review → done
sdd: true                # false = skip full SDD (quick task, Builder direct)
autonomous: false        # true = may bypass the human approval gate
depends_on: []           # other feature ids that must be done first
owner: araozmd
---
```

See `docs/WORKFLOW.md` for the state machine and the human-in-the-loop gate.
