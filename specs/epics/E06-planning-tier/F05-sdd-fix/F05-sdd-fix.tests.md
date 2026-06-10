# /sdd-fix lightweight lane (maintenance epic, brief-only intake) — Test Contract

> The traceability matrix: every R-id in the .spec.md maps to a concrete, executable
> test. The Reviewer fails the feature if any R-id lacks a passing test.
>
> This feature ships **prose + docs + installer wiring** (a portable role file, a Claude
> slash-command wrapper, additive `sdd: false` clauses in builder/reviewer, an installer
> command block, two doc edits), so verification is the house way (cf.
> `tests/test_sdd_drill.sh`): file-existence + required-phrase greps over the portable
> contract, one python fixture that proves the seeded shape (an `sdd: false`,
> `autonomous: true` fix inside a `planned` `E99` maintenance epic) validates against
> `store/tasks.schema.json`, and one sandboxed `./init.sh` exit-0 run. Installer-generation
> assertions (R15/R16) live in **`tests/test_install.sh`** (the existing suite, extended
> additively — the canonical home for "a new `/sdd-*` command is installed"); all other
> automated tests live in **`tests/test_sdd_fix.sh`** (POSIX sh; grep + python3 here-docs;
> zero new deps), wired into `verification.test_command`.
>
> **Suite-wide constraints (permanent-suite anti-pattern):** never assert the exact
> `VERSION` literal (read the file at runtime); never `git diff` a DO-NOT-TOUCH file against
> `main` (whether a PR touched a DO-NOT-TOUCH file is a Reviewer-reads-the-diff concern, not
> a frozen suite assertion). Never mutate the live `state/tasks.json` — the fixture uses a
> temp file carrying the **required root `project` field**.

| R-id | Behavior | Test (file::name) | Type | Status |
|---|---|---|---|---|
| R1 | Portable Fixer role exists, names brief-only `sdd:false` intake + hand-off, stated portable | `tests/test_sdd_fix.sh::R1_fixer_role_exists` — `[ -f agents/fixer.md ]`; grep (case-insensitive) `sdd: false`/`sdd:false`, `maintenance`, `brief`, `hand.*off`/`loop`, and `AGENTS.md-compatible`/`portable` | static | ☐ |
| R2 | `/sdd-fix` command points at the role + reads `$ARGUMENTS` (STOP if empty) | `tests/test_sdd_fix.sh::R2_sdd_fix_command` — `[ -f .claude/commands/sdd-fix.md ]`; grep `agents/fixer.md`, `$ARGUMENTS`, and `empty`/`ask`/`STOP` | static | ☐ |
| R3 | ≤3 text-only options, never images — in BOTH role and command | `tests/test_sdd_fix.sh::R3_text_only_options` — grep `text.*only`/`markdown/ASCII` and `at most 3`/`≤ *3` in `agents/fixer.md` AND `.claude/commands/sdd-fix.md`; assert `never images`/`not generate images` in the role | static | ☐ |
| R4 | Role reuses existing `sdd:false` routing; no new routing/status/schema | `tests/test_sdd_fix.sh::R4_reuse_primitive` — grep `agents/fixer.md` for `sdd: false`/`sdd:false`, `Builder`, `Reviewer`, `reuse`/`existing`, and `no new` + `routing`/`status`/`schema` | static | ☐ |
| R5 | Role: create `E99` on first use (`planned`, `features: []`) + `epic.md` | `tests/test_sdd_fix.sh::R5_epic_create` — grep `agents/fixer.md` for `E99`, `maintenance`, `Maintenance (hotfixes`/`title`, `status: "planned"`/`planned`, `features: []`/`empty`, `epic.md`, and `if absent`/`first use`/`create` | static | ☐ |
| R6 | Role: reuse the same epic by id `E99` thereafter; no second bucket, no renumber | `tests/test_sdd_fix.sh::R6_epic_reuse` — grep `agents/fixer.md` for `E99`, `reuse`, `by id`/`identify`, `not.*second`/`never.*second`/`one`, and `not.*renumber`/`append-only` | static | ☐ |
| R7 | Role: maintenance epic is non-`draft` selectable (`planned`); never seed `draft` | `tests/test_sdd_fix.sh::R7_non_draft` — grep `agents/fixer.md` for `planned`, `selectable`/`next()`, `not.*draft`/`never.*draft` | static | ☐ |
| R8 | Role: append fix `sdd:false`/`pending`/`spec_path`/next-`F##`-above-max, no reuse | `tests/test_sdd_fix.sh::R8_fix_seed` — grep `agents/fixer.md` for `sdd: false`/`sdd:false`, `status: "pending"`/`pending`, `spec_path`, `above`/`max`, `F##`/`next-sequential`, and `append-only`/`no reuse` | static + fixture | ☐ |
| R9 | Role: stamp `autonomous: true` default + `--gated` opt-out; existing flag, no new mechanism | `tests/test_sdd_fix.sh::R9_autonomous_default` — grep `agents/fixer.md` for `autonomous: true`, `default`, `--gated`/`opt-out`/`gated`, `autonomous: false`, and `no new` + `approval mechanism`/`mechanism` | static | ☐ |
| R10 | Role: one fix-oriented inbox brief; never a spec / `spec_path` dir / Architect | `tests/test_sdd_fix.sh::R10_brief_only` — grep `agents/fixer.md` for `progress/inbox/`, `inbox-brief.md`, each forbidden `.spec`/`.plan`/`.tasks`/`.tests`, `not.*spec_path` *directory*/`not create.*directory`, and `not.*spawn`/`never.*spawn` the Architect | static | ☐ |
| R11 | Role: re-validate after each write; fail-stop, never claim success on invalid store | `tests/test_sdd_fix.sh::R11_revalidate_fail_stop` — grep `agents/fixer.md` for `store/tasks.schema.json`, `re-validate`/`revalidate`, and `not.*claim.*success`/`do not claim a successful seed`/`report the failure` | static | ☐ |
| R12 | Builder additive `sdd:false` clause: works from inbox brief, still writes a test; `sdd:true` path intact | `tests/test_sdd_fix.sh::R12_builder_from_brief` — grep `agents/builder.md` for `sdd: false`/`sdd:false`, `progress/inbox/`/`inbox brief`, and `test`; AND assert the `sdd: true` path is still present (grep `tasks.md` worklist / `Loop A` precondition unchanged) | static | ☐ |
| R13 | Reviewer additive `sdd:false` clause: behavioural + test, traceability N/A; `sdd:true` path intact | `tests/test_sdd_fix.sh::R13_reviewer_behavioural` — grep `agents/reviewer.md` for `sdd: false`/`sdd:false`, `behaviour`/`behavioral`/`behavioural`, `traceability`, and `not apply`/`no R-id`/`without R-id`; AND assert the `sdd: true` traceability check (#2, `R-id` → test) is still present | static | ☐ |
| R14 | Role + command: hand off to the existing loop in-session; Fixer writes no code | `tests/test_sdd_fix.sh::R14_handoff` — grep `agents/fixer.md` AND `.claude/commands/sdd-fix.md` for `hand.*off`/`loop`/`Builder`, `in-session`/`session`, and (role) `no production code`/`writes no code`; assert it states the routing is *reused*, not re-implemented | static | ☐ |
| R15 | Installer generates `/sdd-fix` (resolved against `.harness/`, carries `$ARGUMENTS`) + `.opencode` mirror | `tests/test_install.sh` (R15/R16 block) — run the installer into a temp target, then assert `.claude/commands/sdd-fix.md` exists, `grep -qF '.harness/agents/fixer.md'`, `grep -qF '$ARGUMENTS'`; assert `.opencode/command/sdd-fix.md` exists and `cmp -s` equals the `.claude/` copy | behavioral | ☐ |
| R16 | Installer installs the Fixer role + `test_install.sh` asserts command + mirror + role | `tests/test_install.sh` (R15/R16 block) — assert `[ -f "$T/.harness/agents/fixer.md" ]`; the command-exists + `.harness/agents/fixer.md` resolve + `$ARGUMENTS` + opencode-mirror-equals-claude assertions above are the `test_install.sh` wiring | behavioral | ☐ |
| R17 | `/sdd-new`,`/sdd-plan`,`/sdd-drill`,`/sdd-next` + `sdd:true` path unchanged; untouched repo green, no maint epic | `tests/test_sdd_fix.sh::R17_backward_compatible` — assert `.claude/commands/sdd-new.md`, `sdd-plan.md`, `sdd-drill.md`, `sdd-next.md`, `agents/inception.md`, `agents/planner.md`, `agents/driller.md` all still exist and still point at their original contracts (grep `agents/driller.md` in `sdd-drill.md`, etc.); assert the live `state/tasks.json` carries **no** `E99` epic; run `./init.sh` and assert exit 0 | static + behavioral | ☐ |
| R18 | Contract lives in the portable role file, not solely `.claude/` glue | `tests/test_sdd_fix.sh::R18_portable_contract` — assert the lane rules (`sdd: false` seed, reserved `E99` maintenance epic, `autonomous` default, brief-only-never-spec, hand off to the loop) are present in `agents/fixer.md` itself (presence in the portable file is the contract — no assertion about `.claude/` contents) | static | ☐ |
| R19 | WORKFLOW.md documents the lightweight lane; adds no new status/routing | `tests/test_sdd_fix.sh::R19_workflow_doc` — grep `docs/WORKFLOW.md` for `/sdd-fix`, `sdd: false`/`sdd:false`, `maintenance`, `inbox brief`/`brief`, `Builder`, `Reviewer`, `no 4-file spec`/`no spec`, and `no new` + `status`/`routing` | static | ☐ |
| R20 | README one-liner for `/sdd-fix` | `tests/test_sdd_fix.sh::R20_readme_oneliner` — grep `README.md` for `/sdd-fix` | static | ☐ |
| R21 | One MINOR bump recorded in CHANGELOG (no literal version frozen) | `tests/test_sdd_fix.sh::R21_version_changelog` — assert `VERSION` matches `^[0-9]+\.[0-9]+\.[0-9]+$`; read `V=$(cat VERSION)` at runtime and assert `CHANGELOG.md` contains a `## [<V>]` heading whose section mentions `/sdd-fix` (no literal version hard-coded) | static | ☐ |

## The schema fixture (R8 — the load-bearing python here-doc)
Construct a **temp** store (never the live `state/tasks.json`) carrying the **required
root `project` field** and a **`planned` `E99` maintenance epic** with one seeded
**`sdd: false`** fix stamped `autonomous: true`, then assert it validates against
`store/tasks.schema.json` (jsonschema if installed, else the structural fallback that
mirrors `init.sh`):

```json
{"project":"fixture","epics":[{"id":"E99","title":"Maintenance (hotfixes & minor fixes)",
 "status":"planned","features":[{"id":"E99-F01","title":"Fix a typo","status":"pending",
 "sdd":false,"autonomous":true,"depends_on":[],
 "spec_path":"specs/epics/E99-maintenance/F01-fix-a-typo/"}]}]}
```

This proves the seeded shape `/sdd-fix` writes — an `sdd: false` fix with `autonomous: true`
and a `spec_path`, inside a `planned` `E99` epic — is schema-valid as written, with **no
schema change** (`E99` matches `^E[0-9]+$`; `planned`, `sdd: false`, and `autonomous` all
already validate). The fixture is created with `mktemp`, cleaned up on exit, and never
touches the live store.

## Behavioral / end-to-end checks (Reviewer, manual)
- Hand-walk a `/sdd-fix "<desc>"` run from the role contract: confirm the prose
  unambiguously (1) creates the `E99` maintenance epic on first use (`planned`,
  `features: []`, `epic.md`) and **reuses it by id** on later runs (no second bucket, no
  renumber), (2) appends one `sdd: false` fix (next `F##` above max, `autonomous: true`
  default / `--gated` opt-out) plus exactly one fix-oriented inbox brief — and **no** spec,
  **no** `spec_path` directory, **no** Architect, (3) re-validates and fail-stops on a bad
  store, and (4) **hands the seeded fix off to the existing `sdd: false → Builder →
  Reviewer` loop in-session**. Confirm nothing in the contract introduces a new routing
  rule, a new status, or a schema change, and nothing permits writing a feature
  `.spec/.plan/.tasks/.tests`. Any ambiguity is a reject.
- Confirm the Builder/Reviewer edits are **additive** by reading those two files: the new
  `sdd: false` clause is present **and** the existing `sdd: true` four-file instructions
  (Builder's `tasks.md` worklist / Loop A precondition; Reviewer's R-id traceability check)
  read identically — the `sdd: true` path is untouched.
- Confirm purely-additive scope by reading the **PR diff** (not a test that diffs against
  `main`): the diff touches no schema, no `next()` gating in
  `agents/orchestrator.md`/`store/local.md`, no `agents/inception.md`/`planner.md`/
  `driller.md`/`architect.md`, and no existing `/sdd-*` command.
- Run the **full** `verification.test_command` (all existing suites + the new one): green,
  proving the additive change broke nothing.

## Non-functional checks
- Lint: n/a (`lint_command` empty for this repo).
- Types: n/a (`typecheck_command` empty).
- Zero-dependency: `tests/test_sdd_fix.sh` runs on POSIX sh + python3 only; the
  `jsonschema`-absent fallback still validates the seeded-shape fixture (R8). The fixture
  never mutates the live `state/tasks.json` and carries the required root `project` field.
