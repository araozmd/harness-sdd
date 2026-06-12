---
feature: E07-F01
role: architect
action: re-spec
date: 2026-06-12
status: spec rewritten, awaiting human spec-approval gate
---
# E07-F01 re-spec — Antigravity integration surface corrected

The 4-file spec was revised in place to correct the integration surface flagged by
Codex r3 P2 (#3404422700) and the Orchestrator's research
(`progress/research-E07-F01-antigravity-surface.md`, the authoritative input). Frontmatter
stays `status: pending`. The Builder works the corrections **on the existing branch**
`feat/E07-F01-antigravity-support` (commits `50f74a9`, `17280b7` already landed).

## The two core decisions

### 1. Workspace dir `.agent/` (singular) → `.agents/` (plural)
**Decided: `.agents/` plural.** Strongest current signal is Google's own June-2026
codelab (project skills at `<root>/.agents/skills/`) + a 2026 snippet stating `.agents/`
is "natively recognized by Antigravity." The singular `.agent/` traces to Nov-2025
tutorials and appears to be an early-version path that was renamed. The entire glue tree,
entrypoint comment, manifest, deselect byte-compare, and tests move to plural. Left as
**Open question 1** for the gate to confirm (if the live IDE still scans `.agent/`, only
the path literals revert; the rest of the re-spec still applies).

### 2. Persona-registration model — resolved honestly
**Decided: confirmed-primitives fallback is the durable model.** The
`.agents/{rules,workflows}/` paths are well-attested; bare `.agents/agents/*.md` personas
are **not confirmed discoverable** (Codex cites a global plugin-bundle model). Mirroring
how the original spec refused to fabricate an isolated-spawn primitive, the re-spec:
- makes R12 the durable working model — the `.agents/rules/` entrypoint rule +
  `description`-gated `.agents/workflows/` slash commands + `.harness/progress/` hand-off;
- demotes the personas (R4/R5) to **best-effort, conditional** — still written (cheap,
  possibly honored) but with **no requirement claiming they register as subagents**;
- strengthens R11 so the install test verifies **shape** (correct plural dir,
  `description`, role resolves to `.harness/agents/*.md`, no forked body via absent
  sentinel, byte-equality to the Claude command), **not** the original file-existence-only
  check Codex flagged.
Plugin-bundle packaging (global `~/.gemini/...plugins/`) is explicitly **out of scope**
here and recorded as a follow-up. Left as **Open question 2** for the gate.

## R-id diff vs. the prior spec
- **Added: R13** — the deselect byte-compare safety contract (pristine-only removal, never
  user files, never `rm -rf`, prune-only-when-empty), promoted from the prior spec's
  prose/`R13`-in-the-installer into a first-class, testable acceptance criterion, now
  pointed at `.agents/`.
- **Changed (behavior unchanged, target path moved `.agent/`→`.agents/`):** R2, R3, R4,
  R5, R6, R7, R8, R9, R11, R12. R4/R5 additionally **relaxed to best-effort** (no
  registration claim); R11 **strengthened** beyond file-existence; R12 reworded to be the
  durable model and to disclaim both a Task-tool spawn and a registered bare-file subagent.
- **Changed (clarified gating, no path move):** R1 (GEMINI.md, shared `gemini ||
  antigravity`), R10 (VERSION stays `0.22.0`; CHANGELOG/manifest prose to `.agents/`).
- **Removed:** none. All original R1–R12 retained.

Full R-id set after re-spec: **R1–R13** (R1–R12 + new R13).

## Recommendation on the persona model
Adopt the **confirmed-primitives fallback** (Open question 2, option a): rely on the
`.agents/rules/` entrypoint + `description`-gated `.agents/workflows/` + `.harness/progress/`
hand-off as the working model; keep bare-file personas only as best-effort artifacts
tested for shape. Do not assert subagent registration and do not pull in the global
plugin-bundle packaging in this feature.

## Open questions for the human gate
1. Confirm `.agents/` (plural) is the current scanned workspace dir (the central rename).
2. Persona model: accept the confirmed-primitives fallback (recommended), OR confirm
   bare-file personas register (then promote R4/R5 to hard requirements with a real
   registration test), OR require plugin-bundle packaging (follow-up feature, out of scope).
3. Add a `.agents/skills/` harness skill now, or defer? (Recommended: defer — additive.)
4. Reuse the shared `GEMINI.md` block for Antigravity (R1), or want a distinct additive note?
5. Ship all five SDD workflows (R6), or a narrower `/sdd-next` + `/sdd-new` set?

## Files revised (all under specs/epics/E07-antigravity/F01-antigravity-support/)
- `F01-antigravity-support.spec.md`
- `F01-antigravity-support.plan.md`
- `F01-antigravity-support.tasks.md`
- `F01-antigravity-support.tests.md`

No production code written. Status not changed (Orchestrator owns it + opens the gate).
