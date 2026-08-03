# Builder — E99-F09 (Antigravity claims the shared skill unit)

Spec: `specs/epics/E99-maintenance/F09-antigravity-skills/` · Decision: `ADR-0003`

## What shipped

Four gates moved from `agent_selected codex` to the claim predicate `skill_unit_claimed`
(= `codex || antigravity`), and reclaim became last-claimant-only in both directions:

| Site | Change |
|---|---|
| §5d install | `skill_unit_claimed` — an antigravity selection now writes the units |
| §7 `codex)` | reclaims only when `! agent_selected antigravity` |
| §7 `antigravity)` | reclaims `$HARNESS_OWNED_CMDS` when `! agent_selected codex` (new) |
| §7b gate-off | `skill_unit_claimed` — an antigravity-only target reclaims the gated unit |

The policy companion stayed unconditional (R3) rather than becoming codex-gated, which is
the one place the spec was corrected during specification: Codex discovers repository
skills from the directory, not from this installer's selection, so a `SKILL.md` written
without `agents/openai.yaml` is an implicitly-invocable mutating workflow for anyone who
runs Codex in that repo. That also collapsed the design — no install-time parameterisation
and no companion-only reclaim path — and left the two-file `_ics_safe` atomicity intact.

Renames: `install_skill_unit`, `reclaim_skill_units`, `gen_skill_body`,
`skill_unit_destination_is_symlinked`. `gen_codex_skill_policy` and every `*_stamp_*`
helper kept their Codex names on purpose — they address `.harness/.codex-skills/`, whose
path ADR-0003 deliberately preserves.

## Mutation proof

Committed first (`1206534`), then each gate was broken in isolation and restored with
`git checkout --`. Every mutation killed exactly its owning case:

| Mutation | Case that died | Collateral |
|---|---|---|
| §5d gate → `agent_selected codex` | `R1: antigravity-only install did not write the shared skill unit sdd-next` | — |
| §7 `codex)` → unconditional reclaim | `R4: codex deselect changed a shared skill unit Antigravity still claims` | — |
| §7 `antigravity)` skill reclaim deleted | `R5: antigravity-only deselect stranded a pristine shared unit` | — |
| §7b gate → `agent_selected codex` | `R6: gate off without codex selected left …/sdd-pr-loop/SKILL.md behind` | `test_install.sh` 0 FAILs — correctly unaffected |

The M3 pair is the one that matters most: without it the §7 `antigravity)` reclaim could be
absent entirely and the both-selected R5 block would still pass, because the `codex)` branch
would have done the work.

## Verification

- `sh tools/run-tests.sh` — 29/29 suites green.
- `sh tools/change-size.sh` — production 86 lines / 3 files, inside budget.
- `sh -n` + `dash -n` clean on `harness-install.sh`, `tests/test_install.sh`,
  `tests/test_pr_loop.sh`; `dash tests/test_install.sh` exits 0.

## One pre-existing failure, not from this feature

`dash tests/test_pr_loop.sh` fails locally at `R22: fresh findings on head must exit 0
(got 126)`. **Reproduced identically on unmodified `main`** in a scratch worktree, so it
predates this branch and is untouched by it. Exit 126 is "found but not executable", so it
looks like a fixture-stub permission difference in this environment rather than a harness
defect — `sh tools/run-tests.sh` is green on both. Same family as E99-F12 (local runs
diverging from CI without the suites being able to say so).
