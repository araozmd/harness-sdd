---
id: E29
title: Three supported front ends and native Codex workflow
status: done
---

# E29 — Three supported front ends and native Codex workflow

User-approved on 2026-09-14 after the documentation baseline in PR #184, tagged
v0.78.1. Retain Claude Code first, Codex second, and OpenCode third. Remove Gemini
and Antigravity, delete source GEMINI.md, regenerate canonical AGENTS.md, and enable
the complete native Codex SDD workflow. OpenCode improvements and PR #183's external
Builder-delegate trial remain separate work.

| Feature | Scope |
|---|---|
| E29-F01 | Safe retired-front-end migration, native Codex source generation and PR-fixer, refreshed entrypoint and documentation |

The user approved the four-file E29-F01 proposal and autonomous implementation,
testing, and review. The proposal preserves human approval gates in the shipped
harness; autonomy here applies to this feature only.
