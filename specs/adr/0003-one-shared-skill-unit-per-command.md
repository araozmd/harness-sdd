# ADR-0003 — `.agents/skills/<name>/` holds ONE shared unit per command, claimed by every front-end that reads it

- **Status:** accepted (E99-F09 re-spec, 2026-08-03)
- **Date:** 2026-08-03

## Context

Two features independently targeted the same directory:

| | writes | for |
|---|---|---|
| **E23-F01** (merged, PR #88, shipped v0.49.0+) | `.agents/skills/<cmd>/SKILL.md` + `agents/openai.yaml` | **Codex** |
| **E99-F09** (branch `fix/agy-skills` @ `16994a5`, PR #87, unmerged) | `.agents/skills/<cmd>/SKILL.md` | **Antigravity** |

They do not merely sit near each other — they iterate the **same name list**
(`$HARNESS_SDD_CMDS`, plus `$HARNESS_PR_LOOP_CMDS` when the loop gate is on). A target
selecting **both** front-ends would have two writers for every
`.agents/skills/sdd-*/SKILL.md`, and — worse than the overwrite — two *reclaimers*: each
side deletes what it believes it owns, and the pristine-only guard does not save the
other side, because the file genuinely **is** pristine, just pristine for the other
front-end. That is why PR #87 reached fifteen review rounds and was parked rather than
rebased.

**What the research established.** Antigravity's own bundled customization guide
(`~/.gemini/antigravity-cli/builtin/skills/agy-customizations/`) is explicit:

- *Discovery* — "A skill must be structured as a directory within a `skills/` folder
  inside a customization root (e.g., `.agents/skills/`)" (`docs/skills.md`), and the
  workspace customization root is `.agents/` at the repository root
  (`SKILL.md` → *Discovery Locations*).
- *Contract* — `SKILL.md` "must start with a YAML frontmatter block containing the `name`
  and `description` fields" (`docs/skills.md` → *Main Instruction File*). Everything else
  in the directory is optional; `scripts/`, `examples/`, `resources/` and `references/`
  are named as optional siblings, so an unrecognised sibling is inert.
- *Precedence* — skills are keyed by name, and "if there are naming conflicts (e.g., two
  skills with the same name), the higher-priority customization overrides the lower-priority
  one" (`SKILL.md` → *Loading Priority and Precedence*). Two units for one workflow is a
  conflict the system resolves by discarding one, not a supported arrangement.

The decisive observation is that the unit **E23-F01 already writes satisfies that contract
exactly**: `gen_codex_skill` emits `---` / `name: <cmd>` / `description: <cmd's description>` /
`---` followed by the canonical workflow body. Verified against a real install. There is
therefore no Antigravity-shaped unit to migrate *to* — it is already on disk, written by the
Codex path, and only the *gating* is wrong.

Three options were on the table:

1. **Namespace the two apart** (e.g. `.agents/skills/agy-sdd-next/` alongside
   `.agents/skills/sdd-next/`). Removes the write collision, but a target selecting both
   front-ends then advertises two discoverable skills per workflow with byte-identical
   bodies and divergent names, and every future command change must be made twice.
2. **Move Codex somewhere else** and leave `.agents/skills/` to Antigravity — the shape PR
   #87 assumed. E23-F01 is merged and released; relocating it is a breaking layout change
   for every already-upgraded target, and the E99-F09 brief puts it explicitly out of scope.
3. **One shared unit, claimed by both.**

## Decision

`.agents/skills/<cmd>/` is **one harness-owned unit per command, shared by every front-end
that reads that surface**. The claiming set is `{codex, antigravity}`.

- **One generator, one body.** The `SKILL.md` bytes for a command do not depend on which
  claiming front-ends are selected. There is exactly one writer.
- **Install when *any* claimant is selected.** The install gate widens from
  `agent_selected codex` to "any claiming front-end selected".
- **Reclaim when the *last* claimant is deselected.** Deselecting one front-end while
  another claimant remains selected must leave `SKILL.md` in place. The existing
  stamp-and-pristine ownership rules are unchanged; only *when* they are applied changes.
- **The unit is atomic, policy companion included.** `agents/openai.yaml` encodes an
  OpenAI-namespaced policy (`allow_implicit_invocation: false`) that means nothing to
  Antigravity, and the tempting move is to gate it on `codex`. That is wrong: Codex
  discovers repository skills from the directory itself, not from the harness's front-end
  selection, so a `SKILL.md` on disk **without** its companion is an implicitly-invocable
  mutating workflow for anyone who runs Codex in that repo — whether or not `codex` was
  ever selected. The installer already encodes this reasoning in the reclaim direction
  ("when an edited `SKILL.md` survives, retain its policy companion"); this decision makes
  it symmetric. The policy follows the discoverable unit, not the selection. To Antigravity
  the file is an unrecognised optional sibling and therefore inert.
- **The ownership stamp keeps its historical path**, `.harness/.codex-skills/`. Renaming it
  would orphan the ownership proof on every installed target, which does not merely lose
  tidiness: an unproven live unit is treated as *foreign or edited* and is then preserved
  forever, unreclaimable. The name is inaccurate and deliberately so; this ADR is where
  that is on the record.
- **Antigravity's personas do not become skills.** `.agents/agents/*.md` and
  `.agents/workflows/*.md` are **not** customization types in Antigravity's own quick
  reference (Rules, Skills, Plugins, Hooks, MCP Servers). Commands need the Skills surface
  because a workflow must be invocable by name; role prompts do not, because
  `.agents/rules/harness.md` is a recognised Rule and already routes to the canonical role
  bodies under `.harness/agents/`. Whether to *retire* those two unrecognised trees is a
  separate decision with its own migration story, and is not taken here.

## Consequences

- **Easier.** The collision stops being a hazard to design around: there is one writer, so
  no ordering, no last-writer-wins, and no cross-front-end reclaim to defend against. The
  Antigravity work shrinks from a migration to a gating-and-reclaim-scoping change.
- **Easier.** An Antigravity-only target gains discoverable `/sdd-*` commands for the first
  time — today it receives only `.agents/workflows/*.md`, which Antigravity's documented
  discovery does not read.
- **Harder — an existing shipped behavior inverts.** Deselecting `codex` from an
  `antigravity,codex` target currently deletes the pristine skill units, and
  `tests/test_install.sh` asserts exactly that (the `TCD` block). Under this decision the
  units must survive. That assertion is not collateral to be quietly flipped: it is a
  contract change, must be rewritten deliberately, and belongs in `CHANGELOG.md`.
- **Harder — "who claims this unit" becomes a real predicate.** Reclaim can no longer be
  read off the front-end being deselected; it depends on the remaining selection. Every new
  front-end that learns to read `.agents/skills/` must be added to the claiming set, and
  forgetting to do so fails *silently* in the destructive direction (its units get reclaimed
  out from under it). A test that selects one front-end cannot detect this class of bug —
  the both-selected/deselect-one case is the only shape that can.
- **Harder — a misleading path name is now load-bearing.** `.harness/.codex-skills/` stamps
  units that Antigravity may be the sole claimant of. Anyone reading the installer will
  reasonably assume it is Codex-only; the comment at its definition and this ADR are the
  only things preventing a "cleanup" rename that would strand every installed target.
- **Deferred, deliberately.** `.agents/workflows/` and `.agents/agents/` remain installed
  for Antigravity even though its documented discovery does not read them. They are inert,
  not harmful, and removing files from installed targets needs its own reclaim and
  migration decision.
