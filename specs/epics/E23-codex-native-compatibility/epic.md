---
id: E23
title: "Native Codex compatibility"
status: pending
---

# Epic E23 — Native Codex compatibility

## Business brief

The harness's portable SDD lifecycle remains a strong fit for Codex, but its Codex
installation adapter still targets surfaces that current Codex releases no longer
support. In particular, it installs global custom prompts and only emits named
Codex role definitions when a concrete model pin is configured. That leaves the
default inherited-model configuration without the discoverable commands and named
roles that the harness promises.

This epic brings the Codex adapter onto current, repository-local extension
surfaces while retaining the same portable role files, file-based handoffs, human
gate, and Reviewer-owned completion semantics. The change must be isolated to
Codex-owned glue so existing Claude Code, OpenCode, Antigravity, and Gemini
installations continue to behave exactly as before.

## Success criteria

- A current Codex installation exposes every supported SDD workflow through
  repository-local skills.
- The installed project contains usable named Codex role definitions under the
  default inherited-model configuration as well as when explicit model pins exist.
- An upgrade safely reclaims only legacy Codex prompt files known to be pristine
  harness output and preserves user-edited files.
- Regression tests demonstrate that the Claude Code, OpenCode, Antigravity, and
  Gemini adapter outputs are unaffected.
- User-facing installation and workflow documentation accurately describes the
  supported Codex invocation and repository-local artifact layout.

## Features

| id | title | status | sdd | autonomous | depends_on |
|---|---|---|---|---|---|
| F01 | Modern Codex skills and inherited role registration | pending | true | true | — |
