# E31 spec revalidation — what is already built

- **Date:** 2026-09-17
- **Role:** Scout-style read-only audit (requested before Builder approval)
- **Scope:** `specs/epics/E31-opencode-first-class/F01-shared-skill-surface/E31-F01.*` and
  `F02-source-host-parity/E31-F02.*` against the current tree at `main` (`bbc9560`).
- **Method:** grep/read of `harness-install.sh`, the tests, `.gitignore`, `docs/`, ADR-0003,
  plus the two throwaway-target installs and `opencode serve` probes from the epic Notes.
- **Verdict:** the specs are accurate; **the two features are almost entirely unbuilt**. Large
  parts of the underlying *target* machinery they lean on already exist and must be reused,
  not re-implemented.

## F01 — shared skill surface

| R-id | Requirement | Status | Evidence |
|---|---|---|---|
| R1 | opencode-only selection installs the shared skill units | **Not built** | `skill_unit_claimed()` → `agent_selected codex` (`harness-install.sh:6519-6521`); a `--agents=opencode` target produced no `.agents/skills/` (verified) |
| R2 | codex remains, opencode deselected ⇒ units survive | **Partial (regression lock)** | Holds today only *because* opencode is not a claimant; no mixed-claimant logic exists |
| R3 | last claimant deselected ⇒ pristine units reclaimed | **Partial** | codex-only reclaim works (`:7087`); no "last claimant" computation |
| R4 | host-neutral adapter (Codex `$sdd-*` + OpenCode `/sdd-*`, no `/skills`) | **Not built** | Codex-only literal at `gen_skill_body` (`:6535`) |
| R5 | shared `sdd-fix-parallel` self-gates in OpenCode | **Not built** | Shared unit written unconditionally (`:6781`); leak reproduced in a fresh `codex,opencode` target |
| R6 | codex-only bytes/behavior unchanged | **Not built as a guard** | Trivially true at baseline; no assertion pins it |

## F02 — source `--self` OpenCode glue

| R-id | Requirement | Status | Evidence |
|---|---|---|---|
| R1 | `--self` regenerates `opencode.json`, `.opencode/command/*`, `.opencode/agent/pr-fixer.md` | **Not built** | `self_install` rejects opencode (`:7283`, `:7292`); the stage loop (`:7317`) has no OpenCode paths |
| R2 | source `opencode.json` defines `builder-heavy` | **Not built** | Committed `opencode.json` has no `builder-heavy`; only `gen_opencode_json` emits it, for targets (`:4340`) |
| R3 | `pr-fixer` follows `pr_loop.enabled` via `--self` | **Partial** | Target emitter exists (`gen_oc_agent`, gated `:6512`); `--self` path absent |
| R4 | `sdd-test-concurrency` in source; no gated command/marker | **Partial** | Target generation exists (`:6475`); source/self absent; `.opencode-parallel` already classified local-only (`tools/harness-owned-paths.sh:157`) |
| R5 | self reconciler owns the OpenCode paths | **Not built** | `self_reconcile` `allowed()` (`:7218-7224`) whitelists only `.claude/`, `.codex/`, `.agents/skills/sdd-*`, `.escalation-arming` |
| R6 | E26-F02 drift gate covers OpenCode source glue | **Not built** | `glue_diff` compares only `.claude/`, `.codex/`, `.agents/skills`, `.escalation-arming` (`tests/test_self_drift.sh:37-43`) |
| R7 | source-layout output (`["AGENTS.md"]`, `{file:./agents/*}`) | **Partial** | Committed file already has this shape *by hand*; nothing generates or enforces it |
| R8 | host test asserts `/sdd-*` + `builder-heavy` resolve from source | **Partial** | `tests/test_agents_host.sh` mentions opencode 43× but only for host detection/toggles; no command/agent-resolution assertion |

## Already built (reuse, do not re-implement)

- Target `opencode.json` emitter **with `builder-heavy`** — `gen_opencode_json` (`:4324-4348`).
- Target `.opencode/command/*.md` emission + concurrency gate — `:6470-6502`.
- Target file-based `pr-fixer` sub-agent emitter — `gen_oc_agent` (`:4330-4345` region), gated `:6512`.
- `/sdd-test-concurrency` command body and marker handling — `:5401-5440`, `:4280-4295`.
- Target-side drift coverage of `.opencode/command/`, `.opencode/agent/pr-fixer.md`, `opencode.json`
  — `tools/harness-owned-paths.sh:76-79`.
- OpenCode host detection / selection toggles — `tests/test_agents_host.sh` (43 opencode hits).

## Spec gaps found (fix before/at build)

1. **Installer's own user-facing text still says Codex-only.** The §5d success line says the
   units are "read by Codex" (`:6786`), and the install manifest describes `.agents/skills` as
   Codex glue (`:4089-4102`). F01's plan lists `docs/` but not these in-script strings; add them
   to F01 tasks (R4) or they will contradict the new host-neutral unit.
2. **F02 should say explicitly that target emitters already exist.** Its R1 reads as if
   `gen_opencode_json`/`gen_oc_agent` are to be written; they are not. The work is `--self`
   wiring, ownership, and gates. A Builder reading only the spec could duplicate them.
3. **F01's R2/R6 are regression locks, not new behavior** (both hold trivially today). Keep
   them, but the Builder must not "implement" them as new logic — the tests pin them.
4. **Golden-comparison suite.** `tests/test_codex_native.sh` (see `:189`) compares generated
   `.opencode/command/*` and `.agents/skills` bytes against a frozen fixture; the F01 adapter
   change will require its normalization to be updated in the same PR. F01's plan names this
   file but not the golden fixture — add it to tasks.
5. **OpenCode model harvest (F02 open question).** `self_model` in `--self` harvests Claude and
   Codex tiers only (`:1882`); the source repo has no OpenCode pin today, so R2 is met by the
   role existing. If the role set or a pin changes, this is the seam — already noted.

## Recommendation

- Specs are sound; no re-drill needed. Approve F01 as `in-progress` after applying gap (1) and
  (4) to its tasks; treat F02 as a wiring feature over existing emitters and note gap (2).
- Do not build F01 and F02 in one PR (both edit `harness-install.sh`); F01 first, per the epic.
- No code was changed by this audit; `E31-F01` remains `spec-ready` (parked at the human gate).
