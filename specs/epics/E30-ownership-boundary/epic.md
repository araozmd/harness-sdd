---
id: E30
title: "Body/project ownership boundary: every .harness/ path is either harness-owned (refreshed on upgrade) or project-authored (seeded once, never clobbered) — specs/glossary.md is classified as both, so an upgrade destroys a project's domain glossary"
status: done
owner: araozmd
---

# Epic E30 — Body/project ownership boundary

## Business brief
The installer's central promise is that it can be re-run at any time: the harness body is
refreshed, the project's own content is left alone. `harness-install.sh:59-62` states that
contract in prose — the BODY is "agents, docs, store, tools, templates, init.sh, config,
AGENTS.md"; PROJECT-authored content is "specs/product.md, state/tasks.json, specs/epics,
progress". `specs/glossary.md` appears in **neither** list, yet `HARNESS_BODY_PROSE`
(harness-install.sh:703) puts it in the body, so every upgrade overwrites it.

That is not a theoretical hole. The shipped `specs/glossary.md` is example content for an
unrelated chatbot-handoff domain whose own second line invites the edit — "Add terms as the
project grows" — and `agents/planner.md:51-55` pairs it with `specs/product.md` as the
project's own domain vocabulary, while `docs/SPEC-FORMAT.md:16` lists it as project domain
model. A project follows that instruction and the next upgrade silently deletes the result.
Observed 2026-09-16 in `previta/protocolos`: a 90-line Protocolos domain glossary (commit
`9e08fe0`) was destroyed by a v0.79.0 upgrade run, with no warning and no backup.

The epic is the boundary itself, not one file. `specs/glossary.md` is the instance we have
proof for; the same "documented as customizable, classified as body" shape may hold for
other `HARNESS_BODY_PROSE` members — `docs/CONFIG-LAYERING.md:22` and `docs/INSTALL.md:681`
both describe `specs/_templates/` as something a project resolves locally. F01 fixes the
proven instance; later features audit the rest and make the header's ownership-class list
normative rather than decorative.

## Success criteria (outcomes)
- A project that edits `.harness/specs/glossary.md` still has those edits after the next
  `harness-install.sh` run, with no operator action, no flag, and no backup file to merge.
- A pristine install — one whose glossary is still byte-identical to the shipped example —
  keeps receiving the refreshed example, so the seed is not frozen at install date.
- A fresh install is byte-identical to today's behaviour.
- Every path the installer writes has exactly one documented owner, and the ownership-class
  list in the `harness-install.sh` header agrees with `HARNESS_BODY_PROSE`,
  `docs/INSTALL.md:993` and `docs/UMBRELLA.md:101`.

## Non-goals
- No relocation of `specs/glossary.md`: `agents/planner.md` and `docs/SPEC-FORMAT.md` name
  that path, so moving it in the target would break the role prompts that read it.
- No new config key, flag or prompt to opt into preservation — the ablation doctrine
  (`docs/RATIONALE.md`) says never accrete an option where a rule will do.
- No retroactive recovery of glossaries already destroyed by past upgrades; the fix is
  forward-looking (protocolos' copy is restored from git separately).

## Features
- **E30-F01** — make `specs/glossary.md` seed-once and preserve a project's edits, refreshing
  it only while it is still byte-identical to the shipped example.

## Notes
Sequencing: F01 stands alone and is the proven defect. Candidate follow-ups, to be seeded
only if an audit substantiates them — `specs/_templates/` customization vs refresh; making
the header's ownership-class list normative and test-enforced against `HARNESS_BODY_PROSE`.

Thin children are the open design question F01 must settle: `docs/UMBRELLA.md:101` lists
`specs/glossary.md` among the prose that becomes a **pointer stub** in a thin child. A
project-owned glossary and a pointer stub are contradictory, so F01 must decide whether a
thin child gets its own real glossary or keeps pointing at the coordinator's.
