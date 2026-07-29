---
feature: E23-F01
role: reviewer
round: 6
verdict: rejected
date: 2026-07-29
---

# E23-F01 review round 6

Round 6 correctly reconciles mixed symlinked stamp leaves and restores Gemini's
pre-feature live-generation behavior. One Important ownership-boundary case remains.

`codex_skill_stamp_tree_is_symlinked()` currently treats the nested
`.harness/.codex-skills/<command>/agents/` directory as unsafe for the entire skill
unit. That directory is a component only of the policy stamp, not of the sibling
`SKILL.md` stamp. If `agents/` is a symlink, gate-off or deselection preserves the
whole unit and leaves a regular, byte-matching `SKILL.md` discoverable.

Required fix:

- keep `.harness/.codex-skills/` and `<command>/` as common unit components;
- treat `<command>/agents/` safety as specific to the policy leaf;
- preserve the unsafe policy stamp, live policy, and external target;
- independently reclaim a safely owned live `SKILL.md` and regular stamp;
- add both gate-off and deselection regressions for the nested directory symlink.

All other round-6 checks passed, including explicit-only policy retention for a
surviving skill, Gemini output equivalence, focused suites, POSIX syntax, diff
hygiene, and change-size tier `ok`.
