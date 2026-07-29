---
feature: E23-F01
role: reviewer
round: 5
verdict: rejected
date: 2026-07-29
---

# E23-F01 review round 5

The ownership-stamp symlink hardening closes external traversal, but two blocking
spec regressions remain.

## Mixed safe/unsafe Codex stamp leaves

`codex_skill_stamp_is_symlinked()` treats either symlinked stamp leaf as making the
whole unit unsafe. During PR-loop gate-off, a symlinked policy stamp therefore
prevents independent reclamation of a regular, byte-matching `SKILL.md` and its
regular stamp. The pristine gated skill remains discoverable, violating R2 and the
round-2 independent-reclamation requirement.

Required fix:

- assess the `SKILL.md` and `agents/openai.yaml` stamp leaves independently;
- preserve an unsafe stamp and its corresponding live artifact;
- still reclaim the other live artifact when its own regular stamp proves ownership;
- keep external symlink targets byte-identical;
- add a mixed-leaf gate-off regression.

## Gemini behavior changed outside scope

Round 5 also made selected Gemini role generation conditional on model-stamp-tree
safety. R9 and the plan's DO-NOT-TOUCH list require Gemini generated semantics to
remain byte-identical to pre-feature behavior.

Required fix:

- restore Gemini live-role generation to its pre-feature behavior;
- reject unsafe Gemini stamp writes without suppressing the existing live-artifact
  generation path;
- add a regression proving selected Gemini output bytes match the pre-feature
  baseline even when its stamp tree is unsafe.

Focused suites passed, but their coverage did not exercise either mixed state.
