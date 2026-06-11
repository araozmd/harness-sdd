# Architect contract: architecture.md mandatory input, specs cite ADRs — Test Contract

> The traceability matrix: every R-id in the .spec.md maps to a concrete, executable test.
> The Reviewer fails the feature if any R-id lacks a passing test.
>
> This feature ships **prose + a template section + docs** (an amended consumer role, one
> additive Reviewer clause, a template section, three doc edits), so verification is the
> house way (cf. `tests/test_sdd_plan.sh`, `tests/test_sdd_drill.sh`): file-existence +
> required-phrase greps over the portable contract, one **temp-dir markdown** fixture that
> proves the `## Architecture alignment` shape is internally consistent, one **temp JSON
> store** fixture that proves no schema change is needed, and one sandboxed `./init.sh`
> exit-0 run. All automated tests live in **`tests/test_architect_adr.sh`** (POSIX sh;
> grep + python3 here-docs; zero new deps), wired into `verification.test_command`.
>
> **Suite-wide constraints (permanent-suite anti-pattern):** never assert the exact
> `VERSION` literal (read the file at runtime); never `git diff` a DO-NOT-TOUCH file
> against `main`. Never mutate the live `state/tasks.json` or any live spec — the JSON
> fixture uses a temp file carrying the **required root `project` field**, and the markdown
> fixture is built in a temp dir.

| R-id | Behavior | Test (file::name) | Type | Status |
|---|---|---|---|---|
| R1 | Architect reads `architecture.md` + `adr/*` as **mandatory-when-present** input | `tests/test_architect_adr.sh::R1_mandatory_input` — grep `agents/architect.md` for `specs/architecture.md`, `specs/adr/`, `mandatory`/`required`, and `present`/`when.*exist`/`whenever` | static | ☐ |
| R2 | Architect reuses the F03-D7 brief hook for touched ADR ids | `tests/test_architect_adr.sh::R2_brief_hook` — grep `agents/architect.md` for `inbox brief`/`brief`, `ADR-`/`ADR ids`, and `record`/`touch`/`F03` (reads the ids the brief already lists) | static | ☐ |
| R3 | Every spec (when present) cites touched `ADR-NNNN` in `## Architecture alignment` + "how honored" | `tests/test_architect_adr.sh::R3_cite_section` — grep `agents/architect.md` for `## Architecture alignment`/`Architecture alignment`, `ADR-NNNN`/`ADR-`, `touch`, and `honor`/`how` | static | ☐ |
| R4 | Present-but-nothing-touched ⇒ explicit `ADRs touched: none` | `tests/test_architect_adr.sh::R4_explicit_none` — grep `agents/architect.md` for `ADRs touched: none`/`touched: none`/`none`, and `explicit`/`legitimate`/`not.*silent` | static | ☐ |
| R5 | Divergence stated in-spec; never authors an ADR delta / invokes /sdd-drill | `tests/test_architect_adr.sh::R5_divergence` — grep `agents/architect.md` for `diverg`/`depart`, `state.*divergence`/`in.*spec`, and `not.*ADR delta`/`not.*author.*delta`/`not.*sdd-drill`/`F03` | static | ☐ |
| R6 | `feature.spec.md` template gains the `## Architecture alignment` section + `none` fallback | `tests/test_architect_adr.sh::R6_template_section` — grep `specs/_templates/feature.spec.md` for `## Architecture alignment`, `ADR-`/`ADR-NNNN`, and `ADRs touched: none`/`touched: none` | static | ☐ |
| R7 | Legacy detection: present = exists AND non-empty/non-template | `tests/test_architect_adr.sh::R7_present_detection` — grep `agents/architect.md` for `present`, `non-empty`/`not empty`/`real content`, and `template`/`stub` (a stub counts as absent) | static | ☐ |
| R8 | Absent ⇒ note absence + proceed, no fabricated citation, no failure, section not required | `tests/test_architect_adr.sh::R8_graceful_absent` — grep `agents/architect.md` for `absent`/`no.*architecture`, `proceed`, `not.*fail`/`no failure`, and `not.*fabricat`/`no.*fabricat`/`no.*invented` | static | ☐ |
| R9 | Pre-F04 specs without the section stay valid (no retro-fit) | `tests/test_architect_adr.sh::R9_no_retrofit` — grep `agents/architect.md` for `after`/`written after`, `existing`/`pre-`/`already`, and `valid`/`no retro-fit`/`not.*retro` | static | ☐ |
| R10 | Umbrella shared specs cite ADRs too, orthogonal to the contract artifact | `tests/test_architect_adr.sh::R10_umbrella` — grep `agents/architect.md` for `umbrella`/`shared`, `slice`/`contract`, and `ADR`/`architecture alignment` (rule applies to shared spec, orthogonal to the contract artifact) | static | ☐ |
| R11 | Reviewer clause fires only where architecture + `sdd: true`; confirms section cites ≥1 ADR or `none` | `tests/test_architect_adr.sh::R11_reviewer_fires` — grep `agents/reviewer.md` for `Architecture alignment`/`ADR`, `specs/architecture.md`/`architecture`, `sdd: true`/`four-file spec`, and `ADR-`/`ADRs touched: none`/`cite` | static | ☐ |
| R12 | Missing section ⇒ soft flag not hard reject; clause does not fire for legacy / `sdd: false` | `tests/test_architect_adr.sh::R12_reviewer_soft` — grep `agents/reviewer.md` for `flag`/`soft`, `not.*hard reject`/`not.*reject`/`rather than blocking`, `does not fire`/`legacy`/`no.*architecture`, and `sdd: false`/`brief-only` (carve-out) | static | ☐ |
| R13 | `docs/SPEC-FORMAT.md` documents the section + cite-your-ADRs rule | `tests/test_architect_adr.sh::R13_spec_format_doc` — grep `docs/SPEC-FORMAT.md` for `Architecture alignment`, `ADR`, `cite`/`touch`, and `ADRs touched: none`/`none`/`absent` (graceful) | static | ☐ |
| R14 | `docs/WORKFLOW.md` adds a distinct ADR-citation section placing it vs /sdd-plan + /sdd-drill | `tests/test_architect_adr.sh::R14_workflow_doc` — grep `docs/WORKFLOW.md` for `Architecture-aligned`/`cites ADRs`/`Architecture alignment`, `/sdd-plan`, `/sdd-drill`, and `ADR`; assert the heading text differs from F05's `Lightweight fix lane`/`sdd-fix` (distinct section) | static | ☐ |
| R15 | `README.md` carries a one-line "specs cite ADRs" note | `tests/test_architect_adr.sh::R15_readme` — grep `README.md` for `ADR` together with `cite`/`architecture decision`/`touch` | static | ☐ |
| R16 | No schema change; a feature row with no citation field validates; `./init.sh` exit 0 | `tests/test_architect_adr.sh::R16_no_schema_change` — python fixture: a TEMP store with root `project` + an ordinary feature (no new field) validates against `store/tasks.schema.json` (jsonschema if present, else structural fallback); plus `./init.sh` exit 0 | fixture + behavioral | ☐ |
| R17 | Producers/commands/templates unchanged; no-architecture repo behaves as today | `tests/test_architect_adr.sh::R17_backward_compatible` — assert `agents/planner.md`, `agents/driller.md`, `agents/inception.md`, `.claude/commands/sdd-new.md`/`sdd-plan.md`/`sdd-drill.md`/`sdd-next.md`, `specs/_templates/architecture.md`, `specs/_templates/adr.md` all still exist; assert `sdd-plan.md` still points at `agents/planner.md` and `sdd-drill.md` at `agents/driller.md`; run `./init.sh` exit 0 | static + behavioral | ☐ |
| R18 | Contract lives in the portable role files + template + docs, not solely `.claude/` glue | `tests/test_architect_adr.sh::R18_portable_contract` — assert the citation rule (`## Architecture alignment`, `ADR`, `mandatory`/`present`) is present in `agents/architect.md` itself AND the verification clause in `agents/reviewer.md` itself (presence in the portable files is the contract — no assertion about `.claude/` contents) | static | ☐ |
| R19 | One MINOR bump recorded in CHANGELOG (no literal version frozen) | `tests/test_architect_adr.sh::R19_version_changelog` — assert `VERSION` matches `^[0-9]+\.[0-9]+\.[0-9]+$`; read `V=$(cat VERSION)` at runtime and assert `CHANGELOG.md` has a `## [<V>]` heading whose section mentions `Architecture alignment`/`ADR`/`cite` (no literal version hard-coded) | static | ☐ |

## The markdown fixture (R3/R4/R6 — the load-bearing temp-dir here-doc)
Build a synthetic feature `.spec.md` in a **temp dir** (`mktemp -d`, cleaned on exit)
carrying the `## Architecture alignment` section in **both** documented forms, and assert
each form is detectable by the same greps the Reviewer/template prescribe — proving the
documented shape is internally consistent. It never edits a live spec:

```markdown
## Architecture alignment
- ADR-0001 — Event-sourced store: this feature appends events, honoring the decision.
```

and the no-touch form:

```markdown
## Architecture alignment
ADRs touched: none — this feature is presentation-only and constrains no recorded decision.
```

Assert the first contains `## Architecture alignment` + `ADR-0001`; the second contains
`## Architecture alignment` + `ADRs touched: none`. Both are written to the temp dir with
`mktemp -d` and removed on exit.

## The schema fixture (R16 — the load-bearing python here-doc)
Construct a **temp** store (never the live `state/tasks.json`) carrying the **required root
`project` field** and an ordinary feature row with **no** new citation field, then assert
it validates against `store/tasks.schema.json` (jsonschema if installed, else the
structural fallback that mirrors `init.sh`):

```json
{"project":"fixture","epics":[{"id":"E99","title":"Aligned epic","status":"planned",
 "features":[{"id":"E99-F01","title":"Cited feature","status":"spec-ready","sdd":true,
 "autonomous":false,"depends_on":[],"spec_path":"specs/epics/E99-x/F01-y/"}]}]}
```

This proves the consumer change (citation in spec markdown) needs **no** store edit — a
feature row without any ADR-citation field is schema-valid as written. The fixture is
created with `mktemp`, cleaned up on exit, and never touches the live store.

## Behavioral / end-to-end checks (Reviewer, manual)
- Hand-walk the amended `agents/architect.md`: confirm the prose unambiguously (1) lists
  `architecture.md` + `adr/*` as a mandatory-when-present input that reuses the F03-D7
  brief hook, (2) requires the `## Architecture alignment` citation section (with the
  explicit `ADRs touched: none` for no-touch and the stated-divergence path), and (3)
  degrades gracefully when artifacts are absent (note absence + proceed, no fabricated
  citation, no failure). Any ambiguity is a reject.
- Hand-walk the additive `agents/reviewer.md` clause: confirm it fires **only** where
  architecture artifacts exist AND the spec is `sdd: true`, treats a missing section as a
  **soft flag** (not a hard reject), and carves out legacy/no-architecture and `sdd: false`
  items. Confirm it is a **distinct section** that does not overlap F05's `## sdd: false
  items…` clause and never contradicts it (one is `sdd: false`, the other `sdd: true`).
- Confirm purely-additive scope by reading the **PR diff** (not a test that diffs against
  `main`): the diff touches no `store/tasks.schema.json`, no `agents/planner.md`/`driller.md`,
  no `specs/_templates/architecture.md`/`adr.md`, no `/sdd-*` command, and no existing test
  suite.
- Run the **full** `verification.test_command` (all existing suites + the new one): green,
  proving the additive change broke nothing.

## Non-functional checks
- Lint: n/a (`lint_command` empty for this repo).
- Types: n/a (`typecheck_command` empty).
- Zero-dependency: `tests/test_architect_adr.sh` runs on POSIX sh + python3 only; the
  `jsonschema`-absent fallback still validates the no-schema-change fixture (R16). Fixtures
  never mutate the live `state/tasks.json` or any live spec, and the JSON fixture carries
  the required root `project` field.
