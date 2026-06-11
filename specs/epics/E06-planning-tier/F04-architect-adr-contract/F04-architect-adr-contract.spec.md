---
id: E06-F04
title: "Architect contract: architecture.md mandatory input, specs cite ADRs"
epic: E06-planning-tier
status: done               # pending → spec-ready → in-progress → in-review → done
sdd: true
autonomous: false           # installed-body role + template + docs change; human reviews
depends_on: [E06-F02]
owner: araozmd
---

# Architect contract: architecture.md mandatory input, specs cite ADRs — Functional Spec

## Context
The planning tier built the producer side of the loop but never the consumer side. F02
(`/sdd-plan`) writes `specs/architecture.md` + `specs/adr/NNNN-*.md`, and F03
(`/sdd-drill`) records, in every feature's inbox brief, the `ADR-NNNN` ids that feature is
expected to honor (the **F03-D7 hook**). But the **Architect's contract
(`agents/architect.md`) still ignores all of it**: when it writes a feature's four-file
spec it reads only the inbox brief, never `architecture.md`/the ADRs, and the spec never
cites the decisions it touches. The durable design artifacts the planning tier produces
are therefore **write-only** — nothing downstream consumes them. That is exactly the gap
epic E06 set out to close: *"specs written after inception cite the architecture decisions
they touch; 'we lacked the whole picture' refactors stop recurring."*

This feature makes the Architect (and, minimally, the Reviewer) **consume** the
architecture, closing the loop F02/F03 opened. It amends `agents/architect.md` so that —
**whenever they exist** — `specs/architecture.md` and the relevant `specs/adr/*` are a
**mandatory input** alongside the inbox brief, and so every feature spec **cites the
`ADR-NNNN` ids it touches** in a defined, checkable place (the F03 brief already lists
those ids). It **degrades gracefully** for legacy repos that never ran `/sdd-plan`: when
the artifacts are absent the Architect records that and proceeds — no failure, no
fabricated citations — and every existing spec without a citation stays valid. A single,
**additive** Reviewer clause verifies the citation only when architecture artifacts exist.

F04 is **consume-only**: it changes only how the Architect/Reviewer *read and reference*
F02/F03's artifacts. It reshapes no producer, changes no ADR file format or numbering,
touches no `/sdd-plan`/`/sdd-drill` skill, and makes **no TaskStore schema change**. The
change is purely **additive** — repos without `specs/architecture.md` behave exactly as
today, and `/sdd-new`'s altitude-3 flow (which produces no `architecture.md`) still works.

## Business rules
- **Consume, never reshape.** F04 amends only `agents/architect.md` (consumer),
  `agents/reviewer.md` (one additive verification clause), the
  `specs/_templates/feature.spec.md` template, and docs. It must NOT edit
  `agents/planner.md`/`agents/driller.md`, the `/sdd-plan`/`/sdd-drill` commands, the ADR
  file format/numbering, `specs/_templates/architecture.md`/`adr.md`, or
  `store/tasks.schema.json`.
- **Mandatory-when-present, graceful-when-absent.** `specs/architecture.md` and the
  relevant `specs/adr/*` are a **required** Architect input when they exist; their absence
  is a documented, **non-failing** path. The Architect never fabricates a citation and
  never fails for lack of an architecture.
- **Reuse the F03-D7 hook.** The Architect reads the touched `ADR-NNNN` ids the inbox
  brief already records (under its constraints/decisions section) rather than re-deriving
  them; it may add ids the brief missed, but the brief is the seed.
- **Cite in one defined place.** Every feature spec written after this lands surfaces the
  touched ADR ids in a single, consistent, checkable section of the `.spec.md` (see D1).
- **"Touches none" is an explicit, legitimate state.** When architecture artifacts exist
  but the feature genuinely touches no ADR, the spec records that explicitly — it is not a
  silent omission (see D2/D3).
- **Backward compatible / additive.** No existing spec is invalidated (the rule applies to
  specs written **after** this lands); no schema change; `./init.sh` stays green; `/sdd-new`
  altitude-3 and any repo without `architecture.md` behave exactly as today.
- **Portability pillar.** The normative contract lives in the portable role files
  (`agents/architect.md`, `agents/reviewer.md`) + the template + docs, not in `.claude/`
  glue; it must hold on any AGENTS.md-compatible CLI.
- **One MINOR `VERSION` bump**, recorded in `CHANGELOG.md` (installed-body change:
  `agents/`, `specs/_templates/`, `docs/`).

## Decisions (D1..D6, resolving the intent brief's six open questions)
- **D1 — Citation placement: a dedicated `## Architecture alignment` section in the
  feature `.spec.md` (the consistent, checkable home), not inline tags and not only in
  `plan.md`.** The brief's first open question. A single named section lists each touched
  `ADR-NNNN` plus a one-line "how this honors it" (and, for a divergence, "how it
  departs"). It lands in `.spec.md` (the *what/why* file the human reads at the gate and
  the Reviewer traces), because the citation is a business-level claim ("this feature
  honors decision X"), not a code-level detail. Inline per-requirement tags were rejected
  as noisy and scattered (no single place to check); `plan.md`-only was rejected because
  the human reviews `.spec.md` at the gate and the Reviewer's traceability pass reads it.
  The `plan.md` may still reference ADRs in its design narrative, but the **normative,
  checkable citation lives in `.spec.md`'s `## Architecture alignment` section**. The
  template (`specs/_templates/feature.spec.md`) gains exactly this section so every new
  spec has a consistent slot.
- **D2 — Enforcement strength: when `architecture.md` exists the section is REQUIRED, and
  "touches no decision" is recorded explicitly as `ADRs touched: none` (with a one-line
  why); the Architect does not silently omit it.** The brief's second open question.
  Whenever architecture artifacts are present, the `## Architecture alignment` section is
  mandatory in every spec the Architect writes — but its content may legitimately be
  `ADRs touched: none` when the feature genuinely constrains no recorded decision.
  Requiring the explicit "none" (rather than an optional/absent section) makes "touches
  nothing" distinguishable from "forgot to consider it", which is what makes the Reviewer
  check meaningful (D3). When architecture artifacts are **absent**, the section is not
  required at all (graceful degradation, D5).
- **D3 — Reviewer strictness: soft flag, not hard reject, and the explicit `none`
  disambiguates "legitimately touches none" from "forgot".** The brief's third open
  question. The additive Reviewer clause fires **only when** `specs/architecture.md`
  exists (and at least one ADR exists) **and** the feature under review carries a
  four-file spec (`sdd: true`). It then confirms the `.spec.md` has an
  `## Architecture alignment` section that either cites ≥1 `ADR-NNNN` or explicitly states
  `ADRs touched: none`. A **missing-or-empty** section in that situation is a
  **flag-for-the-Builder-to-justify** (the existing "suspected but not provably violated"
  soft-flag verdict), **not** a hard reject — because the Reviewer cannot prove the author
  *forgot* versus *legitimately touches none* from the files alone. A spec that **does**
  carry the section (citing ids, or stating `none`) passes. The clause never blocks a
  legacy/no-architecture feature (the precondition gates it off) and never blocks an
  `sdd: false` brief-only item (no `.spec.md` to check) — keeping it strictly additive and
  non-overlapping with F05's `sdd: false` Reviewer clause.
- **D4 — Divergence path: state-it-in-spec; deltas remain F03's job.** The brief's sixth
  open question (resolved toward the brief's own "likely"). When a feature must
  intentionally depart from an ADR, the Architect **states the divergence in the
  `## Architecture alignment` section** (which ADR, how it departs, why). It does **not**
  author an ADR delta and does **not** invoke `/sdd-drill` — recording per-epic/per-feature
  ADR deltas is the Driller's (F03's) job and is out of scope here. The spec's stated
  divergence is the durable record; promoting it into a formal ADR delta, if warranted, is
  a separate F03/human decision.
- **D5 — Legacy detection: present = the file exists AND is non-empty/non-template-stub;
  a bare or template-only `architecture.md` counts as absent.** The brief's fourth open
  question. The Architect treats `specs/architecture.md` as **present** only when it
  exists and carries real content (not an empty file and not the untouched template
  scaffold), and the ADR set as present when `specs/adr/` holds at least one real
  `NNNN-*.md`. A file-exists-only test would misfire on a scaffold a repo created but never
  filled. When the architecture is judged **absent**, the Architect records its absence
  (so the omission is deliberate, not accidental) and proceeds with the inbox brief alone —
  no citation section is required, and the Reviewer clause does not fire (D3).
- **D6 — Umbrella/shared-contract specs are IN scope: shared `.spec`/`.plan` cite ADRs by
  the same rule; slices inherit it.** The brief's fifth open question. The ADR-citation
  rule applies to a shared umbrella `.spec.md` exactly as to a single-repo spec — when the
  umbrella repo has `specs/architecture.md`, its shared spec carries the
  `## Architecture alignment` section (or `ADRs touched: none`). The contract-artifact
  reference (umbrella mode) and the ADR citation are **orthogonal** obligations that
  coexist; F04 adds the ADR citation without touching the umbrella contract-artifact rule.
  Per-repo slices follow the ADR set of the repo they live in (a child repo with no
  `architecture.md` simply has no citation to make — graceful degradation, D5). Keeping
  umbrella specs in scope avoids a silent hole where the highest-leverage cross-repo specs
  would skip the architecture citation.

## Acceptance criteria (EARS)
> Each is one testable behavior with a stable id. See docs/SPEC-FORMAT.md.

### The amended Architect contract — mandatory-when-present input
- **R1** — `agents/architect.md` shall require the Architect, when writing a feature spec,
  to read `specs/architecture.md` and the relevant `specs/adr/NNNN-*.md` as a
  **mandatory input** (alongside the inbox brief) **whenever those artifacts are present**.
- **R2** — `agents/architect.md` shall state that the Architect reuses the **F03-D7 hook** —
  it reads the `ADR-NNNN` ids the feature's inbox brief already records (under the brief's
  constraints/decisions section) as the seed for which decisions the feature touches,
  rather than re-deriving them from scratch.

### The amended Architect contract — cite the touched ADRs
- **R3** — `agents/architect.md` shall require every feature `.spec.md` it writes (when
  architecture artifacts are present) to cite the `ADR-NNNN` ids the feature **touches** in
  a dedicated **`## Architecture alignment`** section, each with a one-line statement of
  **how the feature honors** that decision (D1).
- **R4** — `agents/architect.md` shall state that, when architecture artifacts are present
  but the feature genuinely touches **no** ADR, the `## Architecture alignment` section is
  still written and records **`ADRs touched: none`** with a one-line why — an explicit,
  legitimate state, not a silent omission (D2).
- **R5** — `agents/architect.md` shall state that when a feature must **intentionally
  diverge** from an ADR, the Architect **states the divergence in the
  `## Architecture alignment` section** (which ADR, how it departs, why), and shall state
  that it does **not** author an ADR delta and does **not** invoke `/sdd-drill` (recording
  ADR deltas remains F03's job) (D4).

### The feature.spec.md template section
- **R6** — `specs/_templates/feature.spec.md` shall add a **`## Architecture alignment`**
  section whose shape lists each touched `ADR-NNNN` + a one-line "how this honors it" and
  documents the `ADRs touched: none` fallback, so every new spec has a consistent,
  checkable slot for the citation (D1, D2).

### Graceful degradation (legacy / no-architecture)
- **R7** — `agents/architect.md` shall state that the Architect treats `specs/architecture.md`
  as **present** only when it exists **and** carries real content (not empty and not the
  untouched template stub), and the ADR set as present only when `specs/adr/` holds at
  least one real `NNNN-*.md` (D5).
- **R8** — If `specs/architecture.md`/the ADRs are **absent** (legacy repo, or
  `/sdd-new` altitude-3 with no plan), then `agents/architect.md` shall direct the
  Architect to record their absence and proceed from the inbox brief alone — writing **no**
  fabricated citation and **not** failing — and the `## Architecture alignment` section is
  not required in that spec (D5).
- **R9** — `agents/architect.md` shall state that existing specs written **before** this
  contract (without a `## Architecture alignment` section) remain valid — the citation rule
  applies only to specs written **after** F04 lands (no retro-fit).

### Umbrella / shared-contract specs (D6)
- **R10** — `agents/architect.md` shall state that the ADR-citation rule applies to a
  shared **umbrella** `.spec.md` exactly as to a single-repo spec (when the umbrella repo
  has architecture artifacts), as an obligation **orthogonal to** — coexisting with — the
  existing umbrella contract-artifact reference; per-repo slices follow the ADR set of the
  repo they live in (D6).

### The additive Reviewer clause
- **R11** — `agents/reviewer.md` shall add an **additive** clause stating that, **where**
  `specs/architecture.md` and at least one ADR exist **and** the feature under review
  carries a four-file spec (`sdd: true`), the Reviewer confirms the `.spec.md` has an
  `## Architecture alignment` section that either cites ≥1 `ADR-NNNN` or explicitly states
  `ADRs touched: none` (D3).
- **R12** — `agents/reviewer.md` shall state that a **missing or empty**
  `## Architecture alignment` section (in the situation R11 gates on) is **flagged for the
  Builder/Architect to justify** (a soft flag), **not** a hard reject — because the
  Reviewer cannot prove "forgot" versus "legitimately touches none" from the files — and
  shall state that the clause **does not fire** for a legacy/no-architecture feature or for
  an `sdd: false` brief-only item (no `.spec.md` to check) (D3).

### Docs
- **R13** — `docs/SPEC-FORMAT.md` shall document the `## Architecture alignment` section
  and the cite-your-ADRs rule (cite touched `ADR-NNNN` when architecture artifacts exist;
  `ADRs touched: none` when none apply; graceful degradation when absent).
- **R14** — `docs/WORKFLOW.md` shall document where the Architect's ADR-citation contract
  sits relative to `/sdd-plan` (produces `architecture.md` + ADRs) and `/sdd-drill`
  (records touched ADR ids in the brief), in an **additive section distinct from** the
  existing `/sdd-plan`, `/sdd-drill`, and F05 `/sdd-fix` sections (no edit that overlaps
  those sections).
- **R15** — Where `README.md` lists the SDD contract / spec files, it shall carry a
  one-line note that feature specs cite the architecture decisions (ADRs) they touch.

### Backward compatibility / portability / no schema change
- **R16** — `store/tasks.schema.json` shall be unchanged by this feature; a TaskStore that
  carried no ADR citation before shall validate exactly as before, and `./init.sh` shall
  exit 0 on the untouched repo.
- **R17** — The harness shall leave `/sdd-new`, `/sdd-plan`, `/sdd-drill`, `/sdd-next`,
  `agents/planner.md`, `agents/driller.md`, `agents/inception.md`, the
  `specs/_templates/architecture.md`/`adr.md` templates, and the ADR file
  format/numbering behaviorally unchanged; a repo with no `specs/architecture.md` shall
  behave exactly as today (`/sdd-new` altitude-3 included).
- **R18** — The ADR-citation contract shall live in the portable role files
  (`agents/architect.md`, `agents/reviewer.md`) + the `specs/_templates/feature.spec.md`
  template + docs, not solely in `.claude/` glue (the rule's presence in the portable files
  is the contract).

### Versioning
- **R19** — The repository shall record this change as one MINOR `VERSION` bump with a
  matching `CHANGELOG.md` entry (a heading equal to the `VERSION` file's content) that
  describes the Architect ADR-citation contract, the `## Architecture alignment` template
  section, and the additive Reviewer clause.

## Out of scope
- F02 `/sdd-plan` and F03 `/sdd-drill` — producing `architecture.md`/ADRs and recording
  touched ADR ids in the brief. F04 only makes the Architect/Reviewer **consume** them; it
  edits neither producer.
- The ADR file format, numbering (`specs/adr/NNNN-*.md`, 4-digit, above-max, no reuse), or
  the `specs/_templates/architecture.md`/`adr.md` template shapes — unchanged.
- Authoring or promoting **ADR deltas** when a feature diverges — F04 records the
  divergence in the spec (D4); creating a formal ADR delta remains F03's job.
- Validating the **content/correctness** of an ADR or of a feature's honoring of it — F04
  checks that the citation is *present and shaped*, not that the decision is *right*.
- Retro-fitting ADR citations onto already-written specs (E00–E05, E06-F01..F03/F05) — the
  rule applies to specs written **after** this lands (R9).
- Any `store/tasks.schema.json` change — the citation lives in the spec markdown, never in
  the store (R16).
- F06 drift-check on epic rollup — separate feature.

## Open questions
- None — the six questions from the intent brief are resolved as D1–D6 above.

## Constraints carried into the test contract
- Tests must not freeze the exact `VERSION` value (read `VERSION` at runtime) and must not
  `git diff` a DO-NOT-TOUCH file against `main` (the permanent-suite anti-pattern). The
  genuine permanent invariant is the **content** of the portable contract (role +
  template + docs), not a byte-freeze of any file.
- The verification path stays zero-dependency: POSIX sh + grep + python3 here-docs. Any
  JSON fixture carries the **required root `project` field** and uses a **temp** store
  created with `mktemp` — it never mutates the live `state/tasks.json`; any markdown
  fixture is created in a temp dir and never edits a live spec. Schema stays draft-07;
  `./init.sh` exits 0 afterward.
- F05 coordination: F04's edits to `agents/reviewer.md` and `docs/WORKFLOW.md` are
  **additive and non-overlapping** with F05's (`/sdd-fix`) edits — distinct section
  headings — so the branches merge cleanly (see `.plan.md` → F05 coordination).
