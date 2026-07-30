---
feature: E23-F01
role: architect
date: 2026-07-29
status: spec-drafted
---

# E23-F01 Architect hand-off

## Output

Drafted and refined the four-file spec at:

- `specs/epics/E23-codex-native-compatibility/F01-codex-skill-adapter/codex-skill-adapter.spec.md`
- `specs/epics/E23-codex-native-compatibility/F01-codex-skill-adapter/codex-skill-adapter.plan.md`
- `specs/epics/E23-codex-native-compatibility/F01-codex-skill-adapter/codex-skill-adapter.tasks.md`
- `specs/epics/E23-codex-native-compatibility/F01-codex-skill-adapter/codex-skill-adapter.tests.md`

The final spec has ten requirements (R1–R10), within
`change_size.max_requirements: 12`, and covers repository-local Codex skills,
PR-loop gating and reclamation, legacy prompt migration, always-present selected
Codex roles with optional model keys, non-Codex regression protection, and release
documentation/versioning.

## Architecture input

`specs/architecture.md` is absent. Platform ADR-0001 exists but governs deterministic
task selection and is not touched by this installer-adapter feature, so no ADR
alignment claim was fabricated.

## Doc-critic checkpoint

Target type: `feature-spec`.

The standalone Doc-critic spawn was attempted but could not start because the active
agent thread limit was reached. Per the best-effort contract, the Architect proceeded
with an inline document review plus the Orchestrator's advisory findings.

Findings and fixes applied:

- Traceability had drifted after reducing the first draft from twelve requirements:
  removed all R11/R12 references and remapped tasks, plan rows, and test rows to the
  exact R1–R10 semantics.
- Two legacy-migration references incorrectly pointed to model-routing R7: corrected
  them to legacy-migration R5 in the technical plan and behavioral checks.
- The context described global custom prompts as absolutely “removed”: changed it to
  the precise claim that the surface is deprecated and is not the supported
  project-workflow surface.
- Confirmed the canonical identity and filenames remain E23-F01 and
  `codex-skill-adapter.*`; no E22 path or id appears in the four-file spec.

## Builder boundary

The Builder may change the installer, the five named installer regression suites,
README/installation/harness documentation, generated installer manifest/help text,
CHANGELOG, and VERSION. It must not change portable role semantics, TaskStore/state
contracts, shared command bodies, or the generated behavior of Claude Code, OpenCode,
Antigravity, and Gemini.
