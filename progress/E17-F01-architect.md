# Architect — E17-F01 spec decisions

Spec written 2026-07-26 into
`specs/epics/E17-model-routing/F01-per-role-model-selection/` (4 files, R1–R25).

Inputs used: `progress/inbox/E17-F01.md` (binding), `progress/E17-F01-scout.md`,
`progress/E17-F01-cli-model-surfaces.md`, `specs/adr/0001-*.md`, `specs/_templates/`.

## Architecture alignment

`specs/architecture.md` does not exist in this repo — recorded as absent in the spec
rather than omitted silently (graceful degradation per `agents/architect.md`). The ADR
set **is** present, so the section is written with **`ADRs touched: none`**: ADR-0001
governs `next()` selection and this feature touches only installer glue + config.

## The five decisions that carry the feature

1. **`inherit` compiles to key omission on all five front-ends.** The literal string is
   never written. It is an error on OpenCode, unknown on Codex, and "key absent" already
   means "inherit" everywhere. One rule, no special cases — and it makes the
   byte-identity invariant (R11) fall out for free.

2. **Config is one level deep under `models:`, with dotted pin keys.** Roles sit directly
   under `models:` (`models.architect: reasoning`); pins are
   `models.pin.<front-end>.<tier>`. Chosen because the repo has no YAML parser and
   nothing reads two-level-nested keys — this keeps every read on the proven
   `_cfg_telemetry_log` awk shape. It also means a future `builder-heavy` (E17-F02) is
   one new line, **no config migration**.

3. **Built-in tier table uses floating vendor aliases only** (`opus`/`sonnet`/`haiku`,
   `pro`/`flash`). Codex and OpenCode have no floating alias, so an unpinned tier there
   resolves to **omission plus one info line** naming the `pin.` key. The harness ships
   no frozen model id, per the brief.

4. **Codex/gemini scope decision — see below.**

5. **Validation:** unknown tier ⇒ warn + inherit + exit 0 (forward compatibility with a
   newer config on an older installer); pins written verbatim, unvalidated — with one
   exception, an `opencode` pin lacking `/` is dropped with a warning, because that is
   the single failure mode research proved *aborts the operator's run*.

## Scope decision on codex and gemini

**F01 creates new native per-role artifacts for both, project-local and conditional.**

- `gemini` → `.gemini/agents/<role>.md`. Gemini's `--model`/`/model` is documented as
  *not* reaching sub-agents, so frontmatter is the only lever; a session-level fallback
  would be provably ineffective.
- `codex` → `.codex/agents/<role>.toml` **inside `$TARGET`**, never `$CODEX_HOME`. The
  existing global prompts are safe to share only because their bodies are
  target-independent; a model stamp is target-*dependent*, so a global write would let
  target A silently retune target B. Project-local also keeps deselection inside the
  pristine-compare machinery. Accepted risk: project-local `.codex/agents/` discovery is
  unconfirmed — if wrong, the file is inert, which is strictly better than a harmful
  global write.
- Both trees are created **only when at least one role resolves to a concrete value**
  (R17), so an unconfigured target stays byte-identical to today.

## `opencode.json` never-rewritten conflict — resolved

Create-if-absent stays. An existing `opencode.json` is regenerated **only** when it is
byte-identical to `.harness/.opencode.stamp` (a byte copy of the last body the installer
generated, written only when that body carried ≥1 model key) or to a freshly generated
**model-free** body — which covers every pre-E17 target. Anything else is left untouched
with a warning. The stamp file also becomes the deselect reference, which makes
reclamation survive a config change.

## Determinism / deselect trap

`remove_if_pristine` regenerates its reference at deselect time, so R21 (two runs with an
unchanged config produce byte-identical artifacts) is the load-bearing requirement, with
R22/R23 covering reclamation and user-edit preservation. Every generator is a hoisted
function shared by both paths; the plan's DO-NOT-TOUCH list forbids duplicating emission
logic into the deselect branch. Known accepted degradation (documented in the plan): if
the operator edits `models:` and deselects *without* re-installing in between, the file
is left in place with the existing "differs from the generated stamp" warning.

## Split recommendation (for the human)

**Recommended: split.** Seam is R15–R17 (the two brand-new artifact types) versus
everything else. F01b adds no config key and no resolver change, so completing it later
needs **no config migration**. Tasks are ordered so T14–T18 lift out whole. If the human
prefers one shot, the spec is complete and buildable as written.

## Other resolved open questions from the brief

- **Role coverage: 6, not 5** — `doc-critic` is included, because the installer already
  emits it in `HARNESS_CLAUDE_SHIMS`, `ag_personas` and `gen_opencode_json`; excluding it
  would create an asymmetric gap.
- **Orchestrator stampability** — stamped, with an explicit documented caveat that it
  applies only where the orchestrator is a spawned sub-agent (Claude) or the configured
  primary (OpenCode); the host session's model is chosen by how the operator launched it.
- **E09-F02 local overrides** — explicitly out of scope, listed in the spec.
- **Antigravity `agy >= 1.1.5` floor** — documented, not probed; the installer never
  shells out to a front-end CLI.

## Doc-critic checkpoint

**Skipped — no Task/sub-agent tool was available in this Architect session**, so
`agents/doc-critic.md` could not be spawned at the `target-type=feature-spec` checkpoint.
Recorded here per the role file's best-effort clause. The Orchestrator may run the
doc-critic against the four files before the human gate if it wants that pass.
