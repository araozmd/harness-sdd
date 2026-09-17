# E31-F01 Reviewer verdict — OpenCode claims the shared `.agents/skills` surface

- **Date:** 2026-09-17
- **Reviewer:** independent (Reviewer role)
- **Commit under review:** `2d08e6b` (base `main`), branch `feat/E31-F01-opencode-shared-skill-surface`
- **Spec:** `specs/epics/E31-opencode-first-class/F01-shared-skill-surface/E31-F01.*`
- **Verdict:** **REJECT** — one blocking finding (release record), everything else verified.
- **Change-size tier:** `ok` (production 55 lines / 3 files; budget advise >1500/25, escalate >3000/50). No decision required.
- **Working tree at review start/end:** clean (no `.mutbak` residue; no staged/unstaged changes).

---

## 1. Environment

| Command | Result |
|---|---|
| `./init.sh` | exit **0** (`✅ environment ready`) |
| `sh tools/run-tests.sh` | `all 47 suites passed (/usr/bin/sh [GNU bash, version 5.3.15(1)-release (x86_64-pc-linux-gnu)], --jobs 8)`, exit 0 |

**What the green is a statement ABOUT (reviewer check 1).** `run-tests.sh` picks the
strictest shell it can probe (`dash`, `posh`, `ash`, `sh`). On this host **dash/posh/ash are
absent** (`command -v dash posh ash` → nothing; `/usr/bin/sh` → `bash`), so the runner
fell back to bash and named it. The 47-suite green is therefore a claim about **bash**, not
about POSIX `sh`/dash. That is the honest E99-F135 outcome, not a defect in this change,
but it means a dash-only construct added here would not be caught by this host's pre-flight.
Reported as an environment caveat; no dash-incompatible construct was found in the diff.

## 2. Traceability — every R-id is covered by a passing, mutation-proven test

Tests exist for all six R-ids and the full suite is green. I independently reproduced the
revert-in-place proof (`git show main:harness-install.sh` over the working copy, sanctioned
backup/restore) and ran a **mutation campaign, one mutation at a time**, each mutation's
applied diff printed and the file restored and diff-confirmed between runs
(runner: `scratchpad/E31-F01-reviewer/`).

| Mutant | Exact edit | Suite (red) | Failure line |
|---|---|---|---|
| `M_R1` | `agent_selected codex \|\| agent_selected opencode` → `agent_selected codex` | `test_install.sh` | `FAIL: E31-F01 R1: opencode-only selection did not install .agents/skills/sdd-next/SKILL.md` |
| `M_R2a` | codex-branch reclaim made unconditional (pre-change destructive shape) | `test_pr_loop.sh` | `FAIL: E31-F01 R2: shared pr-loop skill was reclaimed while OpenCode claims it` |
| `M_R2b` | opencode-branch reclaim made unconditional | `test_install.sh` | `FAIL: E31-F01 R2: deselecting opencode removed sdd-next/SKILL.md while codex remained` |
| `M_R3` | opencode-branch reclaim deleted | `test_install.sh` | `FAIL: E31-F01 R3 (opencode codex): deselecting the last claimant left a pristine shared unit` |
| `M_R4` | adapter reverted to Codex-only + `/skills` | `test_codex_native.sh` | `AssertionError: sdd-fix: adapter lost the OpenCode invocation` |
| `M_R5` | `sdd-fix-parallel` precondition block deleted | `test_installer_toggles.sh` | `FAIL: E31-F01 R5: the shared body does not read .harness/.opencode-parallel` |
| `M_R6` | precondition made `&& agent_selected opencode` (body selection-dependent) | `test_install.sh` | `FAIL: E31-F01 R6: sdd-fix-parallel/SKILL.md bytes depend on whether opencode is selected` |

**Revert-in-place (pre-change installer, new tests):** R1, R4, R5 each red their named
suite (exact messages above). R2's named test and R6 pass pre-change **by design** (the
plan and `E31-spec-revalidation.md` classify them as regression locks). They are not
decoration: `M_R2b` shows the named R2 test reddens when the opencode-branch gate is
removed, and `M_R6` shows the byte-identity test reddens when the one body becomes
selection-dependent. R2's destructive direction is pinned separately and **does** fail
pre-change: probe `claude,codex → claude,opencode` yields `sdd-next=GONE` + reclaim warning
on the pre-change installer vs `PRESENT` + no warning post-change.

**Conclusion:** all six R-ids are mutation-proven. No decorative assertion found.

## 3. Behavioral verification (host is installed, so the e2e oracle was run)

OpenCode 1.18.31 is present. In a temp target installed with `--agents=opencode --pr-loop=true`,
`opencode serve` + `GET /command` shows the shared surface is live: `sdd-fix-parallel`
resolves with `source='skill'` (its `.opencode/command` copy is withheld by the concurrency
gate), and `sdd-next/new/plan/drill/fix/pr-loop` + `sdd-test-concurrency` resolve. This is
the empirical R1/R4 oracle the test contract names.

The R5 leak path was reproduced: `--agents=codex,opencode` with no
`.harness/.opencode-parallel`, `.opencode/command/sdd-fix-parallel.md` **withheld**, yet
`/sdd-fix-parallel` is still served from the shared skill — and the served template carries
`.opencode-parallel`, `supported`, and `/sdd-test-concurrency`. R5's body-level gate is
therefore a real mitigation of a real reachable path, not a paper change.

Note: the test contract's phrasing "7 workflows … (`source:"skill"`)" is imprecise — only
the gated `sdd-fix-parallel` is `source='skill'`; the others are `source='command'` from
`.opencode/command/`. Substantive claim holds. Minor doc fix (non-blocking).

## 4. Scope — clean

`git diff main..2d08e6b --stat` and `git show --name-only 2d08e6b`:

- No changes to `.opencode/`, `opencode.json`, `gen_opencode_json`, `gen_oc_agent`,
  `self_install`, or `HARNESS_SDD_CMDS` (grep of the feature diff for those tokens → NONE).
- **`state/tasks.json` is NOT touched by the feature commit.** Its `spec-ready → in-progress`
  flip lives in the separate chore commit `6950cdd` (human gate closed), which is legitimate
  bookkeeping and outside this feature's diff.
- `--self` regeneration equality independently confirmed: after `sh harness-install.sh --self`,
  `diff -r .agents/skills` → IDENTICAL and `diff .claude/.glue-manifest` → IDENTICAL. Committed
  source glue equals the new emitter output.

## 5. Deliberate deviations — judged

- **Contract inversion (ADR-0003).** New behavior is what R2/R3 require (deselect-one
  preserves for the remaining claimant; last-claimant reclaims). The rewritten assertions are
  *strengthened*, not weakened: the TG block now asserts unit survival plus a **specific**
  warning-prefix negative (`grep -qF "removed deselected agent 'codex' skills" && fail`)
  instead of the old loose `grep -qiF 'codex'`; `test_pr_loop.sh` R4 splits the reclaimed
  Codex-own glue from the retained shared skill. Both are pinned by `M_R2a`.
- **Golden fixture.** Builder's claim verified at `tests/test_codex_native.sh:204`: the golden
  glob is `.claude/agents/*.md`, `.claude/commands/*.md`, `.opencode/command/*.md`,
  `.opencode/agent/*.md`, `opencode.json` — it does **not** include `.agents/skills`, so no
  refresh was needed and the snapshot is not falsified. The adapter negative was correctly
  **scoped** (split on `## Canonical workflow`) rather than deleted, and the adapter block is
  separately asserted (`/skills` absent, both invocations present). No weakening.
- **ADR-0003 recorded.** Claiming set updated `{codex, antigravity}` → `{codex, opencode}`
  with a dated E31-F01 note (Antigravity retired, OpenCode the reader). `init.sh` reports ADR
  citations resolve.

## 6. Cross-file consistency

Docs (`README.md`, `docs/INSTALL.md`, `docs/HARNESS.md`) now describe the shared surface
consistently with the code: claimant set `{codex, opencode}`, "install on any / reclaim on
last", host-neutral adapter, and the Codex-no-op OpenCode precondition. `/skills` is scoped
to Codex everywhere it appears; no OpenCode `/skills` claim remains. No contradiction found
with `ADR-0003` or the epic.

---

## BLOCKING finding

### B1 — The release record the ADR explicitly requires is missing (no `VERSION` bump, no `CHANGELOG.md` entry)

- **Files:** `VERSION` (still `0.80.0`); `CHANGELOG.md` (no entry for this change).
- **Expected:** a MINOR bump + CHANGELOG section in this same PR.
- **Actual:** neither. The feature commit `2d08e6b` changes `harness-install.sh` (the
  installed body), `docs/`, and `.claude/.glue-manifest` (glue) but leaves the version stamp
  and changelog untouched.
- **Why this blocks (quoted authorities, not preference):**
  - `AGENTS.md:61` — "`VERSION` is a public installer contract. Bump it deliberately **in the
    same PR** when the installed body changes: `harness-install.sh`, … `docs/`, … or `.claude/`
    glue." This change touches three of those categories. `.harness/.harness-version` is the
    installer's own existing-install/upgrade signal (`harness-install.sh:2445`), so a body
    change carrying the old version is a real contract gap, not cosmetic.
  - `specs/adr/0003-one-shared-skill-unit-per-command.md:109-113` — the inverted assertion
    "is not collateral to be quietly flipped: it is a contract change, must be rewritten
    deliberately, **and belongs in `CHANGELOG.md`**." That is this exact inversion.
  - Every recent installed-body commit does this in-commit: `1e2ce73` (E30-F01, +`VERSION`
    +`CHANGELOG.md`), `f9c3491`, `6fd4411`. No Orchestrator step owns the bump — a grep of
    `agents/`, `docs/`, `skills/`, `.agents/skills/` finds no other VERSION/CHANGELOG contract
    (only `AGENTS.md`), so "the Orchestrator will do it" is not supported by the harness.
- **Required fix (precise):**
  1. `VERSION` → `0.81.0` (MINOR: new capability — OpenCode claims the shared surface).
  2. Add a `## [0.81.0]` section to `CHANGELOG.md` recording the change and the **contract
     inversion** (deselecting one claimant now preserves the units for the remaining
     claimant; the last claimant's deselect reclaims them), plus the host-neutral adapter and
     the `sdd-fix-parallel` OpenCode precondition.
  3. Sync the version literal in `tests/test_codex_native.sh:208`
     (`assert (src/'VERSION').read_text().strip()=='0.80.0'`) — per `progress/lessons.md`
     (2026-09-16 builder), a bump requires the literal sync or the suite goes red. This is the
     only non-fixture literal pinning the current version (verified by grep).
  4. Keep `harness-install.sh --self` output in sync if the body text changes (it should not).

The code and tests are otherwise correct; this is the single blocking item.

---

## Non-blocking notes (do not block, but act)

1. **Residual Codex-only warnings for now-shared units** — `harness-install.sh:6645`,
   `:6650`, `:6674` still say "selected Codex install left …" while the unit is shared. This
   is **not** in R4's specified scope: spec R4 is the `SKILL.md` adapter, and plan T6
   enumerates only the §5d `ok` line (fixed, `:6802`) and the install-manifest text (fixed,
   `:4090`). It is, however, the same "Codex-only description of a shared unit" divergence
   the revalidation note (plan §"The installer's own strings are part of R4") flags. Decide:
   fix in this PR if cheap, otherwise record a follow-up (F02 or an `sdd:false` fix) so the
   divergence is tracked. The Builder already flagged it in `progress/E31-F01-builder.md`.
2. **`E31-F01.tests.md` traceability Status column is still ⬜ for all six R-ids** although
   every named test exists and passes. Tick the column (or note why it stays open) before the
   handoff; the table currently understates the delivered coverage.
3. **`E31-F01.tests.md` behavioral-oracle wording** ("7 workflows … `source:"skill"`") does
   not match observed OpenCode 1.18.31, where only the gated `sdd-fix-parallel` is
   `source='skill'` and the rest are `source='command'` from `.opencode/command/`. The
   substantive assertion is satisfied; tighten the wording.
4. **Spec R6 wording** ("byte-identical … before and after this feature") is unsatisfiable
   alongside R4, which intentionally changes the adapter bytes for every claimant. The plan
   reinterprets R6 correctly as "identical across selections". Recommend the Architect
   tighten R6's literal text so the next reader does not read it as a byte-freeze. Flagged,
   not blocking (same-feature spec/plan, resolved by the plan).

## Lessons surfaced

- Host environment: this box has **no `dash`/`posh`/`ash`**, so `tools/run-tests.sh` reports
  its strict shell as `/usr/bin/sh` = **bash**. Every green here is a bash green; a
  dash-incompatible construct would pass. Appended to `progress/lessons.md`.
- No new code-level lesson: the mutation campaign confirmed the assertions are pinned.

## Change-size decision

Tier `ok` (55 production lines / 3 files, well inside `advise`). No split and no override
needed. Not a factor in the verdict.

---

# Round 2 verdict — commit `1ff3c26` (base `2d08e6b`)

- **Date:** 2026-09-17
- **Verdict:** **APPROVE** — blocking finding B1 closed; no remaining blocking findings.

## B1 closed (verified independently)

| Check | Result |
|---|---|
| `VERSION` | `0.81.0` (was `0.80.0`) |
| `CHANGELOG.md` `## [0.81.0] — 2026-09-17` | present, above `0.80.0` |
| Explicit **inverted reclaim contract** recorded | **yes** — "Deselecting `codex` from a `codex,opencode` selection no longer deletes the pristine shared units: OpenCode still reads them, and they must survive … previously the surface was reclaimed out from under the remaining claimant — ADR-0003's silent-destructive direction. Reclamation now runs only when the last of `{codex, opencode}` leaves, in either deselect order" |
| Claiming set / adapter / gate recorded | yes (three further bullets: `{codex, opencode}`; host-neutral `$sdd-*`+`/sdd-*`, no `/skills`; `sdd-fix-parallel` body precondition) |
| Pinned literal synced | `tests/test_codex_native.sh:208` → `=='0.81.0'` |
| Stale `0.80.0` references | none (repo-wide grep excluding fixtures: only historical CHANGELOG prose "pre-0.80.0 installer"/"0.80.0 run" and the `## [0.80.0]` heading — correct to leave) |

## Regression + scope

- `./init.sh` → **exit 0**.
- `sh tools/run-tests.sh` → **`all 47 suites passed (/usr/bin/sh [GNU bash, version 5.3.15(1)-release], --jobs 8)`**, exit 0. (Same bash-vs-dash environment caveat as round 1; unchanged.)
- Feature commits `2d08e6b` + `1ff3c26` touch **no** `.opencode/`, `opencode.json`, `state/tasks.json`, `gen_opencode_json`, `gen_oc_agent`, `self_install`, or `HARNESS_SDD_CMDS`. `state/tasks.json` appears in `main..HEAD` only via the human-gate chore commit `6950cdd` (status flip), as accepted in round 1.
- `--self` drift still clean: `diff -r .agents/skills` and `.claude/.glue-manifest` → IDENTICAL.

## Non-blocking items — disposition

- Named in round 1 and addressed: `E31-F01.tests.md` R1–R6 statuses now **✅**; the OpenCode
  behavioral bullet now correctly distinguishes the `source='command'` base commands from the
  skill-served `sdd-fix-parallel`.
- `harness-install.sh:6645/6650/6674` residual "selected Codex install" warnings: **left
  untouched and explicitly recorded as a follow-up** in `progress/E31-F01-builder.md:82-85,
  111-112`. Acceptable — outside R4's specified scope, tracked, not blocking.
- Spec R6 wording ambiguity remains (unchanged, non-blocking, resolved by the plan).

## Change-size decision

Tier **`ok`** (production 56 lines / 4 files; docs/specs 458 lines; budget advise >1500/25,
escalate >3000/50). No split or override required; the docs/spec growth is the feature's own
four-file spec plus its required CHANGELOG/spec/test-contract records. Not a factor.

## Round-1 mutation evidence still holds

No code paths under test changed in `1ff3c26` (the commit is `VERSION`, `CHANGELOG.md`,
`progress/`, `E31-F01.tests.md`, and the one version literal). The seven round-1 mutants
(R1–R6, both reclaim-branch gates) were applied to the same `harness-install.sh` bytes now
present at `HEAD`, so their kills remain valid.

**Remaining blocking findings: none.**
