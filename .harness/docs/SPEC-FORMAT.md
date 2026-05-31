# The Spec Format

This is the standard every spec in this harness follows. It is deliberately
CLI-agnostic and model-agnostic: the same files drive Claude Code, Codex, Gemini
CLI or OpenCode. Specs are also the project's **living documentation**.

## The hierarchy: Product → Epic → Feature

```
specs/
  product.md                         # Layer 0 — constitution: vision, audience,
  glossary.md                        #            domain model, AI features (stable)
  epics/
    E01-dashboard/
      epic.md                        # business brief + feature index + status rollup
      F01-overview-widgets/
        overview-widgets.spec.md     # Business / Functional  (EARS acceptance criteria)
        overview-widgets.plan.md     # Technical / Architecture
        overview-widgets.tasks.md    # Atomic task checklist
        overview-widgets.tests.md    # Contract: R-id → verifying test
```

- **Product** = the stable constitution. High-level on purpose — granular detail
  here cascades errors downstream.
- **Epic** = a shippable area of product value (e.g. *Dashboard*, *Handoff*). Holds
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
| **Ubiquitous** | The `<system>` shall `<response>`. | The dashboard shall display the user's display name. |
| **Event-driven** | **When** `<trigger>`, the `<system>` shall `<response>`. | When the user clicks "Take over", the system shall assign the conversation to that agent. |
| **State-driven** | **While** `<state>`, the `<system>` shall `<response>`. | While a conversation is bot-handled, the system shall show a "Bot active" badge. |
| **Unwanted** | **If** `<condition>`, **then** the `<system>` shall `<response>`. | If the handoff API returns 5xx, then the system shall show a retry banner and keep the message queued. |
| **Optional** | **Where** `<feature>`, the `<system>` shall `<response>`. | Where analytics is enabled, the system shall log a `handoff_started` event. |

Patterns can be combined: *When `<trigger>`, while `<state>`, the `<system>` shall
`<response>`.*

### Writing good EARS

- One requirement = one observable, testable behavior. Split compound clauses.
- Use **shall** for mandatory behavior; avoid "should/may" in acceptance criteria.
- Name the actor as the `<system>` (or a named component), not "the user" — the
  user is in the trigger, the system is what we verify.
- Quantify: "at most 5 notes", "within 2s", not "a few", "fast".
- Give each a stable id. Never renumber a shipped requirement — append.

## Frontmatter (machine-readable state)

Every `.spec.md` starts with YAML frontmatter so the Orchestrator reads state
cheaply (and so the `obsidian` store gets graph/backlink support for free):

```yaml
---
id: E01-F01
title: Overview widgets
epic: E01-dashboard
status: pending          # pending → spec-ready → in-progress → in-review → done
sdd: true                # false = skip full SDD (quick task, Builder direct)
autonomous: false        # true = may bypass the human approval gate
depends_on: []           # other feature ids that must be done first
owner: araozmd
---
```

See `docs/WORKFLOW.md` for the state machine and the human-in-the-loop gate.
