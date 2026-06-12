# Interactive agent-target selection — Tasks

> Atomic, sequential, independent steps. The Builder works these top to bottom, one at
> a time. Each task names the R-id(s) it satisfies. All edits are in
> `harness-install.sh`, `tests/test_install.sh`, `VERSION`, `CHANGELOG.md` only.
> DO NOT TOUCH the items in `.plan.md` → "DO NOT TOUCH" (esp. `AGENTS.md`,
> `agents/*.md`, E07-F01's spec, the portable core).

- [x] **T1** (R10) — In `harness-install.sh`, add a declarative **agent registry**: one
  row per key `claude`, `gemini`, `opencode`, `antigravity`, each carrying its stamp
  action reference and its list of owned glue paths (per `.plan.md` registry table).
  The `antigravity` row's stamp action is a documented **no-op placeholder** (E07-F01
  fills it).

- [x] **T2** (R5, R7) — Add `--agents=<csv>` to the arg-parse `while`/`case` loop and
  read `HARNESS_AGENTS` from the environment. Store the raw override (if any) for the
  resolver. Keep all existing flags/positional handling intact.

- [x] **T3** (R7) — Add a CSV validator: split on commas, trim whitespace, drop empty
  tokens, de-duplicate, and validate each token against the registry keys; on any
  unknown token, `die` non-zero naming the token and make no changes.

- [x] **T4** (R1, R9) — Add the pure-`read` numbered **toggle UI**: print the four agent
  keys numbered, showing each key's pre-checked state; let the user type numbers to
  toggle; confirm to finish. Take the pre-check baseline as a parameter (ALL for fresh /
  persisted set for re-run).

- [x] **T5** (R1, R5, R6, R9, R11) — Add `resolve_agents <target>`, called inside
  `install_one` **before** the pointer/glue blocks: (1) if override present → validate
  (T3) and use it, no prompt; (2) else if `[ -t 0 ]` → pre-check from `.harness/agents`
  if present else ALL, run T4; (3) else → ALL. Set a single resolved `SELECTED` list.
  Do not branch on `UPGRADE`/`VERSION` (decoupled).

- [x] **T6** (R8) — After `resolve_agents`, write `SELECTED` to `<T>/.harness/agents`
  (one sorted key per line), overwriting on every run, beside `.harness-version`.

- [x] **T7** (R2, R3, R4) — Gate each existing stamp block on `SELECTED` membership:
  §4 `write_pointer CLAUDE.md` (claude), §4 `write_pointer GEMINI.md` (gemini), §5
  `.claude/agents`+`.claude/commands` (claude), §5b `.opencode/command` (opencode), §6
  `opencode.json` (opencode), and the future `.agent/` block (antigravity). Leave
  `write_pointer AGENTS.md` **ungated** (always written).

- [x] **T8** (R13) — Add a `remove_pointer <file>` helper (marker-aware in-place edit
  mirroring `write_pointer`) for removing a pointer block from a shared file without
  deleting user prose.

- [x] **T9** (R12, R13) — After resolution, compute the removal set = (prior persisted
  `.harness/agents` − `SELECTED`). For each removed key, delete its registry-listed owned
  glue (dirs via `rm -rf` of the harness-owned dir; pointer blocks via T8; `opencode.json`
  only if it matches the generated template, else skip-and-warn) and print a warning
  naming each removed path. Never delete `AGENTS.md` or `.harness/` body content. Added
  agents (in `SELECTED`, not prior) are handled by their normal gated stamp (T7).

- [x] **T10** (R8, R13 — docs) — Update the `harness-install.sh` header comment and the
  `manifest.txt` body to document the `.harness/agents` state file, the
  `--agents`/`HARNESS_AGENTS` knob, and that deselected agents' glue is removed.

- [x] **T11** (R15) — In `tests/test_install.sh`, add a new assertion group (mirroring
  the existing `R7`-style stamping checks) covering: (a) `--agents=claude` stamps only
  Claude and writes no `GEMINI.md`/`opencode.json`/`.opencode`/`.agent` (R2/R4);
  (b) a no-TTY no-override run stamps ALL (R6 — this is the existing default invocation,
  assert all four front-ends present); (c) explicit `HARNESS_AGENTS` override path (R5);
  (d) an unknown-key override exits non-zero, changes nothing (R7); (e) `.harness/agents`
  persistence round-trip (R8); (f) a re-run that **adds** one agent and **removes**
  another using the persisted set as baseline, asserting the added glue appears, the
  removed glue is gone, `AGENTS.md` survives, and `.harness/agents` reflects the new set
  (R9/R12/R13).

- [x] **T12** (R14) — Bump `VERSION` `0.20.0` → `0.21.0` and add a `## [0.21.0]` entry to
  `CHANGELOG.md` under "Added — ✨ Selectable agent targets (interactive selection +
  re-prompt on update)".

- [x] **T13** — Run `./init.sh` and the full `verification.test_command`
  (`tests/test_install.sh` + the rest of the suite); ensure green before hand-off.
