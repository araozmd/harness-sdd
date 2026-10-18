---
id: E35
title: "pi is a claimed, first-class front end"
status: done                 # draft → planned → in-progress → done (pending = legacy alias of planned; rollup of its features)
owner: araozmd
---

# Epic E35 — pi is a claimed, first-class front end

## Business brief

[pi](https://pi.dev) (`@earendil-works/pi-coding-agent`, 1.x) is a minimal, extensible
terminal coding agent. The harness supports claude, codex, opencode and antigravity; pi is
served today only **by accident**: it reads `AGENTS.md`, and — when the project is trusted
and the `read` tool is on — it discovers the shared `.agents/skills/sdd-*` units that the
codex/opencode/antigravity claimants write. Nothing specifies, tests, or owns that path, and
the parts that make the harness more than one prompt are missing on pi:

1. **No front-end key.** `AGENT_KEYS` (`harness-install.sh:1651`) has no `pi`, so
   `--agents=pi` dies; pi only receives skills as a side effect of another selection, and a
   pi-only target gets nothing.
2. **No role isolation.** pi core deliberately has no sub-agents. The Orchestrator →
   Architect → Builder → Reviewer loop needs each role in a clean context with its own
   model and tool allowlist; on pi that collapses into one context, which defeats the
   independent-Reviewer gate.
3. **No model routing.** ADR-0002 tiers (`reasoning|standard|cheap`, plus the
   `builder-heavy` escalation) do not resolve for pi; pi's native knobs are a
   `provider/id` model and a `thinking` level (`off…max`), which map onto the tier ladder
   the way codex's `model_reasoning_effort` does.
4. **No environment validation.** Project-local pi resources (skills, prompts, agents,
   packages) are **silently skipped** in headless mode unless the project is trusted, and
   the community sub-agent backend must be installed and pinned — nothing tells the user.

## Verified facts (2026-10-13, pi 1.2.0, this repository)

- **Host marker.** A `pi -p` session's shell tool sees `AI_AGENT=pi`,
  `PI_CODING_AGENT=true`, `PI_SESSION_ID=<uuid>`, `PI_PROVIDER`, `PI_MODEL`,
  `PI_REASONING_LEVEL` (live probe; `docs/environment-variables.md`).
- **Non-interactive entry.** `pi -p` (`--print`) runs once and exits non-zero on
  `stopReason` error/aborted/length; `--mode json` streams JSONL. Headless runs must pass
  `-a` (`--approve`) or project resources are skipped (`docs/security.md#project-trust`).
- **Skills.** Project `.agents/skills/` is discovered only when trusted; skills are listed
  only when the `read` tool is available (live probe: listed with `-a --tools read`, NONE
  with `-na`).
- **Prompt templates.** `.pi/prompts/<name>.md` → `/<name>`; `description` frontmatter;
  `$ARGUMENTS`/`$@`/`$1` substitution; trust-gated (`docs/prompt-templates.md`).
- **Sub-agents.** pi core has none (README). The de-facto backend is the community package
  `pi-subagents` (npm, MIT, 0.78.0 = latest on 2026-10-13, the first release that works on
  pi 1.2.0; releases every 1–5 days → must be pinned). Agents live in
  `.pi/agents/**/*.md` with frontmatter `name, description, model, thinking, tools,
  excludeTools, systemPromptMode, inheritProjectContext, inheritSkills, …`. Its legacy
  `.agents/**/*.md` scan explicitly skips `.agents/skills/**`, so the shared skill units are
  not mistaken for agents. Its runtime state shares `~/.pi/agent/extensions/subagent/` with
  pi's own *example* `subagent` extension, which registers a conflicting `subagent` tool.

## Success criteria (epic level)

- `--agents=pi` installs a pi-only target that can run `/sdd-next`, `/sdd-new`,
  `/sdd-plan`, `/sdd-drill`, `/sdd-fix` (and `/sdd-pr-loop` when gated on) natively.
- Role hand-offs on pi run in isolated child contexts with per-role model, thinking level
  and tool allowlist — via the pinned `pi-subagents` backend when present, and via a
  shell-only `pi -p` dispatcher when it is not (the harness never hard-depends on a 0.x
  third-party package).
- ADR-0002 tiers and the `builder-heavy` escalation resolve on pi (`pin.pi.<tier>` +
  tier→`thinking` ladder) and arm/disarm exactly like codex.
- The installer validates the pi environment read-only by default and installs the pinned
  backend **only with explicit approval** (interactive yes or an explicit flag); it never
  touches `~/.pi/agent` on its own.
- Zero regressions for claude, codex, opencode and antigravity.

## Features

| id | title | status | sdd | depends_on |
|---|---|---|---|---|
| F01 | pi front-end key: shared-skill claim, `.pi/prompts` commands, host marker, worker entry, docs | done | true | — |
| F02 | pi role sub-agents: `.pi/agents/<role>.md` for pi-subagents + `tools/pi-dispatch.sh` fallback, `--self` | done | true | F01 |
| F03 | pi model routing: `pin.pi.<tier>`, tier→thinking ladder, escalation arming | done | true | F02 |
| F04 | pi environment preflight + approval-gated pinned `pi-subagents` install | done | true | F02 |
| F05 | integrity-pin the `pi-subagents` install: pre-install `npmCommand`/lockfile guards + post-install sha512 and tree digest | done | true | F04 |

## Notes

- Decision record: ADR-0007 (sub-agent backend = pinned `pi-subagents`, `pi -p`
  fallback). Aligns with ADR-0002 (tiers), ADR-0003 (pi is a shared-skill claimant),
  ADR-0004 (resolved body pointers), ADR-0005 (`--self`-only surfaces).
- Precedents: E31 (OpenCode first-class, full model) and E33 (Antigravity, shared skills
  + dispatch prose). pi follows the **E31 full model**.
- The user authorized an autonomous build of this epic on 2026-10-13
  ("build autonomously the PI as first class frontend … I'm ok with your plan"), so every
  feature is stamped `autonomous: true`.
