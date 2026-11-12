---
epic: E37
date: 2026-11-12
scout: drift-check
---

# Drift check — post E37 rollup (Scout, read-only)

**Completed epic:** E37 "Goldfish spec review: fail-closed readiness lint, paraphrase-back comprehension, living-doc drift" (features E37-F01, E37-F02, E37-F03 all `done`; main at `3678e92`).
**Remaining planning-tier epics checked:** E13 (`draft`), E14 (`draft`). No `planned` or `pending` epics remain in `state/tasks.json`.

## Artifacts compared against

- Range `88c1c94..3678e92`; `git diff --name-status -M` shows only `A` and `M` entries, no `D` or `R` (no path, tool or role was renamed or removed).
- `git log 88c1c94..3678e92 -- specs/adr specs/architecture.md docs/RATIONALE.md`: no ADR changed. `specs/architecture.md` is absent. `docs/RATIONALE.md` gained rows C11, C12, C13 only.
- New or changed tooling: `tools/readiness-check.py` (F01), `tools/drift-report.py` (F03), `agents/doc-critic.md` (F02), `agents/architect.md` (R12 checkpoint), `agents/reviewer.md` (check 9 and `## Accepted trade-offs`), `specs/_templates/feature.spec.md` (F02), `docs/WORKFLOW.md` (`## Living-doc drift report (E37-F03)`), `harness-install.sh`, `README.md`, `VERSION`, `CHANGELOG.md` (0.106.0 to 0.108.0).
- Supersede or obsolete markers: `git diff 88c1c94 3678e92` matches `supersede` only in the new text of the decision-repair wording of `drift-report.py`, not as a `supersedes E0X` or `obsoletes E0X` marker. No marker names E13 or E14.
- Only mention of E13 or E14 in the E37 diff is the `progress/history.md` rollup line (2026-11-12T15:20:47Z) that spawned this check.
- Tool runs (read-only): `python3 -I tools/drift-report.py` wrote `progress/drift/2026-11-12.md`, which I deleted afterwards. `python3 -I tools/readiness-check.py specs/epics/E13-monday` and `.../E14-azure-boards` both exit 2 with "no *.plan.md", because epic directories hold only `epic.md` and no feature plan exists.

## E13 — Monday board integration (`draft`)

**Verdict: still-valid**

- Brief names checked against the tree:
  - `tasks.json`: present (`state/tasks.json`).
  - `/sdd-drill`: present (`.claude/commands/sdd-drill.md`).
  - E11, E12, E10-F03 (mirror and ownership concerns): E11 and E12 are `done`, and E10-F03 is referenced but not seeded. No E37 change touches them.
  - "no-MCP transport", "idempotent reconciliation", "draft / roadmap only": no E37 artifact contradicts these (S1 does not fire).
- Signals:
  - S1 (contradiction): none. E37 changed review gates, not provider or board transport assumptions.
  - S2 (removed or renamed reference): none. The brief names no path, tool or role that E37 removed or renamed.
  - S3 (explicit supersede): none.
- (b) New checkpoints: readiness lint (`*.plan.md`), Architect R12 paraphrase-back, Reviewer check 9 and accepted trade-offs. These bind any future drill output, not the brief. A future E13 feature plan would have to pass `readiness-check.py` (every named path and symbol resolves or is declared `create`) and the paraphrase-back gate. The brief itself specifies no feature artifacts, so this is a constraint on later drilling, not a stale assumption.
- (c) Drift report: `tools/drift-report.py` scans only `specs/product.md`, `specs/architecture.md` (absent) and `specs/adr/**`. It does not read epic briefs, so it does not overlap with E13's `epic.md`. Its output on the current tree is pre-existing (ADR-0003 names nine missing `.agents/...` and `docs/skills.md` paths) and unrelated to E13.

## E14 — Azure Boards integration (`draft`)

**Verdict: still-valid**

- Brief names checked against the tree:
  - `store/board-mirror.md`: present. It still lists `azure-boards` as a stub (`⏳ stub (no-op)`, line 32). E37 did not touch the file.
  - `tasks.json` and the E11/E12/E10-F03 references: as for E13.
  - "no-MCP transport", "Azure DevOps REST API + PAT": no E37 artifact contradicts these.
- Signals:
  - S1 (contradiction): none.
  - S2 (removed or renamed reference): none. `store/board-mirror.md` line 32 and the `azure-boards` stub still match the brief.
  - S3 (explicit supersede): none.
- (b) and (c): the same reasoning as E13. The readiness lint and paraphrase-back gate will apply to any future E14 feature plan, not to the brief. The drift report does not read epic briefs.

## Closing line for the Orchestrator

Both E13 and E14 are **still-valid**; nothing to re-validate was invalidated, and no demotion is warranted. Both stay `draft`, so no flag line is needed. No state change was made, and no `state/tasks.json` edit or epic-brief edit occurred.
