# /sdd-drill skill (decompose draft epic, ADR deltas, epic-level approval) — Test Contract

> The traceability matrix: every R-id in the .spec.md maps to a concrete, executable
> test. The Reviewer fails the feature if any R-id lacks a passing test.
>
> This feature ships **prose + docs** (a portable role file, a Claude slash-command
> wrapper, two doc edits), so verification is the house way (cf. `tests/test_sdd_plan.sh`):
> file-existence + required-phrase greps over the portable contract, one python fixture
> that proves the canonical decomposed shape (a `pending` feature inside a `planned` epic,
> stamped `autonomous: true`) validates against `store/tasks.schema.json`, and one
> sandboxed `./init.sh` exit-0 run. All automated tests live in
> **`tests/test_sdd_drill.sh`** (POSIX sh; grep + python3 here-docs; zero new deps),
> wired into `verification.test_command`.
>
> **Suite-wide constraints (permanent-suite anti-pattern):** never assert the exact
> `VERSION` literal (read the file at runtime); never `git diff` a DO-NOT-TOUCH file
> against `main` (whether a PR touched a DO-NOT-TOUCH file is a Reviewer-reads-the-diff
> concern, not a frozen suite assertion). Never mutate the live `state/tasks.json` —
> the fixture uses a temp file carrying the **required root `project` field**.

| R-id | Behavior | Test (file::name) | Type | Status |
|---|---|---|---|---|
| R1 | Portable Driller role file exists, names what it decomposes, stated portable | `tests/test_sdd_drill.sh::R1_driller_role_exists` — `[ -f agents/driller.md ]`; grep (case-insensitive) `decompose`, `draft`, `feature`, `ADR`/`adr`, and `AGENTS.md-compatible`/`portable` | static | ☐ |
| R2 | `/sdd-drill` command points at the role + reads `$ARGUMENTS` | `tests/test_sdd_drill.sh::R2_sdd_drill_command` — `[ -f .claude/commands/sdd-drill.md ]`; grep `agents/driller.md` and `$ARGUMENTS` | static | ☐ |
| R3 | ≤3 text-only option mockups, never images — in BOTH role and command | `tests/test_sdd_drill.sh::R3_text_only_options` — grep `text.*only`/`markdown/ASCII` and `at most 3`/`≤ *3` in `agents/driller.md` AND `.claude/commands/sdd-drill.md`; assert `never images`/`not generate images` in the role | static | ☐ |
| R4 | `<epic-id>` required; empty arg ⇒ STOP and ask — role AND command | `tests/test_sdd_drill.sh::R4_epic_id_required` — grep `agents/driller.md` AND `.claude/commands/sdd-drill.md` for `<epic-id>`/`epic id`/`epic-id`, `required`, and `empty`/`ask` (+ `STOP`) | static | ☐ |
| R5 | Missing/non-`draft` target ⇒ default refuse; amend appends above max, no re-flip | `tests/test_sdd_drill.sh::R5_precondition_guard` — grep `agents/driller.md` for `not.*draft`/`must be .*draft`, `STOP`/`refuse`, `amend`, `append`, `above`/`max`, and `without renumber`/`not re-flip`/`renumber` | static | ☐ |
| R6 | Role reads the draft epic + vision/architecture/ADRs as input | `tests/test_sdd_drill.sh::R6_reads_inputs` — grep `agents/driller.md` for `epic.md`, `specs/vision.md`, `specs/architecture.md`, and `specs/adr/`/`ADR` as **inputs** | static | ☐ |
| R7 | Role seeds `pending` features, `sdd: true`, intra-epic ids/`depends_on`, no reuse + fixture | `tests/test_sdd_drill.sh::R7_seed_features` — grep `agents/driller.md` for `status: "pending"`/`pending`, `sdd`, `depends_on`, `spec_path`, `next-sequential`/`above`, `no reuse`/`never reuse`; PLUS python fixture (see below) — a `pending` feature inside a `planned` epic validates against `store/tasks.schema.json` | static + fixture | ☐ |
| R8 | Role fills the epic.md feature table with one row per seeded feature | `tests/test_sdd_drill.sh::R8_epic_table` — grep `agents/driller.md` for `epic.md`, `feature table`/`features table`/`table`, and `row`/`one row per` | static | ☐ |
| R9 | Role writes per-feature inbox brief recording touched ADR ids | `tests/test_sdd_drill.sh::R9_inbox_brief` — grep `agents/driller.md` for `progress/inbox/`, `specs/_templates/inbox-brief.md`, and `ADR-`/`ADR ids`/`touch` | static | ☐ |
| R10 | Role re-validates after seeding and fail-stops on validation failure | `tests/test_sdd_drill.sh::R10_revalidate_fail_stop` — grep `agents/driller.md` for `store/tasks.schema.json`, `re-validate`/`revalidate`, and `not.*claim.*success`/`do not claim a successful drill`/`report the failure` | static | ☐ |
| R11 | Role appends per-epic ADR deltas at `specs/adr/NNNN`, above-max, no F02-ADR rewrite | `tests/test_sdd_drill.sh::R11_adr_delta` — grep `agents/driller.md` for `specs/adr/`, `NNNN`/`4-digit`/`zero-pad`, `above`/`max`, `no reuse`/`never reuse`, `delta`, and `not rewrite`/`not renumber`/`existing ADR` | static | ☐ |
| R12 | Role scopes deltas to per-epic decisions; never feature-level design | `tests/test_sdd_drill.sh::R12_adr_boundary` — grep `agents/driller.md` for `per-epic`, `delta`, and `feature-level` (never/deferred) + `Architect`/`F04` | static | ☐ |
| R13 | Approve branch: epic `draft → planned` + stamp every feature `autonomous: true` | `tests/test_sdd_drill.sh::R13_approve_branch` — grep `agents/driller.md` for `approve`, `draft .* planned`/`draft → planned`, `autonomous: true`, and `every`/`all`/`all-or-nothing` | static | ☐ |
| R14 | Keep-gated branch: epic `planned`, every feature stays `autonomous: false` | `tests/test_sdd_drill.sh::R14_keep_gated_branch` — grep `agents/driller.md` for `keep gated`/`gated`, `planned`, `autonomous: false`, and `not leave`/`never leave`/`drilled` (not in draft) | static | ☐ |
| R15 | Single epic-level gate via existing `autonomous` flag — no new status/mechanism | `tests/test_sdd_drill.sh::R15_single_gate` — grep `agents/driller.md` for `one`/`single` + `epic`/`epic-level` decision, `autonomous`, `no new status`, and `no new approval mechanism`/`no schema change` | static | ☐ |
| R16 | Role states F03 is the only path past draft; advances only the epic | `tests/test_sdd_drill.sh::R16_only_path` — grep `agents/driller.md` for `only`/`only path` + `past .draft.`/`out of draft`, consistency with `never past draft`/`planner`, and `only the epic`/`never a feature`/`never another epic` | static | ☐ |
| R17 | Role states decomposes-never-specs (no spec files, no EARS/plan, no Architect spawn) | `tests/test_sdd_drill.sh::R17_decompose_never_specs` — grep `agents/driller.md` for each of `.spec`, `.plan`, `.tasks`, `.tests` as forbidden, `never.*spec`/`decompose.*never spec`, and `not.*spawn`/`never.*spawn` the Architect | static | ☐ |
| R18 | `/sdd-new`, `/sdd-plan`, `/sdd-next`, Inception, Planner unchanged; untouched repo green | `tests/test_sdd_drill.sh::R18_backward_compatible` — assert `.claude/commands/sdd-new.md`, `.claude/commands/sdd-plan.md`, `.claude/commands/sdd-next.md`, `agents/inception.md`, `agents/planner.md` all still exist and still point at their original contracts (grep `agents/planner.md` in `sdd-plan.md`); run `./init.sh` and assert exit 0 | static + behavioral | ☐ |
| R19 | Contract lives in the portable role file, not solely `.claude/` glue | `tests/test_sdd_drill.sh::R19_portable_contract` — assert the consumer rules (`decompose`, `draft → planned`, `autonomous`, decomposes-never-specs) are present in `agents/driller.md` itself (presence in the portable file is the contract — no assertion about `.claude/` contents) | static | ☐ |
| R20 | WORKFLOW.md places `/sdd-drill` between `/sdd-plan` + `/sdd-next`, only flip, no feature specs | `tests/test_sdd_drill.sh::R20_workflow_doc` — grep `docs/WORKFLOW.md` for `/sdd-drill`, `draft`, `planned`, `autonomous`, `/sdd-plan`, `/sdd-next`; assert it states the only step that flips `draft → planned` and that it never writes feature specs (`feature spec`/`no feature`) | static | ☐ |
| R21 | README one-liner for `/sdd-drill` | `tests/test_sdd_drill.sh::R21_readme_oneliner` — grep `README.md` for `/sdd-drill` | static | ☐ |
| R22 | One MINOR bump recorded in CHANGELOG (no literal version frozen) | `tests/test_sdd_drill.sh::R22_version_changelog` — assert `VERSION` matches `^[0-9]+\.[0-9]+\.[0-9]+$`; read `V=$(cat VERSION)` at runtime and assert `CHANGELOG.md` contains a `## [<V>]` heading whose section mentions `/sdd-drill` (no literal version hard-coded) | static | ☐ |

## The schema fixture (R7 — the load-bearing python here-doc)
Construct a **temp** store (never the live `state/tasks.json`) carrying the **required
root `project` field** and a `planned` epic with one seeded `pending` feature stamped
`autonomous: true`, then assert it validates against `store/tasks.schema.json`
(jsonschema if installed, else the structural fallback that mirrors `init.sh`):

```json
{"project":"fixture","epics":[{"id":"E99","title":"Drilled epic","status":"planned",
 "features":[{"id":"E99-F01","title":"Seeded feature","status":"pending","sdd":true,
 "autonomous":true,"depends_on":[],"spec_path":"specs/epics/E99-x/F01-y/"}]}]}
```

This proves the decomposed shape F03 writes — a `pending` feature with `sdd`/`spec_path`,
inside a `planned` epic, with the `autonomous` approval flag stamped — is schema-valid as
written, with **no schema change**. The fixture is created with `mktemp`, cleaned up on
exit, and never touches the live store.

## Behavioral / end-to-end checks (Reviewer, manual)
- Hand-walk a `/sdd-drill <epic-id>` run from the role contract: confirm the prose
  unambiguously (1) reads the target `draft` epic + vision/architecture/ADRs, (2) seeds
  `pending` feature entries + an `epic.md` table + per-feature inbox briefs, (3) appends
  per-epic ADR deltas under F02's convention, and (4) ends in exactly one epic-level
  decision — approve (`planned` + every feature `autonomous: true`) or keep gated
  (`planned`, every feature `autonomous: false`). Confirm nothing in the contract permits
  writing a feature `.spec/.plan/.tasks/.tests`, spawning the Architect, advancing any
  epic but the target, or introducing a new status/approval mechanism. Any ambiguity is a
  reject.
- Confirm purely-additive scope by reading the **PR diff** (not a test that diffs against
  `main`): the diff touches no schema, no `next()` gating in
  `agents/orchestrator.md`/`store/local.md`, no `agents/planner.md`, no
  `agents/architect.md`, no `agents/inception.md`, and no existing `/sdd-*` command.
- Run the **full** `verification.test_command` (all existing suites + the new one):
  green, proving the additive change broke nothing.

## Non-functional checks
- Lint: n/a (`lint_command` empty for this repo).
- Types: n/a (`typecheck_command` empty).
- Zero-dependency: `tests/test_sdd_drill.sh` runs on POSIX sh + python3 only; the
  `jsonschema`-absent fallback still validates the decomposed-shape fixture (R7). The
  fixture never mutates the live `state/tasks.json` and carries the required root
  `project` field.
