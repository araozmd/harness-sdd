# E07-F01 re-spec research — Antigravity integration surface (2026-06-12)

Gathered by the Orchestrator (web tools) to ground the Architect's re-spec. The
original spec was written from Nov-2025-era sources; Codex r3 (#3404422700, P2) and
this research show the **current (June 2026) convention has likely drifted**. The
Architect has no web access — treat this file as the authoritative input.

## The trigger (Codex r3 P2 #3404422700, harness-install.sh:1079)
> "the role personas are emitted as bare `.agent/agents/*.md` files, but the current
> official Antigravity docs describe discoverable subagent templates as `agents/`
> inside a plugin bundle … not as a top-level `.agent/agents` directory
> (https://www.antigravity.google/docs/plugins). In an Antigravity 2.0 workspace …
> the generated personas will sit on disk but not be registered as Antigravity
> subagents, so the advertised native role delegation does not work despite the
> install test only checking file existence."

## Evidence gathered (CONFLICTING — this is the core finding)

| Source (date/authority) | Workspace dir | Notes |
|---|---|---|
| **Google codelab — Getting Started / Autonomous Pipelines** (official, current 2026) | **`.agents/`** (plural) | Project skills at `<project-root>/.agents/skills/`. Scopes: global `~/.gemini/skills/`, product `~/.gemini/antigravity/skills/`, project `.agents/skills/`. |
| Search snippet (2026) | **`.agents/rules`** (plural) | "Workspace rules live in the `.agents/rules` folder of your workspace or git root." "`.agents/` is a special directory natively recognized by Antigravity." |
| Medium getting-started tutorial (Romin Irani, likely Nov-2025) | **`.agent/`** (singular) | `.agent/rules/`, `.agent/workflows/`, `.agent/skills/`. |
| agentpedia 2026 rules guide | **`.agent/rules/`** (singular) | Mixed; same page elsewhere references `.agents/`. |
| Plugins (`~/.gemini/antigravity-cli/plugins/<name>/`) | global, NOT workspace | Plugins are namespaced bundles (skills, **background subagents**, lint rules, MCP, hooks) staged under the **global** gemini config path, not the repo. |

**Interpretation (Architect to confirm/decide):**
1. **Dir name `.agent/` → `.agents/`.** Strongest current signal (Google's own codelab,
   June 2026) is **`.agents/` (plural)**. The singular `.agent/` in the original spec
   appears to be an early-version (Nov 2025) path that was renamed. If current
   Antigravity scans `.agents/`, our entire glue tree is installed where it is **never
   discovered** — the feature is inert (this is why Codex flagged registration, though
   it rated P2). High-confidence change: **rename `.agent/*` → `.agents/*`** across
   rules/agents/workflows + the GEMINI/entrypoint wiring + tests + manifest + the
   deselect byte-compare logic.
2. **Subagent registration mechanism — UNCONFIRMED.** Two competing models:
   (a) bare `.agents/agents/*.md` persona files are read directly; vs
   (b) subagents must be packaged in a **plugin bundle** (the `~/.gemini/...plugins/<name>/`
   model) to register, with the workspace `.agents/` holding only `rules/`, `skills/`,
   `workflows/`. The docs/plugins page (JS-rendered, not machine-readable here) is the
   cited authority for (b). **The skills/rules/workflows path (`.agents/{rules,skills,workflows}/`)
   is well-attested; the *subagents-as-bare-files* path is NOT.** The re-spec should
   either (i) confirm bare `.agents/agents/` works, or (ii) fall back to the **confirmed**
   primitives only — rules + `description`-gated workflows + `progress/` hand-off (the
   original R12 graceful-fallback model) — and NOT assert a bare-file persona
   registration that may not exist, mirroring how the original spec refused to
   fabricate an isolated-spawn primitive.
3. **Skills surface (`.agents/skills/`) is newly attested** and was not in the original
   spec — the Architect may consider whether a harness skill belongs there, but that is
   additive and should not expand scope unless trivial.

## What is NOT in doubt (keep)
- `GEMINI.md` / root entrypoint: Antigravity natively loads `GEMINI.md`-style rules; the
  r1 fix (write `GEMINI.md` for `gemini || antigravity`) stands regardless of the dir
  rename.
- A workflow registers as a `/<name>` slash command only with a `description:` frontmatter.
- `AGENTS.md` is read (Antigravity v1.20.3+, Mar 2026) — reinforces the source-of-truth pointer.
- The deselect-safety contract (remove only pristine harness-generated files, never user
  files) from the r2 P1 fix stands; it just needs to point at the corrected dir.

## Branch state (work already landed on feat/E07-F01-antigravity-support, PR #31, HELD)
- `50f74a9` r1 P2: GEMINI.md entrypoint for antigravity-only installs (`gemini || antigravity`).
- `17280b7` r2 P1: antigravity deselect removes only pristine `.agent/` glue (byte-compare), + regression test.
- These are sound; the re-spec mainly changes the **target path** (`.agent/`→`.agents/`)
  and decides the **persona-registration model**. The Builder will revise on this same branch.

## Open questions for the human spec-approval gate (re-spec)
1. **Confirm `.agents/` (plural)** as the current scanned workspace dir (rename from `.agent/`).
2. **Persona model:** bare `.agents/agents/*.md` (if confirmed discoverable) vs. confirmed-
   primitives fallback (rules + workflows + `progress/` hand-off, no bare-file personas).
   Recommend the conservative fallback unless bare-file discovery is confirmed.
3. Whether to add a `.agents/skills/` harness skill (additive; optional).

## Citations
- Google codelab (Getting Started): https://codelabs.developers.google.com/getting-started-google-antigravity
- Google codelab (Autonomous Pipelines, agents.md + skills.md): https://codelabs.developers.google.com/autonomous-ai-developer-pipelines-antigravity
- Antigravity docs (Rules & Workflows): https://antigravity.google/docs/rules-workflows
- Antigravity docs (Plugins, cited by Codex): https://www.antigravity.google/docs/plugins
- Antigravity blog (Google I/O 2026 deep dive — subagents/hooks): https://antigravity.google/blog/google-io-2026-feature-deep-dive
