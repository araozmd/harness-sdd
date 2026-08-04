# Builder — E24-F03 (thin the child: umbrella-resolved body)

Spec: `specs/epics/E24-upgrade-integrity/F03-thin-child-body/` · Decision: `ADR-0004`

## What shipped

| Piece | Where |
|---|---|
| `umbrella.root` config key (child-side, documented, empty by default) | `harness.config.yaml` |
| `_cfg_umbrella_root_value` / `set_umbrella_root` (section-scoped read + idempotent write) | `harness-install.sh` |
| `umbrella_body_dir` — strict resolution: exists, not a symlink, holds `.harness-version` | `harness-install.sh` |
| `gen_body_stub` / `stub_tree` / `child_is_full_copy` | `harness-install.sh` |
| §1 body copy split into `HARNESS_BODY_PROSE` + `HARNESS_BODY_LOCAL` | `harness-install.sh` |
| §2a persists the cascade's umbrella root into the child's config | `harness-install.sh` |
| Cascade passes `HARNESS_UMBRELLA_ROOT='../../'` per child | `harness-install.sh` |
| `BODY LAYOUT` section in `manifest.txt` | `harness-install.sh` |
| Report-only umbrella resolution line, never a gate failure | `init.sh` |

## Two things the plan flagged that turned out to bite

**Ordering.** §1 decides stub-vs-copy, but on a *fresh* child `harness.config.yaml` does not
exist yet — the seed/preserve stage runs at §2. Reading the key from config alone would have
made every fresh cascade child full-copy, silently, with all tests still green on the
already-installed path. The cascade therefore passes the root by env for §1, and §2a
persists it into the child's config so a later standalone re-run needs no env var.

**`VAR=value func` persists in POSIX sh.** A variable assignment prefixing a *function*
call — unlike one prefixing an external command — stays set after the function returns. The
prefix form would have left `HARNESS_UMBRELLA_ROOT` set for every later target in the
cascade, including a coordinator re-install, which would then have thinned itself. Set and
`unset` explicitly instead.

## Mutation proof

Committed first, then each mechanism broken in isolation and restored:

| Mutation | Case that died | Collateral |
|---|---|---|
| `umbrella_body_dir` returns nothing | `R2: prose-tier AGENTS.md is not a stub in a fresh cascade child` | R5 stayed green (correct — that IS the full-copy path) |
| stub text interpolates `$VERSION` | `R7: a VERSION bump rewrote a thin child's stub` | R2/R3 green |
| `init.sh` fails on an unreachable umbrella | `R6: a thin child whose umbrella is unreachable FAILED the gate` | — |
| `child_is_full_copy` always false | `R9: the cascade converted an existing full-copy child's body to stubs` | R2 green |

The M2 run needed a second attempt worth recording: the first used `perl -0pi -e` with a
backtick in the pattern, the shell ate it as command substitution, and the mutation never
applied — so R7 "passed" while proving nothing. A mutation that does not visibly change the
file is not a mutation; check the diff before trusting the result.

## Verification

- `sh tools/run-tests.sh` — 29/29 green.
- `sh tools/change-size.sh` — production 267 / 17 files, inside budget.
- `sh -n` + `dash -n` clean on `harness-install.sh` and both touched suites; `bash -n init.sh`.
- End-to-end by hand: cascade → child gets stubs + real `init.sh`; the path a stub names
  resolves to the real body from the child's own `.harness/`; the coordinator keeps the
  full body and `root: ""`; `init.sh` in the child exits 0 both with and without the
  umbrella present.

## Note on the suite ordering trap

`tests/test_next_task.sh:542` runs `git diff --quiet -- init.sh`, so the whole suite fails
on any *uncommitted* `init.sh` change — it failed once here for exactly that reason and
passed after committing. Fifth recurrence of the permanent-suite anti-pattern; still
unfixed, still not this feature's job.
