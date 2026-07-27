# Scout: E17-F01 — per-role model selection (config schema + per-front-end agent stamping)

## Question

Recon `harness-install.sh` + `tests/` for: (1) front-end selection/persistence/deselection,
(2) exactly what each of the 5 front-ends generates for the 5 roles and which function writes it,
(3) config plumbing + `migrate_config` requirements for a new `models:` block,
(4) installer-test sandboxing + idiomatic assertion patterns, (5) `manifest.txt` / VERSION coupling.

Read-only recon. No decisions, no production code.

---

## 1. Front-end selection: storage, persistence, deselection

| Concern | Mechanism | Cite |
|---|---|---|
| Registry | `AGENT_KEYS="claude gemini opencode antigravity codex"` | `harness-install.sh:273` |
| Owned generated basenames | `HARNESS_CLAUDE_SHIMS="orchestrator architect builder reviewer scout doc-critic"` and `HARNESS_SDD_CMDS="sdd-next sdd-new sdd-plan sdd-drill sdd-fix sdd-fix-parallel"` | `harness-install.sh:284-285` |
| In-memory set | global `SELECTED` (sorted, **newline**-separated) | `harness-install.sh:569-592` |
| Membership test | `agent_selected <key>` (`grep -qx` against `$SELECTED`) | `harness-install.sh:294-296` |
| Key validation | `agent_known`, `validate_csv` (dies on unknown key) | `harness-install.sh:288-291`, `323-337` |
| Normalization | `normalize_keys` (`tr`, `grep -v ^$`, `sort -u`) | `harness-install.sh:300-302` |
| Resolution order | `resolve_agents`: `--agents`/`HARNESS_AGENTS` override → interactive (`tui_select`, falling back to `toggle_select`) → no-TTY default = ALL | `harness-install.sh:569-592` |
| Persistence | `printf '%s\n' "$SELECTED" > "$H/.agents"` — i.e. `.harness/.agents`, one key/line, rewritten every run | `harness-install.sh:1519` |
| Prior selection capture | `PRIOR_AGENTS` read from `$H/.agents` **before** anything is written; legacy upgrade with no `.agents` falls back to ALL **minus `codex`** | `harness-install.sh:609-628` |

### Deselection (removal) — §7 reconciliation loop, `harness-install.sh:1516-1637`

For each key in `PRIOR_AGENTS` not in `SELECTED`, a `case` branch removes that front-end's glue.
Three distinct removal helpers, all defined inside `install_one`:

- **`remove_pointer <rel-file>`** — `harness-install.sh:897-909`. Strips the
  `<!-- harness:begin -->..<!-- harness:end -->` block in place; deletes the file only if
  nothing but whitespace remains.
- **`remove_owned <dir-rel> <label> <stem...>`** — `harness-install.sh:915-924`. Deletes only
  `<dir>/<stem>.md` for the named stems (never `rm -rf`), then `rmdir` if empty. Used for
  `.claude/agents` (with `$HARNESS_CLAUDE_SHIMS`), `.claude/commands` and `.opencode/command`
  (with `$HARNESS_SDD_CMDS`) — `harness-install.sh:1532-1533`, `1547`.
- **`remove_if_pristine <rel-path> <ref-file> <label>`** — `harness-install.sh:1020-1030`.
  Deletes only when `cmp -s` byte-matches a **freshly regenerated** reference; otherwise leaves
  the file and warns. Used for all Antigravity `.agents/` files (`1580`, `1586`, `1592`) and,
  inline, for `opencode.json` (`1554-1564`) and the global Codex prompts (`1619-1633`).

**Load-bearing invariant for E17-F01:** the pristine-compare removal path regenerates the
reference body at deselect time (`gen_ag_rule`, `gen_ag_persona`, `gen_opencode_json`, and the
still-live `$CMDDIR` sources). **If a model line is stamped into any of those bodies, the deselect
reference generator must stamp the identical model**, or every previously-stamped file will look
"user-edited" and never be reclaimed. `CMDDIR` cleanup is deliberately deferred past §7 for exactly
this reason (`harness-install.sh:1502-1506`, `1639-1641`).

Shared-file special cases: `GEMINI.md` is co-owned by `gemini` **and** `antigravity` and is removed
only when neither remains selected (`1536-1545`, `1601-1609`). `AGENTS.md` is never gated and never
removed (`1032-1035`).

---

## 2. Per-front-end role generation (what exists TODAY)

Only **two** of the five front-ends emit per-role agent definitions at all. This is the single most
important fact for this feature.

### claude — `.claude/agents/<role>.md` (project-local) — PER-ROLE ✅

- Writer: **`emit_agent <name> <tools> <description>`**, `harness-install.sh:1053-1069`; call sites
  `1070-1086`; whole block gated `if agent_selected claude` at `1051`.
- Emits 6 files: `orchestrator, architect, builder, reviewer, scout, doc-critic`
  (the 5 roles **plus `doc-critic`**).
- Frontmatter keys emitted today — exactly three, in this order:
  ```
  ---
  name: <role>
  description: <desc>
  tools: <comma-separated tool list>
  ---
  ```
  (`harness-install.sh:1055-1059`). No `model:` key today.
- Commands: `.claude/commands/<cmd>.md` copied from `$CMDDIR` for `$HARNESS_SDD_CMDS`
  (`1389-1395`); command frontmatter is `description:` only.

### opencode — `opencode.json` (project-local, single JSON file) — PER-ROLE ✅

- Writer: **`gen_opencode_json <dest>`**, `harness-install.sh:928-943`; stamped at `1509-1514`.
- One `agent.<role>` object per role with keys `mode` (`primary` for orchestrator, `subagent` for
  the rest), `description`, `prompt` (`{file:./.harness/agents/<role>.md}`). Same 6 roles.
- **Critical constraint:** `opencode.json` is **created only if absent** — `if agent_selected
  opencode && [ ! -f "$TARGET/opencode.json" ]` (`1509`). An existing file is left untouched with an
  info message (`1512-1513`). So an upgrade **cannot** re-stamp models into an already-installed
  `opencode.json` under today's logic; re-stamping opencode models requires a design decision
  (merge/regenerate vs. no-op) that changes this branch and the `cmp -s` deselect contract at
  `1554-1564`.
- `.opencode/command/<cmd>.md` copied from `$CMDDIR` (`1400-1406`); no `agent:` frontmatter by
  design, so commands run under the primary (orchestrator) agent (`1398-1399`).

### antigravity — `.agents/{rules,agents,workflows}/` (project-local) — PER-ROLE ✅ (best-effort)

- Writers: **`gen_ag_rule <dest>`** (`955-980`), **`gen_ag_persona <role> <desc> <dest>`**
  (`983-999`), role→description table **`ag_personas`** (`1004-1013`). Install block `1417-1449`.
- Emits `.agents/rules/harness.md`, `.agents/agents/<role>.md` × 6, `.agents/workflows/<cmd>.md` × 6
  (workflows are `cp`'d verbatim from `$CMDDIR`, `1444-1446`).
- Persona frontmatter emitted today — exactly **one** key:
  ```
  ---
  description: <desc>
  ---
  ```
  (`harness-install.sh:986-988`). No `name:`, no `tools:`, no `model:`.
- Header comment records that bare-file persona registration is **unconfirmed** and deliberately not
  asserted (`1410-1416`, `1425-1432`); tests assert *shape only* (`tests/test_install.sh:516-528`).

### gemini — `GEMINI.md` pointer block ONLY — **NO per-role surface today** ❌

- Only artifact: the managed `harness:begin..end` block written by **`write_pointer GEMINI.md`**
  (`harness-install.sh:863-892`, called at `1044`). Written when **either** `gemini` **or**
  `antigravity` is selected.
- There is no `.gemini/` directory, no per-role file, no agent definitions of any kind for the
  `gemini` key. A per-role model for gemini has **nothing to stamp into** without inventing a new
  artifact type.

### codex — `${CODEX_HOME:-$HOME/.codex}/prompts/<cmd>.md` (GLOBAL) — **NO per-role surface today** ❌

- Path resolver: **`codex_prompts_dir`** (`harness-install.sh:311-317`) — prefers `$CODEX_HOME`,
  falls back to `$HOME`, prints **empty** when neither is set (caller warns and skips rather than
  aborting under `set -u`).
- Install block §5d, `1468-1500`: copies the 6 `$CMDDIR` command bodies to the **machine-global**
  prompts dir. Registers as `/prompts:<name>`, not `/<name>` (`1496-1498`).
- Format is plain markdown with `description:` frontmatter (inherited from the shared command
  bodies). **No agent/role files, no TOML is emitted anywhere by this installer.** Grep confirms no
  `.toml` writer exists in `harness-install.sh`.
- Pre-existing differing files get a `.pre-harness.bak` backup before overwrite (`1488-1493`).
- Codex's repo entrypoint is the always-written root `AGENTS.md` — codex intentionally has no
  pointer of its own (`1032-1035`, `276-278`).

### Summary table

| key | per-role artifact | path | scope | format / keys emitted | writer fn |
|---|---|---|---|---|---|
| claude | yes (6) | `.claude/agents/<role>.md` | project | md frontmatter: `name`,`description`,`tools` | `emit_agent` (`:1053`) |
| opencode | yes (6) | `opencode.json` → `agent.<role>` | project | JSON: `mode`,`description`,`prompt` | `gen_opencode_json` (`:928`) |
| antigravity | yes (6) | `.agents/agents/<role>.md` | project | md frontmatter: `description` only | `gen_ag_persona` (`:983`) + `ag_personas` (`:1004`) |
| gemini | **none** | `GEMINI.md` block only | project | managed markdown block | `write_pointer` (`:863`) |
| codex | **none** | `$CODEX_HOME/prompts/*.md` | **GLOBAL** | md frontmatter: `description` (commands, not roles) | inline §5d (`:1468`) |

Note: the installer emits **6** role definitions (5 roles + `doc-critic`), while the feature brief
names 5. `doc-critic` needs an explicit in/out decision and, if in, a tier assignment.

---

## 3. Config plumbing

### Reading

There is **no YAML parser**. All config reads are ad-hoc `grep -Eq` presence checks plus small
`awk` scripts that are *section-scoped* (they track a top-level header, reset on any new
non-indented line, and match an indented child):

- `_cfg_has_umbrella_manifest` — `harness-install.sh:206-213`
- `_cfg_has_workflow_identity` — `harness-install.sh:219-226`
- `_cfg_umbrella_manifest_value` — `harness-install.sh:230-239` (strips comment + quotes)
- `_cfg_telemetry_log` — `harness-install.sh:244-253` (same shape; the value-reader template)

Only two config values are actually consumed by the installer today: `telemetry.log`
(`:772`) and `umbrella.manifest` (`:1835`, `:1856`). Everything else in the config is read by
agents/tools at runtime, not by the installer.

**A `models:` reader will need a new value-extraction helper.** `_cfg_telemetry_log` is the exact
idiom to copy for a scalar. Nothing in the repo reads **two-level nested** keys
(`models.per_role.builder`) — that is new ground; the closest prior art is `mirror.board.*`, which is
read only by `tools/sync-board.mjs` (node), never by the installer.

### Timing (matters for stamping)

`resolve_agents` runs at `:629`; the config is seeded/migrated at `:671-686`; **all front-end
stamping happens later at `:1035-1514`**. So `$H/harness.config.yaml` is guaranteed present and
migrated before any stamp — a models reader can safely run in §5.

### Migration — what a new `models:` block must do

`migrate_config <config-path>` — `harness-install.sh:69-202`. Called **only on the preserved path**
(`:685`, the `else` of "config already exists"). Contract: append-only, value-preserving,
comment-preserving, idempotent, POSIX `sh` + `grep`/`awk` only. Helper `_mc_insert_after <file>
<header-regex> <line>` (`:257-263`) inserts one line after a matching header.

Every existing entry follows one of two shapes:

1. **Nested key under an existing top-level header** (e.g. `workflow.identity`, `:149-160`):
   presence check → if header exists, `_mc_insert_after`; else append full `header:\n  key:` block
   at EOF.
2. **Whole top-level block** (e.g. `telemetry:` `:113-122`, `mirror:` `:166-189`,
   `fix_lane:` `:193-201`): a single `grep -Eq '^<name>:[[:space:]]*(#.*)?$'` presence check, and
   when absent a `printf` heredoc-style append at EOF.

For a new `models:` block the requirements are therefore:

- Add it to **BOTH** places — a fresh install copies `$SRC/harness.config.yaml` verbatim
  (`:672`) and **never** calls `migrate_config`; an upgrade only calls `migrate_config`. Missing
  either half means fresh and upgraded targets diverge. (`fix_lane` at `:193-201` +
  `harness.config.yaml:78-81` is the cleanest 2-file precedent to copy.)
- Use shape 2 (top-level block, append at EOF) — `models:` is a new top-level mapping.
- Presence check must tolerate a trailing comment: `^models:[[:space:]]*(#.*)?$` — the
  `verification:` comment bug is documented at `:77-78`.
- If any *child* key is later added under an existing `models:` block, the presence check must be
  **section-scoped** like `_cfg_has_workflow_identity`, not a file-wide `grep` — a same-named key
  elsewhere must not suppress seeding (`:141-148`, and the test at `tests/test_install.sh:665-688`).
- Must be a no-op on second run (byte-identical config), asserted by `cmp -s`.
- **Absent block ⇒ current behavior**, which the brief already requires; note the installer must also
  tolerate a config that has the block with all-empty values.

---

## 4. Installer test harness (`tests/test_install.sh`, 1120 lines)

### Sandboxing

- `SRC` = repo root, `T` = `mktemp -d` target, `trap 'rm -rf "$T"' EXIT` —
  `tests/test_install.sh:9-11`.
- **`export CODEX_HOME="$T/codex-home"` for the WHOLE suite** — `tests/test_install.sh:17`
  (with the rationale comment at `:13-16`). Individual codex tests still override per-run for crisp
  isolation, e.g. `CODEX_HOME="$TB/ch" sh "$SRC/harness-install.sh" …` (`:703`, `:719`, `:784`,
  `:815`, `:849`, `:868`, `:888`).
- `HOME` is sandboxed only where it matters: `HOME="$TX/home" CODEX_HOME="$TX/codex-home" …`
  (`:605`), and the unset-both case uses `env -u HOME -u CODEX_HOME` (`:834`).
- All runs are non-TTY (`sh …`), so selection is always driven deterministically by
  `--agents=` / `HARNESS_AGENTS=` and never by the interactive picker (`:696-697`).

### Helper functions a new assertion should use

Only two, both at `tests/test_install.sh:19-20`:

```sh
fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }
```

There is **no assert library and no test runner** — the file is a straight-line `set -eu` script.
The idiomatic pattern is `<check> || fail "<message with requirement id>"` followed by one
`pass "<summary> (Rnn)"` per logical group.

### Idiomatic assertion vocabulary (copy these)

| Intent | Idiom | Example |
|---|---|---|
| file exists | `[ -f X ] \|\| fail "…"` | `:352` |
| file must NOT exist | `[ -f X ] && fail "…"` | `:724-728` |
| frontmatter key present | `grep -qE '^tools:.*\bTask\b' X \|\| fail "…"` | `:446`, `:450`, `:523` |
| literal substring | `grep -qF '…' X \|\| fail "…"` | `:418` |
| exact whole line | `grep -qxF '…' X \|\| fail "…"` | `:25`, `:258` |
| no duplication (idempotence) | `[ "$(grep -cF '…' X)" = "1" ] \|\| fail "…"` | `:580`, `:589` |
| byte-identity across front-ends | `cmp -s A B \|\| fail "…"` | `:485-496`, `:546-548`, `:803` |
| config idempotence | `cp cfg after1; re-run; cmp -s cfg after1` | `:657-661` |
| per-front-end isolation | fresh `mktemp -d` + `--agents=<key>` + assert peers absent | `:717-730`, `:783-808` |
| deselect behavior | install with N keys, re-run with N-1, capture stderr `_w="$(… 2>&1 >/dev/null)"` | `:813-824` |
| loop over roles | `for r in orchestrator architect builder reviewer scout doc-critic; do … done` | `:521-528` |

Extractable named `test_*()` functions exist (`:22-220`) and are invoked both in the fresh-install
pass and again after upgrade (`:243-246`, `:595-597`) — that is the pattern for an assertion that
must hold in **both** states. New E17-F01 assertions that must survive upgrade should follow it.

### Anti-patterns already codified in this file (do not reintroduce)

- Never freeze an exact `VERSION`; assert a **CHANGELOG heading** instead —
  `tests/test_install.sh:91-97` and `:331-335` with the explicit comment at `:92-93`.
- Never diff DO-NOT-TOUCH files against `main`.
- `tests/test_install.sh` is registered in `verification.test_command`
  (`harness.config.yaml`, `verification:` section) so it runs on every review.

---

## 5. VERSION / `manifest.txt`

- `manifest.txt` is **generated, not a source file.** There is no `manifest.txt` in the repo; it is
  written per-target by a heredoc in §3 of `install_one` — `harness-install.sh:834-860`. Confirmed:
  the only non-doc reference in the tree is that one `cat >` line.
- It is a **human-readable inventory**, not a machine-consumed list: nothing reads it back, no
  install/removal logic keys off it. Removal is driven by `$HARNESS_CLAUDE_SHIMS` /
  `$HARNESS_SDD_CMDS` / the pristine-compare generators, **not** by the manifest.
- Consequence: **adding new generated files does not functionally require a manifest change**, but
  the repo's convention is to update it anyway — both E07-F01 and E08-F01 shipped a manifest-text
  task (`progress/builder-E07-F01.md:27`, `progress/builder-E08-F01.md:35`), and a Codex review
  flagged its omission (`progress/review-E09-F01.md:51`, `progress/builder-E09-F01-round2.md:33`).
  Treat it as a required doc task.
- The manifest body already lists the harness-owned glue lines that would grow if a new artifact
  type is added: `.claude/agents/* .claude/commands/*` (`:842`), `.agents/rules|agents|workflows/*`
  (`:843`), and the `AGENT SELECTION` section (`:853-859`, which still lists only four keys and
  omits `codex` — a pre-existing doc gap worth fixing in passing).
- `VERSION` is `0.37.0` (`VERSION:1`), read at `harness-install.sh:52`, stamped to
  `.harness/.harness-version` at `:833`, and interpolated into the manifest header at `:835`.
  The brief requires a MINOR bump; the test suite must assert the **CHANGELOG entry**, not the
  version string.

---

## Relevant files

- `/Users/araozmd/repos/harness-sdd/harness-install.sh` — every generator, the registry, selection,
  migration, removal. The only production file this feature must touch (plus the config + tests + docs).
- `/Users/araozmd/repos/harness-sdd/harness.config.yaml` — the **fresh-install** config source
  (`fix_lane:` at the end is the newest additive-block precedent).
- `/Users/araozmd/repos/harness-sdd/tests/test_install.sh` — mandatory installer-wiring assertions.
- `/Users/araozmd/repos/harness-sdd/docs/INSTALL.md` — the generated-layout tree (`:15-31`) and the
  fresh-config-defaults paragraph (`:57-67`) both name generated artifacts; both go stale if new
  files are emitted.
- `/Users/araozmd/repos/harness-sdd/docs/CONFIG-LAYERING.md` — where per-developer override
  semantics live (relevant to the brief's E09-F02 open question).
- `/Users/araozmd/repos/harness-sdd/VERSION`, `CHANGELOG.md` — MINOR bump + entry.

Not in scope but easy to confuse: `/Users/araozmd/repos/harness-sdd/.claude/agents/*.md` are the
**source repo's own** hand-maintained sub-agent mirrors (5 files, no `doc-critic`), not installer
output. They are not written by `harness-install.sh`.

## Open questions / risks for the Architect

1. **Two front-ends have no per-role surface at all.** `gemini` emits only a `GEMINI.md` block;
   `codex` emits only global `/prompts:*` command files. Neither has any agent-definition artifact
   to stamp. The brief's open question ("no-op with a warning vs. session-level fallback") is not
   hypothetical for these two — it is the default state.
2. **`opencode.json` is never rewritten after creation** (`harness-install.sh:1509-1514`). Idempotent
   re-stamping of opencode models contradicts today's never-clobber rule. Needs an explicit decision;
   whatever is chosen also changes the `cmp -s` pristine-deselect contract at `:1554-1564`.
3. **Deselect symmetry is a hard trap.** `remove_if_pristine` regenerates the reference at removal
   time. Every generator that gains a model line must gain it on **both** the install and the
   deselect-compare path (`gen_ag_persona`, `gen_opencode_json`, and the `$CMDDIR` sources), or
   stamped files become unremovable. Same for `remove_owned`'s stem lists if any new basename appears.
4. **6 roles, not 5.** `doc-critic` is emitted alongside the 5 named roles everywhere
   (`HARNESS_CLAUDE_SHIMS`, `ag_personas`, `gen_opencode_json`). Its tier must be decided or
   explicitly excluded.
5. **Orchestrator stampability.** For claude the orchestrator is emitted as a `.claude/agents/`
   subagent shim (`:1070`) even though the live Orchestrator is the host session — so a `model:` there
   would apply only when it is spawned as a subagent, not to the driving session. For opencode it is
   `mode: "primary"` and a model would apply to the session. The two are not equivalent.
6. **`AGENT SELECTION` manifest text omits `codex`** (`harness-install.sh:855`) — pre-existing drift.
7. **Vendor-surface verification is still open.** This recon covered the repo only, per the request.
   The brief's per-CLI question (does Claude Code frontmatter accept `model:`? does OpenCode's
   `agent.<n>` accept `model`? do Antigravity personas or Gemini support a per-agent model, and what
   happens on an unrecognized value?) has **not** been verified against current vendor docs and needs
   a Context7/docs pass before the plan is written.
