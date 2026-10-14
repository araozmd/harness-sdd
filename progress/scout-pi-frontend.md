# Scout: pi front end — every place a front end is wired

## Question
Map every wiring point for a new agent key `pi` beside claude/codex/opencode/antigravity,
using E31 (OpenCode) and E33 (Antigravity) as precedents. All refs are `harness-install.sh`
(HI) unless a file is named. VERSION = 0.91.3.

## Precedent scope
- **E33 (Antigravity, v0.87.0, commit 8259717)**: the spec said "DO NOT TOUCH harness-install.sh",
  but the fix rounds added the key anyway: AGENT_KEYS, validate_csv/recorded_active_selection/
  detect_host messages, `skill_unit_claimed`, the §7 deselect arm, the advisory banner,
  `harness-owned-paths.sh`, and the antigravity skip in escalation arming. There is no
  HOST_MARKERS row, no WORKER_INVOKE row, no role files and no `--self` support. Dispatch is
  prose only (`define_subagent`). Tests: `tests/test_antigravity_front.sh` (62 lines of grep
  asserts), plus key-count edits in 7 existing suites.
- **E31 (OpenCode)**: F01 made OpenCode a claimant of the shared skills and made the adapter
  host-neutral. F02 brought opencode into `--self` and the drift gate (test_self_mode,
  test_self_drift, test_source_shims, test_codex_native R9). F02 was a MINOR bump.

## Findings
### 1. harness-install.sh
- Header comment lists the active front ends and says "`all` selects all three" (stale): HI:11-13.
- `AGENT_KEYS="claude codex opencode antigravity"`: HI:1651. Its comment says adding a key
  means "one new key + its gated stamp block + removal case": HI:1645-1647.
- `HOST_MARKERS` table: HI:1726-1730. Provenance block (load-bearing format, parsed by
  test_agents_host R8): HI:1691-1724. Rule: a row ships only with an empirically verified
  `comm -13` env delta, recorded with the CLI + version (R8, HI:1682-1688). With no verified
  marker, add no row; the CLI is then undetectable.
- `WORKER_INVOKE` (non-interactive entrypoint) table: HI:1784-1788, provenance HI:1777-1783.
  Antigravity has no row. `pi` needs a row such as `pi pi non-interactive` only once
  `pi -p` is verified.
- Flag parsing: `AGENTS_OVERRIDE="${HARNESS_AGENTS:-}"` HI:8768. `--agents=*` / `--agents`
  HI:8835-8846. `--print-agents` HI:8847.
- Selection functions with hard-coded key lists that need `pi`:
  - `detect_host` gemini message: HI:2138.
  - `validate_csv` retired-gemini die: HI:2305. It also handles `all` → AGENT_KEYS (HI:2297),
    which is automatic.
  - `recorded_active_selection` case arms and messages: HI:2587-2592 (explicit
    `claude|codex|opencode|antigravity)`; an unknown recorded key DIES).
  - `toggle_select`/`tui_select` iterate AGENT_KEYS, so no change is needed (HI:2320, 2398).
- Legacy fallbacks: `precheck_baseline`/`host_fallback_set` = `claude opencode` (HI:2603,
  2659). `PRIOR_AGENTS` legacy = `claude gemini opencode antigravity` (HI:3332). Do not add
  `pi` to either (it is not legacy).
- Retirement: `retire_legacy_frontends` HI:3089-3211 (gemini/antigravity v0.78.1 sha
  fingerprints). Fixture: `tests/fixtures/frontend-v0.78.1`. `pi` is unaffected.
- Model routing:
  - `model_alias` HI:1908 has claude-only aliases.
  - `codex_effort_alias` HI:1928.
  - `resolve_model` HI:1944: pin key `models.pin.<fe>.<tier>` at HI:1962, an opencode-only
    `provider/model` guard at HI:1981, `SELF_MODE` claude/codex harvest at HI:1953.
  - `resolve_codex_effort` HI:2019.
  - `models_any` HI:2047 (codex arm).
  - `escalation_verdict` HI:2092 (codex effort arm).
  - `write_escalation_arming` skips antigravity (`case … antigravity) continue`) HI:4824,
    4845. `pi` needs the same skip if it stamps no roles, otherwise it reads `neither`/`blocked`.
  - `fe_unstamped` ledger: only codex/opencode (HI:4734).
- Emitters:
  - Pointer files: `write_pointer AGENTS.md` is always written; `CLAUDE.md` is gated (HI:5141-5143).
  - Claude shims: `emit_agent` HI:5265-5313.
  - Command bodies are generated into `$CMDDIR` (HI:5315+) and copied to `.claude/commands`
    (HI:7410-7422) and `.opencode/command` (§5b HI:7424-7471).
  - `gen_oc_agent` HI:4570.
  - `gen_opencode_json` HI:4540 (+ the §6 stamp, HI:7803).
  - Shared skills: `skill_unit_claimed` HI:7477-7479 (add `|| agent_selected pi` if pi
    claims `.agents/skills`), `gen_skill_body` adapter text HI:7488-7518 (the literal "In
    Antigravity or OpenCode, invoke `/…`" is pinned by test_antigravity_front.sh),
    `install_skill_unit` HI:7598, `reclaim_skill_units` HI:7650, §5d HI:7748-7764 (ok-message
    names claimants).
  - Codex roles: §5f HI:7766-7795 and `gen_codex_agent` HI:4621.
  - Personas: `ag_personas` HI:4593.
- Install manifest text (`.harness/manifest.txt`) lists the glue and `(claude|codex|opencode)`:
  HI:4285-4395 (stale; no antigravity).
- §7 deselect: `printf "$SELECTED" > .agents` HI:7927. Antigravity-retire reclaim HI:7932.
  Per-key `case` arms HI:7945-8037: claude / opencode / codex / antigravity, where
  antigravity is only a skill reclaim when no claimant remains. `pi` needs an arm.
  - §7b pr_loop gate-off per selected FE: HI:8040-8093.
- Advisory banner: HI:8193-8250. `_adv_<fe>` counters, single-host phrasing chain (else =
  Antigravity), `_slash_hosts` join. `pi` needs a counter and an `elif`. The final `else`
  currently assumes antigravity.
- `--self`: `self_install` HI:8398-8487 allows only `claude|codex|opencode` (die HI:8408).
  The file harvest list is at HI:8439; the per-FE unstamped probe is at HI:8456-8476.
  Antigravity is excluded from `--self`.

### 2. Ownership / init
- `tools/harness-owned-paths.sh:83-87` lists claude/opencode glue. `:101` gates skill claims
  on `^(codex|opencode|antigravity)$` in `.harness/.agents`. Add `pi` if it claims skills.
  The per-file ledger loop `for _tool in codex` is at `:115`.
- `init.sh:475-494` checks the `--self` glue-manifest drift (`.claude/.glue-manifest`). There
  are no per-FE key checks.

### 3. harness.config.yaml
- The `models:` block is at :243-271. The commented pins (`pin.opencode.*`, `pin.codex.*`,
  `pin.claude.reasoning`) are at :265-271, and the escalation notes per FE are at :356-363.
- A duplicated copy lives in `migrate_config` (HI:~300-320, HI:~495-505).
- `workers.roster` :391. There is no `agents:` key; the selection lives in `.harness/.agents`.

### 4. Dispatch prose
- `agents/orchestrator.md:572-576` (Codex): "select the installed named role … through the
  host's available delegation controls and start a fresh context … If fresh role delegation
  is unavailable, stop and report…".
- `agents/orchestrator.md:579-584` (Antigravity): "defines ephemeral subagents dynamically
  using the `define_subagent` tool (setting `system_prompt` from … `agents/<role>.md`, and
  passing `enable_write_tools=True` …) and launches them via `invoke_subagent` … If subagent
  invocation tools are unavailable, stop and report the limitation…".
- The `$CMDDIR/sdd-next` body carries a one-line Antigravity note at HI:5342, which flows into
  `.claude/commands/sdd-next.md`, `.opencode/command/sdd-next.md` and the skill.
- The Claude shim says "Task tool" (HI:5160ff).

### 5. Docs listing front ends
- README.md:4-5, :15, the "Supported CLIs" table :116-119, :284, :289 (`--self` keys),
  :416-421 ("all four"), :437-444.
- AGENTS.md:4-5.
- docs/HARNESS.md:9, 47-52, 100.
- docs/WORKFLOW.md:5-10.
- docs/INSTALL.md:
  - :6, :38, :97 (claiming set `{codex, opencode}`, stale), :112, :124.
  - :301 is stale ("accepted keys are claude, codex, and opencode").
  - Markers table :311-313, fallback table :337, picker :351.
  - Models sections :889-1127 (tier table :969, pin :1031, "Where the values land" :1050).
  - `--self` :1128.

### 6. Tests
- Runner: `sh tools/run-tests.sh [--jobs N] [--serial] [suite…]`. It runs 8-wide under the
  strictest shell available (dash > posh > ash > sh), parse-checks all suites and tools, and
  prints one summary line when green. There are 73 suites. The only recorded timing is
  183s wall time for 27 suites at 8 jobs (`tools/run-tests.sh:6-9`); the current full run is
  untimed and is likely several minutes.
- Conventions: `fail() { echo "FAIL: $1" >&2; exit 1; }` and `pass() { echo "ok - $1"; }`
  per suite. Sandboxes use mktemp with HOME/CODEX_HOME isolated. The dash allowlist
  `tests/dash-allowlist.txt` is empty by policy.
- Hard-coded key-count asserts that will break:
  - `test_installer_toggles.sh:294-297` and `:921-923` expect exactly "4" keys.
  - `test_frontend_retirement.sh:30` names all keys in the error text, and `:32` requires
    `--agents=all` to equal `antigravity\nclaude\ncodex\nopencode\n`. With `pi` it sorts
    as `…opencode\npi\n`. `:10` pops host env vars; add pi markers there.
  - `test_agents_host.sh:219` (row must be an AGENT_KEYS member), `:298` (baseline), `:461`
    (`.agents` token whitelist `claude codex opencode`).
  - `test_worker_roster.sh:47` (`ROSTERED_COMMANDS`), `:463`.
  - `test_model_routing.sh:136`.
  - `test_install.sh:1312`, `:1359`.
  - `test_codex_native.sh:284-290` (VERSION == top CHANGELOG entry).
- Precedent new suite: `tests/test_antigravity_front.sh` (skill adapter grep, orchestrator
  guidance, docs presence, init.sh green).

### 7. Tool allowlists
- Claude only: the `emit_agent <name> "<tools>"` calls at HI:5279-5310 (e.g. scout
  `Read, Grep, Glob, Bash`; builder `Read, Write, Edit, Bash, Grep, Glob`; orchestrator and
  architect add `Task`). Canonical `agents/*.md` have no tool frontmatter.
- OpenCode: `opencode.json` has no per-role permissions; only the `pr-fixer` file agent has
  `permission: edit: allow, bash: allow` (HI:4577-4582).
- Codex TOML has no tool or sandbox keys (HI:4628-4636).
- Antigravity: a blanket `enable_write_tools=True`.
- There is no translation layer. Each emitter hard-codes its own permissions.

### 8. .agents/skills
- Generated by §5d whenever `skill_unit_claimed` (codex|opencode|antigravity) is true, one
  unit per `$HARNESS_EMITTED_CMDS`. The units are `sdd-next sdd-new sdd-plan sdd-drill
  sdd-fix sdd-fix-parallel sdd-report` (HI:1793), plus `sdd-pr-loop` when gated and the
  source-only `sdd-triage` under `--self`.
- Each unit has `SKILL.md` and `agents/openai.yaml`, with the ownership ledger at
  `.harness/.codex-skills/`.
- In source, units are written by `--self` and recorded in `.claude/.glue-manifest`.
- The stray `.agents/skills/source-command-sdd-report/` (SKILL.md only, mtime 2026-10-05
  07:58:28) was not made by the harness: no code or git history mentions "source-command".
  It matches a burst of Codex CLI sessions at 07:58:29 that day doing an
  "external-import" of Claude sessions (`~/.codex/sessions/2026/10/05/`). The body is the
  `.claude/commands/sdd-report.md` template ("Use this skill when the user asks to run the
  migrated source command"). At that time `sdd-report` had no skill unit; it gained one on
  10-13. Likely Codex's Claude-command migration. It is safe to delete, and the user must
  decide.

### 9. Release
- `VERSION` is 0.91.3 (read at HI:121).
- CHANGELOG entries use the format `## [X.Y.Z] — YYYY-MM-DD` + `### Added|Fixed — <title> (<id>)`.
- AGENTS.md:110-116: PATCH for fixes, MINOR for a capability (E33 was MINOR 0.87.0), tag
  `vX.Y.Z`.
- `test_codex_native` enforces VERSION == top CHANGELOG entry.

## Open questions / risks
- pi 1.2.0 is installed (`~/.local/share/mise/.../bin/pi`, with `~/.pi/agent/{agents,skills,prompts}`).
  Its session env markers, its `-p`/non-interactive entrypoint, whether it reads project
  `.agents/skills`, and its subagent mechanism are unverified. R8 forbids a HOST_MARKERS row
  without a recorded `comm -13` delta.
- Decide whether pi is an E33-style claimant (skills plus prose dispatch, skipped in
  escalation arming and `--self`) or an E31-style first-class FE (native role files, model
  pins, `--self`, drift gate).
- The banner's final `else` assumes antigravity, and several docs are already stale for
  antigravity (INSTALL.md:97, :301; HI:11-12; HI:4389). Expect test churn in roughly 8 suites.
