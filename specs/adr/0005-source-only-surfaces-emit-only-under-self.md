# ADR-0005 — Source-only harness surfaces are emitted only by `--self`, never into a target

- **Status:** accepted (E32 drill, 2026-09-25)
- **Date:** 2026-09-25

## Context

E32 adds surfaces that only make sense in the harness's own source repo: `/sdd-triage`
(it triages `harness-feedback` issues filed against `feedback.repo`) and a GitHub Action
that labels those issues. Every existing command is emitted into *every* target, either
unconditionally (`HARNESS_SDD_CMDS`) or behind a target-owned config gate (`pr_loop.enabled`).
A config gate is the wrong tool here. Any target could set it, and a target has no
business triaging the harness's upstream issues. E26-F01 also forbids hand-editing
`.claude/commands/*` in this repo, so the command can't just be a hand-written file.
The installer already has a mode that runs only against the source repo: `SELF_MODE=1`
(`harness-install.sh --self`).

## Decision

A **source-only** command is emitted by the same emitters as every other command
(ADR-0003: one shared unit per command, all front ends), but **only when `SELF_MODE=1`**.
A target install never writes it, and its uninstall and reclaim logic never touches it. The
labeler workflow under `.github/workflows/` is a plain repo file in the source repo. It isn't
part of the installed body, so the installer never emits or ships it.

## Consequences

- Targets can't reach triage, and the source repo's triage glue stays generated and
  drift-gated (E26-F02) like everything else.
- The emitter gains a second gating axis (source vs target) next to the config gates.
  Tests must cover a normal target install to show the command is absent.
- A fork that wants to triage its own feedback runs `--self` in its fork. That's the same
  story as self-hosting today.
