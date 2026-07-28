---
id: E19
title: "Installer: single-CLI (host) agent default"
status: pending          # draft → planned → in-progress → done (pending = legacy alias of planned; rollup of its features)
owner: araozmd
---

# Epic E19 — Installer: single-CLI (host) agent default

## Business brief
E08 made agent front-ends *selectable*; it did not change what happens when the human
does not choose. On a fresh install the checkbox picker pre-checks **all five** keys
(`AGENT_KEYS="claude gemini opencode antigravity codex"`, `harness-install.sh:334`), and
a non-interactive run with no override stamps all five (`resolve_agents`, :765).

The result is that a user who works in exactly one CLI still gets the other four's glue
littered into their repo — `GEMINI.md`, `opencode.json`, an Antigravity `.agents/` tree,
and global Codex prompts — and reasonably concludes the harness is "multi-CLI by
default". It is a defaults problem, not a missing-capability problem: `--agents=claude`
already produces the right result today, and re-running the installer already reconciles
adds *and* removes.

This epic closes the gap between the sensible default and the correct one by teaching the
installer to resolve the **host** front-end — the CLI the installing session is actually
running in — and to use that as the fresh-install baseline.

It must not become a silent behavior change for automation. When the host cannot be
detected, `host` falls back to **all keys**, preserving today's documented no-TTY
contract exactly; `host` is a best-effort narrowing that never stamps *less* than a
caller expects.

## Success criteria (epic level)
- `--agents=host` / `HARNESS_AGENTS=host` resolves to the front-end the installing
  session is running in, and stamps only that one.
- On a **fresh** install with a detectable host, the interactive picker pre-checks that
  front-end alone; the human can still toggle any other on before confirming.
- An **upgrade** is unaffected: the persisted `.harness/.agents` set remains the
  pre-check baseline, so nobody's existing selection silently narrows.
- When the host is undetectable, `host` resolves to all keys — byte-identical to today's
  no-TTY behavior.
- The `codex` deselection special-case is preserved: its glue lives in a shared,
  cross-target `$CODEX_HOME/prompts`, so host-narrowing must never cause the installer to
  reclaim prompts another harness target owns.
- `AGENTS.md` remains always-written and never gated.

## Success criteria — non-goals
- Detecting the host does **not** imply disabling anything at runtime. The harness is
  already single-CLI at execution time (`execution.builder.backend: in-session`); this
  epic only governs which glue files land on disk.

## Features
| id | title | status | sdd | depends_on |
|---|---|---|---|---|
| F01 | Host detection + explicit `--agents=host` resolution mode | done | true | — |
| F02 | Fresh-install pre-check baseline = the detected host | done | true | E19-F01 |

## Notes
- **`host` is a resolution mode, not a sixth agent key.** It must be accepted by
  `validate_csv` (:519) and consumed by `resolve_agents` (:765) without ever being
  persisted into `.harness/.agents`, which stores concrete keys only. Mixing it into
  `AGENT_KEYS` would leak it into the toggle UI as a selectable row.
- **Detection is inherently heuristic.** Env markers (`CLAUDECODE`, `CODEX_HOME`, and the
  OpenCode/Gemini/Antigravity equivalents) are the obvious signal, but the harness must
  treat a miss as normal, not exceptional — hence the all-keys fallback.
- Ordering: E20-F01 depends on this epic's work because both edit the same installer region
  around the picker; sequencing them avoids a needless conflict.
- **The epic is decomposed into two micro-features so each PR settles in 1–2 review rounds.**
  F01 is deliberately **additive**: it adds detection, the `host` override token,
  `HARNESS_HOST_AGENT` and a `--print-agents` diagnostic, and changes nothing about an install
  that does not name `host`. F02 spends that mechanism on the actual default, in one branch of
  the single `precheck_baseline` helper F01 extracts. The epic's success criteria are met only
  when **both** have merged.
- **Resolved:** `E20-F01`'s dependency was retargeted to `E19-F02`, which is the feature
  that owns the pre-check region E20 extends. Both E20 features have since merged.