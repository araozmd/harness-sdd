# The Spec Format

This is the standard every spec in this harness follows. It is deliberately
CLI-agnostic and model-agnostic: the same files drive Claude Code (primary), Codex
(second), OpenCode (third), and Antigravity. Specs are also the project's **living documentation**.

Command names in this document use the canonical `/sdd-*` spelling. In Codex,
invoke the corresponding `$sdd-*` skill with accompanying argument text, such as
`$sdd-plan A shared reading list`. In Antigravity, invoke them as native `/sdd-*`
slash commands. The spec format and approval gates are the same.

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
| `.tasks.md` | *In what order* — one red/green pair per `R-id` | Architect → Builder |
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

## Tasks — red/green pairs per requirement

ADR-0008 decision 2. A `.tasks.md` lists, for every `R-id` of the `.spec.md`, a **pair**:
`T<n>a (R#)` writes the failing test named in `.tests.md` and observes **RED**; `T<n>b (R#)`
writes the minimal code to pass it and observes **GREEN**. The Builder commits after each
GREEN. Order the pairs walking-skeleton `R-id` first (the thinnest end-to-end behavior
observable at the product boundary). The lint `tools/tasks-pair-check.py <tasks> --spec
<spec>` turns the shape into an exit code (0 ok, 1 violation, 2 usage/input error).

```markdown
- [ ] **T1a** (R1) — write failing `tests/test_x.py::test_y`; run it; observe RED
- [ ] **T1b** (R1) — minimal code in `x.py`; observe GREEN; commit
- [ ] **T2** (R1) — refactor: extract the helper; R1 test stays GREEN; commit
```

The grammar the lint enforces (and this section, the template and the Architect prompt all
state the same one):

- A task is a line `- [ ] **T<n>[a|b]** (R#, R#) — text` (or `- [x]`). Suffix `a` is a test
  task, `b` a code task, no suffix or any other letter is "other" (never dropped). The cited
  `R-id`s are the explicit `R<n>` tokens inside the parentheses; a range such as `R1–R4` is
  not expanded — cite each id.
- For every spec `R-id` (a line `- **R<n>** …`), the first task that cites it must be a `T<n>a`
  task; an `R-id` no task cites is also a violation.
- Refactor tasks are explicit and cite the `R-id`s whose tests guard them. Setup or verify
  tasks with no `R-id` are allowed, but a task that cites no `R-id` and reads "write … tests"
  is the layered shape this removes, and is rejected wherever it sits in the list.
- Lines inside fenced code (the CommonMark rule) are ignored in both files.
- The `.tests.md` traceability table is not read by the lint.

Behavioral (Playwright / e2e) requirements. An `R-id` whose only verification is a
behavioral row gets its own pair by default: its RED is the e2e spec failing against the
running app. Where it exercises the same code path as another `R-id`'s pair, the Architect
may group it by co-citing it on that pair's `a` task (`**T2a** (R2, R4) — …`). A behavioral
`R-id` therefore obeys the same first-task rule as every other — never a code-only first
task. The lint cannot tell which `R-id`s are behavioral; whether the e2e RED was actually
observed is the Reviewer's behavior check.

## Architecture alignment — cite the ADRs you touch

When the project has been planned (`/sdd-plan` wrote `specs/architecture.md` and ADRs at
`specs/adr/NNNN-*.md`), every feature `.spec.md` carries a dedicated
**`## Architecture alignment`** section (it sits between `## Business rules` and
`## Acceptance criteria (EARS)` — see `specs/_templates/feature.spec.md`). The Architect
**cites** the architecture decisions the feature **touches**, seeded from the `ADR-NNNN`
ids the inbox brief already records (the F03-D7 hook). The rule:

- **Cite each touched ADR.** List each `ADR-NNNN` the feature touches, each with a
  one-line "how this feature honors that decision".
- **Namespaces — qualify when there is more than one ADR space.** A project may keep the
  platform space `specs/adr/` plus a product/agent space `specs/<product>/adr/`; the
  number spaces are independent and normally **collide** (`0023` in both, different
  content). The `<ns>` token is the `adr/` directory's parent basename, with `platform`
  reserved for the root space. A **qualified** citation (`<ns>/ADR-NNNN`, or
  `<ns> ADR-NNNN` for a real token) resolves against **that space only** — which is what
  makes a cross-namespace typo detectable. A **bare** `ADR-NNNN` asserts no space, so it
  resolves against **any** of them and is therefore **not** cross-namespace-checked. Both
  `agents/reviewer.md` and `init.sh`'s warn-only sweep apply exactly this rule.
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
