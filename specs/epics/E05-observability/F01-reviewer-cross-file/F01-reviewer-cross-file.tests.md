# Reviewer cross-file consistency + explicit build↔review rounds — Test Contract

> The traceability matrix: every R-id in the .spec.md maps to a concrete test. The
> Reviewer fails the feature if any R-id lacks a passing test. This is a prose-only
> change, so the automated guard is the **role-content-assertion** pattern (grep the
> role files), exactly as `tests/test_inception.sh` guards E04-F01. The one truly
> behavioral criterion (the Reviewer actually catching a planted contradiction) is a
> documented manual check below.

| R-id | Behavior | Test (file::name) | Type | Status |
|---|---|---|---|---|
| R1 | reviewer.md defines a "Cross-file consistency" check item | `tests/test_reviewer.sh` — grep `agents/reviewer.md` for `cross-file` / `consistency` check heading | static (grep) | ⬜ |
| R2 | check loads the collaborators the diff references | `tests/test_reviewer.sh` — grep reviewer.md for `collaborators` + `references`/`invokes` | static (grep) | ⬜ |
| R3 | expansion scoped, curate-don't-dump | `tests/test_reviewer.sh` — grep reviewer.md for `scoped` / `not a .*dump` / `curate` | static (grep) | ⬜ |
| R4 | verifies preconditions not contradicted by invoked contracts | `tests/test_reviewer.sh` — grep reviewer.md for `precondition` + `contradict` | static (grep) | ⬜ |
| R5 | provable violation ⇒ hard reject | `tests/test_reviewer.sh` — grep reviewer.md for `provably` + `reject` | static (grep) | ⬜ |
| R6 | suspected-but-unproven ⇒ flag, not block | `tests/test_reviewer.sh` — grep reviewer.md for `flag` + `justify` | static (grep) | ⬜ |
| R7 | PR #10 worked example present | `tests/test_reviewer.sh` — grep reviewer.md for `PR #10` + `Builder never opens a PR` (or `open.*PR`) | static (grep) | ⬜ |
| R8 | reject ⇒ specific, actionable, file-based feedback | `tests/test_reviewer.sh` — grep reviewer.md for `actionable` + `progress/<run>/review.md` | static (grep) | ⬜ |
| R9 | orchestrator.md states explicit multi-round build↔review until green | `tests/test_reviewer.sh` — grep `agents/orchestrator.md` for `re-review`/`until green` + `in-progress` | static (grep) | ⬜ |
| R10 | each round recorded | `tests/test_reviewer.sh` — grep orchestrator.md for `round` + `record` | static (grep) | ⬜ |
| R11 | docs coherent with multi-round loop | `tests/test_reviewer.sh` — grep `docs/WORKFLOW.md`/`AGENTS.md` do not assert review is a single pass; manual coherence check below | static (grep) + manual | ⬜ |
| R12 | VERSION bumped + CHANGELOG entry | `tests/test_reviewer.sh` — assert `VERSION` == `0.6.0` and `CHANGELOG.md` contains `## [0.6.0]` | static (grep) | ⬜ |
| R13 | DO NOT TOUCH: schema/status enum/builder/architect unchanged | `tests/test_reviewer.sh` — assert the status enum string `"pending", "spec-ready", "in-progress", "in-review", "done"` is present and unchanged in `store/tasks.schema.json`; (optionally `git diff main` clean for the schema while this is the only branch work) | static (grep) | ⬜ |

## Behavioral / end-to-end check (manual, performed once by the Reviewer)
- **Cross-file catch (R4/R5/R7).** Construct (or recall) a diff that adds a step to
  `agents/orchestrator.md` instructing the Builder to open a PR. Confirm that, under
  the new cross-file consistency wording, the Reviewer would load `agents/builder.md`,
  find Loop A's "Builder reports completion / never opens a PR" precondition, and
  **hard reject** with a file-based contradiction note — i.e. it reproduces the PR #10
  catch without any failing automated test. This validates the rule is operative, not
  merely present.
- **Coherence (R11).** Read the review-phase wording in `AGENTS.md` and
  `docs/WORKFLOW.md`; confirm none presents review as a single pass.

## Non-functional checks
- `./init.sh` exits zero.
- `tests/test_reviewer.sh` exits zero (and is executable; zero non-stdlib deps:
  POSIX sh + grep).
- The full `tests/` suite still passes (`test_inception.sh`, `test_install.sh`,
  `test_cascade.sh`, `test_umbrella.sh`).
