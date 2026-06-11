# Architect contract: architecture.md mandatory input, specs cite ADRs — Technical Plan

> Translates the .spec.md intent into design. Every decision cites the R-id(s) it serves.
> This feature ships **prose + a template section + docs + one test suite** — there is no
> application code. F04 is the **consumer** half of the planning tier: it amends the
> Architect's portable role contract (and adds one additive Reviewer clause) so the
> `architecture.md`/ADRs F02 produces and the touched-ADR ids F03 records get *read and
> cited*, mirroring how F02/F03 themselves were built (portable role file + docs + grep
> tests).

## Stack & dependencies
- Markdown prose only: amend `agents/architect.md` (the consumer contract), amend
  `agents/reviewer.md` (one additive clause), amend the `specs/_templates/feature.spec.md`
  template (new section), and edit three docs (`docs/SPEC-FORMAT.md`, `docs/WORKFLOW.md`,
  `README.md`).
- Verification: POSIX sh + grep + python3 here-docs (`tests/test_architect_adr.sh`), wired
  into `verification.test_command`. One sandboxed `./init.sh` exit-0 run; one temp-dir
  markdown fixture proving the `## Architecture alignment` shape (citing an ADR, and the
  `ADRs touched: none` fallback) is what the contract describes; one temp JSON store
  fixture proving no schema change is required for a spec-cited feature.
- New dependencies: **none** (zero-dependency pillar holds; `jsonschema` stays optional).
- Reused, unchanged: `specs/_templates/architecture.md`, `specs/_templates/adr.md`, the ADR
  numbering convention, `agents/planner.md`, `agents/driller.md`, the F01 schema, every
  `/sdd-*` command.

## Data model  (serves: R16)
**No schema change.** The ADR citation lives entirely in the feature `.spec.md` markdown
(the `## Architecture alignment` section), never in `state/tasks.json`. The store is
untouched: a feature row carrying no new field validates against `store/tasks.schema.json`
exactly as before. The R16 fixture asserts this by validating a normal feature row (no
citation field) against the live schema in a temp store.

## Artifacts the amended contract governs  (serves: R3, R4, R5, R6, R8)
> These are produced by a *running* Architect, not by the Builder. The Builder ships the
> role + template + docs that mandate them; the fixture asserts the *shape* is what the
> contract describes, not that a session ran.

| Artifact | Governed by | R-id |
|---|---|---|
| `## Architecture alignment` section in a feature `.spec.md` (cites `ADR-NNNN` + "how honored") | the amended `agents/architect.md` + template | R3, R6 |
| `ADRs touched: none` recorded when architecture present but nothing touched | amended contract + template | R4, R6 |
| divergence stated in the section (which ADR, how it departs, why) | amended contract | R5 |
| no citation section when architecture absent (legacy / altitude-3) | amended contract | R8 |

## Files to change  (serves: R#)
| File | Change | R-id |
|---|---|---|
| `agents/architect.md` | **modify** — extend "Read these first": add `specs/architecture.md` + `specs/adr/NNNN-*.md` as **mandatory-when-present** input (R1), reusing the F03-D7 brief hook for touched ADR ids (R2). Extend the `.spec.md` output contract: require a **`## Architecture alignment`** section citing touched `ADR-NNNN` + "how honored" (R3); record **`ADRs touched: none`** when present-but-nothing-touched (R4); **state divergence in-spec**, never author an ADR delta or invoke `/sdd-drill` (R5). Add a **graceful-degradation** rule: present = exists AND non-empty/non-template (R7); absent ⇒ note absence + proceed from brief, no fabricated citation, section not required (R8); pre-F04 specs stay valid (R9). State the rule applies to umbrella shared specs too, orthogonal to the contract-artifact reference (R10). State the contract is portable (R18). | R1, R2, R3, R4, R5, R7, R8, R9, R10, R18 |
| `specs/_templates/feature.spec.md` | **modify** — add a `## Architecture alignment` section (lists each touched `ADR-NNNN` + one-line "how this honors it"; documents the `ADRs touched: none` fallback) between `## Business rules` and `## Acceptance criteria (EARS)`. | R6 |
| `agents/reviewer.md` | **modify (additive, distinct section)** — add a new section (e.g. `## ADR-citation check (architecture-aligned specs)`) that fires only **where** `specs/architecture.md` + ≥1 ADR exist **and** the feature carries a four-file spec; confirm the `.spec.md` has a `## Architecture alignment` section citing ≥1 `ADR-NNNN` or stating `ADRs touched: none` (R11); a missing/empty section is a **soft flag**, not a hard reject; the clause does not fire for legacy/no-architecture or `sdd: false` items (R12). | R11, R12 |
| `docs/SPEC-FORMAT.md` | **modify** — document the `## Architecture alignment` section + the cite-your-ADRs rule (cite when present; `none` when nothing applies; graceful when absent). | R13 |
| `docs/WORKFLOW.md` | **modify (additive, distinct section)** — add a new section (e.g. `## Architecture-aligned specs (the Architect cites ADRs)`) placing the contract relative to `/sdd-plan` (produces) and `/sdd-drill` (records touched ids); **distinct from** the existing `/sdd-plan`, `/sdd-drill`, and F05 `/sdd-fix` sections. | R14 |
| `README.md` | **modify** — one-line note that feature specs cite the architecture decisions (ADRs) they touch, beside the existing SDD-contract / `/sdd-*` mentions. | R15 |
| `tests/test_architect_adr.sh` | **create** — static grep contract assertions over `agents/architect.md`, `agents/reviewer.md`, `specs/_templates/feature.spec.md`, and the three docs; one temp-dir markdown fixture for the `## Architecture alignment` shape; one temp JSON store fixture for "no schema change"; one `./init.sh` exit-0 run. | R1–R19 |
| `harness.config.yaml` | **modify** — append `&& sh tests/test_architect_adr.sh` to `verification.test_command` and extend its trailing comment (e.g. `+ architect-adr`). | R1–R19 (wiring) |
| `VERSION` | **modify** — one MINOR bump (read current value at build time; do not hard-code). | R19 |
| `CHANGELOG.md` | **modify** — new `## [<new version>]` entry describing the Architect ADR-citation contract, the template section, and the additive Reviewer clause. | R19 |

## DO NOT TOUCH
- `agents/planner.md`, `agents/driller.md` — F04 is consume-only; the producers are
  unchanged. The F03-D7 hook (touched ADR ids in the brief) is *consumed*, not edited (R2,
  R17).
- `.claude/commands/sdd-new.md`, `.claude/commands/sdd-plan.md`,
  `.claude/commands/sdd-drill.md`, `.claude/commands/sdd-next.md`, `agents/inception.md`,
  `agents/orchestrator.md` — intake/plan/drill/loop unchanged; no new command (R17).
- `specs/_templates/architecture.md`, `specs/_templates/adr.md` — the ADR/architecture
  shapes and numbering are read-only inputs F04 cites, never reshapes (R17).
- `store/tasks.schema.json` — no schema change; the citation lives in spec markdown (R16).
- `store/local.md` — the `next()` gate / selection logic is untouched.
- Existing test suites (`tests/test_*.sh`) — additive only; do not edit them.
- Existing feature specs (E00–E05, E06-F01..F03/F05) — not retro-fitted (R9).
- `state/tasks.json` feature/epic statuses — the Orchestrator owns the F04 feature's own
  lifecycle; the Builder flips no status while implementing.

## Approach notes
- **Mirror the F02/F03 build.** The portable role file is the durable contract; the test
  is static greps over the role/template/docs (house style, cf. `tests/test_sdd_plan.sh`,
  `tests/test_sdd_drill.sh`) plus small temp-dir fixtures. Use the exact phrases the spec
  pins (`Architecture alignment`, `ADRs touched: none`, `mandatory`, `present`, `absent`,
  `ADR-NNNN`, `divergence`, `soft flag`/`flag`, `does not fire`) so the greps bind to
  normative text.
- **`## Architecture alignment` is the single load-bearing string.** It is the section
  heading in the template (R6), the thing the Architect must write (R3/R4), and the thing
  the Reviewer looks for (R11). The markdown fixture builds a synthetic `.spec.md` in a
  temp dir carrying the section both ways (citing `ADR-0001` and stating `ADRs touched:
  none`) to prove the documented shape is internally consistent — it never edits a live
  spec.
- **Graceful degradation is prose, not a runtime parser (R7/R8/R9).** "Present = exists AND
  non-empty/non-template", "absent ⇒ note + proceed, no fabricated citation", and "pre-F04
  specs stay valid" are contract statements the test greps for; there is no file-detection
  code to implement beyond the contract.
- **Reviewer clause is gated and soft (R11/R12).** The clause's precondition (architecture
  present AND `sdd: true` spec) is what keeps it from blocking legacy or `sdd: false`
  items; the verdict is a soft flag (reusing the Reviewer's existing "suspected but not
  provably violated → flag, don't block" verdict rule), not a new hard-reject. The test
  greps the new section for the precondition, the "cite ≥1 ADR or state none" check, the
  "flag / soft / not hard reject" wording, and the "does not fire for legacy / sdd: false"
  carve-out.
- **No schema change (R16).** The R16 fixture validates an ordinary feature row (no new
  field) against the live `store/tasks.schema.json` in a temp store with the required root
  `project` field — proving the consumer change needs no store edit.
- **Sequencing:** `agents/architect.md` → `specs/_templates/feature.spec.md` →
  `agents/reviewer.md` → docs (`SPEC-FORMAT.md`, `WORKFLOW.md`, `README.md`) → tests →
  config wiring → VERSION + CHANGELOG last (so the CHANGELOG heading matches the final
  VERSION).
- **Portability (R18).** No opencode/`.claude/` entry is a hard gate — portability is
  satisfied by the contract living in `agents/architect.md` + `agents/reviewer.md` + the
  template + docs. The test asserts the rule's *presence in the portable files*, never
  anything about `.claude/` contents.

## F05 coordination (in-flight `feat/sdd-fix-lane`, v0.18.0) — MUST merge cleanly
E06-F05 (`/sdd-fix`) is an in-flight branch that **also** edits `agents/reviewer.md` and
`docs/WORKFLOW.md` additively. To guarantee both branches merge without conflict, F04's
edits to those two files are designed to be **additive and non-overlapping** with F05's,
in **distinct sections that do not share surrounding lines**:

- **`agents/reviewer.md`** — F05 inserts a section `## sdd: false items — behavioural
  verification, traceability N/A` (right after the contract-artifact check, before
  `## Be honest, not generous`). F04 inserts a **different, later** section,
  `## ADR-citation check (architecture-aligned specs)`, placed **after** the
  "Cross-file consistency" / contract-artifact checks and **before** `## Be honest, not
  generous` but as its **own** heading — and the two clauses are **semantically disjoint**
  by design: F05's clause is "when `sdd: false`, traceability N/A"; F04's clause **only
  fires when `sdd: true`** (D3/R12), so they never contradict and never touch the same
  lines. If a textual conflict still arises at merge time, resolve by **keeping both
  sections** (they are independent); neither weakens the other.
- **`docs/WORKFLOW.md`** — F05 adds a `### Lightweight fix lane (/sdd-fix)` subsection.
  F04 adds a **separate** `## Architecture-aligned specs (the Architect cites ADRs)`
  section, distinct from F05's and from the existing `## Whole-project inception
  (/sdd-plan)`, `## Per-epic drill-down (/sdd-drill)` sections. The two are non-adjacent;
  resolution on any incidental conflict is **keep both**.
- **VERSION/CHANGELOG** — whichever of F04/F05 merges second rebases onto the other's
  VERSION and takes the next MINOR; the CHANGELOG entries are independent `## [x.y.z]`
  blocks that do not overlap.

## Risks
- **Over-strict Reviewer (false rejects on legacy/no-architecture).** If the Reviewer
  clause is written without its precondition, it would block every legacy feature.
  Mitigation: R11/R12 pin the clause to fire **only where** architecture artifacts exist
  **and** the spec is `sdd: true`, and make a missing section a **soft flag**, never a hard
  reject. The test greps the precondition and the soft-flag wording.
- **Conflating "touches none" with "forgot".** Without the explicit `ADRs touched: none`,
  the Reviewer could not tell a deliberate no-touch from an omission. Mitigation: D2/R4
  require the explicit `none`, which the Reviewer treats as a pass and a blank section as a
  flag (D3/R12).
- **Accidental producer reshape.** Editing the contract could drift into changing the ADR
  format or the brief. Mitigation: D-list and DO-NOT-TOUCH keep F02/F03 artifacts and
  templates read-only; the test asserts `agents/planner.md`/`agents/driller.md` and the
  architecture/adr templates still exist and point at their original contracts.
- **F05 merge conflict.** Two branches editing the same two files. Mitigation: the
  distinct-section design above + "keep both" resolution rule; the clauses are
  semantically disjoint (`sdd: false` vs `sdd: true`).
- **Schema drift temptation.** A reviewer might want a store field for the citation.
  Mitigation: R16 + the no-schema-change fixture make "citation lives in markdown" the
  contract; `store/tasks.schema.json` is DO-NOT-TOUCH.
