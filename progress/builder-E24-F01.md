# Builder — E24-F01 (`init.sh` drift guard)

## What shipped
A new section `1b` in `init.sh`, between the structural checks and TaskStore validation:
when the harness is an installed copy in a git work tree, the harness-owned paths must
match what the branch records, or the gate fails.

~48 lines in `init.sh`, one new test suite, docs, `VERSION` 0.50.2 → **0.51.0** (MINOR — a
new capability, not a bugfix; a clean target is unaffected).

## Decisions taken during implementation

**One check, not two.** The spec's open question about a separate version-stamp check
resolved to "no". `.harness/.harness-version` is a tracked file *inside* the harness-owned
tree and every upgrade rewrites it, so a half-applied upgrade already surfaces through the
dirty-tree check. There is no second signal available at runtime: `init.sh` has no access
to the harness *source*, so installed-vs-latest is not a comparison it can make at all.

**A bash array, not `set --`.** The first draft passed the pathspec set via `set --`.
`init.sh` sources `.harness/init.project.sh` at the end (line ~256), and a sourced hook
inherits the caller's positional parameters — so `set --` would have silently handed every
project hook a list of git pathspecs. Changed to `HARNESS_OWNED=(...)`; `init.sh` is bash,
so arrays are available.

**`ls-files` runs before `status`, and that order is load-bearing.** In a repo where
nothing is tracked, `git status --porcelain -- .harness/` reports `?? .harness/` — non-empty.
A status-first implementation reads that as drift and hard-fails an install that simply was
never committed, which is the exact false positive R9 exists to prevent. Verified against
git 2.55.0; `tests/test_init_drift_guard.sh` R9 asserts both fixture preconditions
explicitly so the ordering cannot be refactored away silently.

**Scope by ownership, expressed as an exclusion.** The checked set is `.harness/` minus six
project-owned paths, plus six root-level generated-glue paths — not an enumeration of the
~29 owned files. Enumerating them would put `harness-install.sh`'s knowledge in a second
place, and the next feature that adds a body file would silently fall out of scope.

## Verification
- `tests/test_init_drift_guard.sh` — 12 assertions across R1–R10, all green. Behavioral:
  each case installs a real target, commits it, perturbs one thing, runs the installed
  gate, reads the exit code.
- `sh tools/run-tests.sh` — **all 29 suites pass**.
- `tools/change-size.sh` — tier `ok`: 88 production lines / 3 files.

### Mutation campaign (7 mutants, 7 killed)
The four requirements that assert an absence or a pass are the ones a no-op guard would
satisfy, so the suite was checked against deliberately broken implementations rather than
trusted for going green on the first run:

| # | Mutation | Killed by |
|---|---|---|
| M1 | `fail` → `echo` on drift (guard never fails) | R2 |
| M2 | `ls-files` gate removed (status decides everything) | R9 |
| M3 | project-owned exclusions dropped (over-broad scope) | R4 |
| M4 | root-level glue dropped from the checked set | R5 |
| M5 | guard keyed on the `*/.harness` suffix instead of the stamp | R6 |
| M6 | escape hatch made silent | R8 |
| M7 | sample cap removed (`head -n 10` → `head -n 999`) | R3 |

Each mutant was killed by the requirement that owns the behavior, not by an unrelated
assertion — which is the property that makes the matrix meaningful.

## Note on process
The first mutation run was done on an **uncommitted** implementation, and its
`git checkout -- init.sh` cleanup wiped the working copy — the same write-then-never-land
failure this feature exists to detect, reproduced by hand inside the feature that fixes it.
Re-applied and checkpoint-committed before continuing. Worth a line in the Builder contract:
**commit before mutation testing**, because the standard cleanup step is a revert.

## Not done here
- `docs/HARNESS.md` was left unedited: T11 made that conditional on the file enumerating
  `init.sh`'s checks, and it does not — it mentions `init.sh` only in passing.
- The producing side (making the cascade land the upgrade) is E24-F02, untouched here.
  `harness-install.sh` is on this feature's DO-NOT-TOUCH list and was not modified.
