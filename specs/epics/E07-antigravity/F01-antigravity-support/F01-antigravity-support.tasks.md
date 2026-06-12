# Antigravity native support — Tasks

> Atomic, sequential steps. The Builder works these top to bottom, one at a time, **on
> the existing branch `feat/E07-F01-antigravity-support`** (commits `50f74a9`, `17280b7`
> already landed the `.agent/` singular glue + deselect byte-compare). This re-spec's
> work is primarily the **`.agent/` → `.agents/` (plural) rename** across generation,
> entrypoint wiring, manifest, the deselect byte-compare, and the tests — plus the
> honest best-effort persona model and strengthened (beyond-existence) test assertions.
> Each task names the R-id(s) it satisfies. No canonical `agents/*.md` is touched.
>
> **Do the rename as a scoped, reviewed substitution — not a blind global sed.** Only the
> Antigravity glue paths move; verify each site below.

- [x] **T1** (R2,R4,R6) — In `harness-install.sh` §5c, change the `mkdir -p` line so all
  three glue dirs are **plural**: `"$TARGET/.agents/rules" "$TARGET/.agents/agents"
  "$TARGET/.agents/workflows"`.

- [x] **T2** (R2,R3,R12) — In §5c, change the `gen_ag_rule` destination to
  `"$TARGET/.agents/rules/harness.md"`. In the `gen_ag_rule` body, update the working-model
  prose: reference `.agents/agents/` and `.agents/workflows/` (plural); state the R12 model
  explicitly — Antigravity drives the harness through the `description`-gated
  `.agents/workflows/` slash commands + the `.agents/agents/` personas, with
  `.harness/progress/` hand-off, and **not** a Task-tool-style spawn and **not** an asserted
  bare-file subagent registration. Keep it a few lines; no copied role body.

- [x] **T3** (R4,R5) — In §5c's persona loop, change the `gen_ag_persona` destination to
  `"$TARGET/.agents/agents/$_agr.md"` (plural). Persona body is otherwise unchanged
  (`description` frontmatter, defers to `.harness/agents/<role>.md`, `.harness/init.sh`
  first + halt, `.harness/progress/` hand-off, no copied role body). These remain
  **best-effort** — written but not claimed to register.

- [x] **T4** (R6,R7,R8,R9) — In §5c's workflow loop, change the `cp` destination to
  `"$TARGET/.agents/workflows/$_w.md"` (plural). Mirror from `$CMDDIR/$_w.md`, do not
  re-author.

- [x] **T5** (R12) — Update the §5c `ok` line to `ok "Antigravity glue (rules + agents +
  workflows) installed (.agents/)"` (plural).

- [x] **T6** (R13) — In the §7 `antigravity)` deselect branch, change every relpath passed
  to `remove_if_pristine` to the plural dir: `.agents/rules/harness.md`,
  `.agents/agents/$_agr.md` (in the loop), `.agents/workflows/$_agw.md` (in the loop). Then
  change the four `rmdir` prune targets to `"$TARGET/.agents/rules"`,
  `"$TARGET/.agents/agents"`, `"$TARGET/.agents/workflows"`, `"$TARGET/.agents"`. **Do not
  change the byte-compare safety logic** (pristine-only removal, never user files, never
  `rm -rf`) — only the path literals. Leave the shared-GEMINI.md removal logic intact.

- [x] **T7** (R10) — In §3, update the `manifest.txt` HARNESS-OWNED glue line to
  `.agents/rules/*  .agents/agents/*  .agents/workflows/*  (repo root, regenerated;
  Antigravity glue)`.

- [x] **T8** (R1,R12) — Update the §4 `write_pointer`/`GEMINI.md` comment that mentions
  "the `.agent/rules/harness.md` rule (§5c)" to read `.agents/rules/harness.md` (plural).
  No behavioral change to the shared-GEMINI.md logic.

- [x] **T9** (R10) — In `CHANGELOG.md`, edit the existing `## [0.22.0]` Antigravity section
  so every `.agent/` reads `.agents/` (plural), and add a clause: personas are best-effort;
  the durable working model is the `.agents/rules/` entrypoint + `description`-gated
  `.agents/workflows/` slash commands + `.harness/progress/` hand-off. **Do not bump
  `VERSION`** — it is already `0.22.0` for this same MINOR capability.

- [x] **T10** (R11) — In `tests/test_install.sh`, update the Antigravity glue assertion
  group: change every `$T/.agent/...` path to `$T/.agents/...` (rule, personas, workflows).
  Keep/confirm the **shape-not-existence** assertions: correct plural dir; `description`
  present (rule + personas + workflows); persona defers to `.harness/agents/<role>.md`;
  each workflow resolves its role against `.harness/agents/*.md` and carries `$ARGUMENTS`;
  each workflow `cmp -s` byte-identical to its Claude command; and the
  canonical-orchestrator **sentinel is ABSENT** in the rule and every persona (no fork). Do
  NOT add an assertion that personas "register" as subagents.

- [x] **T11** (R11,R13) — In `tests/test_install.sh`, update the three Antigravity/GEMINI.md
  regression tests to the plural dir: `--agents=antigravity writes GEMINI.md entrypoint`
  (the `.agent/rules/harness.md` existence check → `.agents/rules/harness.md`); `antigravity
  deselect is byte-exact` (every `.agent/...` path → `.agents/...`, including the user-file
  preservation + pristine-removal + `.agent/` survives → `.agents/` checks); and `GEMINI.md
  shared by gemini+antigravity` (no path change unless it references `.agent/`). Keep all
  assertions — they already exceed file-existence.

- [x] **T12** — Run the full `verification.test_command` suite (`sh tests/test_install.sh`
  + `./init.sh`); ensure green before hand-off. Confirm no stray `.agent/` (singular)
  literal remains in the Antigravity glue paths (`grep -n "\.agent/" harness-install.sh
  tests/test_install.sh` should show no Antigravity-glue singular paths).
