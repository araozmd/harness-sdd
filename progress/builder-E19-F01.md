---
feature: E19-F01
role: builder
date: 2026-07-28
branch: feat/E19-F01-agents-host
status: ready-for-review
---

# Builder hand-off — E19-F01 (host detection + `--agents=host`)

All 28 tasks in `E19-F01.tasks.md` are ticked. `./init.sh` is green and the FULL
`verification.test_command` chain (25 suites, including the new one) exits 0.

## What shipped

| File | Change |
|---|---|
| `harness-install.sh` | `HOST_MARKERS` table + rules/provenance header; `marker_present`; `detect_host`; `precheck_baseline` (extraction); `override_host_kind`; the `host` branch in `resolve_agents`; `--print-agents`; header comment + `manifest.txt` wording |
| `tests/test_agents_host.sh` | **new** — 27 test functions covering R1–R31 |
| `tests/test_install.sh` | **+22 lines, −0** — `--agents=host` end-to-end + "`host` never persisted" |
| `harness.config.yaml` | `&& sh tests/test_agents_host.sh` appended to `verification.test_command` |
| `docs/INSTALL.md` | new "Host detection — `--agents=host`" section (markers table, `HARNESS_HOST_AGENT`, `--print-agents`, both fallbacks + the asymmetry rationale) |
| `README.md` | `--agents=host` / `--print-agents` in the agent-selection block |
| `VERSION` / `CHANGELOG.md` | `0.39.0` → `0.40.0` + matching entry |

Nothing on the DO-NOT-TOUCH list was modified. Audited by diff: the ONLY deletions in
`harness-install.sh` are the six lines of the inline interactive baseline that moved into
`precheck_baseline`, plus two reflowed comment lines. `AGENT_KEYS`, `validate_csv`'s token
grammar, the `PRIOR_AGENTS` block (with its `grep -vx codex` exclusion) and every
§7/§7b / ledger symbol are byte-identical.

## Additivity (R22) — the load-bearing invariant

`tests/test_install.sh` was green before any code was written (T1 baseline, 29 `ok` lines)
and is green now with **zero edits to any pre-existing assertion** (`git diff --numstat`:
`22 0`). The hard-stop rule never fired. Structurally: the `host` branch is unreachable
unless the caller names `host`, and `--print-agents` short-circuits before `install_one`.

## Marker rows — verified, and one deliberately omitted

The plan's `comm -13` procedure was actually executed (plain login shell vs. a shell each
CLI spawned). Results, all recorded in the table's PROVENANCE comment:

| Key | Marker(s) shipped | Verified on |
|---|---|---|
| `claude` | `CLAUDECODE`, `CLAUDE_CODE_ENTRYPOINT` | Claude Code 2.1.220 |
| `codex` | `CODEX_THREAD_ID` | codex-cli 0.145.0 (`codex exec`) |
| `opencode` | `OPENCODE`, `OPENCODE_PID` | opencode 1.18.5 (`opencode run`) |
| `antigravity` | `ANTIGRAVITY_AGENT`, `ANTIGRAVITY_CONVERSATION_ID` | agy 1.1.7 (`agy -p`) |
| `gemini` | **no row — undetectable** | gemini CLI not installed ⇒ nothing observable |

Deliberately rejected candidates: `CODEX_SANDBOX` / `CODEX_SANDBOX_NETWORK_DISABLED`
(vanish with the sandbox off — re-checked with `--dangerously-bypass-approvals-and-sandbox`
under a pty, where `CODEX_THREAD_ID` survived and they did not); `CODEX_CI` (a mode flag);
`AGENT=1` from opencode (names no front-end); every `*_API_KEY` and `CODEX_HOME` (R6 —
`CODEX_HOME` was confirmed *unset* by codex and *set* by the test suite, exactly the trap
the spec names). `GEMINI_CLI` never appeared in the `agy` delta, so the feared
gemini/antigravity collision does not arise from these names.

Honest caveat, also in the source comment: codex/opencode/antigravity were exercised
through each CLI's non-interactive entrypoint. If an interactive TUI turns out not to
export the same name, that front-end is merely undetected there — which degrades to the
fallback, i.e. today's behavior. The failure mode is inert.

Incidental confirmation of R5's premise: every nested CLI run inherited `CLAUDECODE=1`
from the outer session, so a nested install genuinely sees two front-ends' markers and is
correctly reported as undetected rather than tie-broken.

## Deviations from the spec

None behavioral. Two notes for the Reviewer:

1. The spec/plan expected "shipping with one row is fine"; four rows ship because the
   verification procedure succeeded for four CLIs. This *strengthens* R5 coverage — the
   ambiguity test uses two real shipped rows (`CLAUDECODE` + `OPENCODE`) instead of the
   `HARNESS_HOST_AGENT` fallback the `.tests.md` sketch allowed for a one-row table.
2. `override_host_kind` is one helper more than the plan's symbol table lists. It is the
   pre-`validate_csv` classifier the plan describes in prose (R16); factoring it out keeps
   `resolve_agents` readable and makes "`host` never enters `validate_csv`" inspectable.

## Verification output

`./init.sh` → `✅ environment ready — agents may proceed` (exit 0).

Full `verification.test_command` chain → `CHAIN_EXIT=0`, every suite reporting its own
"All … passed." line, including `All install tests passed.` and
`All agents-host tests passed.` (27 `ok` lines in the new suite, R1–R31).

## Not done by design

Status left at `in-progress`; no PR opened. The Orchestrator owns the move to `in-review`.
The `.tests.md` "Reviewer, by hand" behavioral checks (running `--print-agents` from a real
CLI session and from a plain terminal) are still the Reviewer's.

---

# Builder follow-up — review round 1 (REJECT → fixed)

Reviewer verdict `progress/review-E19-F01.md`: one blocking defect (**B1**, test rigor) plus
non-blocking N1–N8. B1, N1, N5 and N2 are fixed on this branch. Nothing in
`harness-install.sh`'s *behavior* changed — the only installer edit is the PROVENANCE
comment block, which is new-in-this-feature text.

## B1 — R8's test now bites

The old check asserted only that the **agent-key name** appeared somewhere in the
provenance block. Two problems the Reviewer proved: `gemini` already appeared there (in the
note saying gemini has *no* verified marker), and variable names were never inspected at
all.

Two changes, in `tests/test_agents_host.sh`:

1. **The comment block was restructured so evidence is per-key.** Each entry now names only
   the variables its own row ships; the rejected candidates (`CODEX_SANDBOX*`, `CODEX_CI`,
   `AGENT`, `GEMINI_CLI`, `*_API_KEY`, `CODEX_HOME`) moved to a separate **REJECTED
   CANDIDATES** section, so a negative mention can no longer be mistaken for evidence. The
   format is declared load-bearing in the comment itself, next to a pointer at the test.
2. **New `prov_entry <key>` parser + a rewritten `test_host_marker_rows_documented`.** For
   every row: the key's own entry must exist, must carry a version-shaped token
   (`[0-9]+\.[0-9]+`), and **every variable name on that row** must appear (word-matched)
   inside *that key's* entry. The loop reads from a file, not a pipe, so `fail` exits the
   suite instead of a subshell.

### Mutation proof (real output)

```
===== MUTATION 1: 'gemini GEMINI_CLI' row, no new provenance =====
SUITE_EXIT=1
FAIL: R8: the PROVENANCE entry for 'gemini' records no CLI version — R8 requires the CLI and version it was observed on

===== MUTATION 2: append MADE_UP_VAR to the antigravity row =====
SUITE_EXIT=1
FAIL: R8: marker 'MADE_UP_VAR' on row 'antigravity' is not recorded in that key's PROVENANCE entry — an unverified marker must never ship

===== MUTATION 3 (harder): gemini row + a versioned provenance entry that does NOT name GEMINI_CLI =====
SUITE_EXIT=1
FAIL: R8: marker 'GEMINI_CLI' on row 'gemini' is not recorded in that key's PROVENANCE entry — an unverified marker must never ship

===== RESTORED — baseline green again =====
SUITE_EXIT=0
```

Mutation 3 is mine, not the Reviewer's: it closes the obvious next hole (fake a versioned
entry) and proves the two rules are independent.

## N1 — `host_of` no longer reads a crash as "undetected"

It now captures stdout, fails over to `__INSTALLER_EXITED_NONZERO__` on a non-zero exit and
`__NO_HOST_LINE_ON_STDOUT__` when the contract line never appeared, so a negative assertion
fails loudly with the sentinel in its message. R2/R4 messages now print the observed value.

Proof — a mutation that crashes **only on the undetected path**, so every positive
assertion still passes and only the negatives are at risk:

```
===== PRE-FIX host_of under mutation 5 =====
SUITE_EXIT=3
  → NO FAIL from the R2/R4/R6 negatives: a CRASH read as 'undetected' (this is N1)
  (1 ok line, then a bare exit 3 with no diagnostic)

===== FIXED host_of, same mutation =====
SUITE_EXIT=1
FAIL: R2: an empty CLAUDECODE counted as a present marker (got '__INSTALLER_EXITED_NONZERO__')
```

## N2 — `agy` version corrected to what was actually verified

The binary self-updated mid-session (`agy` reported 1.1.7 at the start; the binary on disk
was replaced 7s before the probe wrote its env dump). Rather than guess which build
produced the delta, I **re-ran the probe** on the current build and recorded that:

```
$ agy --version → 1.1.8
ANTIGRAVITY_AGENT=1
ANTIGRAVITY_CONVERSATION_ID=bb162f9c-ba7a-45ec-b6fa-c07919511d6a
ANTIGRAVITY_LS_VERSION=cli-1.1.8
```

`harness-install.sh`, `docs/INSTALL.md` and `CHANGELOG.md` now all say **1.1.8**; no stale
`1.1.7` remains.

## N5 — board drift

`specs/epics/E19-single-cli-default/epic.md` F01 row: `spec-ready` → `in-review`, matching
`state/tasks.json`.

## N3, N4, N7, N8 — deferred per the coordinator, one line each

- **N3** (no TTY case for `--agents=host`): the `host` arm sits inside the override branch
  *before* `[ -t 0 ]`, so it is TTY-independent by construction; the Reviewer confirmed the
  TTY half by hand.
- **N4** (weak proxies in R27/R28/R30): agreed they are shallow; none is the primary guard
  for its requirement.
- **N7** (`precheck_baseline` does not re-validate persisted keys against `AGENT_KEYS`):
  pre-existing semantics, deliberately not changed under a "strictly additive" feature.
- **N8** (`for _dh_t in $_dh_decl` glob-expands `HARNESS_HOST_AGENT='*'`): lands in the R10
  warn-and-continue path; cosmetic only.

## Verification after the fixes

`./init.sh` → exit 0:

```
✅ harness structure intact
✅ TaskStore (local) valid against schema
✅ ADR citations resolve (namespaces: specs/adr)
✅ environment ready — agents may proceed
```

FULL `verification.test_command` chain (25 suites) → **`CHAIN_EXIT=0`**, **583 `ok` lines**,
zero `FAIL`, 21 "All … passed." summaries including `All install tests passed.` and
`All agents-host tests passed.`

Constraints held: `git diff --numstat tests/test_install.sh` = **`22 0`** (still zero
deletions, no pre-existing assertion edited); every installer invocation still goes through
`hrun` under `env -i` with a sandboxed `CODEX_HOME`; no frozen `VERSION` literal; no diff
against `main`. Not committed, not pushed, status untouched.
