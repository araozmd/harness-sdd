# Antigravity native support — Technical Plan

> Translates the `.spec.md` intent into design. Every decision cites the R-id(s) it
> serves. The implementation mirrors, almost line-for-line, the existing per-tool
> stamping in `harness-install.sh` (the Claude `.claude/` block and the OpenCode
> `.opencode/command/` block) — that is the proven pattern this feature extends.
>
> **Re-spec note.** Most of this design already shipped on
> `feat/E07-F01-antigravity-support` (PR #31, HELD) — see *Branch state* below. This
> revision does NOT rebuild from scratch: it **renames the target dir `.agent/` →
> `.agents/` (plural)** across generation, entrypoint wiring, manifest, the deselect
> byte-compare, and the tests, and it **relaxes the persona requirements to best-effort
> + strengthens the tests beyond file-existence** per the corrected `.spec.md`. The
> Builder works the `.tasks.md` ON THIS SAME BRANCH.

## Branch state (already landed — the Builder revises this, not greenfield)
- **`50f74a9`** (r1 P2) — `GEMINI.md` entrypoint written for `gemini || antigravity`
  installs; shared-entrypoint deselect logic. **Sound; keep** (path-agnostic).
- **`17280b7`** (r2 P1) — antigravity deselect removes only **pristine** `.agent/` glue
  via byte-compare (`remove_if_pristine`, `gen_ag_rule`, `gen_ag_persona`, `ag_personas`),
  + regression tests. **Sound; keep the contract — only the dir literal moves to
  `.agents/`.**
- Both commits currently target `.agent/` (singular). `VERSION` is already `0.22.0` and
  `CHANGELOG.md` already has the `[0.22.0]` Antigravity section — both must be updated to
  say `.agents/` (plural) but the version number does NOT need to change again (still the
  same MINOR capability; the re-spec is a correction within the unreleased feature).

## Stack & dependencies
- Language/framework: POSIX `sh` (the installer is `/bin/sh`, zero dependencies).
  Tests are POSIX `sh` (`tests/test_install.sh`). No new runtime deps.
- New dependencies: none.
- Antigravity integration surface relied upon (see `.spec.md` "Antigravity integration
  surface" — research-grounded, gate-confirmed):
  - native load of root `GEMINI.md` rules (R1),
  - native read of `<workspace>/.agents/{rules,agents,workflows}/*.md` — **plural** (R2/R4/R6),
  - a workflow registers as a `/<name>` slash command **iff** its frontmatter carries a
    `description` (R7),
  - **NOT relied upon:** that bare `.agents/agents/*.md` files register as subagents
    (unconfirmed — R4/R5 are best-effort; the durable model is R12's rules+workflows).

## Design overview
The glue already lives in **one generation block** (`§5c`) inside `install_one()` in
`harness-install.sh`, placed after the OpenCode block (`§5b`) and before the deferred
`CMDDIR` cleanup. It is gated on `agent_selected antigravity`. The workflow bodies are
`cp`'d from the shared `CMDDIR/*.md` command bodies (exactly like OpenCode), so the three
front-ends never drift (R9). Antigravity-specific framing (the `description`-bearing
frontmatter, the persona/rule wrappers) is added around that shared body. The root
`GEMINI.md` pointer is written by `§4 write_pointer` when `gemini || antigravity` (R1).

**The change this revision makes:** every `.agent/` literal in the four hoisted emitters
(`gen_ag_rule`, `gen_ag_persona`, the `§5c` install loop, and the `§7` antigravity-deselect
compare) plus the manifest and tests becomes **`.agents/`** (plural). The persona body
copy/`description` framing is unchanged; only the directory path and the surrounding prose
(R12 "working model" wording in the rule) move/clarify.

## Files to change  (serves: R1–R13)
| File | Change | R-id |
|---|---|---|
| `harness-install.sh` | In the §5c `mkdir -p`, change `"$TARGET/.agent/rules" "$TARGET/.agent/agents" "$TARGET/.agent/workflows"` → **`.agents/`** plural for all three. | R2,R4,R6 |
| `harness-install.sh` | `gen_ag_rule` dest call + the rule's own prose: write to **`.agents/rules/harness.md`**; the rule body references `.agents/agents/` and `.agents/workflows/` (plural) when describing the working model, and states the R12 model (rules + `description`-gated workflows + `.harness/progress/` hand-off; not a Task-tool spawn, not an asserted bare-file subagent registration). No copied role body. | R2,R3,R12 |
| `harness-install.sh` | §5c persona loop: write each persona to **`.agents/agents/<role>.md`** (plural). Body unchanged (defers to `.harness/agents/<role>.md`, `description` frontmatter, init.sh-first + halt, `.harness/progress/` hand-off, no copied body). | R4,R5 |
| `harness-install.sh` | §5c workflow loop: `cp "$CMDDIR/<name>.md"` → **`.agents/workflows/<name>.md`** (plural). Mirror, do not re-author. | R6,R7,R8,R9 |
| `harness-install.sh` | §5c `ok` line: `ok "Antigravity glue (rules + agents + workflows) installed (.agents/)"` (plural). | R12 |
| `harness-install.sh` | §7 antigravity-deselect branch: change every `.agent/...` relpath passed to `remove_if_pristine` to **`.agents/...`** (rule, each persona, each workflow), and the `rmdir` prune targets to `.agents/rules`, `.agents/agents`, `.agents/workflows`, `.agents`. The byte-compare contract (pristine-only removal, never user files, never `rm -rf`) is **unchanged** — only the path moves. | R13 |
| `harness-install.sh` | §3 manifest.txt HARNESS-OWNED list: change the glue line to `.agents/rules/*  .agents/agents/*  .agents/workflows/*  (repo root, regenerated; Antigravity glue)`. | R10 |
| `harness-install.sh` | §4 `write_pointer`/`GEMINI.md` comment that references "the `.agent/rules/harness.md` rule (§5c)": update the path comment to `.agents/rules/harness.md`. (No behavioral change to the shared-GEMINI.md logic from `50f74a9`.) | R1,R12 |
| `tests/test_install.sh` | Antigravity glue assertion group: change every `$T/.agent/...` path to **`$T/.agents/...`** (rule, personas, workflows). Keep/strengthen the **shape** assertions: dir correct, `description` present, persona defers to `.harness/agents/<role>.md`, workflow resolves its role + carries `$ARGUMENTS`, workflow byte-identical to Claude command, and the **canonical-body sentinel is ABSENT** in every glue file (no fork). Do NOT add a bare assertion that personas "register" — test shape only (the R11 fix). | R11 |
| `tests/test_install.sh` | The three deselect/entrypoint regression tests (`antigravity-only writes GEMINI.md`; `antigravity deselect is byte-exact`; `GEMINI.md shared by gemini+antigravity`): change every `.agent/` literal to **`.agents/`**. Keep all assertions; they already exceed file-existence (byte-compare, user-file preservation). | R11,R13 |
| `VERSION` | **No bump needed** — already `0.22.0` for this MINOR capability; the re-spec corrects the unreleased feature. (Reviewer confirms it is still a single MINOR.) | R10 |
| `CHANGELOG.md` | Edit the existing `[0.22.0]` Antigravity section so every `.agent/` reads `.agents/` (plural), and add a clause noting personas are best-effort (durable model = `.agents/rules` entrypoint + `description`-gated `.agents/workflows` + `.harness/progress/` hand-off). | R10 |

## Generation details (Builder guidance, not pinned internals)
- **The change is mechanical + honest-prose.** The bulk is a literal `.agent/` →
  `.agents/` rename in the four hoisted emitters, manifest, and tests. Do it as a
  scoped, reviewed substitution — **not** a blind global sed (the string `.agent` could
  appear elsewhere; only the Antigravity glue paths move). Verify the rule/persona/workflow
  destinations, the `rmdir` prunes, the manifest line, and every test path.
- **Rule body (R2/R3/R12).** Keep it a few lines: source of truth `.harness/AGENTS.md`;
  start as Orchestrator (`.harness/agents/orchestrator.md`); run `.harness/init.sh` first;
  and a "working model (R12)" line stating Antigravity drives the harness through the
  `description`-gated `.agents/workflows/` slash commands + the `.agents/agents/` personas,
  with `.harness/progress/` hand-off — **not** a Task-tool spawn, and **not** an asserted
  bare-file subagent registration. No role body.
- **Persona shape (R4/R5) — best-effort.** Unchanged shape: `description` frontmatter +
  "You are the **<role>** … canonical definition is `.harness/agents/<role>.md` — read and
  follow it … run `.harness/init.sh` first, halt on failure … hand off through
  `.harness/progress/`." No role body copied. These are written even though discovery is
  unconfirmed (cheap, possibly honored) — the tests assert their **shape**, never that
  they register.
- **Workflow shape (R7/R9).** Each `.agents/workflows/<name>.md` is a plain `cp` of
  `$CMDDIR/<name>.md`; those bodies already begin with `---\ndescription: …\n---` (satisfies
  R7) and already act as their role resolved against `.harness/agents/*.md` with
  `$ARGUMENTS` (R8). The `cp` keeps them byte-identical to the Claude/OpenCode copies (R9).
- **Test strength (R11) — beyond existence.** The assertion group must, per glue file:
  check the **correct (plural) dir**; `description` present; persona/rule **defers** to
  the `.harness/agents/*.md` path; workflow **resolves** its role + carries `$ARGUMENTS`;
  workflow **`cmp -s`** equal to the Claude command; and the canonical-orchestrator
  **sentinel ABSENT** in rule + every persona (proves no fork). This replaces the original
  R11's mere file-existence claim that Codex flagged.

## DO NOT TOUCH
- `agents/*.md` — the **canonical** role definitions. The Antigravity glue points at
  them via `.harness/agents/*.md`; it must never fork, copy, or edit a role body.
  (Business rule; R3, R5.)
- `store/tasks.schema.json` and the set of status values — no schema/status change.
- `init.sh`, the markdown TaskStore (`store/`), `progress/` hand-off mechanics, and the
  4-file spec format / `specs/_templates/` — the portable core stays as-is.
- The existing `.claude/` (§5), OpenCode (§5b), and `opencode.json` (§6) blocks and the
  `write_pointer` logic (§4) beyond the path comment in R1 — do not refactor them; the
  Antigravity block already sits alongside, do not restructure the proven stamping.
- The byte-compare deselect **contract** itself (`remove_if_pristine`, the pristine-only
  rule, never `rm -rf`, prune-only-when-empty) — from `17280b7`; change only the path
  literals it operates on, never its safety logic.
- The shared-`GEMINI.md` ownership logic from `50f74a9` (kept until neither `gemini` nor
  `antigravity` is selected) — keep as-is; only update its path comment.
- The umbrella/cascade machinery (`manifest_upsert`, arg parsing, `--umbrella` flow) —
  unrelated to this single-repo feature.
- The existing non-Antigravity assertions in `tests/test_install.sh` — touch only the
  Antigravity-glue group and the three antigravity/GEMINI.md regression tests.

## Approach notes
- **Idempotency / upgrade safety.** The `.agents/` glue is regenerated every run (like
  `.claude/` and `.opencode/`), so it is harness-owned and overwrite-on-upgrade — NOT in
  the "seed once / never clobber" project-owned set. No `tasks.json`/`product.md`
  preservation applies. The existing idempotency test covers it once paths are updated.
- **Single source of truth for command bodies.** Reusing the `$CMDDIR/*.md` bodies (R9)
  is the key anti-drift decision: it mirrors OpenCode and prevents a second
  hand-maintained copy of the SDD command prose.
- **VERSION/CHANGELOG.** Already at `0.22.0` for this MINOR capability — the re-spec is a
  correction inside the unreleased feature, so no further bump; just fix the `.agents/`
  prose in `CHANGELOG.md`.
- **Open-question dependencies (R12).** If the gate confirms bare-file personas register,
  a follow-up may promote R4/R5 to hard registration requirements with a real registration
  test. If the gate requires plugin-bundle packaging, that is a separate (global-install)
  follow-up feature. Neither invalidates this plan — it delivers the confirmed-primitive
  glue and documents the working model. If the gate rejects the plural rename (says the
  live IDE scans `.agent/`), revert the path literals only; the test-strengthening and the
  best-effort persona framing still apply.
