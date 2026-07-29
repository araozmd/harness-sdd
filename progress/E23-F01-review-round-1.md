---
feature: E23-F01
role: reviewer
round: 1
verdict: rejected
date: 2026-07-29
---

# E23-F01 review round 1

Spec compliance passed R1–R10. Code-quality review rejected the implementation with
four Important findings:

1. Selected installs overwrite pre-existing or edited `.agents/skills/sdd-*` and
   `.codex/agents/*.toml` files before proving harness ownership. Add last-written
   stamps and update only absent, current-generated, or stamp-matching artifacts.
2. Ungated legacy prompts have no cross-target ownership ledger, so byte identity alone
   cannot prove that another pre-0.48 repository no longer relies on them. Preserve
   ownership-unknown ungated prompts; only ledger-proven `sdd-pr-loop` may be reclaimed.
3. Canonical command bodies use the deprecated prompt placeholder `$ARGUMENTS`. Codex
   skills must explicitly define how text accompanying the `$skill` mention maps to that
   canonical term; tests must verify the adapter semantics, not only the literal token.
4. SDD workflows mutate state/code/PRs and formerly required explicit invocation. Add
   `agents/openai.yaml` with `policy.allow_implicit_invocation: false` to every generated
   skill, and reconcile that metadata with the skill as one ownership unit.

Required regression coverage:

- foreign and edited selected-skill/role files survive install/reinstall;
- harness-owned artifacts still update across routing/body changes and reclaim safely;
- ungated legacy prompts are preserved as ownership-unknown;
- ledger-proven legacy `sdd-pr-loop` cleanup still works;
- every installed skill is explicit-only and documents invocation-argument mapping;
- Claude Code, OpenCode, Antigravity, and Gemini byte contracts remain unchanged.
