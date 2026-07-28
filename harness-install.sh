#!/bin/sh
# harness-install.sh — install or upgrade the agent harness into a target repo.
#
#   ./harness-install.sh [--agents=<csv>] <target-repo-path>
#   ./harness-install.sh --umbrella <umbrella-dir> [--shared-repo] [--recursive] [--dry-run|--list]
#
# Idempotent: run once to install, re-run to upgrade.
#
# Agent selection (E08-F01): the installer stamps a SELECTABLE set of coding-agent
# front-ends — claude (CLAUDE.md + .claude/), gemini (GEMINI.md), opencode
# (opencode.json + .opencode/command/), antigravity (.agents/, E07-F01). Resolution:
#   - --agents=<csv> or HARNESS_AGENTS=<csv> (comma-separated keys) → that set, no
#     prompt (the override always wins). An unknown key aborts non-zero.
#   - else an interactive TTY → a numbered toggle list (pre-checked from the saved
#     .harness/.agents set, or ALL on a fresh install).
#   - else (no TTY, no override) → ALL agents (preserves the historical behavior).
# The resolved set is persisted to .harness/.agents (a dot-file beside .harness-version;
# dot-prefixed to avoid colliding with the .harness/agents/ role-bodies dir) and re-prompted
# on every re-run, decoupled from VERSION/upgrade detection. A re-run that DESELECTS
# an agent deletes that agent's harness-owned, regenerated glue and warns (it never
# touches the shared AGENTS.md entrypoint or the .harness/ body; a hand-edited
# opencode.json is left in place with a warning).
#
#   - The harness BODY (agents, docs, store, tools, templates, init.sh, config, AGENTS.md)
#     is copied into <target>/.harness/ and OVERWRITTEN on every run.
#   - PROJECT-authored content (specs/product.md, state/tasks.json, specs/epics,
#     progress) is seeded once on a fresh install and NEVER clobbered on upgrade.
#   - Claude Code glue (.claude/) and the entrypoint pointer blocks in
#     CLAUDE.md / AGENTS.md / GEMINI.md are regenerated each run; existing prose in
#     those files is preserved (only the marked block is replaced).
#
# Umbrella mode (--umbrella, see docs/UMBRELLA.md): cascades a single install across
# an umbrella directory — writes the coordinator profile into the umbrella, discovers
# its immediate git children (depth 1), installs the normal child profile into each,
# and auto-populates umbrella.manifest.yaml. Single-target mode (no --umbrella) is
# unchanged. Pass --dry-run (alias --list) with --umbrella to preview exactly which
# coordinator + git children would be touched, writing nothing.
#
# Shared spec repository (--shared-repo, umbrella mode only, see docs/UMBRELLA.md):
# OPT-IN. After the cascade, make the umbrella ROOT its own git repo that tracks the
# shared .harness/ + umbrella docs and GIT-IGNORES the product child repos (each its own
# repo). `git init` runs ONLY if the umbrella root has no .git yet (an existing repo is
# never re-initialized); the umbrella-root .gitignore is append-seeded with the discovered
# child dirs (never clobbered). Without the flag, the umbrella stays a non-git parent dir
# exactly as before — the flag is the only thing that version-controls the root.
#
# POSIX sh, zero dependencies (matches init.sh's ethos).

set -eu

SRC="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
VERSION="$(cat "$SRC/VERSION" 2>/dev/null || echo "0.0.0")"
MARK_BEGIN="<!-- harness:begin -->"
MARK_END="<!-- harness:end -->"

die()  { echo "❌ install: $1" >&2; exit 1; }
info() { echo "   $1"; }
ok()   { echo "✅ $1"; }

# ── config migration (append-only, value-preserving, idempotent, zero-dep) ────
# migrate_config <config-path>
#   Appends any MISSING default keys to a PRESERVED harness.config.yaml without
#   altering existing values or comments. Driven by an explicit table of guaranteed
#   defaults (extend the table to add future additive keys). For each missing key:
#     - if its section header exists, insert the indented key line after the header;
#     - if the header is absent, append the full header+key block at EOF.
#   Never rewrites an existing line. A second run finds every key present and writes
#   nothing (idempotent). POSIX sh + grep/awk only.
migrate_config() {
  _cfg="$1"
  [ -f "$_cfg" ] || return 0

  # Default table entries are processed below. Each entry knows its section header,
  # the (two-space-indented) key line to add, and the regex that detects the key.

  # --- verification.integration_command ---
  # Section-header match tolerates a trailing `# comment` (e.g. `verification: # ...`),
  # otherwise migration would append a SECOND `verification:` mapping at EOF.
  if ! grep -Eq '^[[:space:]]*integration_command:' "$_cfg"; then
    if grep -Eq '^verification:[[:space:]]*(#.*)?$' "$_cfg"; then
      _mc_insert_after "$_cfg" '^verification:[[:space:]]*(#.*)?$' \
        '  integration_command: ""   # umbrella integration gate (see docs/UMBRELLA.md)'
    else
      {
        printf '\n'
        printf 'verification:\n'
        printf '  integration_command: ""   # umbrella integration gate (see docs/UMBRELLA.md)\n'
      } >> "$_cfg"
    fi
  fi

  # --- umbrella.manifest ---
  # Scope the presence check to the top-level `umbrella:` section — an unrelated
  # nested `manifest:` (e.g. under `metadata:`) must not suppress the default.
  if ! _cfg_has_umbrella_manifest "$_cfg"; then
    if grep -Eq '^umbrella:[[:space:]]*(#.*)?$' "$_cfg"; then
      _mc_insert_after "$_cfg" '^umbrella:[[:space:]]*(#.*)?$' \
        '  manifest: ""   # path to umbrella.manifest.yaml; presence = umbrella mode'
    else
      {
        printf '\n'
        printf 'umbrella:\n'
        printf '  manifest: ""   # path to umbrella.manifest.yaml; presence = umbrella mode\n'
      } >> "$_cfg"
    fi
  fi

  # --- telemetry: block (E05-F02) ---
  # A preserved pre-telemetry config keeps working (absence of the block ⇒ enabled
  # with the default log), but a fresh install ships the discoverable `enabled`
  # kill-switch + `log:` knob, so add the whole block on upgrade for parity. Append-only
  # at EOF (it is a top-level block; no header to insert into when absent).
  if ! grep -Eq '^telemetry:[[:space:]]*(#.*)?$' "$_cfg"; then
    {
      printf '\n'
      printf '# Telemetry (E05-F02): local-only sub-agent + human-gate timing. See docs/UMBRELLA.md\n'
      printf '# is unrelated; see agents/orchestrator.md "## Telemetry". Absent block ⇒ enabled defaults.\n'
      printf 'telemetry:\n'
      printf '  enabled: true            # false ⇒ Orchestrator skips telemetry capture entirely\n'
      printf '  log: telemetry.jsonl     # resolved under HARNESS_DIR; gitignored/local-only\n'
    } >> "$_cfg"
  fi

  # --- store.on_write_command (post-write sync hook) ---
  # Insert under the top-level `store:` header (tolerating a trailing comment). Empty
  # default ⇒ no hook, i.e. today's behavior. Scope the presence check to NOT match a
  # same-named key elsewhere by requiring the two-space indent of a store child.
  if ! grep -Eq '^[[:space:]]+on_write_command:' "$_cfg"; then
    if grep -Eq '^store:[[:space:]]*(#.*)?$' "$_cfg"; then
      _mc_insert_after "$_cfg" '^store:[[:space:]]*(#.*)?$' \
        '  on_write_command: ""   # post-write sync hook; empty ⇒ none (see store/board-mirror.md)'
    else
      {
        printf '\n'
        printf 'store:\n'
        printf '  on_write_command: ""   # post-write sync hook; empty ⇒ none (see store/board-mirror.md)\n'
      } >> "$_cfg"
    fi
  fi

  # --- workflow.identity (E10-F01 scoped `--mine` ownership) ---
  # Insert under the top-level `workflow:` header (tolerating a trailing comment).
  # Empty default ⇒ solo / board-wide, exactly today's behavior (owner ignored). A
  # preserved pre-E10 config that lacks this key would make `/sdd-next --mine`
  # fail-closed as an unresolved identity, so seed the documented default on upgrade.
  # Scope the presence check to an `identity:` INSIDE the top-level `workflow:` section
  # (via _cfg_has_workflow_identity) so a same-named key under another section — e.g. an
  # auth/tool block — never suppresses seeding the workflow child.
  if ! _cfg_has_workflow_identity "$_cfg"; then
    if grep -Eq '^workflow:[[:space:]]*(#.*)?$' "$_cfg"; then
      _mc_insert_after "$_cfg" '^workflow:[[:space:]]*(#.*)?$' \
        '  identity: ""   # current developer identity for scoped `/sdd-next --mine` (E10-F01); empty ⇒ board-wide'
    else
      {
        printf '\n'
        printf 'workflow:\n'
        printf '  identity: ""   # current developer identity for scoped `/sdd-next --mine` (E10-F01); empty ⇒ board-wide\n'
      } >> "$_cfg"
    fi
  fi

  # --- mirror.board block (optional board projection) ---
  # Top-level block; append at EOF when absent (no header to insert into). Empty provider
  # ⇒ tools/sync-board.mjs is a no-op, so a preserved config without this block behaves
  # exactly as before. See store/board-mirror.md.
  if ! grep -Eq '^mirror:[[:space:]]*(#.*)?$' "$_cfg"; then
    {
      printf '\n'
      printf '# Board mirror (optional, opt-in): one-way projection of tasks.json onto a project\n'
      printf '# board. INERT by default (empty provider). MIRROR, not a backend. See store/board-mirror.md.\n'
      printf 'mirror:\n'
      printf '  board:\n'
      printf '    provider: ""          # ""|none disables; github-projects+jira implemented; azure-boards stub\n'
      printf '    owner: ""             # github-projects: org/user login\n'
      printf '    project_number: 0     # github-projects: Project number\n'
      printf '    repo: ""              # github-projects: owner/repo holding the issues\n'
      printf '    base_url: ""          # jira: Jira Server/DC base URL (e.g. https://jira.acme.internal)\n'
      printf '    project_key: ""       # jira: target Jira project key (e.g. HAR)\n'
      printf '    pat_file: "jira.pat"   # jira: gitignored PAT file, resolved under the harness dir (this .harness/) ⇒ .harness/jira.pat; JIRA_PAT env var wins. NEVER commit a PAT.\n'
      printf '    assignee: ""          # optional: gh login (or "@me") assigned once work starts; empty ⇒ skip (no-op for jira in F01)\n'
      printf '    # issue_type_map:     # jira: harness concept -> Jira issue type (omit ⇒ epic:Epic, feature:Story)\n'
      printf '    #   epic: "Epic"\n'
      printf '    #   feature: "Story"\n'
      printf '    epic_name_field: ""   # jira: optional Server/DC "Epic Name" custom field id (e.g. customfield_10011); set only if required on the Epic create screen. Empty ⇒ omitted (default)\n'
      printf '    # status_map:         # optional: harness status -> board column / Jira workflow state (omit ⇒ identity)\n'
      printf '    #   pending: "Todo"\n'
      printf '    #   done: "Done"\n'
    } >> "$_cfg"
  fi

  # --- fix_lane block (E15-F03 bounded E99 parallel dispatch) ---
  # Top-level additive defaults; absence is behaviorally equivalent to these values.
  if ! grep -Eq '^fix_lane:[[:space:]]*(#.*)?$' "$_cfg"; then
    {
      printf '\n'
      printf '# Bounded E99 fix dispatch; shared_paths extends immutable built-ins.\n'
      printf 'fix_lane:\n'
      printf '  max_parallel: 3\n'
      printf '  shared_paths: []\n'
    } >> "$_cfg"
  fi

  # --- models block (E17-F01 per-role model routing) ---
  # Top-level, append-only at EOF, OPT-IN and INERT: every role seeds to `inherit`,
  # which compiles to KEY OMISSION on every front-end — so a migrated target's
  # generated agent definitions stay byte-identical until the operator edits a tier.
  # Keep this block byte-identical to the tail of the source harness.config.yaml, so a
  # FRESH install (which copies the config verbatim and never migrates) and an UPGRADED
  # install (which only migrates) converge on the same text. Presence check tolerates a
  # trailing comment on the `models:` line so a second run never duplicates the block.
  if ! grep -Eq '^models:[[:space:]]*(#.*)?$' "$_cfg"; then
    cat >> "$_cfg" <<'EOF'

# Per-role model routing (E17-F01) — OPT-IN and INERT by default.
# Tiers: reasoning | standard | cheap | inherit
# `inherit` compiles to KEY OMISSION on every front-end — the generated agent
# definitions are byte-identical to a harness without this block.
# NOTE: `orchestrator` applies only where the orchestrator is a spawned sub-agent
# (Claude) or the configured primary agent (OpenCode). The model of the session you
# launched by hand is chosen by how you launched it, not by the harness.
models:
  default: inherit        # tier for any role not listed below
  orchestrator: inherit
  architect: inherit      # try: reasoning
  builder: inherit        # try: standard
  reviewer: inherit       # try: standard
  scout: inherit          # try: cheap
  doc-critic: inherit     # try: cheap
  # Exact-value escape hatch: `pin.<front-end>.<tier>`, written VERBATIM in that
  # front-end's own vocabulary. REQUIRED for codex and opencode, which have no
  # floating tier alias — an unpinned tier there stamps nothing.
  #   opencode MUST be "provider/model" (an invalid value aborts your OpenCode run)
  #   codex    MUST be a bare model id (the provider comes from `model_provider`)
  #   antigravity accepts only tier aliases and needs `agy` >= 1.1.5 (inert below it)
  # pin.opencode.reasoning: ""
  # pin.opencode.standard: ""
  # pin.opencode.cheap: ""
  # pin.codex.reasoning: ""
  # pin.codex.standard: ""
  # pin.codex.cheap: ""
  # pin.claude.reasoning: ""
EOF
  fi

  # --- pr_loop block (E18-F01 Codex review loop) ---
  # Top-level, append-only at EOF. `enabled` is OPT-IN, so an absent block is behaviorally
  # equivalent to the values below (see _cfg_pr_loop_value / pr_loop_enabled): a preserved
  # pre-E18 config resolves to DISABLED and keeps working untouched. The block is still
  # appended on upgrade so the on switch is discoverable, and so seeded and migrated
  # configs converge. Keep this text BYTE-IDENTICAL to the tail of the source
  # harness.config.yaml (modulo the `enabled:` line, which seed_pr_loop_optin forces to
  # the opt-in default on a fresh copy): a FRESH install copies the config and never
  # migrates, an UPGRADE only migrates, and R17 requires the two to converge on the same
  # bytes.
  if ! grep -Eq '^pr_loop:[[:space:]]*(#.*)?$' "$_cfg"; then
    cat >> "$_cfg" <<'EOF'

# Codex PR review loop (E18-F01) — the policy knobs of `/sdd-pr-loop`.
# `enabled` is OPT-IN: it is off unless it reads exactly `true`. An absent block, an
# absent key, an empty value or any other value all mean OFF, and nothing is stamped.
# Turn it on ONLY on a repo that has the Codex GitHub App installed plus an authed
# `gh` (and `jq` on PATH) — without them /sdd-pr-loop can only fail its own preflight.
# While it is on, /sdd-pr-loop and the pr-fixer sub-agent are stamped into every
# selected front-end; flipping it back to false reclaims all of that glue.
# Per-run env overrides (env wins over config): HARNESS_PR_LOOP_ENABLED,
# HARNESS_AUTO_MERGE, HARNESS_MAX_ROUNDS, HARNESS_BLOCKING_SEVERITIES,
# HARNESS_MERGE_STRATEGY. Execution knobs are env-ONLY (never config):
# HARNESS_POLL_INTERVAL (60), HARNESS_POLL_CEILING (900),
# HARNESS_FIRST_RESPONSE (180), HARNESS_DRY_RUN.
# (The harness's own source repo opts in; every fresh install is seeded with `false`.)
pr_loop:
  enabled: false                 # opt-in master gate; ONLY `true` stamps /sdd-pr-loop glue
  auto_merge: true               # merge once every gate is green and threads are Codex-only
  max_rounds: 4                  # round cap; the cap round labels the PR needs-human
  blocking_severities: "P0,P1"   # comma-separated severities that block a merge
  merge_strategy: "merge"        # merge | squash
EOF
  fi
}

# seed_pr_loop_optin <file> — force `pr_loop.enabled` to the OPT-IN default (`false`) in a
# freshly SEEDED config, section-scoped so no same-named key elsewhere is touched.
#
# A fresh install copies the harness's own harness.config.yaml verbatim, and the harness
# source repo legitimately runs with `enabled: true` (it has the Codex GitHub App). Copying
# that value into a target would arm a review loop the target may have no way to run — the
# same reason `test_command` is blanked on seed. The replacement line is BYTE-IDENTICAL to
# the one migrate_config appends, which is what keeps seeded and migrated blocks convergent
# (E18-F01 R15/R17). A no-op when the block or the key is absent — absent already means off.
seed_pr_loop_optin() {
  awk '
    /^pr_loop:[[:space:]]*(#.*)?$/ { p=1; print; next }
    p && /^[^[:space:]#]/ { p=0 }
    p && /^[[:space:]]+enabled:/ {
      print "  enabled: false                 # opt-in master gate; ONLY `true` stamps /sdd-pr-loop glue"
      next
    }
    { print }
  ' "$1" > "$1.prltmp" && mv "$1.prltmp" "$1"
}

# _cfg_has_umbrella_manifest <file> — true (exit 0) iff a `manifest:` key exists
# INSIDE the top-level `umbrella:` section (not anywhere else in the YAML).
_cfg_has_umbrella_manifest() {
  awk '
    /^umbrella:[[:space:]]*(#.*)?$/ { u=1; next }
    u && /^[^[:space:]#]/ { u=0 }
    u && /^[[:space:]]+manifest:/ { found=1 }
    END { exit found ? 0 : 1 }
  ' "$1"
}

# _cfg_has_workflow_identity <file> — true (exit 0) iff an `identity:` key exists
# INSIDE the top-level `workflow:` section (not a same-named key under any other
# section). Mirrors _cfg_has_umbrella_manifest so migrate_config never mis-detects
# an unrelated indented `identity:` and skips seeding `workflow.identity`.
_cfg_has_workflow_identity() {
  awk '
    /^workflow:[[:space:]]*(#.*)?$/ { w=1; next }
    w && /^[^[:space:]#]/ { w=0 }
    w && /^[[:space:]]+identity:/ { found=1 }
    END { exit found ? 0 : 1 }
  ' "$1"
}

# _cfg_umbrella_manifest_value <file> — print the umbrella.manifest value (unquoted,
# comment-stripped) from inside the top-level `umbrella:` section; empty if unset.
_cfg_umbrella_manifest_value() {
  awk '
    /^umbrella:[[:space:]]*(#.*)?$/ { u=1; next }
    u && /^[^[:space:]#]/ { u=0 }
    u && /^[[:space:]]+manifest:/ {
      sub(/^[[:space:]]+manifest:[[:space:]]*/, ""); sub(/[[:space:]]*#.*$/, "")
      gsub(/^"|"$|^'\''|'\''$/, ""); print; exit
    }
  ' "$1"
}

# _cfg_telemetry_log <file> — print the telemetry.log value (unquoted, comment-stripped)
# from inside the top-level `telemetry:` section; empty if unset. Same scoping as the
# python reader's _configured_log, so the installer ignores exactly what the writer uses.
_cfg_telemetry_log() {
  awk '
    /^telemetry:[[:space:]]*(#.*)?$/ { t=1; next }
    t && /^[^[:space:]#]/ { t=0 }
    t && /^[[:space:]]+log:/ {
      sub(/^[[:space:]]+log:[[:space:]]*/, ""); sub(/[[:space:]]*#.*$/, "")
      gsub(/^"|"$|^'\''|'\''$/, ""); print; exit
    }
  ' "$1"
}

# _cfg_models_value <file> <key> — print the `models.<key>` scalar (unquoted,
# comment-stripped) from inside the top-level `models:` section; empty if unset or if
# the file does not exist. Same section-scoped shape as _cfg_telemetry_log. <key> may be
# a DOTTED composite (e.g. `pin.opencode.cheap`); each `.` is matched LITERALLY (rewritten
# to the bracket expression `[.]`) so `pin.codex.cheap` can never match `pinXcodexYcheap`.
# Commented example lines (`  # pin.codex.cheap: ""`) never match — the `#` precedes the key.
_cfg_models_value() {
  [ -f "$1" ] || return 0
  awk -v k="$2" '
    BEGIN { gsub(/\./, "[.]", k); re = "^[[:space:]]+" k ":" }
    /^models:[[:space:]]*(#.*)?$/ { m=1; next }
    m && /^[^[:space:]#]/ { m=0 }
    m && $0 ~ re {
      sub(/^[[:space:]]+[^:]*:[[:space:]]*/, ""); sub(/[[:space:]]*#.*$/, "")
      gsub(/^"|"$|^'\''|'\''$/, ""); print; exit
    }
  ' "$1"
}

# _cfg_pr_loop_value <file> <key> — print the `pr_loop.<key>` scalar (unquoted,
# comment-stripped) from inside the TOP-LEVEL `pr_loop:` section; empty if unset or if the
# file does not exist. Section-scoped exactly like _cfg_models_value, so a same-named key
# nested under ANOTHER section (e.g. `ci:\n  enabled: false`) can never change pr_loop
# behavior (E18-F01 R19). Commented example lines never match — the `#` precedes the key.
_cfg_pr_loop_value() {
  [ -f "$1" ] || return 0
  awk -v k="$2" '
    BEGIN { gsub(/\./, "[.]", k); re = "^[[:space:]]+" k ":" }
    /^pr_loop:[[:space:]]*(#.*)?$/ { p=1; next }
    p && /^[^[:space:]#]/ { p=0 }
    p && $0 ~ re {
      sub(/^[[:space:]]+[^:]*:[[:space:]]*/, ""); sub(/[[:space:]]*#.*$/, "")
      gsub(/^"|"$|^'\''|'\''$/, ""); print; exit
    }
  ' "$1"
}

# pr_loop_enabled — exit 0 ONLY when `pr_loop.enabled` resolves to the literal `true`.
# Precedence: HARNESS_PR_LOOP_ENABLED env → config value → the built-in default `false`
# (E18-F01 R18/R20). The gate is OPT-IN: an absent block, an absent key, an empty value
# and any non-`true` value alike mean DISABLED. `/sdd-pr-loop` only functions on a repo
# that has the Codex GitHub App installed plus an authed `gh`, so defaulting it on would
# grow a command that can do nothing but fail its own preflight on a fresh install.
# Enablement is therefore an explicit choice made at install time (E20-F01 surfaces it in
# the installer; until then it is a documented one-line hand-edit). Reads the target
# config through $H, which is empty before install_one sets it (⇒ default: disabled).
pr_loop_enabled() {
  _prl_v="${HARNESS_PR_LOOP_ENABLED:-}"
  if [ -z "$_prl_v" ] && [ -n "${H:-}" ]; then
    _prl_v="$(_cfg_pr_loop_value "$H/harness.config.yaml" enabled)"
  fi
  [ "$_prl_v" = "true" ] && return 0
  return 1
}

# _mc_insert_after <file> <header-regex> <line>  — insert <line> immediately after the
# first line matching <header-regex>, leaving every other line byte-for-byte intact.
_mc_insert_after() {
  _f="$1"; _re="$2"; _line="$3"
  awk -v re="$_re" -v add="$_line" '
    { print }
    !done && $0 ~ re { print add; done=1 }
  ' "$_f" > "$_f.mctmp" && mv "$_f.mctmp" "$_f"
}

# ── agent registry (E08-F01) ──────────────────────────────────────────────────
# Declarative table of the selectable coding-agent front-ends the installer can
# stamp. Each agent is one row: a stable KEY, the existing stamp block it gates,
# and the harness-owned glue paths it OWNS for removal (R10). Adding a future
# agent is one new key here plus its gated stamp block + removal case.
#
# The selectable keys — the ONLY legal tokens for `--agents`/`HARNESS_AGENTS`,
# the `.harness/.agents` state file, and the toggle UI — are exactly:
AGENT_KEYS="claude gemini opencode antigravity codex"
# AGENTS.md (the shared portable entrypoint) is deliberately NOT a key: it is
# always written, never gated, never removed (see write_pointer AGENTS.md). It
# also doubles as Codex CLI's native entrypoint — Codex reads AGENTS.md from the
# repo root with no glue, so `codex` needs no entrypoint pointer of its own; its
# only stamped glue is the GLOBAL /sdd-* prompts (§5d).
#
# Harness-OWNED generated basenames (stems; all files are <stem>.md). These are the
# ONLY files a deselection may delete, so a selective re-run never removes a user's
# own agents/commands sharing the same dir (Codex r2 P1). Keep in sync with the
# emit_agent calls and the command-copy loops in install_one().
HARNESS_CLAUDE_SHIMS="orchestrator architect builder reviewer scout doc-critic pr-fixer"
HARNESS_SDD_CMDS="sdd-next sdd-new sdd-plan sdd-drill sdd-fix sdd-fix-parallel"

# E18-F01: the pr_loop glue is GATED on the OPT-IN `pr_loop.enabled`, so it is emitted
# from a SEPARATE list — joining $HARNESS_SDD_CMDS would make it unconditional (and, with
# the gate off by default, would defeat the opt-in entirely). Removal, by
# contrast, must always consider it (a target stamped while the gate was on has to be
# reclaimable after the gate flips off), so every reclamation loop iterates the UNION.
# `pr-fixer` rides in HARNESS_CLAUDE_SHIMS above for the same reason: ledger only —
# its emission stays gated. remove_owned is by-name and `[ -f ]`-guarded, so a stem
# that was never stamped is a harmless no-op.
HARNESS_PR_LOOP_CMDS="sdd-pr-loop"
HARNESS_OWNED_CMDS="$HARNESS_SDD_CMDS $HARNESS_PR_LOOP_CMDS"

# The ONE pr-fixer description, shared by every front-end's emitter and by the §7/§7b
# reclamation compares, so the two can never diverge — a second copy would let the
# install stamp and the pristine reference disagree, which is exactly what makes an
# already-stamped file unremovable.
PR_FIXER_DESC="Fixes exactly ONE Codex review comment in an isolated context: reads the comment and the cited hunk, applies the smallest change, commits, returns. One comment, one fix, one commit, one return."

# ── per-role model routing (E17-F01) ──────────────────────────────────────────
# Config (`models:` in .harness/harness.config.yaml) → the NATIVE model value of each
# selected front-end. Everything here is a PURE function of (config bytes, front-end,
# role): the resolved value goes to stdout, every diagnostic goes to stderr. That purity
# is load-bearing — the deselect path re-generates each artifact and byte-compares it
# against what is on disk (remove_if_pristine), so a non-deterministic stamp would make a
# previously-installed file permanently unremovable.
#
# The six roles the installer already emits an agent definition for. Adding a future role
# variant (e.g. E17-F02's `builder-heavy`) is ONE new name here + one `models:` line — no
# config migration, because the map is flat and keyed off role names.
MODEL_ROLES="orchestrator architect builder reviewer scout doc-critic"

# Set to 1 to force every resolution to EMPTY (used to regenerate the "model-free" body
# an older opencode.json is compared against). Never set outside that narrow window.
MODELS_OFF=0
# Run-scoped stderr de-duplication ledger (set in install_one). resolve_model runs inside
# `$(...)` subshells, so an in-memory flag would not survive; the marker file does. Six
# roles × five front-ends is 30 resolutions per run — without this the output degenerates
# into thirty identical advisory lines.
MODEL_DIAG=""

# _models_cfg — path of the target config the resolver reads. Empty before install_one
# sets $H, in which case every lookup below yields empty (⇒ `inherit` ⇒ omission).
_models_cfg() { [ -n "${H:-}" ] && printf '%s\n' "$H/harness.config.yaml"; return 0; }

# _model_warn_once <dedup-key> <message…> — print <message> to stderr at most once per
# <dedup-key> per install run.
_model_warn_once() {
  _mw_key="$1"; shift
  if [ -n "${MODEL_DIAG:-}" ] && [ -f "$MODEL_DIAG" ]; then
    grep -qxF "$_mw_key" "$MODEL_DIAG" && return 0
    printf '%s\n' "$_mw_key" >> "$MODEL_DIAG"
  fi
  echo "$*" >&2
  return 0
}

# model_tier <role> — print the resolved TIER: `models.<role>`, else `models.default`,
# else `inherit`. An unrecognized tier is a WARNING, not a fatal error (a config written
# for a newer harness must never block an upgrade on an older installer): warn once
# naming the role and the value, resolve as `inherit`, keep exit status 0.
model_tier() {
  _mt_cfg="$(_models_cfg)"
  _mt_v="$(_cfg_models_value "$_mt_cfg" "$1")"
  [ -n "$_mt_v" ] || _mt_v="$(_cfg_models_value "$_mt_cfg" default)"
  [ -n "$_mt_v" ] || _mt_v="inherit"
  case "$_mt_v" in
    reasoning|standard|cheap|inherit) ;;
    *)
      _model_warn_once "tier:$1:$_mt_v" \
        "⚠️  models.$1: unrecognized tier '$_mt_v' — treating it as 'inherit' (known tiers: reasoning standard cheap inherit)"
      _mt_v="inherit" ;;
  esac
  printf '%s\n' "$_mt_v"
}

# model_alias <front-end> <tier> — the built-in tier→native value table. Every entry is
# a FLOATING vendor alias, never a version-pinned model id, so a new model release is
# picked up without a harness change. Antigravity/Gemini expose only two tiers upstream
# (flash/pro), so `reasoning` and `standard` both map to `pro` — stated, not hidden.
# `codex` and `opencode` have NO floating alias (they require a concrete id / a
# `provider/model` pair), so they are deliberately absent: an unpinned tier there stamps
# nothing rather than having the harness invent a model id.
model_alias() {
  case "$1:$2" in
    claude:reasoning)                          printf 'opus\n' ;;
    claude:standard)                           printf 'sonnet\n' ;;
    claude:cheap)                              printf 'haiku\n' ;;
    antigravity:reasoning|antigravity:standard) printf 'pro\n' ;;
    antigravity:cheap)                         printf 'flash\n' ;;
    gemini:reasoning|gemini:standard)          printf 'pro\n' ;;
    gemini:cheap)                              printf 'flash\n' ;;
  esac
  return 0
}

# resolve_model <front-end> <role> — print that front-end's NATIVE model value for the
# role, or NOTHING to mean "omit the model key entirely". Order: tier → an explicit
# `models.pin.<front-end>.<tier>` (verbatim, wins) → the built-in floating alias →
# omission. `inherit` always yields empty: the literal string `inherit` is never written
# into a generated artifact (it is unknown on Codex and a HARD ERROR on OpenCode, while
# "key absent" means "use the session model" on all five front-ends).
resolve_model() {
  [ "${MODELS_OFF:-0}" = 1 ] && return 0
  _rm_fe="$1"; _rm_role="$2"
  _rm_tier="$(model_tier "$_rm_role")"
  [ "$_rm_tier" = "inherit" ] && return 0

  _rm_pin="$(_cfg_models_value "$(_models_cfg)" "pin.$_rm_fe.$_rm_tier")"
  if [ -n "$_rm_pin" ]; then
    # A pin is otherwise written VERBATIM — but `inherit` is a TIER name, not a model id,
    # and R5 is absolute: the literal string `inherit` must never reach a generated
    # artifact on ANY front-end (it is an unknown model id on Codex and a hard error on
    # OpenCode). Writing it into a `pin.` field is an easy misreading of the documented
    # tier vocabulary, so it compiles to the same thing the `inherit` TIER does: omission.
    if [ "$_rm_pin" = "inherit" ]; then
      _model_warn_once "inheritpin:$_rm_fe:$_rm_tier" \
        "⚠️  models.pin.$_rm_fe.$_rm_tier = 'inherit' is a tier name, not a model id — ignored, no model key written"
      return 0
    fi
    # OpenCode is the one front-end where a syntactically invalid value ABORTS the
    # operator's runs, so its `provider/model` shape is guarded (a format check, not a
    # model-list check — the installer cannot know any vendor's model list).
    if [ "$_rm_fe" = "opencode" ]; then
      case "$_rm_pin" in
        */*) ;;
        *)
          _model_warn_once "ocpin:$_rm_tier" \
            "⚠️  models.pin.opencode.$_rm_tier = '$_rm_pin' is not in provider/model form — ignored, no model key written to opencode.json"
          return 0 ;;
      esac
    fi
    printf '%s\n' "$_rm_pin"
    return 0
  fi

  _rm_alias="$(model_alias "$_rm_fe" "$_rm_tier")"
  if [ -n "$_rm_alias" ]; then printf '%s\n' "$_rm_alias"; return 0; fi

  _model_warn_once "nopin:$_rm_fe:$_rm_tier" \
    "ℹ️  $_rm_fe has no built-in alias for tier '$_rm_tier' — set models.pin.$_rm_fe.$_rm_tier in .harness/harness.config.yaml to stamp a model there"
  return 0
}

# models_any <front-end> — exit 0 iff at least one role resolves to a non-empty value.
# Gates the CONDITIONAL creation of the `.gemini/agents/` and `.codex/agents/` trees, so
# an unconfigured target never grows a directory it did not have before.
models_any() {
  for _ma_role in $MODEL_ROLES; do
    if [ -n "$(resolve_model "$1" "$_ma_role")" ]; then return 0; fi
  done
  return 1
}

# agent_known <key> — true (exit 0) iff <key> is a registered agent key (R7, R10).
agent_known() {
  for _k in $AGENT_KEYS; do [ "$_k" = "$1" ] && return 0; done
  return 1
}

# agent_selected <key> — true (exit 0) iff <key> is a line in $SELECTED (R3/R4).
agent_selected() {
  printf '%s\n' "$SELECTED" | grep -qx "$1"
}

# normalize_keys <space-or-newline-list> — print the given keys de-duplicated and
# sorted, one per line (the stable on-disk + comparison form for .harness/.agents).
normalize_keys() {
  printf '%s\n' "$1" | tr ' ' '\n' | grep -v '^$' | sort -u
}

# codex_prompts_dir — print the GLOBAL Codex prompts dir, or nothing if it cannot be
# resolved. Codex reads custom prompts from `$CODEX_HOME/prompts` (default `~/.codex`).
# Under `set -u` a bare `$HOME` expansion aborts the WHOLE install when neither var is
# set (minimal CI/container/systemd) — and since the no-TTY default selects codex, even
# a plain noninteractive install would hit it (Codex r1 P2). So resolve defensively:
# prefer CODEX_HOME, fall back to HOME, and emit EMPTY (never a bare `/.codex`) when
# neither is set so callers can warn-and-skip instead of crashing or writing to `/`.
codex_prompts_dir() {
  if [ -n "${CODEX_HOME:-}" ]; then
    printf '%s\n' "${CODEX_HOME}/prompts"
  elif [ -n "${HOME:-}" ]; then
    printf '%s\n' "${HOME}/.codex/prompts"
  fi
}

# ── cross-target ownership ledger for the GATED global prompt (E18-F01) ────────
# `${CODEX_HOME:-$HOME/.codex}/prompts/` is machine-GLOBAL and shared by every harness
# target on the box, but `pr_loop.enabled` is PER-TARGET — and OPT-IN, so `false` is the
# default. Deciding to reclaim a SHARED artifact from ONE target's local gate therefore
# destroys a prompt another target still wants: installing any second project with the
# default config used to silently delete `/prompts:sdd-pr-loop` out from under an
# already-enabled project, which only got it back by re-running its own installer.
# (Codex r4 P1 #3662785235.)
#
# This is the same hazard that keeps `codex` out of the legacy PRIOR_AGENTS baseline in
# install_one: never infer ownership of a cross-target artifact from one target's state.
# The ungated `/sdd-*` prompts do not need a ledger — every selecting target re-stamps
# them on its next run — but a gate-OFF target never re-stamps `sdd-pr-loop`, so its loss
# is permanent. Hence: the gated prompt carries a ledger of the targets that currently
# want it. A target appends itself while its gate is on (§5d), drops itself when the gate
# goes off or it deselects codex (§7/§7b), and the prompt is reclaimed ONLY once the
# ledger is EMPTY.
#
# FAIL SAFE — unknown ownership never deletes. A missing, unreadable or unwritable ledger
# beside an existing prompt means "someone else put this here" ⇒ keep it. A stale prompt
# is a harmless no-op; deleting another project's working command is not.
#
# Ledger hygiene: entries are garbage-collected on every read — an entry whose recorded
# target no longer carries a `.harness/` install cannot want anything, so a deleted (or
# un-harnessed) target can never pin the prompt forever. Entries are canonical physical
# paths and the file is rewritten sorted+unique, so re-running converges instead of
# oscillating.

# _prompt_owner_id — the current target's canonical (symlink-resolved) ledger identity.
_prompt_owner_id() {
  ( CDPATH= cd -- "$TARGET" 2>/dev/null && pwd -P ) || printf '%s\n' "$TARGET"
}

# _owners_file <prompts-dir> <cmd-name> — the ledger path for that prompt. Dot-prefixed
# and NOT `.md`, so Codex's `*.md` prompt discovery never surfaces it as a command.
_owners_file() { printf '%s\n' "$1/.$2.owners"; }

# _owners_live <prompts-dir> <cmd-name> — print the ledger's LIVE owners, one per line,
# dropping entries whose target no longer holds a `.harness/` install. Returns 1 when the
# ledger is missing or unreadable (ownership UNKNOWN — callers must not reclaim).
_owners_live() {
  _ol_f="$(_owners_file "$1" "$2")"
  { [ -f "$_ol_f" ] && [ -r "$_ol_f" ]; } || return 1
  while IFS= read -r _ol_e || [ -n "$_ol_e" ]; do
    [ -n "$_ol_e" ] || continue
    [ -d "$_ol_e/.harness" ] || continue
    printf '%s\n' "$_ol_e"
  done < "$_ol_f"
}

# _owners_claim <prompts-dir> <cmd-name> — record the current target as an owner
# (idempotent). Never rewrites a ledger it cannot read: clobbering it would erase the
# other targets' claims, which is exactly the data loss this ledger exists to prevent.
_owners_claim() {
  _oc_f="$(_owners_file "$1" "$2")"
  if [ -e "$_oc_f" ] && [ ! -r "$_oc_f" ]; then return 0; fi
  { _owners_live "$1" "$2" || :; _prompt_owner_id; } | sort -u > "$_oc_f.tmp" 2>/dev/null || return 0
  mv "$_oc_f.tmp" "$_oc_f" 2>/dev/null || rm -f "$_oc_f.tmp" 2>/dev/null || :
}

# _owners_release <prompts-dir> <cmd-name> — drop the current target's claim. Exits 0 ONLY
# when the prompt is left UNOWNED (safe to reclaim, ledger removed); 1 when another live
# target still wants it, or ownership is unknown/unmanageable — in both of which cases the
# caller must leave the shared prompt alone.
_owners_release() {
  _or_f="$(_owners_file "$1" "$2")"
  [ -e "$_or_f" ] || return 1                              # no ledger ⇒ unknown ⇒ keep
  { [ -r "$_or_f" ] && [ -w "$_or_f" ]; } || return 1      # unreadable/frozen ⇒ keep
  _or_rest="$(_owners_live "$1" "$2" | grep -vxF "$(_prompt_owner_id)" || :)"
  if [ -n "$_or_rest" ]; then
    printf '%s\n' "$_or_rest" > "$_or_f" 2>/dev/null || :
    return 1
  fi
  rm -f "$_or_f" 2>/dev/null || :
  return 0
}

# _is_pr_loop_cmd <cmd-name> — true for the pr_loop-GATED command names (the only ones
# whose global prompt is ledger-governed).
_is_pr_loop_cmd() {
  case " $HARNESS_PR_LOOP_CMDS " in *" $1 "*) return 0 ;; esac
  return 1
}

# validate_csv <csv> — split a comma-separated override on commas, trim each token,
# drop empties, de-duplicate, validate each against the registry; `die` non-zero
# naming the first unknown token (R7). On success, print the sorted keys (one per
# line). Makes no filesystem changes (caller has not touched the target yet).
validate_csv() {
  _out=""
  _ifs="$IFS"; IFS=','
  for _tok in $1; do
    IFS="$_ifs"
    # trim surrounding whitespace
    _tok="$(printf '%s' "$_tok" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -n "$_tok" ] || continue
    agent_known "$_tok" || die "unknown agent key '$_tok' in --agents/HARNESS_AGENTS (known: $AGENT_KEYS)"
    _out="$_out $_tok"
    IFS=','
  done
  IFS="$_ifs"
  normalize_keys "$_out"
}

# toggle_select <baseline-newline-list> — pure-`read` numbered toggle UI (R1, R9).
# Only ever called on an interactive TTY. Prints the agent keys numbered with each
# key's pre-check state taken from <baseline>; the user types space/comma-separated
# numbers to toggle entries, then a blank line (or `done`) confirms. Prints the
# resolved sorted keys (one per line) on stdout; all prompts go to stderr so the
# captured stdout is purely the selection.
toggle_select() {
  _baseline="$1"
  # Build a positional list of keys and a parallel on/off state.
  _i=0
  for _k in $AGENT_KEYS; do
    _i=$((_i + 1))
    eval "_key_$_i=\$_k"
    if printf '%s\n' "$_baseline" | grep -qx "$_k"; then
      eval "_on_$_i=1"
    else
      eval "_on_$_i=0"
    fi
  done
  _n="$_i"
  echo "Select which agent front-ends to stamp (toggle by number, blank line to confirm):" >&2
  while :; do
    _i=0
    while [ "$_i" -lt "$_n" ]; do
      _i=$((_i + 1))
      eval "_k=\$_key_$_i; _s=\$_on_$_i"
      if [ "$_s" = 1 ]; then _mark="[x]"; else _mark="[ ]"; fi
      printf '  %d) %s %s\n' "$_i" "$_mark" "$_k" >&2
    done
    printf 'toggle #s (or Enter to confirm): ' >&2
    if ! read -r _line; then break; fi
    [ -n "$_line" ] || break
    case "$_line" in done|DONE|d) break ;; esac
    for _num in $(printf '%s' "$_line" | tr ',' ' '); do
      case "$_num" in
        *[!0-9]*) echo "  ignoring '$_num' (not a number)" >&2; continue ;;
      esac
      if [ "$_num" -ge 1 ] && [ "$_num" -le "$_n" ]; then
        eval "_cur=\$_on_$_num"
        if [ "$_cur" = 1 ]; then eval "_on_$_num=0"; else eval "_on_$_num=1"; fi
      else
        echo "  ignoring '$_num' (out of range 1-$_n)" >&2
      fi
    done
  done
  _sel=""
  _i=0
  while [ "$_i" -lt "$_n" ]; do
    _i=$((_i + 1))
    eval "_k=\$_key_$_i; _s=\$_on_$_i"
    [ "$_s" = 1 ] && _sel="$_sel $_k"
  done
  normalize_keys "$_sel"
}

# tui_capable — true (exit 0) iff we can drive a raw-mode cursor TUI: stdin is an
# interactive TTY AND `stty` can save + enter + restore raw mode. Probes by saving
# the current terminal settings and immediately restoring them; any failure (no
# stty, not a real tty, sandboxed) returns non-zero so the caller falls back to the
# numbered toggle_select. Emits nothing to stdout (probe output is discarded).
tui_capable() {
  [ -t 0 ] || return 1
  command -v stty >/dev/null 2>&1 || return 1
  _probe="$(stty -g 2>/dev/null)" || return 1
  [ -n "$_probe" ] || return 1
  # Confirm we can actually restore from a saved snapshot.
  stty "$_probe" 2>/dev/null || return 1
  return 0
}

# tui_select <baseline-newline-list> — raw-mode arrow-key + spacebar checkbox UI
# (the preferred interactive picker; falls back via resolve_agents to toggle_select
# when tui_capable is false). Renders the agent keys as a cursor-driven list:
#   ↑/↓ (or k/j) move a `>` cursor · Space toggles the highlighted [x]/[ ] · Enter
#   confirms · q/Esc confirms the current selection too.
# Pre-check state seeds from <baseline> exactly as toggle_select does. ALL UI goes to
# stderr; only the resolved sorted keys (one per line, via normalize_keys) hit stdout,
# so the captured SELECTED contract is unchanged. Raw mode is entered with `stty` and
# UNCONDITIONALLY restored: an EXIT trap restores on the normal return path, while a
# shared `_tui_abort` routine restores AND aborts the whole installer (kill -INT $$ +
# exit 130). Ctrl-C is terminal-independent: the INT/TERM trap catches it where the
# terminal generates SIGINT, and an explicit byte-3 (ETX) arm in the read loop catches
# it on `-isig` terminals / PTYs that deliver it as a raw byte — so Ctrl-C never leaves
# the terminal in raw mode NOR silently continues to write files on the next Enter.
tui_select() {
  _baseline="$1"
  # Positional key list + parallel on/off state (same seeding as toggle_select).
  _i=0
  for _k in $AGENT_KEYS; do
    _i=$((_i + 1))
    eval "_key_$_i=\$_k"
    if printf '%s\n' "$_baseline" | grep -qx "$_k"; then
      eval "_on_$_i=1"
    else
      eval "_on_$_i=0"
    fi
  done
  _n="$_i"
  _cursor=1

  # Save terminal settings and guarantee restoration on ANY exit path.
  _saved_stty="$(stty -g 2>/dev/null)"
  # Ctrl-C abort is delivered two ways depending on the terminal, and BOTH must end
  # in the exact same restore+abort sequence (Codex P2 #3405383752, #3405430430):
  #   • Signal path — terminals/PTYs that keep `isig` (interrupt special chars) on
  #     translate Ctrl-C into SIGINT. The INT/TERM trap below catches it.
  #   • Raw-byte path — terminals that already have `-isig`, or PTYs that deliver
  #     VINTR as raw byte 3 (ETX), send Ctrl-C straight into the read loop as a byte.
  #     The loop's `case 3)` arm handles it (see below). Without this arm the byte is
  #     unhandled and the picker spins in raw mode forever.
  # `_tui_abort` is the single shared restore+abort routine both paths call:
  #   restore the saved stty, show the cursor (stderr), clear traps so the re-raised
  #   signal hits the default disposition, then abort the WHOLE installer. tui_select
  #   runs inside a command-substitution subshell (SELECTED="$(tui_select …)"), so a
  #   bare `exit` would only end the subshell and let the parent continue on the next
  #   Enter; instead we `kill -INT "$$"` — in POSIX sh `$$` is the ORIGINAL (parent)
  #   shell's PID even inside a subshell, so this aborts the installer process itself
  #   (no top-level trap → default terminate). `exit 130` is the belt-and-suspenders
  #   fallback if the kill is somehow swallowed. EXIT (normal confirm) just restores
  #   the terminal and must NOT force a non-zero status, or the captured SELECTED
  #   contract would look like a failure.
  _tui_abort() {
    stty "$_saved_stty" 2>/dev/null
    printf '\033[?25h' >&2
    trap - EXIT INT TERM
    kill -INT "$$" 2>/dev/null
    exit 130
  }
  # shellcheck disable=SC2064
  trap "stty '$_saved_stty' 2>/dev/null; printf '\\033[?25h' >&2" EXIT
  trap '_tui_abort' INT TERM
  # Raw-ish mode: no echo, char-at-a-time (-icanon min 1). We intentionally do NOT
  # add `isig`: Ctrl-C is handled portably via the explicit byte-3 arm in the read
  # loop, which works even where `isig` is unavailable/off; the INT/TERM trap stays
  # as the secondary net for terminals that DO generate the signal.
  stty -echo -icanon min 1 time 0 2>/dev/null
  printf '\033[?25l' >&2  # hide cursor

  printf '%s\n' \
    "Select which agent front-ends to stamp:" \
    "  ↑/↓ (or k/j) move · Space toggles [x]/[ ] · Enter confirms" >&2

  _drawn=0
  _redraw() {
    # Move cursor up to overwrite the previous render (after the first draw).
    if [ "$_drawn" = 1 ]; then printf '\033[%dA' "$_n" >&2; fi
    _i=0
    while [ "$_i" -lt "$_n" ]; do
      _i=$((_i + 1))
      eval "_k=\$_key_$_i; _s=\$_on_$_i"
      if [ "$_s" = 1 ]; then _mark="[x]"; else _mark="[ ]"; fi
      if [ "$_i" = "$_cursor" ]; then _point=">"; else _point=" "; fi
      printf '\033[2K\r %s %s %s\n' "$_point" "$_mark" "$_k" >&2
    done
    _drawn=1
  }
  _redraw

  # Read one byte at a time; decode arrows (ESC [ A/B) and act on space/enter/etc.
  while :; do
    _c="$(dd bs=1 count=1 2>/dev/null | od -An -tu1 | tr -d ' ')"
    # Empty read = EOF (e.g. Ctrl-D / byte 4 closing stdin). Don't spin in raw mode —
    # treat it as an abort so the terminal is restored and no install_one runs.
    [ -n "$_c" ] || _tui_abort
    case "$_c" in
      3|4)    # Ctrl-C (ETX) / Ctrl-D (EOT) raw byte → abort. Covers terminals/PTYs
              # that deliver the interrupt as a byte instead of SIGINT (`-isig`).
        _tui_abort ;;
      10|13)  # LF / CR → Enter, confirm
        break ;;
      32)     # Space → toggle highlighted row
        eval "_cur=\$_on_$_cursor"
        if [ "$_cur" = 1 ]; then eval "_on_$_cursor=0"; else eval "_on_$_cursor=1"; fi
        _redraw ;;
      107)    # 'k' → up
        if [ "$_cursor" -gt 1 ]; then _cursor=$((_cursor - 1)); _redraw; fi ;;
      106)    # 'j' → down
        if [ "$_cursor" -lt "$_n" ]; then _cursor=$((_cursor + 1)); _redraw; fi ;;
      113)    # 'q' → confirm current selection and quit
        break ;;
      27)     # ESC — could be a bare Esc (abort/confirm) or an arrow sequence ESC [ A/B.
        # The continuation bytes must be read NON-blocking: a bare Esc sends no further
        # bytes, so a blocking `min 1` read would hang and freeze the installer. Switch
        # to `min 0 time 1` (0.1s grace) for the sequence reads, then restore `min 1`.
        stty -echo -icanon min 0 time 1 2>/dev/null
        _c2="$(dd bs=1 count=1 2>/dev/null | od -An -tu1 | tr -d ' ')"
        if [ "$_c2" = 91 ]; then
          _c3="$(dd bs=1 count=1 2>/dev/null | od -An -tu1 | tr -d ' ')"
        else
          _c3=""
        fi
        stty -echo -icanon min 1 time 0 2>/dev/null
        if [ "$_c2" != 91 ]; then
          break   # bare Esc (or anything not starting a CSI) → confirm current selection
        fi
        case "$_c3" in
          65)  # 'A' → up arrow
            if [ "$_cursor" -gt 1 ]; then _cursor=$((_cursor - 1)); _redraw; fi ;;
          66)  # 'B' → down arrow
            if [ "$_cursor" -lt "$_n" ]; then _cursor=$((_cursor + 1)); _redraw; fi ;;
        esac ;;
    esac
  done

  # Restore terminal NOW and clear the trap (normal completion path).
  stty "$_saved_stty" 2>/dev/null
  printf '\033[?25h' >&2
  trap - EXIT INT TERM

  _sel=""
  _i=0
  while [ "$_i" -lt "$_n" ]; do
    _i=$((_i + 1))
    eval "_k=\$_key_$_i; _s=\$_on_$_i"
    [ "$_s" = 1 ] && _sel="$_sel $_k"
  done
  normalize_keys "$_sel"
}

# resolve_agents <target> — resolve the SELECTED agent set for this run (R1, R5,
# R6, R9, R11). Resolution order, first match wins, decoupled from VERSION/UPGRADE:
#   1. Override (R5/R7): a non-empty $AGENTS_OVERRIDE (from --agents/HARNESS_AGENTS)
#      → validate_csv, no prompt — wins over persisted + TTY.
#   2. Interactive (R1/R9): else if stdin is a TTY → pre-check baseline is the
#      persisted .harness/.agents if present (R9) else ALL (R1). On a raw-capable
#      TTY this runs the arrow-key + spacebar checkbox picker (tui_select); when
#      raw mode is unavailable it gracefully falls back to the numbered
#      toggle_select. Both resolve the identical SELECTED set from the same baseline.
#   3. No-TTY default (R6): else → ALL keys (back-compat: stamp everything).
# Sets the global SELECTED to a sorted, newline-separated key list.
resolve_agents() {
  _t="$1"
  _persisted="$_t/.harness/.agents"
  if [ -n "${AGENTS_OVERRIDE:-}" ]; then
    SELECTED="$(validate_csv "$AGENTS_OVERRIDE")"
    info "agents: explicit selection ($(printf '%s' "$SELECTED" | tr '\n' ' '))"
  elif [ -t 0 ]; then
    if [ -f "$_persisted" ]; then
      _base="$(normalize_keys "$(cat "$_persisted")")"
    else
      _base="$(normalize_keys "$AGENT_KEYS")"
    fi
    # Preferred interactive path: arrow-key + spacebar checkbox TUI when the
    # terminal supports raw mode; otherwise fall back to the numbered toggle list.
    if tui_capable; then
      SELECTED="$(tui_select "$_base")"
    else
      SELECTED="$(toggle_select "$_base")"
    fi
    info "agents: interactive selection ($(printf '%s' "$SELECTED" | tr '\n' ' '))"
  else
    SELECTED="$(normalize_keys "$AGENT_KEYS")"
  fi
}

# ── install_one <target> ──────────────────────────────────────────────────────
# Installs (or upgrades) the harness into <target>. Identical behavior to the
# historical single-target installer. Sets LAST_UPGRADE to 0 (fresh) or 1 (upgrade)
# so callers can branch. <target> must already be validated as a directory != SRC.
LAST_UPGRADE=0
install_one() {
  TARGET="$1"
  H="$TARGET/.harness"
  UPGRADE=0
  if [ -f "$H/.harness-version" ]; then UPGRADE=1; fi

  # Run-scoped ledger for model-routing diagnostics (E17-F01): resolve_model runs inside
  # command substitutions, so de-duplication has to survive a subshell — hence a file.
  # Cleared per target so a cascade install still advises once per repo. Removed with
  # CMDDIR after §7.
  MODELS_OFF=0
  MODEL_DIAG="$(mktemp 2>/dev/null || mktemp -t harness-mdl)"
  : > "$MODEL_DIAG"

  # ── agent selection (E08-F01) ───────────────────────────────────────────────
  # Capture the PRIOR persisted selection (for add/remove reconciliation, R12/R13)
  # BEFORE anything is written this run, then resolve the new SELECTED set. Note
  # this is decoupled from UPGRADE/VERSION — it runs every install_one (R11).
  PRIOR_AGENTS=""
  if [ -f "$H/.agents" ]; then
    PRIOR_AGENTS="$(normalize_keys "$(cat "$H/.agents")")"
  elif [ "$UPGRADE" = 1 ]; then
    # Legacy upgrade: a pre-E08 install stamped ALL front-ends but persisted no
    # selection. Treat an existing install with no .harness/.agents as the
    # all-agents baseline, so the first selective upgrade can actually remove the
    # now-deselected glue (e.g. GEMINI.md, opencode.json) instead of leaving it
    # stale. A fresh install (UPGRADE=0) keeps PRIOR_AGENTS empty — nothing to
    # remove. (Codex P2 #3400941300.)
    #
    # EXCLUDE codex from this fallback: a legacy install (no persisted selection)
    # predates the codex front-end entirely, so it never installed the GLOBAL codex
    # prompts. Because that glue lives in a shared, cross-target `$CODEX_HOME/prompts`
    # dir, letting the all-agents fallback assume prior codex ownership would reclaim
    # pristine prompts that may belong to ANOTHER harness target. codex removal must
    # therefore fire only from an EXPLICIT persisted prior selection, never this
    # legacy baseline. (Codex r4 P2.)
    PRIOR_AGENTS="$(normalize_keys "$AGENT_KEYS" | grep -vx codex)"
  fi
  resolve_agents "$TARGET"

  echo "── harness install v$VERSION → $TARGET ──"
  if [ "$UPGRADE" = 1 ]; then info "existing install (v$(cat "$H/.harness-version")) — upgrading"; fi
  mkdir -p "$H"

  # ── 1. harness body → .harness/  (verbatim, overwritten each run) ───────────
  copy() { # copy <relpath>   (file or directory) from SRC into .harness/
    _src="$SRC/$1"; _dst="$H/$1"
    if [ ! -e "$_src" ]; then die "source missing: $1"; fi
    mkdir -p "$(dirname "$_dst")"
    rm -rf "$_dst"
    cp -R "$_src" "$_dst"
  }
  copy AGENTS.md
  copy init.sh
  copy agents
  copy docs
  copy store
  copy tools
  copy specs/_templates
  copy specs/glossary.md
  copy umbrella.manifest.example.yaml
  copy umbrella.gitignore.example
  chmod +x "$H/init.sh" 2>/dev/null || true
  chmod +x "$H/tools/telemetry-report.py" 2>/dev/null || true
  chmod +x "$H/tools/sync-board.mjs" 2>/dev/null || true
  chmod +x "$H/tools/tasks-lock.py" 2>/dev/null || true   # E15-F01 board write lock helper
  chmod +x "$H/tools/validate-board.py" 2>/dev/null || true   # E15-F01 shared board validator (init.sh + tasks-lock)
  chmod +x "$H/tools/fix-worktree.sh" 2>/dev/null || true   # E15-F02 isolated fix-worktree lifecycle helper
  chmod +x "$H/tools/task-diagnostics.py" 2>/dev/null || true   # E16-F01 warn-only dependency diagnostics
  chmod +x "$H/tools/next-task.mjs" 2>/dev/null || true   # E16-F03 deterministic read-only selector
  chmod +x "$H/tools/wait-for-codex.sh" 2>/dev/null || true   # E18-F01 /sdd-pr-loop background Codex watcher
  # NOTE: harness.config.yaml is intentionally NOT copied here — it is seeded once
  # below (project-owned), so upgrades never erase bootstrap-set verification commands.
  ok "harness body installed (.harness/)"

  # ── 2. project workspace → .harness/  (seed once, never clobber) ────────────
  mkdir -p "$H/specs/epics" "$H/progress" "$H/state"
  if [ ! -f "$H/specs/epics/.gitkeep" ]; then : > "$H/specs/epics/.gitkeep"; fi

  # harness.config.yaml is project-owned once seeded: bootstrap fills in the
  # verification commands (and store backend), so an upgrade must NOT clobber it.
  if [ ! -f "$H/harness.config.yaml" ]; then
    cp "$SRC/harness.config.yaml" "$H/harness.config.yaml"
    # the target is a DIFFERENT product — start its verification commands blank.
    sed -e 's|^\( *test_command:\).*|\1 ""        # set during bootstrap|' \
        -e 's|^\( *lint_command:\).*|\1 ""        # set during bootstrap|' \
        -e 's|^\( *typecheck_command:\).*|\1 ""   # set during bootstrap|' \
        "$H/harness.config.yaml" > "$H/harness.config.yaml.tmp" \
        && mv "$H/harness.config.yaml.tmp" "$H/harness.config.yaml"
    # ...and the target may not have the Codex GitHub App — the review loop is OPT-IN, so
    # a fresh seed never inherits this repo's own `pr_loop.enabled: true` (E18-F01 R15).
    seed_pr_loop_optin "$H/harness.config.yaml"
    info "seeded harness.config.yaml (verification commands blank, pr_loop disabled)"
  else
    info "harness.config.yaml preserved (bootstrap verification commands kept)"
    # Additive, value-preserving migration: append any missing default keys (e.g.
    # the F01 umbrella.manifest / verification.integration_command) to the preserved
    # config without altering existing values or comments.
    migrate_config "$H/harness.config.yaml"
  fi

  # init.project.sh is project-owned: init.sh (BODY, overwritten on upgrade) sources
  # it for project-specific gate checks, so they live HERE and survive upgrades.
  if [ ! -f "$H/init.project.sh" ]; then
    cat > "$H/init.project.sh" <<'EOF'
# init.project.sh — project-specific gate checks.
# Sourced by init.sh from the PROJECT ROOT (not .harness/), so paths and commands
# like `npm test` / `pytest` resolve against the repo. Seeded once; NEVER clobbered
# on upgrade — put your real checks here instead of editing init.sh. Inherits the
# `fail "msg"` (abort the gate) and `ok "msg"` helpers from init.sh.
#
# Examples:
#   command -v node >/dev/null 2>&1 || fail "node not installed"
#   npm test --silent             || fail "tests are failing — do not start work"
EOF
    info "seeded init.project.sh (no checks yet)"
  else
    info "init.project.sh preserved"
  fi

  if [ ! -f "$H/specs/product.md" ]; then
    cat > "$H/specs/product.md" <<'EOF'
---
status: draft
---

# <Product name> — Product Constitution

> Layer 0. The stable, high-level "what & why". Rewrite this for your product,
> then run /sdd-next to bootstrap (detect test/lint commands, draft epics).

## What this product is
TODO

## Who it is for
TODO

## Principles & hard constraints
TODO
EOF
    info "seeded specs/product.md (stub)"
  fi

  if [ ! -f "$H/state/tasks.json" ]; then
    cat > "$H/state/tasks.json" <<'EOF'
{
  "$schema": "../store/tasks.schema.json",
  "project": "TODO-rename-me",
  "epics": [
    {
      "id": "E00",
      "title": "Harness bootstrap",
      "status": "in-progress",
      "features": [
        {
          "id": "E00-F01",
          "title": "Bootstrap: adapt the harness to this project",
          "status": "pending",
          "sdd": true,
          "autonomous": false,
          "depends_on": [],
          "spec_path": "specs/epics/E00-bootstrap/F01-adapt/"
        }
      ]
    }
  ]
}
EOF
    info "seeded state/tasks.json (bootstrap task)"
  fi

  if [ ! -f "$H/progress/history.md" ]; then
    printf '# Project history\n\n> Append one line per completed feature (Reviewer verdict).\n' > "$H/progress/history.md"
  fi
  if [ ! -f "$H/progress/.gitkeep" ]; then : > "$H/progress/.gitkeep"; fi

  # Telemetry is local-only runtime data. In an installed consumer the harness body
  # under .harness/ is committed and shared, so a blanket parent ignore would over-
  # exclude it. Seed a TARGETED .harness/.gitignore that ignores the telemetry log, so
  # the committed harness body coexists with a local-only log. We ignore BOTH the default
  # `telemetry.jsonl` AND the configured `telemetry.log` if it was overridden to a
  # different RELATIVE path (resolved under .harness/, where this .gitignore lives) — so a
  # documented override like `custom/my.jsonl` is still kept out of VCS. An ABSOLUTE
  # override lives outside the repo and needs no ignore. NOTE: if you change telemetry.log
  # AFTER install without re-running the installer, add the new path here yourself.
  _tlog="$(_cfg_telemetry_log "$H/harness.config.yaml" 2>/dev/null)"
  # Also ignore the default Jira mirror PAT file (mirror.board.pat_file default `jira.pat`,
  # resolved under the harness dir ⇒ `.harness/jira.pat`, i.e. `jira.pat` relative to this
  # .harness/ .gitignore where the tool actually reads it) so a
  # provisioned Jira PAT can NEVER be committed by default. The PAT value itself is never
  # written to config — only this path is seeded here. See store/board-mirror.md "jira contract".
  # Also ignore the runtime board write lockfile (E15-F01: mirror.board-neutral
  # advisory lock on state/tasks.json). It is a zero-byte flock target created at
  # runtime under .harness/ (state/tasks.json.lock), never board data — keep it out
  # of VCS. Path is relative to this .harness/ .gitignore. See store/local.md set_status.
  # Also ignore the /sdd-pr-loop round cache (E18-F01): <HARNESS_DIR>/.pr-loop/<pr>/round-<n>/
  # holds fetched GitHub review JSON + per-round fix notes. Pure runtime scratch, rebuildable
  # from the `gh` API, never board data — keep it out of VCS. Path is relative to this
  # .harness/ .gitignore, where the loop actually writes it.
  _ignores='telemetry.jsonl
jira.pat
state/tasks.json.lock
.pr-loop/'
  case "$_tlog" in
    ''|telemetry.jsonl|/*) : ;;                 # default, unset, or absolute → nothing extra
    *) _ignores="$_ignores
$_tlog" ;;                                       # relative override → also ignore it
  esac
  if [ ! -f "$H/.gitignore" ]; then
    { printf '# Local-only telemetry log (see .harness/agents/orchestrator.md "## Telemetry").\n'
      printf '# Jira mirror PAT file (mirror.board.pat_file default) — never commit a PAT.\n'
      printf '%s\n' "$_ignores"; } > "$H/.gitignore"
    info "seeded .harness/.gitignore (ignores telemetry log)"
  else
    printf '%s\n' "$_ignores" | while IFS= read -r _pat; do
      [ -n "$_pat" ] || continue
      grep -qF "$_pat" "$H/.gitignore" || printf '%s\n' "$_pat" >> "$H/.gitignore"
    done
    info ".harness/.gitignore ensured (telemetry log ignored)"
  fi

  # Personal/runtime agent state must never be committed to a SHARED project (e.g. a
  # spec/umbrella repo a team clones). Claude Code writes per-developer config
  # (.claude/settings.local.json), a scheduler lock (.claude/scheduled_tasks.lock), local
  # prompt override files, and browser-MCP scratch at the PROJECT ROOT — none of which belong in VCS, while the
  # harness-GENERATED .claude/agents and .claude/commands DO. Seed/extend the project-root
  # .gitignore with TARGETED, append-only ignores (never clobbering existing entries), so a
  # shared repo stays free of one developer's local state. Full model:
  # .harness/docs/CONFIG-LAYERING.md.
  _root_ignores='.claude/settings.local.json
.claude/scheduled_tasks.lock
.claude/worktrees/
AGENTS.local.md
CLAUDE.local.md
AGENTS.override.md'
  if [ ! -f "$TARGET/.gitignore" ]; then
    { printf '# Personal/runtime agent state — never commit (see .harness/docs/CONFIG-LAYERING.md).\n'
      printf '%s\n' "$_root_ignores"
      printf '# Per-tool MCP scratch dirs your setup may create — add your own (example):\n'
      printf '#.playwright-mcp/\n'; } > "$TARGET/.gitignore"
    info "seeded project-root .gitignore (personal/runtime agent state)"
  else
    printf '%s\n' "$_root_ignores" | while IFS= read -r _pat; do
      [ -n "$_pat" ] || continue
      grep -qxF "$_pat" "$TARGET/.gitignore" || printf '%s\n' "$_pat" >> "$TARGET/.gitignore"
    done
    info "project-root .gitignore ensured (personal/runtime agent state)"
  fi
  ok "project workspace ready (.harness/specs, state, progress)"

  # ── 3. version stamp + manifest ─────────────────────────────────────────────
  printf '%s\n' "$VERSION" > "$H/.harness-version"
  cat > "$H/manifest.txt" <<EOF
harness-sdd install manifest — v$VERSION
Generated by harness-install.sh. Do not edit by hand.

HARNESS-OWNED  (overwritten on every upgrade):
  .harness/AGENTS.md  .harness/init.sh
  .harness/agents/  .harness/docs/  .harness/store/  .harness/tools/  .harness/specs/_templates/
  .harness/specs/glossary.md  .harness/umbrella.manifest.example.yaml  .harness/umbrella.gitignore.example
  .claude/agents/*  .claude/commands/*   .opencode/command/*   (repo root, regenerated)
  .agents/rules/*  .agents/agents/*  .agents/workflows/*   (repo root, regenerated; Antigravity glue)
  CLAUDE.md / AGENTS.md / GEMINI.md  -> only the harness:begin..end block

PR LOOP GLUE  (OPT-IN — created ONLY while pr_loop.enabled reads exactly true; a fresh
install seeds false, so none of this exists until you turn it on — E18-F01):
  .claude/commands/sdd-pr-loop.md   .opencode/command/sdd-pr-loop.md
  .agents/workflows/sdd-pr-loop.md  \${CODEX_HOME:-~/.codex}/prompts/sdd-pr-loop.md (GLOBAL)
  .claude/agents/pr-fixer.md  .opencode/agent/pr-fixer.md  .agents/agents/pr-fixer.md
  Flipping pr_loop.enabled back to false on a re-run RECLAIMS all of the above
  (pristine-only in the user-owned \$CODEX_HOME prompts dir and .agents/ tree) and prunes
  empty dirs. No pr-fixer artifact is ever created for the codex or gemini front-ends.
  The GLOBAL prompt is shared by every target on this machine, so it is ledger-governed
  (\${CODEX_HOME:-~/.codex}/prompts/.sdd-pr-loop.owners): turning the gate off here only
  retires THIS repo's claim, and the prompt survives while any other target still wants
  it — or whenever that ownership cannot be read.

MODEL ROUTING  (created ONLY when models: resolves a role to a concrete value):
  .gemini/agents/*               per-role Gemini agent definitions (regenerated)
  .codex/agents/*                per-role Codex agent definitions, PROJECT-LOCAL
                                 (never written to \$CODEX_HOME / ~/.codex)
  .harness/.opencode.stamp       byte copy of the last generated opencode.json, kept
                                 only while it carries a model key (enables re-stamping)
  .harness/.model-agents/        byte copies of the last generated .gemini/.codex per-role
                                 files, kept only while those files exist (lets a switch
                                 back to \`inherit\` reclaim them instead of orphaning them)
  With no models: block — or every role on \`inherit\` — none of the above exists and
  the generated tree is byte-identical to a harness without model routing.

PROJECT-OWNED  (seeded once, never clobbered on upgrade):
  .harness/harness.config.yaml   (verification commands + store backend)
  .harness/init.project.sh       (project-specific init.sh gate checks)
  .harness/specs/product.md  .harness/specs/epics/
  .harness/state/tasks.json  .harness/progress/
  umbrella.manifest.yaml         (umbrella mode only: coordinator manifest)

AGENT SELECTION  (E08-F01):
  .harness/.agents               harness-owned: the selected agent keys, one per line
                                 (claude|gemini|opencode|antigravity|codex), overwritten each run.
  Choose with --agents=<csv> / HARNESS_AGENTS=<csv>, an interactive toggle list, or
  (no TTY, no override) ALL. Deselecting an agent on a re-run REMOVES its glue above
  (its pointer block / .claude|.opencode dir / generated opencode.json) and warns;
  the shared AGENTS.md entrypoint and the .harness/ body are never removed.
EOF

  # ── 4. entrypoint pointer blocks (idempotent marked region) ─────────────────
  write_pointer() { # write_pointer <relative-file>
    _f="$TARGET/$1"
    _block="$MARK_BEGIN
## Agent Harness (Spec-Driven Development)
This project uses a portable agent harness installed in \`.harness/\`.
Start every agent session as the **Orchestrator**:
1. Run \`.harness/init.sh\` — if it exits non-zero, STOP.
2. Read \`.harness/AGENTS.md\` (the harness source of truth) and resolve its
   relative paths against \`.harness/\` (config, agents/, specs/, state/, store/,
   docs/, progress/).
3. Local prompt override (if present): read \`AGENTS.local.md\` beside this entrypoint
   after committed instructions as personal, additive guidance; committed instructions remain authoritative on conflict.
4. Product/source code lives at the repo root; harness bookkeeping lives in
   \`.harness/\`. In Claude Code, run \`/sdd-next\`.
$MARK_END"
    if [ -f "$_f" ] && grep -qF "$MARK_BEGIN" "$_f"; then
      # Replace the marked block IN PLACE: keep the prefix before the begin marker
      # and the suffix after the end marker, so user content on either side keeps
      # its original order (the markers contain no sed-special characters).
      {
        sed "/$MARK_BEGIN/,\$d" "$_f"   # prefix: everything before the begin marker
        printf '%s\n' "$_block"
        sed "1,/$MARK_END/d" "$_f"      # suffix: everything after the end marker
      } > "$_f.tmp"
      mv "$_f.tmp" "$_f"
    else
      if [ -f "$_f" ]; then printf '\n' >> "$_f"; fi
      printf '%s\n' "$_block" >> "$_f"
    fi
  }
  # remove_pointer <relative-file> — delete the marked harness:begin..end block from
  # <file> in place, preserving any user prose on either side (mirrors write_pointer's
  # marker-aware edit). If the file becomes empty/whitespace-only afterward (it was
  # harness-only), remove it. Never touches a file that has no harness block. (R13)
  remove_pointer() {
    _f="$TARGET/$1"
    [ -f "$_f" ] || return 0
    grep -qF "$MARK_BEGIN" "$_f" || return 0
    {
      sed "/$MARK_BEGIN/,\$d" "$_f"   # prefix: everything before the begin marker
      sed "1,/$MARK_END/d" "$_f"      # suffix: everything after the end marker
    } > "$_f.tmp"
    mv "$_f.tmp" "$_f"
    # Remove the file only if nothing but whitespace remains (it was harness-only).
    if ! grep -q '[^[:space:]]' "$_f"; then rm -f "$_f"; fi
    info "removed harness pointer block from $1"
  }
  # remove_owned <dir-rel> <agent-label> <stem...> — on deselection, delete ONLY the
  # named harness-generated files (<dir>/<stem>.md) inside <dir>, then rmdir <dir> if it
  # is now empty. A user's own files in the same dir are preserved (the dir survives,
  # non-empty). This keeps removal scoped to harness-owned glue so a selective re-run
  # never deletes unrelated project/user config. (R13; Codex r2 P1)
  remove_owned() {
    _rel="$1"; _dir="$TARGET/$1"; _label="$2"; shift 2
    [ -d "$_dir" ] || return 0
    _removed=''
    for _b in "$@"; do
      if [ -f "$_dir/$_b.md" ]; then rm -f "$_dir/$_b.md"; _removed="$_removed $_b.md"; fi
    done
    [ -n "$_removed" ] && echo "⚠️  removed deselected agent '$_label' glue:$_removed (in $_rel/)" >&2
    rmdir "$_dir" 2>/dev/null || { [ -n "$_removed" ] && echo "ℹ️  kept $_rel/ — contains non-harness files" >&2; }
  }
  # gen_opencode_json <dest> — write the canonical generated opencode.json to <dest>.
  # Single source of truth for both the stamp (§6) and the deselect byte-comparison,
  # so removal deletes ONLY a pristine generated file and never a user-edited one.
  # _oc_model <role> — the `"model": "<value>", ` JSON member for <role>, or the EMPTY
  # string when the role resolves to `inherit`/omission. Interpolated inline below, so an
  # unconfigured target yields byte-for-byte the same opencode.json it always did.
  _oc_model() {
    _ocm="$(resolve_model opencode "$1")"
    if [ -n "$_ocm" ]; then printf '"model": "%s", ' "$_ocm"; fi
  }
  gen_opencode_json() {
    _oc_m_orchestrator="$(_oc_model orchestrator)"
    _oc_m_architect="$(_oc_model architect)"
    _oc_m_builder="$(_oc_model builder)"
    _oc_m_reviewer="$(_oc_model reviewer)"
    _oc_m_scout="$(_oc_model scout)"
    _oc_m_doc_critic="$(_oc_model doc-critic)"
    cat > "$1" <<EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "instructions": [".harness/AGENTS.md"],
  "agent": {
    "orchestrator": { "mode": "primary",  "description": "The Leader: routes the next task, delegates. Never writes code.", ${_oc_m_orchestrator}"prompt": "{file:./.harness/agents/orchestrator.md}" },
    "architect":    { "mode": "subagent", "description": "Spec Author: writes the 4-file spec (EARS).",                     ${_oc_m_architect}"prompt": "{file:./.harness/agents/architect.md}" },
    "builder":      { "mode": "subagent", "description": "Implementer: writes code from an approved spec.",                 ${_oc_m_builder}"prompt": "{file:./.harness/agents/builder.md}" },
    "reviewer":     { "mode": "subagent", "description": "Evaluator: verifies against the spec, runs tests.",               ${_oc_m_reviewer}"prompt": "{file:./.harness/agents/reviewer.md}" },
    "scout":        { "mode": "subagent", "description": "Read-only recon; writes findings to progress/.",                  ${_oc_m_scout}"prompt": "{file:./.harness/agents/scout.md}" },
    "doc-critic":   { "mode": "subagent", "description": "Advisory doc review pass over planning docs + specs. Documents only, never code.", ${_oc_m_doc_critic}"prompt": "{file:./.harness/agents/doc-critic.md}" }
  }
}
EOF
  }

  # gen_oc_agent <role> <description> <dest> — write one FILE-BASED OpenCode sub-agent
  # (.opencode/agent/<role>.md). Hoisted for the same reason as the antigravity emitters:
  # the §7/§7b reclamation byte-compares an on-disk file against a freshly generated body,
  # so emission must live in exactly ONE function. Deliberately independent of
  # gen_opencode_json — the `agent:` map in opencode.json (and the .harness/.opencode.stamp
  # byte contract it feeds) is NOT touched by pr_loop (E18-F01 R11/R12). The body POINTS at
  # the canonical .harness/agents/<role>.md; it never duplicates a role body. No `model:`
  # key: pr-fixer is not in MODEL_ROLES and inherits the session model (R14).
  gen_oc_agent() {
    _oca_role="$1"; _oca_desc="$2"; _oca_dest="$3"
    {
      printf -- '---\n'
      printf 'description: %s\n' "$_oca_desc"
      printf 'mode: subagent\n'
      printf 'permission:\n'
      printf '  edit: allow\n'
      printf '  bash: allow\n'
      printf -- '---\n'
    } > "$_oca_dest"
    cat >> "$_oca_dest" <<EOF

You are the **$_oca_role** for this project's agent harness (installed in \`.harness/\`).

Your full, canonical role definition is \`.harness/agents/$_oca_role.md\` — read it now and
follow it exactly. Resolve every relative path it mentions against \`.harness/\`
(e.g. \`harness.config.yaml\` -> \`.harness/harness.config.yaml\`, \`progress/\` ->
\`.harness/progress/\`).
EOF
  }

  # ── Antigravity .agents/ glue generators — single source of truth ─────────────
  # These are hoisted out of §5c so BOTH the install stamp (§5c) and the deselect
  # byte-compare (§7) call the exact same emitters. The deselect path removes an
  # `.agents/` file ONLY when it is byte-identical to a freshly-generated stamp
  # (pristine), never delete-by-name — so a user's own `.agents/agents/builder.md`
  # (or any standard-named persona/workflow they authored) is preserved. Mirrors
  # the opencode.json `cmp -s` "pristine generated" vs "differs — left in place"
  # contract above. (Codex r2 P1 #3404240336.)

  # gen_ag_rule <dest> — write the canonical .agents/rules/harness.md entrypoint rule.
  gen_ag_rule() {
    cat > "$1" <<'EOF'
---
description: SDD harness entrypoint — boot as the Orchestrator against .harness/.
---

This workspace uses the portable **SDD agent harness** installed in `.harness/`.
Antigravity does not auto-load `AGENTS.md`, so this rule loads the harness for you.

- **Source of truth:** `.harness/AGENTS.md` — read it and resolve every relative
  path it mentions against `.harness/` (config, `agents/`, `specs/`, `state/`,
  `store/`, `docs/`, `progress/`).
- **Start every session as the Orchestrator:** `.harness/agents/orchestrator.md`.
- **Before any work:** run `.harness/init.sh`. If it exits non-zero, STOP.
- **Working model (R12):** Antigravity drives the harness through the
  `description`-gated `.agents/workflows/` slash commands and the `.agents/agents/`
  personas, with `.harness/progress/` files as the hand-off / isolation boundary —
  NOT a Task-tool-style isolated spawn, and NOT an asserted bare-file subagent
  registration (bare-file persona discovery is unconfirmed; the durable primitives
  are this rule + the `description`-gated workflows + the `.harness/progress/`
  hand-off). Hand off through `.harness/progress/`, never by forwarding chat history.

The role files in `.agents/agents/` and the workflows in `.agents/workflows/` are thin
pointers at the canonical `.harness/agents/*.md` roles — they do not duplicate them.
EOF
  }

  # gen_ag_persona <role> <description> <dest> — write one .agents/agents/<role>.md.
  gen_ag_persona() {
    _agp_role="$1"; _agp_desc="$2"; _agp_dest="$3"
    # Fixed key order (description, model); `model:` present or absent, never moved.
    # Antigravity accepts only tier aliases here and needs `agy` >= 1.1.5 — below that
    # the key is inert, never an error. (E17-F01 R13/R19/R21.)
    _agp_model="$(resolve_model antigravity "$_agp_role")"
    {
      printf -- '---\n'
      printf 'description: %s\n' "$_agp_desc"
      if [ -n "$_agp_model" ]; then printf 'model: %s\n' "$_agp_model"; fi
      printf -- '---\n'
    } > "$_agp_dest"
    cat >> "$_agp_dest" <<EOF

You are the **$_agp_role** for this project's agent harness (installed in \`.harness/\`).

Your full, canonical role definition is \`.harness/agents/$_agp_role.md\` — read it now and
follow it exactly. Resolve every relative path it mentions against \`.harness/\`
(e.g. \`harness.config.yaml\` -> \`.harness/harness.config.yaml\`, \`progress/\` ->
\`.harness/progress/\`). Run \`.harness/init.sh\` before any work and halt on its
non-zero exit. Hand off through \`.harness/progress/\` files, never by forwarding
chat history.
EOF
  }

  # ag_personas — emit the role→description mapping ONE place, reused by the §5c
  # install loop and the §7 deselect compare so they can never diverge. Each line is
  # `<role>\t<description>`; callers read it field-by-field.
  ag_personas() {
    cat <<'EOF'
orchestrator	The Leader. Reads state, runs init.sh, routes the next task, delegates to architect/builder/reviewer/scout. Never writes code.
architect	The Spec Author. Writes the 4-file spec in EARS. No production code.
builder	The Implementer. Writes code from an APPROVED spec, one task at a time.
reviewer	The Evaluator. Verifies against the spec, runs tests, approves or rejects.
scout	Read-only codebase reconnaissance. Writes findings to progress/.
doc-critic	Advisory doc review pass over harness-generated planning docs + specs at the plan-output/epic-decomposition/feature-spec checkpoints. Documents only, never production code.
EOF
  }

  # ── model-routing per-role artifacts for gemini + codex (E17-F01) ─────────────
  # These two front-ends have no per-role generated artifact today, so "stamp a model per
  # role" means CREATING the native per-role agent definition. Both emitters are hoisted
  # here so the install stamp (§5e/§5f) and the deselect byte-compare (§7) call the exact
  # same function — emitting twice from two places is what would make a stamped file
  # permanently unremovable. Neither tree is created unless `models_any` says at least one
  # role resolves, so an unconfigured target grows no new directory.

  # gen_gemini_agent <role> <description> <dest> — one `.gemini/agents/<role>.md`.
  # Gemini's `--model` flag and `/model` command do not reach sub-agents, so per-agent
  # frontmatter is the only lever that exists. The body POINTS at the canonical
  # `.harness/agents/<role>.md`; it never duplicates a role body.
  gen_gemini_agent() {
    _gga_role="$1"; _gga_desc="$2"; _gga_dest="$3"
    _gga_model="$(resolve_model gemini "$_gga_role")"
    {
      printf -- '---\n'
      printf 'name: %s\n' "$_gga_role"
      printf 'description: %s\n' "$_gga_desc"
      if [ -n "$_gga_model" ]; then printf 'model: %s\n' "$_gga_model"; fi
      printf -- '---\n'
    } > "$_gga_dest"
    cat >> "$_gga_dest" <<EOF

You are the **$_gga_role** for this project's agent harness (installed in \`.harness/\`).

Your full, canonical role definition is \`.harness/agents/$_gga_role.md\` — read it now and
follow it exactly. Resolve every relative path it mentions against \`.harness/\`
(e.g. \`harness.config.yaml\` -> \`.harness/harness.config.yaml\`, \`progress/\` ->
\`.harness/progress/\`). Run \`.harness/init.sh\` before any work and halt on its
non-zero exit. Hand off through \`.harness/progress/\` files, never by forwarding
chat history.
EOF
  }

  # gen_codex_agent <role> <description> <dest> — one `.codex/agents/<role>.toml`, written
  # INSIDE the target repo. Codex's other glue (§5d /sdd-* prompts) is machine-GLOBAL,
  # which is only safe because those prompt bodies are target-independent. A model stamp
  # is target-DEPENDENT: writing it to `$CODEX_HOME/agents/` would let one target silently
  # retune every other target on the same machine. Project-local also keeps deselection
  # inside $TARGET, where the pristine-compare machinery lives.
  #
  # Codex discovers agent files by DIRECTORY CONVENTION (`$CODEX_HOME/agents/` and the
  # project-local `<repo>/.codex/agents/`); no registration in `.codex/config.toml` is
  # needed. But it requires the trio `name` / `description` / `developer_instructions` —
  # a file that spells the last key `instructions` is rejected at load time with
  # "must define `developer_instructions`" (verified with `codex doctor --json`, CLI
  # 0.145.0) and its model stamp silently never applies. Project-local `.codex/` is only
  # read when the project is TRUSTED by Codex; see docs/INSTALL.md.
  gen_codex_agent() {
    _gca_role="$1"; _gca_desc="$2"; _gca_dest="$3"
    _gca_model="$(resolve_model codex "$_gca_role")"
    {
      printf '# Generated by harness-install.sh — per-role model routing. Do not edit by hand.\n'
      printf 'name = "%s"\n' "$_gca_role"
      printf 'description = "%s"\n' "$_gca_desc"
      if [ -n "$_gca_model" ]; then printf 'model = "%s"\n' "$_gca_model"; fi
      printf 'developer_instructions = "Read .harness/agents/%s.md and follow it exactly; resolve every relative path against .harness/. Run .harness/init.sh first and halt on a non-zero exit."\n' "$_gca_role"
    } > "$_gca_dest"
  }

  # remove_if_pristine <rel-path> <ref-file> <agent-label> — delete <TARGET>/<rel-path>
  # ONLY when it is byte-identical to <ref-file> (a freshly-generated stamp). If it
  # differs (user-edited or foreign), LEAVE it in place with a notice — exactly
  # mirroring the opencode.json case. Echoes the removed relpath on stdout (so the
  # caller can summarize) and prints user-facing notices to stderr.
  remove_if_pristine() {
    _rip_rel="$1"; _rip_ref="$2"; _rip_label="$3"
    _rip_f="$TARGET/$_rip_rel"
    [ -f "$_rip_f" ] || return 0
    if cmp -s "$_rip_f" "$_rip_ref"; then
      rm -f "$_rip_f"
      printf '%s\n' "$_rip_rel"
    else
      echo "⚠️  $_rip_rel differs from the generated stamp (edited) — left in place (deselected '$_rip_label' not removed)" >&2
    fi
  }

  # ── per-role model-artifact stamps + reclamation (E17-F01 R11/R22/R23) ────────
  # `.harness/.model-agents/<front-end>/<file>` is a byte copy of the last per-role
  # artifact the installer wrote for that front-end — the exact device
  # `.harness/.opencode.stamp` already uses for opencode.json (R20).
  #
  # It exists because the reclamation reference has to be the bytes produced by the
  # config that was in force WHEN THE FILE WAS WRITTEN, not by the config in force
  # now. Both reclamation cases change the config by construction:
  #   • every role moved back to `inherit` (§5e/§5f) — a freshly generated body then
  #     carries no `model:` key while the on-disk file still does, so without the
  #     stamp EVERY pristine file would be misread as user-edited and orphaned,
  #     leaving the old model silently in force (Codex r1 P1 #3654925551);
  #   • a front-end deselected in the same run as a `models:` edit (§7)
  #     (Codex r1 P2 #3654925555).
  # The stamp is kept ONLY while the artifacts it describes exist and is removed with
  # them, so a target where nothing resolves keeps its R11 byte-identity.

  # stamp_model_agent <front-end> <file> <src> — remember the bytes just written.
  stamp_model_agent() {
    mkdir -p "$H/.model-agents/$1"
    cp "$3" "$H/.model-agents/$1/$2"
  }

  # reclaim_model_agents <front-end> — remove this front-end's per-role model
  # artifacts, pristine-only, and prune the harness-created dirs. Called from BOTH the
  # install path (nothing resolves any more) and §7 (front-end deselected), so the two
  # never diverge. Emission stays in the ONE hoisted emitter per front-end (R21).
  reclaim_model_agents() {
    _rma_fe="$1"
    # NOTE: the emitter is dispatched through a NAME, not a `case` inside the loop
    # below — bash 3.2 (still the /bin/sh on macOS) mis-parses a `case` nested in a
    # `$( )` command substitution. Same single-emitter guarantee, one indirection.
    case "$_rma_fe" in
      gemini) _rma_top=".gemini"; _rma_ext="md";   _rma_gen=gen_gemini_agent ;;
      codex)  _rma_top=".codex";  _rma_ext="toml"; _rma_gen=gen_codex_agent ;;
      *) return 0 ;;
    esac
    _rma_sub="$_rma_top/agents"
    _rma_stamp="$H/.model-agents/$_rma_fe"
    if [ -d "$TARGET/$_rma_sub" ]; then
      _rma_tmp="$(mktemp 2>/dev/null || mktemp -t harness-ma)"
      _rma_gone="$(ag_personas | while IFS='	' read -r _rma_r _rma_d; do
        [ -n "$_rma_r" ] || continue
        _rma_f="$_rma_r.$_rma_ext"
        [ -f "$TARGET/$_rma_sub/$_rma_f" ] || continue
        # Reference: the remembered bytes when they match what is on disk (the file may
        # have been written under a different `models:` config); otherwise a freshly
        # generated body, which still covers targets stamped before stamps existed.
        "$_rma_gen" "$_rma_r" "$_rma_d" "$_rma_tmp"
        _rma_ref="$_rma_tmp"
        if [ -f "$_rma_stamp/$_rma_f" ] \
           && cmp -s "$TARGET/$_rma_sub/$_rma_f" "$_rma_stamp/$_rma_f"; then
          _rma_ref="$_rma_stamp/$_rma_f"
        fi
        remove_if_pristine "$_rma_sub/$_rma_f" "$_rma_ref" "$_rma_fe"
      done)"
      rm -f "$_rma_tmp"
      # Never `rm -rf`: named files above, then rmdir — which fails harmlessly when a
      # user-edited (or foreign) file was deliberately left behind.
      rmdir "$TARGET/$_rma_sub" 2>/dev/null || true
      rmdir "$TARGET/$_rma_top" 2>/dev/null || true
      [ -n "$_rma_gone" ] && info "reclaimed $_rma_fe per-role model artifacts ($_rma_sub/)"
    fi
    # The stamps describe files the harness no longer owns — drop them, or an
    # all-`inherit` target would keep state a never-configured one does not have (R11).
    if [ -d "$_rma_stamp" ]; then
      ag_personas | while IFS='	' read -r _rma_r _rma_d; do
        [ -n "$_rma_r" ] || continue
        rm -f "$_rma_stamp/$_rma_r.$_rma_ext"
      done
      rmdir "$_rma_stamp" 2>/dev/null || true
      rmdir "$H/.model-agents" 2>/dev/null || true
    fi
    return 0
  }

  # AGENTS.md is the shared portable entrypoint — ALWAYS written, never gated (R2 note).
  # It is also Codex CLI's native repo entrypoint (Codex reads AGENTS.md with no glue),
  # so a `codex`-only install needs no dedicated pointer here — AGENTS.md already serves it.
  write_pointer AGENTS.md
  # Per-agent entrypoint pointers are gated on selection (R2/R3/R4).
  agent_selected claude && write_pointer CLAUDE.md
  # The GEMINI.md managed block reads as "act as the Orchestrator, run
  # .harness/init.sh, read .harness/AGENTS.md" — Antigravity natively loads
  # GEMINI.md-style rules, so this same pointer also serves Antigravity as the
  # in-repo entrypoint (E07-F01 R1/R12); the .agents/rules/harness.md rule (§5c) is
  # the Antigravity-specific hook layered on top. Written when EITHER gemini OR
  # antigravity is selected — both share GEMINI.md as their in-repo entrypoint.
  if agent_selected gemini || agent_selected antigravity; then write_pointer GEMINI.md; fi
  ok "entrypoint pointers written (AGENTS.md + selected agents)"

  # ── 5. Claude Code sub-agent shims + /sdd-next (regenerated each run) ────────
  # Gated on selection (R3/R4): the Claude glue is stamped only when `claude` is in
  # SELECTED. The OpenCode mirror in §5b copies from these files, so it is gated on
  # `opencode` independently and re-derives the command bodies if Claude is skipped.
  if agent_selected claude; then
  mkdir -p "$TARGET/.claude/agents" "$TARGET/.claude/commands"
  emit_agent() { # emit_agent <name> <tools> <description>
    # Frontmatter key order is FIXED (name, description, tools, model) regardless of
    # config state — the `model:` line is either present in that one position or absent
    # entirely, never reordered. Order is part of the byte contract the deselect
    # pristine-compare depends on. (E17-F01 R12/R19/R21.)
    _ea_model="$(resolve_model claude "$1")"
    {
      printf -- '---\n'
      printf 'name: %s\n' "$1"
      printf 'description: %s\n' "$3"
      printf 'tools: %s\n' "$2"
      if [ -n "$_ea_model" ]; then printf 'model: %s\n' "$_ea_model"; fi
      printf -- '---\n'
    } > "$TARGET/.claude/agents/$1.md"
    cat >> "$TARGET/.claude/agents/$1.md" <<EOF

You are the **$1** for this project's agent harness (installed in \`.harness/\`).

Your full, canonical role definition is \`.harness/agents/$1.md\` — read it now and
follow it exactly. Resolve every relative path it mentions against \`.harness/\`
(e.g. \`harness.config.yaml\` -> \`.harness/harness.config.yaml\`, \`progress/\` ->
\`.harness/progress/\`). Run \`.harness/init.sh\` before any work and halt on failure.
Hand off through \`.harness/progress/\` files, never by forwarding chat history.
EOF
  }
  emit_agent orchestrator "Read, Bash, Edit, Grep, Glob, Task" \
    "The Leader. Reads state, runs init.sh, routes the next task, delegates to architect/builder/reviewer/scout. Never writes code."
  # architect carries `Task` so it can spawn the doc-critic sub-agent at its
  # pre-`spec-ready` `target-type=feature-spec` checkpoint (agents/architect.md).
  emit_agent architect "Read, Write, Edit, Grep, Glob, Bash, Task" \
    "The Spec Author. Writes the 4-file spec in EARS. No production code."
  emit_agent builder "Read, Write, Edit, Bash, Grep, Glob" \
    "The Implementer. Writes code from an APPROVED spec, one task at a time."
  emit_agent reviewer "Read, Bash, Grep, Glob, Edit" \
    "The Evaluator. Verifies against the spec, runs tests, approves or rejects."
  emit_agent scout "Read, Grep, Glob, Bash" \
    "Read-only codebase reconnaissance. Writes findings to progress/."
  # doc-critic sub-agent shim (E09): the advisory review pass the architect (and the
  # planner/driller slash commands) spawn at their pre-hand-off checkpoints. Points at
  # the canonical .harness/agents/doc-critic.md; documents-only, no production-code review.
  emit_agent doc-critic "Read, Grep, Glob, Write" \
    "Advisory doc review pass over harness-generated planning docs + specs at the plan-output/epic-decomposition/feature-spec checkpoints. Documents only, never production code."
  # pr-fixer (E18-F01 R10): the /sdd-pr-loop worker sub-agent, spawned once per blocking
  # Codex comment. GATED on the opt-in pr_loop.enabled — unlike the six roles above it is
  # NOT stamped by default. It rides the SAME emit_agent path (one shim, pointing at
  # the canonical .harness/agents/pr-fixer.md — the role body is never duplicated).
  if pr_loop_enabled; then
    emit_agent pr-fixer "Read, Edit, Bash, Grep, Glob" "$PR_FIXER_DESC"
  fi
  ok "Claude Code sub-agent shims installed (.claude/agents/)"
  fi  # end: claude-gated sub-agent shims

  # ── slash-command bodies (generated once into a temp dir, then mirrored to the
  # selected front-ends' command dirs). Generating into a neutral CMDDIR lets the
  # OpenCode mirror (§5b) work even when `claude` is NOT selected (R3/R4). ─────────
  CMDDIR="$(mktemp -d 2>/dev/null || mktemp -d -t harness-cmd)"
  cat > "$CMDDIR/sdd-next.md" <<'EOF'
---
description: Run the Orchestrator loop on the next actionable task (init → route → delegate)
---

Act as the **Orchestrator** (`.harness/agents/orchestrator.md`), resolving all
relative paths against `.harness/`.

1. Run `.harness/init.sh`. If it exits non-zero, STOP and report.
2. Read `.harness/harness.config.yaml` and the TaskStore (per `.harness/store/local.md`).
3. Find the next actionable feature and route it by status per
   `.harness/docs/WORKFLOW.md`:
   - `pending` + sdd:true → spawn **architect**, then `spec-ready` and PAUSE (human gate).
   - `spec-ready` + autonomous:true → set `in-progress`, spawn **builder**, then `in-review`.
   - `in-progress` → spawn **builder** with the approved specs only, then `in-review`.
   - `in-review` → spawn **reviewer**; approve → `done`, reject → back to `in-progress`.
4. Append what happened to `.harness/progress/history.md`.

`$ARGUMENTS` may carry either a specific feature id or a scope token; forward it verbatim
to the Orchestrator:
- a specific feature id (e.g. `E01-F01`) → operate on that feature (unchanged).
- `--mine` → **scoped selection**: consider only features whose **effective owner**
  (feature `owner` else parent epic `owner`) equals the identity resolved from
  `workflow.identity` in `.harness/harness.config.yaml` (`@me`/`self` → authed `gh` user
  via `gh api user`; else literal). This is **owned-only** — it never claims unassigned
  work and never writes an `owner`; if the identity is unresolved or no owned actionable
  feature exists, it **fails closed** (selects nothing, reports, changes no state) and
  does **not** widen to board-wide selection. Bare `/sdd-next` (no `--mine`) is unchanged
  board-wide selection and ignores `owner`. The scoping semantics live in the
  **Orchestrator contract** (`.harness/agents/orchestrator.md` → "Ownership & scoped
  selection"); this command only forwards the token.
EOF

  cat > "$CMDDIR/sdd-new.md" <<'EOF'
---
description: Seed a new idea into the TaskStore as Inception (interactive intake → pending entry + inbox brief)
---

Act as **Inception** (`.harness/agents/inception.md`). That role file is the durable
contract; this command carries the interactive front-end. Resolve all relative paths
against `.harness/`.

The free-text idea is in `$ARGUMENTS`. If it is empty, ask the human for it.

1. Run `.harness/init.sh`. If it exits non-zero, STOP and report — do not seed into a
   broken environment.
2. Read `.harness/harness.config.yaml` and the TaskStore (`.harness/state/tasks.json`,
   per `.harness/store/local.md`).
3. Run a short, **adaptive** Q&A with the human to clarify: the problem and who it is
   for, the success outcome, the scope/boundaries, and any constraints. Where the
   shape forks, offer **at most 3** options as **text-only** (markdown/ASCII) mockups
   — never images. Keep it short; ask only what you need to triage and brief.
4. **Triage** the idea to exactly one altitude, per `.harness/agents/inception.md`:
   (1) new task on an existing feature / (2) new feature under an existing
   epic / (3) new epic + `epic.md` + `F01`. The write step is **altitude-dependent** —
   fork here. For altitudes 2 and 3, **allocate** a next-sequential id; for altitude 1,
   do NOT allocate a new id (you reuse the existing feature's id).
5. **Write** — branch by altitude:
   - **Altitude 1 (new task on an existing feature):** do NOT allocate a new id and do
     NOT insert a new feature into `.harness/state/tasks.json`. Branch on the existing
     feature's status (the inbox brief is read by the Architect only while a feature
     is `pending`):
     - **If it is still `pending`:** **append** a task-level note (and any dependency)
       to the EXISTING feature's `.harness/progress/inbox/<existing-feature-id>.md`
       brief — creating that brief from the `.harness/specs/_templates/inbox-brief.md`
       template if the feature predates the inbox convention. Per
       `.harness/agents/inception.md`, do not invent a competing feature. Then skip to
       step 8 (steps 6–7 cover only the new-entry path).
     - **If it is already `spec-ready`, `in-progress`, `in-review`, or `done`:** do
       NOT append to the brief — it has already been consumed, so the note would be a
       silent no-op. STOP and tell the human the addition must go back through
       specification: either raise it with the Architect to re-spec / update that
       feature's spec & task list, or re-run `/sdd-new` to seed it as a NEW feature
       (altitude 2) that `depends_on` the existing one. Do not write a no-op note.
   - **Altitudes 2 & 3:** write the `pending` feature entry into
     `.harness/state/tasks.json` (and, for a new epic, the epic entry +
     `.harness/specs/epics/<slug>/epic.md` + first `F01`), then continue to steps 6–7.
6. **Re-validate** `.harness/state/tasks.json` against
   `.harness/store/tasks.schema.json` (altitudes 2 & 3, after the new entry). If it
   fails, report the failure and do NOT claim a successful seed.
7. **Write** the intent brief to `.harness/progress/inbox/<feature-id>.md` (frontmatter
   + sections), copying `.harness/specs/_templates/inbox-brief.md` as the template.
8. **Report** the `<feature-id>` (for altitude 1, the EXISTING feature's id), the
   relevant `.harness/state/tasks.json` entry, the
   `.harness/progress/inbox/<feature-id>.md` path, and tell the human to **run
   `/sdd-next`** next. Do NOT spawn the Architect and do NOT change any status —
   Inception seeds, never specs, and never moves a feature past `pending`.
EOF

  cat > "$CMDDIR/sdd-plan.md" <<'EOF'
---
description: Whole-project inception as Planner — produce vision + architecture + ADRs and seed a block of draft epics (interactive)
---

Act as **Planner** (`.harness/agents/planner.md`). That role file is the durable
contract; this command carries the interactive front-end. Resolve all relative paths
against `.harness/`.

The free-text whole-project idea is in `$ARGUMENTS`. If it is empty, ask the human for it.

1. Run `.harness/init.sh`. If it exits non-zero, STOP and report — do not plan into a
   broken environment.
2. Read `.harness/harness.config.yaml` and the TaskStore (`.harness/state/tasks.json`,
   per `.harness/store/local.md`).
3. **Re-run guard.** If `.harness/specs/vision.md` or `.harness/specs/architecture.md`
   already exists, a default run STOPS and reports that the project already has a plan —
   point the human at `/sdd-drill` (F03) to deepen existing epics, or at an explicit
   amend mode that **appends** (never overwrites or renumbers). Do not silently
   overwrite.
4. Run a short, **adaptive** Q&A with the human to clarify: the problem and who it is
   for, the outcomes, the non-goals, and the roadmap shape. Where the shape forks, offer
   **at most 3** options as **text-only** (markdown/ASCII) mockups — never images. Keep
   it short; ask only what you need to write the vision and sketch the roadmap.
5. **Write** `.harness/specs/vision.md` from `.harness/specs/_templates/vision.md`
   (north star: problem, users, outcomes, non-goals; it complements
   `.harness/specs/product.md`/`glossary.md`).
6. **Write** `.harness/specs/architecture.md` from
   `.harness/specs/_templates/architecture.md` (system shape + stable upfront
   decisions), and one ADR per decision at `.harness/specs/adr/NNNN-<title>.md` from
   `.harness/specs/_templates/adr.md` (4-digit, above the max existing ADR number);
   `architecture.md` references each ADR by its `ADR-NNNN` id. Stay at whole-system
   depth — defer per-epic deltas to `/sdd-drill` (F03).
7. **Seed** the roadmap: for each epic, write a `.harness/state/tasks.json` row with
   `status: "draft"` and `features: []` (ids as a next-sequential block strictly above
   the max existing `E##`, append-only, no reuse), and create
   `.harness/specs/epics/<id>-<slug>/epic.md` anchored by a one-paragraph business brief
   and carrying the **drillable-minimum five elements** (no `F01`, no feature spec, no
   EARS, no detailed technical plan):
   1. **Business brief** — one paragraph stating the problem/opportunity and the user.
   2. **Epic-level success criteria (outcomes)** — what "done" looks like for this epic.
   3. **Technical considerations / restrictions / non-goals** — constraints and explicit
      non-goals that bound the epic.
   4. **Cross-epic dependencies and boundaries** — which other epics this epic touches,
      relies on, or must stay clear of.
   5. **Pointers to relevant shared ADRs** — references in `architecture.md` / ADRs that
      constrain this epic (or an explicit note that none apply).
8. **Doc-critic checkpoint (before re-validation).** Spawn the **Doc-critic**
   (`.harness/agents/doc-critic.md`) as a sub-agent with `target-type=plan-output`,
   passing the paths just written (`specs/vision.md`, `specs/architecture.md`, each ADR,
   and every seeded `epic.md`). Apply any advisory findings inline, then proceed. If the
   critic invocation errors or times out, proceed best-effort and append a note under
   `.harness/progress/<run>/` recording the skipped/failed review.
9. **Re-validate** `.harness/state/tasks.json` against
   `.harness/store/tasks.schema.json`. If it fails, report the failure and do NOT claim
   a successful plan.
10. **Report** the artifacts written (`.harness/specs/vision.md`,
   `.harness/specs/architecture.md`, each `.harness/specs/adr/NNNN-*.md`), the seeded
   `draft` epics (ids + titles + `epic.md` paths), and tell the human to **run
   `/sdd-drill <epic-id>`** next. Do NOT spawn the Architect, do NOT write any feature
   spec, and do NOT advance any epic past `draft` — the Planner produces, never specs.
EOF

  cat > "$CMDDIR/sdd-drill.md" <<'EOF'
---
description: Per-epic drill-down as Driller — decompose one draft epic into features + ADR deltas, then one epic-level approval (interactive)
---

Act as **Driller** (`.harness/agents/driller.md`). That role file is the durable
contract; this command carries the interactive front-end. Resolve all relative paths
against `.harness/`.

The target `<epic-id>` is in `$ARGUMENTS`. The `<epic-id>` is **required** — if
`$ARGUMENTS` is **empty**, STOP and **ask** the human for the epic id rather than drilling
an arbitrary epic.

1. Run `.harness/init.sh`. If it exits non-zero, STOP and report — do not drill into a
   broken environment.
2. Read `.harness/harness.config.yaml` and the TaskStore (`.harness/state/tasks.json`, per
   `.harness/store/local.md`).
3. **Precondition guard.** Resolve `<epic-id>`. If it does not resolve to an existing epic,
   or the epic's status is **not** `draft` (`planned` / `in-progress` / `done` / legacy
   `pending`), a default run STOPS and reports why (missing / not-`draft`) — seed nothing,
   append no ADR, change no status. (Re-running on an already-`planned` epic is an explicit
   **amend** opt-in that appends features/ADRs above the current max without renumbering or
   re-flipping.)
4. Read the target `draft` epic (`.harness/specs/epics/<id>-<slug>/epic.md` + its
   `.harness/state/tasks.json` row) and F02's design artifacts (`.harness/specs/vision.md`,
   `.harness/specs/architecture.md`, `.harness/specs/adr/NNNN-*.md`) as inputs.
5. Run a short, **adaptive** Q&A with the human to settle the feature breakdown. Where the
   breakdown forks, offer **at most 3** options as **text-only** (markdown/ASCII) mockups —
   never images. Keep it short.
6. **Seed** the decomposition: write each new feature into the epic's `features` array
   (`status: "pending"`, `sdd: true`, one-line `title`, `spec_path`, intra-epic
   `depends_on`; ids as a next-sequential block strictly above the epic's max `F##`,
   append-only, no reuse); fill the `epic.md` feature table (one row per feature); and write
   a per-feature inbox brief at `.harness/progress/inbox/<E##>-F<NN>.md` from
   `.harness/specs/_templates/inbox-brief.md`, recording the `ADR-NNNN` ids each feature
   must honor.
7. **Append** any per-epic **ADR deltas** the decomposition forces at
   `.harness/specs/adr/NNNN-<title>.md` (4-digit, above the max existing ADR number, no
   reuse) — do NOT rewrite or renumber F02's existing ADRs. Stay at per-epic depth; defer
   feature-level design to the feature's own spec.
8. **Doc-critic checkpoint (before re-validation).** Spawn the **Doc-critic**
   (`.harness/agents/doc-critic.md`) as a sub-agent with `target-type=epic-decomposition`,
   passing the target `epic.md` path, its feature table, the per-feature inbox brief paths,
   and any ADR delta paths. Apply any advisory findings inline, then proceed. If the critic
   invocation errors or times out, proceed best-effort and append a note under
   `.harness/progress/<run>/` recording the skipped/failed review.
9. **Re-validate** `.harness/state/tasks.json` against `.harness/store/tasks.schema.json`. If
   it fails, report the failure and do NOT claim a successful drill.
10. Present the **single epic-level decision** (one decision, not per feature):
   - **approve** → flip the epic `draft → planned` and stamp `autonomous: true` on every
     seeded feature (all-or-nothing); or
   - **keep gated** → flip the epic `draft → planned`, leaving every seeded feature
     `autonomous: false` so each parks at the per-feature spec-approval gate.
   Re-validate again after the flip/stamp.
11. **Report** the seeded features (ids + titles + `spec_path`s), the inbox briefs + ADR
    ids, any ADR deltas, and the decision taken; tell the human to **run `/sdd-next`** to
    execute. Do NOT spawn the Architect, do NOT write any feature `.spec/.plan/.tasks/.tests`,
    and advance ONLY the target epic to `planned` — the Driller decomposes, never specs.
EOF

  cat > "$CMDDIR/sdd-fix.md" <<'EOF'
---
description: Lightweight fix lane as Fixer — seed an sdd:false fix under the reserved maintenance epic (brief only, no spec/drill) and hand it to the existing Builder → Reviewer loop (interactive)
---

Act as **Fixer** (`.harness/agents/fixer.md`). That role file is the durable contract;
this command carries the interactive front-end. Resolve all relative paths against
`.harness/`.

The free-text fix description is in `$ARGUMENTS`. If `$ARGUMENTS` is **empty**, STOP and
**ask** the human what to fix rather than seeding an empty fix.

1. Run `.harness/init.sh`. If it exits non-zero, STOP and report — do not seed into a
   broken environment.
2. Read `.harness/harness.config.yaml` and the TaskStore (`.harness/state/tasks.json`,
   per `.harness/store/local.md`).
3. Run a short, **adaptive** Q&A with the human to settle the fix's shape: what's broken,
   the intended fix, how to verify, and a non-empty `## Files expected to change` list
   of normalized repo-relative paths. Remove one leading `./`, then reject absolute
   paths, unsafe components, wildcards, control characters, and ambiguous prose.
   Where the shape forks, offer **at most 3** text-only options; never images.
4. **Maintenance epic (create-on-first-use / reuse-by-id).** Look up epic `E99` in
   `.harness/state/tasks.json`. If **absent**, create it with `id: "E99"`, slug
   `maintenance`, title `"Maintenance (hotfixes & minor fixes)"`, `status: "planned"`,
   `features: []`, and write `.harness/specs/epics/E99-maintenance/epic.md` (title +
   one-paragraph brief only — no feature spec). If **present**, reuse that same epic **by
   id `E99`** — never create a second maintenance epic and never renumber its existing fixes.
5. **Seed** one fix: append a feature to `E99`'s `features` array with `sdd: false`,
   `status: "pending"`, a one-line `title`, a `spec_path`
   (`specs/epics/E99-maintenance/F<NN>-<slug>/`, **directory not created**), and an `id`
   allocated next-sequential strictly **above** the epic's max `F##` (append-only, no
   reuse). Stamp it `autonomous: true` by **default**; if the human passes a `--gated`
   opt-out, stamp it `autonomous: false` instead (it then parks at the normal gate).
6. Write **exactly one** fix-oriented inbox brief at `.harness/progress/inbox/<id>.md`
   (problem + intended fix + how to verify + `## Files expected to change`) from
   `.harness/specs/_templates/inbox-brief.md`. Do **NOT** create any feature
   `.spec.md`/`.plan.md`/`.tasks.md`/`.tests.md`, do **NOT** create the `spec_path`
   directory, and do **NOT** spawn the Architect — brief-only, never a spec.
7. **Re-validate** `.harness/state/tasks.json` against `.harness/store/tasks.schema.json`
   after the epic create and after the fix append. If it fails, report the failure and do
   NOT claim a successful seed.
8. **Hand off in-session.** After seeding + re-validation, **hand the seeded fix off to
   the existing `sdd: false → Builder → Reviewer` loop in-session** — do not stop at
   seeding. Trigger the existing Orchestrator routing (`pending + sdd: false → Builder →
   Reviewer`, the same behaviour `/sdd-next` drives) on the just-seeded fix; **reuse** that
   routing, do not re-implement it. The Fixer writes no production code (the Builder does).
9. **Report** the maintenance-epic state (created/reused `E99`), the seeded fix (id +
   title + `spec_path` + `autonomous` value), the inbox brief, that no spec / `spec_path`
   directory / Architect was created or spawned, and that the fix was handed off to the
   existing `sdd: false` loop in-session.
EOF

  cat > "$CMDDIR/sdd-fix-parallel.md" <<'EOF'
---
description: Run a bounded batch of isolated autonomous E99 fixes through targeted workers
---

Act as the **Fixer parallel coordinator** (`.harness/agents/fixer.md` → “Parallel
dispatch mode”), resolving all durable paths against `.harness/`.

This command is argument-free. If `$ARGUMENTS` is non-empty, STOP and report usage
`/sdd-fix-parallel`.

1. Run `.harness/init.sh`; stop on non-zero.
2. Execute the Fixer role's P1–P7 sequence: native concurrency/config/in-session
   Builder preflight, one-time F02 provisioning while the primary is clean, complete
   manifest with provisioning failures before claim/dispatch, coordinator bookkeeping
   branch plus one F01 atomic claim with explicit canonical `HARNESS_DIR`,
   parallel-safe fan-out before any wait, guarded exclusive numeric wave,
   bookkeeping PR reconciliation, updated-base proof, and aggregate report.
3. Each worker uses `.harness/agents/orchestrator.md` “Targeted parallel-fix worker mode”
   for one id and its pre-provisioned branch/worktree, creates only its post-approval
   code PR, continues siblings, and reports an observed merge for coordinator-owned
   done and teardown.
4. No ready work is a zero-mutation `no ready E99 fixes` success. Missing native
   delegation or `execution.builder.backend: delegate` fails before
   manifest/provisioning/claim and points to serial `/sdd-fix`; never invent a vendor
   API or background shell agent.
EOF
  # /sdd-pr-loop (E18-F01) — written UNCONDITIONALLY, even when pr_loop.enabled is false.
  # This is load-bearing, not an oversight: the codex-prompts and antigravity reclamation
  # paths byte-compare an on-disk copy against `$CMDDIR/<name>.md`, so gating GENERATION
  # would make an already-stamped copy permanently unremovable the moment the gate flips
  # off. Only the per-front-end MIRRORING below is gated (R1/R2/R3).
  cat > "$CMDDIR/sdd-pr-loop.md" <<'EOF'
---
description: Drive the Codex review cycle on an open PR — trigger @codex review, watch in the background, classify severities, fix blocking findings, merge when every gate is green
---

Drive the Codex review cycle on an open PR until every gate is green or the round cap is
hit. Resolve every relative path against `.harness/`.

The PR number is in `$ARGUMENTS`. If `$ARGUMENTS` is empty, resolve the current branch's
PR with `gh pr view --json number --jq '.number'`; if that fails, STOP and ask which PR.

> **Preconditions.** This loop only works on a repository with the **Codex GitHub App**
> installed, an **authed `gh`**, and **`jq`** on PATH. Step 0 verifies all of them and
> fails fast with a named remedy — never post first and discover it later.

## Configuration

Policy lives in `.harness/harness.config.yaml` under `pr_loop:`. Precedence for every
knob is **env override → config value → built-in default**; an absent block or an absent
key behaves exactly as the default.

| Config key | Env override | Default |
|---|---|---|
| `pr_loop.enabled` | `HARNESS_PR_LOOP_ENABLED` | `false` (opt-in) |
| `pr_loop.auto_merge` | `HARNESS_AUTO_MERGE` | `true` |
| `pr_loop.max_rounds` | `HARNESS_MAX_ROUNDS` | `4` |
| `pr_loop.blocking_severities` | `HARNESS_BLOCKING_SEVERITIES` | `P0,P1` |
| `pr_loop.merge_strategy` | `HARNESS_MERGE_STRATEGY` | `merge` |

`pr_loop.enabled` is the **opt-in** master gate: this command is only installed at all
because it reads exactly `true`. Anything else — an absent block, an absent key, an empty
or malformed value — means off, and the installer stamps no `/sdd-pr-loop` glue.

Execution knobs are **env-only** (never config): `HARNESS_POLL_INTERVAL` (60),
`HARNESS_POLL_CEILING` (900), `HARNESS_FIRST_RESPONSE` (180), `HARNESS_DRY_RUN`.

Round cache: `.harness/.pr-loop/<pr>/round-<n>/` — gitignored and best-effort; if it is
missing or corrupt, reconstruct it from the `gh` API.

## Per-round runbook

For `round` from 1 to `max_rounds`, with `round_dir=.harness/.pr-loop/<pr>/round-<round>`:

### 0. Preflight — BEFORE posting anything

```bash
sh .harness/tools/wait-for-codex.sh preflight "$pr_number"
```

It checks `gh` on PATH, `gh auth status`, `jq` on PATH, a resolvable repo slug, and that
the PR exists and is OPEN. It posts **nothing**. On a non-zero exit (`5`), **STOP** and
report its one-line diagnostic verbatim — do not post `@codex review`, do not poll, do
not fall back to a hand-rolled check. A repo without the Codex GitHub App should leave
`pr_loop.enabled` at its opt-in default of `false` rather than run this loop.

### 1. Trigger the review

Resolve the repo slug once (the `gh api` calls below need it):

```bash
slug=$(gh repo view --json owner,name --jq '"\(.owner.login) \(.name)"')
owner=${slug%% *}; repo=${slug##* }
```

- **Round 1:** mark the PR ready for review (`gh pr ready <pr>`), then comment `@codex review`.
- **Round 2+:** comment `@codex review` again to request a re-review of the new commits.

**Capture the triggering comment's id straight from the post response.** Step 2 uses it
both to poll reactions (the 👍-only clean case) and as the **freshness anchor**
(`trigger-ts.txt`, the `created_at >= trigger` filter). Derive it from the URL
`gh pr comment` prints, **never from a separate comment-list call**: a non-paginated
`GET issues/<n>/comments` returns only the first 30 (oldest) comments, so on a busy PR
the just-posted `@codex review` is on a later page and the lookup returns a stale id or
`null` — which silently disables the freshness filter.

```bash
trigger_url=$(gh pr comment "$pr_number" --body "@codex review")   # this IS the round's trigger post
trigger_comment_id="${trigger_url##*issuecomment-}"                # .../pull/N#issuecomment-<id>
```

(The "comment `@codex review`" step and this capture are a single action — do not post twice.)

If `HARNESS_DRY_RUN=1`, **skip the real `gh pr comment` post** entirely and synthesize
stub review data in `$round_dir` for downstream testing.

### 2. Poll for the review (background watcher)

Wait for a Codex review to land on the latest commit. **Do not poll by hand.** A by-hand
poll is why landed Codex comments get missed: in an interactive session you fetch the
review state once, see nothing yet, and the turn ends — so a review that lands minutes
later goes unnoticed until a human nudges "review again". Foreground `sleep` is also
blocked in this harness, so an inline "sleep 30; check; repeat" cannot run either.

Instead, launch the harness watcher **in the background** and let the harness wake you
when it exits:

```bash
# Claude Code: Bash tool with run_in_background: true. Elsewhere: `… &` or the host's
# equivalent. It keeps polling across turns and re-invokes you on exit.
sh .harness/tools/wait-for-codex.sh "$pr_number" "$trigger_comment_id" "$round_dir"
```

The watcher polls every `HARNESS_POLL_INTERVAL` seconds (default **60**) up to
`HARNESS_POLL_CEILING` (default **900** = 15 min) and writes the **four sources** into
`$round_dir` on every poll (`gh pr view` alone does NOT return Codex's findings):

- `pr.json` — `gh pr view --json reviews,comments,statusCheckRollup,headRefOid`
- `review-comments.json` — `repos/<o>/<r>/pulls/<n>/comments`, paginated + flattened —
  **the inline findings**, anchored to file/line. Returned by neither `--json comments`
  (issue comments only) nor `reviews[*].body` (summary banner only).
- `issue-comments.json` — `repos/<o>/<r>/issues/<n>/comments`, paginated, scanned for a
  clean banner posted past the first 100 comments.
- `reactions.json` — reactions on the `@codex review` comment (Codex reacts 👍 when it
  has nothing to say).
- `trigger-ts.txt` — the freshness anchor, resolved once at startup.

When the watcher exits, the harness re-invokes you. **Branch on its exit code** — never
re-poll by hand:

| Exit | Meaning | Next |
|---|---|---|
| `0` | Review **with findings** landed on the head commit | Step 3, classify `review-comments.json` |
| `3` | **Clean review, 0 findings** (head banner as a review **or** an issue comment, or a 👍 reaction) | Skip classification; treat the round as zero blocking |
| `2` | **Timeout** — ceiling hit, no resolution | Abort the round with `needs-human`. Never treat a timeout as "clean". |
| `4` | Usage / precondition error (incl. an unresolvable trigger timestamp) | Fix the args and relaunch; do not disable the freshness filter |
| `5` | No Codex activity inside `HARNESS_FIRST_RESPONSE` (default 180s) | Report the diagnostic: the Codex GitHub App is most likely not installed. Do NOT wait out the ceiling. |

The exit codes encode the freshness conditions the watcher checks: (1) Codex-bot inline
comments filed against `headRefOid` **and created at/after the trigger comment** →
findings; (2) a summary banner containing `Reviewed commit: <short headRefOid>` with zero
head findings → clean; (2b) that same head banner delivered as an **issue comment** →
clean; (3) a Codex-bot 👍 (`+1`) on the trigger comment → clean.

**Two freshness pitfalls the watcher guards against** (both previously stalled clean PRs):

- **Re-anchored stale threads.** GitHub re-stamps old unresolved threads' `commit_id` to
  each new head, so a stale thread's `commit_id` matches `headRefOid` even though it
  predates this round. An inline comment counts only when `created_at >= trigger.created_at`.
- **Clean banner as an issue comment.** Codex's zero-findings result ("Didn't find any
  major issues." + `Reviewed commit: <head>`) posts to `.comments[]`, which conditions
  1/2 never scan.

**Codex bot identity.** Accept **exactly two** author logins and nothing else:
`chatgpt-codex-connector` (what `gh pr view` / GraphQL reports) and
`chatgpt-codex-connector[bot]` (what the REST API reports). Never prefix-match: any account
whose login merely *begins* with the bot name (`chatgpt-codex-connector-evil`) could then
👍 the trigger comment or post a `Reviewed commit: <head>` banner and be read as a clean
Codex review — zero findings, no classification, auto-merge. The two literals cover the
GraphQL/REST spelling split completely.

> **No background tool available?** The watcher still runs in the foreground and exits
> with the same codes — it just blocks until resolution or ceiling.

### 3. Parse and classify comments

Walk **`review-comments.json` (the inline findings)** + `pr.json` `reviews[*].body` +
`issue-comments.json` looking for severity tags. Codex tags severity as a **badge image**,
not bare text — e.g. `![P2 Badge](https://img.shields.io/badge/P2-yellow?style=flat)`.
Match `P0|P1|P2|nit` **case-insensitively anywhere in the body** (this catches both the
badge alt-text/URL form and any bare-text form); **first match wins**; **default to `P2`**
when nothing matches.

**Only FRESH inline comments count for this round** — the same freshness guard the watcher
applies (see step 2). An inline comment counts only when it is filed against the head
commit **and** its `created_at >= trigger.created_at`; otherwise a stale thread GitHub
re-anchored to head slips back into `blocking.json` and defeats the guard. The watcher
persists the anchor to `trigger-ts.txt`; apply it when reading the unfiltered
`review-comments.json`:

**A head oid you could not read is not a head oid.** A `pr.json` that is missing or
truncated makes `jq` exit non-zero with empty output; a `pr.json` that parses but carries
no `headRefOid` makes `jq -r` print `null` and exit **0**. Either way `$head` is not the
head commit, every comment fails `commit_id == $h`, and `fresh-comments.json` — hence
`blocking.json` — comes out `[]`, which step 6 reads as "zero blocking findings ⇒ all
gates green ⇒ merge". So guard the **value** as well as the exit status and fail closed:
an unreadable head aborts the round as `needs-human`, it is not a clean round. (`since`
needs no such guard — an empty `since` disables the freshness filter and admits *more*
findings, which errs toward review rather than toward the merge.)

```bash
since=$(cat "$round_dir/trigger-ts.txt" 2>/dev/null)  # empty ⇒ filter off ⇒ admits MORE
head_ok=0            # fail closed: only a head oid we actually READ may filter findings
if ! head=$(jq -r '.headRefOid // ""' "$round_dir/pr.json") || [ -z "$head" ]; then
  # Head oid UNKNOWN: pr.json missing, truncated, or without a headRefOid. Filtering on ""
  # would match nothing and hand the gate an empty blocking.json. Testing the status on the
  # `if` itself reads the same whether or not the host shell runs with `set -e`, and
  # `[ -z "$head" ]` catches the absent/null key that `jq -r` reports with exit status 0.
  rm -f "$round_dir/fresh-comments.json"   # never leave a previous round's file standing
  echo "could not read headRefOid from pr.json — needs-human, not merging" >&2
else
  head_ok=1          # the filter below is anchored to a head oid that was really read
  jq --arg h "$head" --arg since "$since" '
    [ .[] | select((.commit_id // "") == $h)
          | select($since == "" or ((.created_at // "") >= $since)) ]' \
    "$round_dir/review-comments.json" > "$round_dir/fresh-comments.json"
fi
# classify severities from fresh-comments.json (not the raw review-comments.json)
```

With `head_ok=0` there is no `fresh-comments.json` to classify and therefore no
`blocking.json`: take the `needs-human` terminal state of step 5's cap row (label, hand
over, return failure). Only `head_ok=1` with an empty `blocking.json` means "zero fresh
blocking findings".

To re-check the round files offline at any point (no `gh`, no network), run
`sh .harness/tools/wait-for-codex.sh evaluate "$round_dir"` — exit `0` findings,
`3` clean, `1` pending, applying exactly the rules above.

Then filter to the **blocking severities only** (`pr_loop.blocking_severities`, default
`P0,P1`; `P2`/`nit` never block). Save into the round dir:

```
comments.json     # all comments with a severity tag attached
blocking.json     # filtered to the blocking severities only
status.json       # statusCheckRollup snapshot
```

### 4. Stall detection

Compare `blocking.json` to the **previous round**'s (`round-<n-1>/blocking.json`) by
comment id (or, if ids are unstable, by `(path, line, severity, body-hash)`). If **any**
blocking comment id appears in both rounds, the fixes are not landing: **escalate to the
`max_rounds - 1` behavior immediately**, even if the current round is 1 or 2.

### 5. Branch on round

| Round | Behavior |
|---|---|
| below `max_rounds - 1` | For each blocking comment, spawn one **`pr-fixer`** sub-agent, passing it the PR number, comment id, file path, line and body. It commits one fix and writes `fix-<comment_id>.md` into the round dir. After all fixers return, `git push`. |
| `max_rounds - 1` | Build **one combined fix prompt** (all blocking comments concatenated) and escalate to a **different worker** if the host CLI offers one; where no router exists, run one combined **in-session** pass instead. Then push. |
| `max_rounds` (cap) | Stop the loop. `gh pr edit "$pr_number" --add-label needs-human`. Post the handover summary listing every round, the blocking comments that survived, and the cache path. Return failure. |

At the default `max_rounds: 4` that is rounds 1–2 per-comment, round 3 combined
escalation, round 4 `needs-human`. A `max_rounds` below `3` simply has no per-comment
fixer rounds.

**Front-ends without a `pr-fixer` sub-agent** (codex, gemini) do not spawn one: apply each
blocking comment's fix **in-session**, under the same discipline — one comment, one
targeted fix, one commit, one `fix-<comment_id>.md` note — then push once at the end of
the round.

**Always write the worker file for this round** so the handover summary stays
reconstructible from cache:

```bash
echo "<worker>" > "$round_dir/worker"   # e.g. claude | opencode | agy | codex
echo "<role>"   > "$round_dir/role"     # implementation | fix | escalation
```

### 6. Re-check the gates

After the fix commits land, re-fetch the PR JSON and check the gates **before** triggering
another Codex round:

- CI green (`statusCheckRollup[*].conclusion == "SUCCESS"` for required checks)
- Tests / typecheck / lint green (subsets of CI)
- Zero unresolved blocking comments — i.e. `blocking.json` is empty

If all are green, **proceed to "ready to merge"** — do not waste another Codex round. If
checks are still pending, wait for them; if any fail, treat the failure like a blocking
comment for the next round.

#### Squash-merge prep (only when `merge_strategy` is `squash`)

**Compose the message locally — never ask Codex for it.** The watcher resolves on exactly
three signals (fresh inline findings on head, a fresh `Reviewed commit <sha>` banner as a
review or an issue comment, a `+1` reaction on the trigger comment), and a raw-text reply
to an `@codex summarize` request is none of them: polling for one runs to the ceiling,
exits `2`, and strands the squash path in `needs-human` with no `squash-message.txt` ever
written. Everything the message needs is already in the round cache, so write it yourself
— no post, no poll, nothing that can hang:

```bash
msg=".harness/.pr-loop/$pr_number/squash-message.txt"
default_branch=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')
{
  gh pr view "$pr_number" --json title --jq '.title'
  echo
  echo "<2-4 lines, in your own words: the core implementation goal>"
  echo
  git log --reverse --format='- %s' "origin/$default_branch..HEAD"
  echo
  echo "Blocking fixes resolved:"
  for f in .harness/.pr-loop/"$pr_number"/round-*/fix-*.md; do
    [ -f "$f" ] && sed -n 's/^- One-line: //p' "$f"
  done
} > "$msg"
[ -s "$msg" ] || rm -f "$msg"   # empty ⇒ the merge below uses GitHub's default body
```

A missing or empty `$msg` is **not** a failure: the merge command below falls back to
GitHub's default squash body, so the squash path always reaches its merge.

## Handover summary

Before posting **either** terminal-state comment, build the handover summary by walking
the cache:

```bash
for d in .harness/.pr-loop/"$pr_number"/round-*/; do
  n=$(basename "$d" | sed 's/round-//')
  worker=$(cat "$d/worker" 2>/dev/null || echo "?")
  role=$(cat "$d/role" 2>/dev/null || echo "?")
  echo "- round-$n: $worker ($role)"
done
for d in .harness/.pr-loop/"$pr_number"/round-*/; do cat "$d/worker" 2>/dev/null; done \
  | sort | uniq -c
```

Save the rendered summary to `.harness/.pr-loop/<pr>/handover-summary.md` and post it on
**both** terminal states.

## Terminal states

### Ready to merge (success)

Post a summary comment on the PR:

```
sdd-pr-loop: all gates green ✅

Handover summary:
- Rounds run: <n>
- Worker totals: <worker>=<count>, ...
- Round-by-round:
  • round-1: <worker> (fix x<count>)
  • ...
- Blocking comments resolved: <count>
- Cache: .harness/.pr-loop/<pr>/
```

**Resolve Codex threads first — never human ones.** A repo ruleset may require every
review thread resolved before merge, but this loop may only auto-resolve threads **it
owns** (opened by the Codex bot). Auto-resolving a human reviewer's unresolved
conversation would silently bypass the merge gate that keeps human feedback meaningful.
So: fetch each unresolved thread with its participants; if **any** non-Codex participant
appears on an unresolved thread, **stop and go to the needs-human terminal state — resolve
nothing and do not merge**. Only when every remaining unresolved thread is Codex-owned do
you resolve them (via the GraphQL `resolveReviewThread` mutation — there is no REST/`gh pr`
equivalent) and proceed.

**A thread you could not read in full is not Codex-owned.** `--paginate` walks the outer
`reviewThreads` connection, but each thread's nested `comments` connection is fetched
once and capped at 100 — a human reply at position 101 would be invisible and the thread
would look Codex-only, which is exactly the auto-merge-over-human-feedback hole this rule
exists to close. So compare each thread's `comments.totalCount` against the number of
authors actually returned and **fail closed**: a truncated thread is *not* provably
Codex-only and takes the same needs-human path as a human reply. (`totalCount` rather
than a nested `pageInfo`, because a second `pageInfo` in the same response is precisely
what `gh api --paginate` scans when it looks for the next cursor.)

**An enumeration you could not finish is not an empty enumeration.** If the thread query
itself fails — transient API error, expired auth, a pagination hiccup — `gh` exits non-zero
having printed nothing, and that empty output is byte-identical to "this PR has no
unresolved threads". No inspection of the output can tell the two apart, so check the
command's **exit status** and fail closed: a failed enumeration is a needs-human terminal
state that resolves nothing and merges nothing. Hence `merge_ok` starts at `0` and is
raised only on the branch that actually *proved* every unresolved thread Codex-owned.

```bash
# Per unresolved thread emit "<allcodex> <id>", where <allcodex> is true only when the
# thread was read in FULL and EVERY participant is the Codex bot. A human reply on a
# Codex-opened thread makes it false — and so does a comment list longer than the 100
# fetched here, since an author you never read must never be assumed to be the bot.
# Both tests run in jq — no shell word-splitting. The two bot logins are inlined because
# `gh api --jq` takes no --arg, and are compared as EXACT literals: a prefix test would
# let `chatgpt-codex-connector-evil` pass as the thread's only participant, so the loop
# would resolve an impostor's thread and merge over it.
merge_ok=0            # fail closed: only a COMPLETED, clean enumeration may raise this
if ! unresolved=$(gh api graphql -f query='
  query($owner:String!,$repo:String!,$pr:Int!,$endCursor:String){
    repository(owner:$owner,name:$repo){
      pullRequest(number:$pr){
        reviewThreads(first:100,after:$endCursor){
          nodes{ id isResolved comments(first:100){ totalCount nodes{ author{ login } } } }
          pageInfo{ hasNextPage endCursor }
        }}}}' \
  -f owner="$owner" -f repo="$repo" -F pr="$pr_number" --paginate \
  --jq '.data.repository.pullRequest.reviewThreads.nodes[]
        | select(.isResolved | not)
        | (.comments.totalCount == (.comments.nodes | length)) as $whole
        | ([.comments.nodes[].author.login // ""]
             | all(. == "chatgpt-codex-connector"
                or . == "chatgpt-codex-connector[bot]")) as $codex
        | "\($whole and $codex) \(.id)"')
then
  # Enumeration FAILED: `unresolved` is empty because gh errored, not because the PR is
  # clean. Testing the status on the `if` itself (rather than after the assignment) reads
  # the same whether or not the host shell runs with `set -e`.
  echo "could not enumerate review threads — needs-human, not merging" >&2
elif printf '%s\n' "$unresolved" | grep -q '^false '; then
  echo "a thread is non-Codex or was not read in full — needs-human" >&2  # resolve NOTHING
else
  merge_ok=1          # enumeration completed; every unresolved thread is provably Codex's
  printf '%s\n' "$unresolved" | while read -r _allcodex tid; do
    [ -z "$tid" ] && continue
    gh api graphql -f query='
      mutation($id:ID!){ resolveReviewThread(input:{threadId:$id}){ thread{ id isResolved } } }' \
      -f id="$tid" >/dev/null
  done
fi
```

**If `merge_ok=0`, stop here** — go straight to the needs-human terminal state and run
**none** of the merge commands below.

While `pr_loop.auto_merge` is **false**, stop after posting the all-gates-green summary
and hand back to the human — resolve threads if you like, but **do not merge**. That
hand-back **completes** the loop: **return success**. It is the one terminal state where an
unmerged PR is the intended outcome, so never route it to needs-human.

Where `pr_loop.auto_merge` is **true**, merge with the configured `merge_strategy`,
deleting the remote branch in the same call. Track whether the merge command itself
**succeeded** (`merged`) — separate from `merge_ok`, which only recorded thread
eligibility — so cleanup never runs on a failed or pending merge:

```bash
merged=0
if [ "${merge_ok:-0}" != "1" ]; then
  echo "unresolved non-Codex threads remain — needs-human, not merging" >&2
elif [ "${merge_strategy:-merge}" = "squash" ]; then
  msg=".harness/.pr-loop/$pr_number/squash-message.txt"
  if [ -s "$msg" ]; then
    gh pr merge "$pr_number" --squash --delete-branch --body-file "$msg" && merged=1
  else                        # no message composed — squash with GitHub's default body
    gh pr merge "$pr_number" --squash --delete-branch && merged=1
  fi
else
  gh pr merge "$pr_number" --merge --delete-branch && merged=1
fi
```

`--delete-branch` removes the remote branch and the local tracking branch. Clean up any
lingering local branch **only if the merge command itself succeeded** (`merged=1`) —
never merely because thread eligibility was satisfied:

```bash
if [ "${merged:-0}" = "1" ]; then
  default_branch=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')
  branch=$(gh pr view "$pr_number" --json headRefName --jq '.headRefName')
  git checkout "$default_branch" >/dev/null 2>&1 || true
  git pull --ff-only >/dev/null 2>&1 || true
  git branch -D "$branch" 2>/dev/null || true          # local
  git remote prune origin >/dev/null 2>&1 || true      # drop the stale remote-tracking ref
fi
```

If `gh pr merge` fails (branch-protection race, a required review not yet registered, a
re-opened thread), retry once after 30s. If it still fails the PR will not land: take the
needs-human terminal state below — label `needs-human`, post the error alongside the
handover summary, and **return failure**. A merge that auto-merge was asked to land and did
not land is never reported as success.

### Needs-human (failure)

Apply the `needs-human` label, post the **same handover summary** block (so the human sees
exactly which workers tried and where they got stuck), and return failure. Reached by: the
`max_rounds` cap, a watcher timeout (exit `2`), an unresolved non-Codex thread, or a merge
that would not land.

**Every path into this state returns failure**, whatever the reason — the only successes
are a merge that actually landed and the `auto_merge: false` hand-back above. So an
unmerged PR is a success **only** when auto-merge was off; when auto-merge was on and the
merge did not land, that is this state, and it is a failure.

## Cache layout

```
.harness/.pr-loop/<pr>/
  round-1/
    pr.json                   # reviews summary, issue comments, checks, head oid
    review-comments.json      # the inline findings (source of truth)
    issue-comments.json       # paginated issue-comment stream (clean-banner scan)
    reactions.json            # reactions on the @codex trigger comment (👍 = clean)
    trigger-ts.txt            # freshness anchor
    fresh-comments.json, comments.json, blocking.json, status.json
    worker, role
    fix-<comment-id>.md       # one per fix
  round-2/ ...
  handover-summary.md
  squash-message.txt          # only when merge_strategy: squash
```
EOF
  # Mirror the generated command bodies into the SELECTED front-ends. Claude Code
  # reads .claude/commands/ (gated on `claude`, R3/R4); OpenCode reads
  # .opencode/command/ (gated on `opencode`, R3/R4). Both copy from the same CMDDIR,
  # so OpenCode commands appear even when `claude` is deselected.
  if agent_selected claude; then
    mkdir -p "$TARGET/.claude/commands"
    for _c in $HARNESS_SDD_CMDS; do
      cp "$CMDDIR/$_c.md" "$TARGET/.claude/commands/$_c.md"
    done
    ok "Claude Code commands /sdd-next + /sdd-new + /sdd-plan + /sdd-drill + /sdd-fix + /sdd-fix-parallel installed (.claude/)"
    if pr_loop_enabled; then
      for _c in $HARNESS_PR_LOOP_CMDS; do
        cp "$CMDDIR/$_c.md" "$TARGET/.claude/commands/$_c.md"
      done
      ok "Claude Code command /sdd-pr-loop installed (.claude/ — pr_loop.enabled)"
    fi
  fi

  # ── 5b. OpenCode commands (regenerated each run, gated on `opencode`) ────────
  # With no `agent:` frontmatter the command runs under the primary agent, which is
  # the orchestrator in the opencode.json below.
  if agent_selected opencode; then
    mkdir -p "$TARGET/.opencode/command"
    for _c in $HARNESS_SDD_CMDS; do
      cp "$CMDDIR/$_c.md" "$TARGET/.opencode/command/$_c.md"
    done
    ok "OpenCode commands /sdd-next + /sdd-new + /sdd-plan + /sdd-drill + /sdd-fix + /sdd-fix-parallel installed (.opencode/)"
    if pr_loop_enabled; then
      for _c in $HARNESS_PR_LOOP_CMDS; do
        cp "$CMDDIR/$_c.md" "$TARGET/.opencode/command/$_c.md"
      done
      # OpenCode discovers a file-based sub-agent at .opencode/agent/<name>.md. This is
      # the vendored source's own shape and keeps gen_opencode_json (and the
      # .harness/.opencode.stamp byte contract) completely untouched (R11/R12).
      mkdir -p "$TARGET/.opencode/agent"
      gen_oc_agent pr-fixer "$PR_FIXER_DESC" "$TARGET/.opencode/agent/pr-fixer.md"
      ok "OpenCode command /sdd-pr-loop + pr-fixer sub-agent installed (.opencode/ — pr_loop.enabled)"
    fi
  fi

  # ── 5c. Antigravity glue (.agents/, regenerated each run, gated on `antigravity`) ─
  # Antigravity (a Gemini-based agentic IDE) natively reads workspace-local
  # <root>/.agents/{rules,agents,workflows}/*.md. We stamp a glue layer that POINTS at
  # the canonical roles in .harness/agents/*.md — it never forks a role body. Mirrors
  # the per-tool pattern: personas model the .claude/agents shims (R4/R5 — best-effort:
  # bare-file persona discovery is unconfirmed, so they are written but not relied on),
  # and the workflows are COPIED from the shared CMDDIR command bodies exactly like
  # OpenCode (§5b), so the three front-ends stay byte-identical (R9). Placed after §5b and
  # before the CMDDIR cleanup so the workflow bodies are still available. (E07-F01 R2,R4,R6.)
  if agent_selected antigravity; then
    mkdir -p "$TARGET/.agents/rules" "$TARGET/.agents/agents" "$TARGET/.agents/workflows"

    # Entrypoint rule (R2/R3): points the agent at the source of truth + entry role;
    # mandates init.sh first. No copied role body — references by .harness/ path only.
    # Body lives in gen_ag_rule (hoisted) so the §7 deselect compare can reproduce it.
    gen_ag_rule "$TARGET/.agents/rules/harness.md"

    # Personas (R4/R5 — best-effort): one per harness role, each with a `description` + a
    # body that DEFERS to the canonical .harness/agents/<role>.md, mandates init.sh-first +
    # halt-on-fail, and hands off via .harness/progress/. No copied role body. Bare-file
    # persona discovery is UNCONFIRMED, so these are written (cheap, possibly honored) but
    # the harness does not claim they register as subagents — the durable model is the rule
    # + the `description`-gated workflows (R12). Descriptions come from ag_personas (the
    # single role→description source, shared with the §7 deselect compare so they can never
    # diverge).
    ag_personas | while IFS='	' read -r _agr _agd; do
      [ -n "$_agr" ] || continue
      gen_ag_persona "$_agr" "$_agd" "$TARGET/.agents/agents/$_agr.md"
    done

    # Workflows (R6/R7/R8/R9): COPY the shared command bodies from CMDDIR (mirror, like
    # the OpenCode block — do not re-author). The bodies already begin with their own
    # `---\ndescription: …\n---` frontmatter, which satisfies Antigravity's slash-command
    # registration (R7), and they already act as their role resolved against
    # .harness/agents/*.md carrying $ARGUMENTS (R8). A `cp` keeps them byte-identical to
    # the Claude/OpenCode copies so the front-ends stay byte-identical.
    for _w in $HARNESS_SDD_CMDS; do
      cp "$CMDDIR/$_w.md" "$TARGET/.agents/workflows/$_w.md"
    done

    # Gated pr_loop glue (E18-F01 R2/R13): the /sdd-pr-loop workflow + the pr-fixer
    # persona. gen_ag_persona is called HERE, deliberately OUTSIDE the ag_personas loop
    # above — adding a `pr-fixer` row to ag_personas would also create
    # `.gemini/agents/pr-fixer.md` and `.codex/agents/pr-fixer.toml` (§5e/§5f iterate the
    # same map) and break E17-F01 R11. The persona is emitted, never model-routed (R14).
    if pr_loop_enabled; then
      for _w in $HARNESS_PR_LOOP_CMDS; do
        cp "$CMDDIR/$_w.md" "$TARGET/.agents/workflows/$_w.md"
      done
      gen_ag_persona pr-fixer "$PR_FIXER_DESC" "$TARGET/.agents/agents/pr-fixer.md"
    fi

    ok "Antigravity glue (rules + agents + workflows) installed (.agents/)"
  fi

  # ── 5d. Codex CLI prompts (GLOBAL, gated on `codex`) ─────────────────────────
  # Codex CLI has no project-local custom-command mechanism (no `.codex/commands/`
  # or workspace-local prompts dir it reads). Its ONLY custom-slash-command surface
  # is the GLOBAL prompts dir `${CODEX_HOME:-$HOME/.codex}/prompts/*.md`, where each
  # `<name>.md` registers as the slash command `/prompts:<name>` (Codex namespaces
  # prompt files under `/prompts:`, NOT top-level `/<name>`). So — unlike every other
  # front-end, whose glue
  # is workspace-local under $TARGET — the `codex` stamp writes OUTSIDE the target, to
  # a single machine-global dir. Consequences, by design (accepted at install time):
  #   • the prompts are shared by EVERY harness target on this machine (they overwrite
  #     each other), and are not scoped per-repo;
  #   • that is harmless because each body resolves its relative paths against `.harness/`
  #     of whatever repo Codex is launched in (Codex runs from the repo root and reads
  #     that repo's AGENTS.md), so ONE global copy correctly drives any target;
  #   • deselect removal (§7) only reclaims byte-pristine copies (a user edit survives),
  #     and honors $CODEX_HOME so it never touches an unrelated home.
  # Copies the same CMDDIR bodies as §5b/§5c, so all front-ends stay byte-identical.
  if agent_selected codex; then
    _cdx="$(codex_prompts_dir)"
    if [ -z "$_cdx" ]; then
      # Neither CODEX_HOME nor HOME set: skip Codex glue rather than abort the whole
      # install (other front-ends must still complete). (Codex r1 P2.)
      echo "⚠️  codex selected but neither CODEX_HOME nor HOME is set — skipping GLOBAL /prompts:sdd-* install" >&2
    else
      mkdir -p "$_cdx"
      # The gated /sdd-pr-loop prompt joins the same copy loop (and therefore the same
      # backup/warn behavior) only while pr_loop.enabled is true (R2/R3).
      _cdx_cmds="$HARNESS_SDD_CMDS"
      if pr_loop_enabled; then _cdx_cmds="$HARNESS_OWNED_CMDS"; fi
      for _c in $_cdx_cmds; do
        _dst="$_cdx/$_c.md"
        # This dir is a USER-owned global namespace, not a harness-owned workspace dir,
        # so a same-named file may be the user's OWN prompt — an original, OR a later
        # edit of a previously-installed one. Never silently lose it: if the current file
        # differs from the harness body we're about to write, back it up and warn BEFORE
        # overwriting. Refresh the backup whenever the current contents differ from what
        # the backup already holds, so a post-install user edit is captured too (not just
        # the first original) — otherwise a stale backup + silent clobber would drop the
        # user's latest content. A routine re-install/upgrade where the current file is
        # already the (identical) harness body never enters this branch, so it neither
        # warns nor churns the backup. (Codex r2 P2 + r3 P2.)
        if [ -f "$_dst" ] && ! cmp -s "$_dst" "$CMDDIR/$_c.md"; then
          if [ ! -f "$_dst.pre-harness.bak" ] || ! cmp -s "$_dst" "$_dst.pre-harness.bak"; then
            cp "$_dst" "$_dst.pre-harness.bak"
          fi
          echo "⚠️  existing global Codex prompt $_dst differs from the harness copy — backed up to $_dst.pre-harness.bak before overwriting" >&2
        fi
        cp "$CMDDIR/$_c.md" "$_dst"
        # Stake this target's claim on the GATED prompt in the shared, cross-target
        # prompts dir, so no OTHER target's gate-off run can reclaim it out from under us.
        if _is_pr_loop_cmd "$_c"; then _owners_claim "$_cdx" "$_c"; fi
      done
      # Codex surfaces a prompts-dir file `<name>.md` as the slash command
      # `/prompts:<name>` (NOT top-level `/<name>`) — advertise it that way.
      ok "Codex CLI prompts /prompts:sdd-next + /prompts:sdd-new + /prompts:sdd-plan + /prompts:sdd-drill + /prompts:sdd-fix + /prompts:sdd-fix-parallel installed (GLOBAL: $_cdx)"
    fi
  fi

  # ── 5e. Gemini per-role agent definitions (gated on `gemini` + a resolvable model) ─
  # CONDITIONAL by design (E17-F01 R11/R17): this tree is created ONLY when at least one
  # role resolves to a concrete value. With no `models:` block — or every role on
  # `inherit` — `.gemini/agents/` is never created and the target tree stays exactly what
  # it was before this feature existed.
  if agent_selected gemini && models_any gemini; then
    mkdir -p "$TARGET/.gemini/agents"
    ag_personas | while IFS='	' read -r _gmr _gmd; do
      [ -n "$_gmr" ] || continue
      gen_gemini_agent "$_gmr" "$_gmd" "$TARGET/.gemini/agents/$_gmr.md"
      stamp_model_agent gemini "$_gmr.md" "$TARGET/.gemini/agents/$_gmr.md"
    done
    ok "Gemini per-role agent definitions installed (.gemini/agents/)"
  elif agent_selected gemini; then
    # Nothing resolves any more — but a PREVIOUS run may have stamped this tree with a
    # concrete tier. Skipping here would leave those files (and their old `model:` keys)
    # discoverable, so the documented switch back to session inheritance would silently
    # keep using the old model. Reconcile instead: reclaim the pristine stamps and prune,
    # which is what makes R11 ("no `.gemini/agents/` at all") true on a target that WAS
    # configured, not just on a fresh one. (Codex r1 P1 #3654925551.)
    reclaim_model_agents gemini
  fi

  # ── 5f. Codex per-role agent definitions (gated on `codex` + a resolvable model) ──
  # PROJECT-LOCAL, always: written under $TARGET, never into $CODEX_HOME/$HOME/.codex.
  # A model stamp is target-dependent, so the machine-global path §5d uses for prompts
  # would let one repo silently retune another. Same conditional creation as §5e.
  if agent_selected codex && models_any codex; then
    mkdir -p "$TARGET/.codex/agents"
    ag_personas | while IFS='	' read -r _cxr _cxd; do
      [ -n "$_cxr" ] || continue
      gen_codex_agent "$_cxr" "$_cxd" "$TARGET/.codex/agents/$_cxr.toml"
      stamp_model_agent codex "$_cxr.toml" "$TARGET/.codex/agents/$_cxr.toml"
    done
    ok "Codex per-role agent definitions installed (.codex/agents/ — project-local)"
  elif agent_selected codex; then
    # Same reconciliation as §5e — see the note there. Only the PROJECT-LOCAL tree is
    # touched; nothing under $CODEX_HOME is ever created or removed by model routing.
    reclaim_model_agents codex
  fi

  # NOTE: CMDDIR cleanup is intentionally DEFERRED to AFTER §7 — the antigravity
  # deselect compare byte-checks each `.agents/workflows/<name>.md` against the
  # source `$CMDDIR/<name>.md`, so the temp workflow bodies must stay available
  # through the reconciliation loop. CMDDIR is only a temp dir; cleaning it later
  # is harmless and still unconditional. (Codex r2 P1 #3404240336.)

  # ── 6. opencode.json (gated on `opencode`; create if absent; never clobber) ──
  # Unlike every other generated artifact, opencode.json is NOT regenerated on a plain
  # re-run — it is a config file the operator may own. Per-role model routing needs a
  # re-stamp path, so the never-clobber contract is refined rather than dropped
  # (E17-F01 R20): regenerate in place ONLY when the on-disk file is byte-identical to
  # something the installer itself produced —
  #   (a) `.harness/.opencode.stamp`, the byte copy of the last opencode.json we wrote
  #       (this is what makes a re-stamp possible AFTER a model was already stamped), or
  #   (b) a freshly generated MODEL-FREE body (every pre-E17 target, and every target
  #       whose roles are all `inherit`).
  # Anything else is a user-owned file: left byte-for-byte untouched, with a warning that
  # model changes were not applied.
  #
  # The body is installed with `cat "$_oc_new" > …`, NEVER `cp`. `$_oc_new` is a mktemp
  # file (mode 0600) and `cp` to a NON-EXISTENT destination copies the source's permission
  # bits, which would silently make a fresh install's opencode.json 0600 where the
  # pre-E17 `gen_opencode_json "$TARGET/opencode.json"` (a plain `>` redirect) produced
  # 0666 & ~umask ⇒ 0644 — and would make fresh targets diverge from upgraded ones, since
  # `cp` onto an EXISTING file keeps that file's mode. `>` creates at the umask default
  # and preserves an existing file's mode, i.e. the exact pre-feature behaviour on both
  # paths. Asserted by tests/test_model_routing.sh::test_opencode_json_restamp_rules.
  if agent_selected opencode; then
    _oc_new="$(mktemp 2>/dev/null || mktemp -t harness-oc)"
    gen_opencode_json "$_oc_new"
    _oc_written=0
    if [ ! -f "$TARGET/opencode.json" ]; then
      cat "$_oc_new" > "$TARGET/opencode.json"
      _oc_written=1
      ok "opencode.json created"
    else
      _oc_free="$(mktemp 2>/dev/null || mktemp -t harness-ocf)"
      MODELS_OFF=1; gen_opencode_json "$_oc_free"; MODELS_OFF=0
      if { [ -f "$H/.opencode.stamp" ] && cmp -s "$TARGET/opencode.json" "$H/.opencode.stamp"; } \
         || cmp -s "$TARGET/opencode.json" "$_oc_free"; then
        cat "$_oc_new" > "$TARGET/opencode.json"
        _oc_written=1
        info "opencode.json regenerated (pristine harness stamp; model routing applied)"
      else
        echo "⚠️  opencode.json differs from the generated stamp (edited) — left untouched; model routing changes were NOT applied" >&2
      fi
      rm -f "$_oc_free"
    fi
    # The stamp exists only to make a re-stamp possible once a model key is present; a
    # model-free body is already reproducible from gen_opencode_json, so no stamp is kept
    # for it (that keeps R11 true: an unconfigured target grows no new file).
    if [ "$_oc_written" = 1 ]; then
      if grep -q '"model":' "$TARGET/opencode.json"; then
        cp "$TARGET/opencode.json" "$H/.opencode.stamp"
      else
        rm -f "$H/.opencode.stamp"
      fi
    fi
    rm -f "$_oc_new"
  fi

  # ── 7. selection persistence + add/remove reconciliation (E08-F01) ───────────
  # Persist the resolved selection beside .harness-version as harness-owned metadata
  # (one sorted key per line, overwritten every run) (R8).
  printf '%s\n' "$SELECTED" > "$H/.agents"

  # Reconcile removals (R12 adds are handled by the gated stamps above): for any key
  # in the PRIOR persisted set but NOT in SELECTED, delete that agent's harness-owned,
  # regenerated glue and warn, naming each removed path. NEVER touch AGENTS.md or the
  # .harness/ body (R13). Scoped to the registry-owned paths only.
  if [ -n "$PRIOR_AGENTS" ]; then
    printf '%s\n' "$PRIOR_AGENTS" | while IFS= read -r _rk; do
      [ -n "$_rk" ] || continue
      agent_selected "$_rk" && continue   # still selected → keep
      case "$_rk" in
        claude)
          remove_pointer CLAUDE.md
          # HARNESS_CLAUDE_SHIMS carries `pr-fixer` and HARNESS_OWNED_CMDS carries
          # `sdd-pr-loop` as REMOVAL-ledger entries (E18-F01 R4): a target stamped while
          # pr_loop.enabled was true must still be reclaimable. remove_owned is by-name and
          # `[ -f ]`-guarded, so a never-stamped stem is a harmless no-op.
          remove_owned .claude/agents   claude $HARNESS_CLAUDE_SHIMS
          remove_owned .claude/commands claude $HARNESS_OWNED_CMDS
          rmdir "$TARGET/.claude" 2>/dev/null || true   # prune parent only if now empty
          ;;
        gemini)
          # GEMINI.md is SHARED: it is the in-repo entrypoint for gemini AND
          # antigravity (E07-F01 R1/R12). Remove it only when NEITHER owner remains
          # selected — otherwise deselecting gemini while antigravity stays selected
          # would wrongly strip Antigravity's entrypoint.
          if ! agent_selected antigravity; then
            remove_pointer GEMINI.md
            echo "⚠️  removed deselected agent 'gemini' glue: GEMINI.md harness block" >&2
          fi
          # E17-F01: reclaim the per-role model artifacts (.gemini/agents/<role>.md)
          # through the SAME helper §5e's reconciliation uses, so deselection and
          # "everything back to inherit" can never diverge. Pristine-only (a
          # user-edited file is left in place with a warning); never `rm -rf`.
          reclaim_model_agents gemini
          ;;
        opencode)
          remove_owned .opencode/command opencode $HARNESS_OWNED_CMDS
          # E18-F01 R4/R7: `.opencode/agent/` is a pr_loop-owned dir. By-name removal of the
          # harness stem only, then rmdir the subdir and the parent — each only when empty,
          # so a user's own file-based agent (and the dir holding it) survives.
          remove_owned .opencode/agent   opencode pr-fixer
          rmdir "$TARGET/.opencode" 2>/dev/null || true   # prune parent only if now empty
          # opencode.json: delete ONLY a file byte-identical to what the installer
          # generates (a pristine, untouched stamp). ANY user edit — even adding a
          # `model`/providers key to the generated file — makes it differ, so it is
          # left in place with a warning. This is precise where the old substring
          # heuristic was too broad and could delete edited config. (Codex r4 P2)
          # E17-F01 R22: with model routing the generated body depends on the config, so
          # compare against `.harness/.opencode.stamp` (the exact bytes we last wrote)
          # FIRST, then fall back to a freshly generated body. The stamp closes the gap
          # where the operator edits `models:` and deselects WITHOUT an install in
          # between. On removal the stamp goes with the file it describes.
          if [ -f "$TARGET/opencode.json" ]; then
            _ref="$(mktemp 2>/dev/null || mktemp -t harness-oc)"
            gen_opencode_json "$_ref"
            if { [ -f "$H/.opencode.stamp" ] && cmp -s "$TARGET/opencode.json" "$H/.opencode.stamp"; } \
               || cmp -s "$TARGET/opencode.json" "$_ref"; then
              rm -f "$TARGET/opencode.json"
              rm -f "$H/.opencode.stamp"
              echo "⚠️  removed deselected agent 'opencode' glue: opencode.json (pristine generated)" >&2
            else
              echo "⚠️  opencode.json differs from the generated stamp (edited) — left in place (deselected 'opencode' not removed)" >&2
            fi
            rm -f "$_ref"
          fi
          ;;
        antigravity)
          # E07-F01: the antigravity stamp (§5c) OWNS a scoped `.agents/` glue tree
          # (rules/harness.md, the role personas, the sdd-* workflows). Deselection
          # removes ONLY files byte-identical to a freshly-generated stamp (pristine)
          # — NOT delete-by-name — so a user's OWN `.agents/agents/builder.md` (or any
          # standard-named persona/workflow they authored) survives. This mirrors the
          # opencode.json `cmp -s` contract above and fixes the data-loss case where a
          # pre-this-version no-op antigravity install left `antigravity` persisted in
          # `.harness/.agents` while the user authored their own `.agents/` files.
          # (Codex r2 P1 #3404240336; r3 P1 #3400997183 stays honored — scoped, never
          # destructive of non-harness files.)
          _agtmp="$(mktemp 2>/dev/null || mktemp -t harness-ag)"
          # rule
          gen_ag_rule "$_agtmp"
          remove_if_pristine .agents/rules/harness.md "$_agtmp" antigravity
          # personas — compare each against its freshly-generated body (same source
          # role→description map as the install loop, so no divergence).
          ag_personas | while IFS='	' read -r _agr _agd; do
            [ -n "$_agr" ] || continue
            gen_ag_persona "$_agr" "$_agd" "$_agtmp"
            remove_if_pristine ".agents/agents/$_agr.md" "$_agtmp" antigravity
          done
          # pr-fixer (E18-F01 R4): emitted OUTSIDE ag_personas (see §5c), so reclaim it
          # outside the loop too — same emitter, same pristine-only contract.
          gen_ag_persona pr-fixer "$PR_FIXER_DESC" "$_agtmp"
          remove_if_pristine ".agents/agents/pr-fixer.md" "$_agtmp" antigravity
          # workflows — the install path `cp`s these verbatim from $CMDDIR, so the
          # pristine reference is the still-present $CMDDIR/<name>.md source bytes.
          # HARNESS_OWNED_CMDS so a stamped `sdd-pr-loop` workflow is reclaimable too.
          for _agw in $HARNESS_OWNED_CMDS; do
            [ -f "$CMDDIR/$_agw.md" ] || continue
            remove_if_pristine ".agents/workflows/$_agw.md" "$CMDDIR/$_agw.md" antigravity
          done
          rm -f "$_agtmp"
          # Prune each now-empty `.agents/` subdir + the parent, only when empty
          # (never `rm -rf` — preserve any user files left in place above).
          rmdir "$TARGET/.agents/rules" 2>/dev/null || true
          rmdir "$TARGET/.agents/agents" 2>/dev/null || true
          rmdir "$TARGET/.agents/workflows" 2>/dev/null || true
          rmdir "$TARGET/.agents" 2>/dev/null || true   # prune parent only if now empty
          # GEMINI.md is SHARED with gemini (E07-F01 R1/R12). Antigravity owns it as
          # an in-repo entrypoint too, so remove it on antigravity deselection ONLY
          # when gemini is also not selected — mirroring the gemini case. (Without
          # this, deselecting an antigravity-only install would orphan GEMINI.md,
          # since the gemini branch never runs when gemini was never a prior agent.)
          if ! agent_selected gemini; then
            remove_pointer GEMINI.md
            echo "⚠️  removed deselected agent 'antigravity' glue: GEMINI.md harness block" >&2
          fi
          ;;
        codex)
          # §5d installs GLOBAL prompts to ${CODEX_HOME:-$HOME/.codex}/prompts. Reclaim
          # ONLY byte-pristine copies (cmp -s against the still-present $CMDDIR source),
          # so a user-edited /sdd-* prompt survives — mirroring the opencode.json /
          # antigravity pristine-only contract. Honors $CODEX_HOME. NOTE: these prompts
          # are machine-global and may be shared by another harness target that still
          # selects `codex`; a subsequent install there re-stamps them (bodies are
          # regenerated every run), so removal here is safe but announced as GLOBAL.
          _cdx="$(codex_prompts_dir)"
          if [ -n "$_cdx" ]; then
            _cdx_removed=""
            for _cdw in $HARNESS_OWNED_CMDS; do
              [ -f "$CMDDIR/$_cdw.md" ] || continue
              # The GATED prompt is ledger-governed (see _owners_release): dropping codex
              # here retires only THIS target's claim, and the shared file survives while
              # any other target still wants it. Unlike the ungated /sdd-* prompts, a
              # target that stops wanting it never re-stamps it, so a wrong delete is
              # permanent for everyone else.
              if _is_pr_loop_cmd "$_cdw" && ! _owners_release "$_cdx" "$_cdw"; then
                if [ -f "$_cdx/$_cdw.md" ]; then
                  echo "⚠️  $_cdx/$_cdw.md is still claimed by another harness target (or its ownership is unknown) — left in place (GLOBAL, shared prompts)" >&2
                fi
                continue
              fi
              if [ -f "$_cdx/$_cdw.md" ] && cmp -s "$_cdx/$_cdw.md" "$CMDDIR/$_cdw.md"; then
                rm -f "$_cdx/$_cdw.md"
                _cdx_removed="$_cdx_removed $_cdw.md"
              elif [ -f "$_cdx/$_cdw.md" ]; then
                echo "⚠️  $_cdx/$_cdw.md differs from the generated prompt (edited) — left in place (deselected 'codex' not fully removed)" >&2
              fi
            done
            [ -n "$_cdx_removed" ] && echo "⚠️  removed deselected agent 'codex' glue:$_cdx_removed (in $_cdx/ — GLOBAL, shared prompts)" >&2
            rmdir "$_cdx" 2>/dev/null || true   # prune only if now empty
          fi
          # E17-F01: reclaim the PROJECT-LOCAL per-role model artifacts
          # (.codex/agents/<role>.toml) through the same shared helper as §5f. The GLOBAL
          # prompt reclamation above is untouched, and nothing under $CODEX_HOME/agents is
          # ever created or removed.
          reclaim_model_agents codex
          ;;
      esac
    done
  fi

  # ── 7b. pr_loop gate-off reclamation (E18-F01 R5) ────────────────────────────
  # The §7 loop above reconciles ONE axis: a front-end that was in PRIOR_AGENTS and is no
  # longer SELECTED. `pr_loop.enabled: true → false` is a DIFFERENT axis — the front-end
  # is still selected, so that loop structurally never visits it and a previously-stamped
  # /sdd-pr-loop command + pr-fixer artifact would be orphaned (still discoverable, still
  # advertising a loop the operator turned off).
  #
  # So: while the gate is OFF, walk every STILL-SELECTED front-end and reclaim its pr_loop
  # glue under exactly the R4 ownership rules — by name inside harness-owned workspace
  # dirs, byte-pristine-compare inside the user-owned global Codex prompts dir and the
  # Antigravity `.agents/` tree — then prune only dirs left empty.
  #
  # ORDERING IS LOAD-BEARING: this must run BEFORE the `rm -rf "$CMDDIR"` below, because
  # the pristine references are the still-present `$CMDDIR/<name>.md` bytes. That is also
  # why §5 generates the body unconditionally (R1) — with generation gated, the reference
  # would vanish the moment the gate flipped and the stamped copy would be unremovable.
  if ! pr_loop_enabled; then
    _prl_gone=""
    if agent_selected claude; then
      for _prc in $HARNESS_PR_LOOP_CMDS; do
        if [ -f "$TARGET/.claude/commands/$_prc.md" ]; then
          rm -f "$TARGET/.claude/commands/$_prc.md"; _prl_gone="$_prl_gone .claude/commands/$_prc.md"
        fi
      done
      if [ -f "$TARGET/.claude/agents/pr-fixer.md" ]; then
        rm -f "$TARGET/.claude/agents/pr-fixer.md"; _prl_gone="$_prl_gone .claude/agents/pr-fixer.md"
      fi
      rmdir "$TARGET/.claude/commands" 2>/dev/null || true
      rmdir "$TARGET/.claude/agents" 2>/dev/null || true
      rmdir "$TARGET/.claude" 2>/dev/null || true
    fi
    if agent_selected opencode; then
      for _prc in $HARNESS_PR_LOOP_CMDS; do
        if [ -f "$TARGET/.opencode/command/$_prc.md" ]; then
          rm -f "$TARGET/.opencode/command/$_prc.md"; _prl_gone="$_prl_gone .opencode/command/$_prc.md"
        fi
      done
      if [ -f "$TARGET/.opencode/agent/pr-fixer.md" ]; then
        rm -f "$TARGET/.opencode/agent/pr-fixer.md"; _prl_gone="$_prl_gone .opencode/agent/pr-fixer.md"
      fi
      rmdir "$TARGET/.opencode/agent" 2>/dev/null || true
      rmdir "$TARGET/.opencode/command" 2>/dev/null || true
      rmdir "$TARGET/.opencode" 2>/dev/null || true
    fi
    if agent_selected antigravity; then
      # `.agents/` is a user-owned namespace ⇒ pristine-compare, never delete-by-name.
      _prl_tmp="$(mktemp 2>/dev/null || mktemp -t harness-prl)"
      gen_ag_persona pr-fixer "$PR_FIXER_DESC" "$_prl_tmp"
      _prl_gone="$_prl_gone $(remove_if_pristine .agents/agents/pr-fixer.md "$_prl_tmp" antigravity)"
      rm -f "$_prl_tmp"
      for _prc in $HARNESS_PR_LOOP_CMDS; do
        [ -f "$CMDDIR/$_prc.md" ] || continue
        _prl_gone="$_prl_gone $(remove_if_pristine ".agents/workflows/$_prc.md" "$CMDDIR/$_prc.md" antigravity)"
      done
      rmdir "$TARGET/.agents/agents" 2>/dev/null || true
      rmdir "$TARGET/.agents/workflows" 2>/dev/null || true
      rmdir "$TARGET/.agents" 2>/dev/null || true
    fi
    if agent_selected codex; then
      # GLOBAL, cross-target prompts dir — pristine-only, honors $CODEX_HOME.
      # THIS target's gate says nothing about what OTHER targets sharing $CODEX_HOME want,
      # so reclamation is ledger-governed: retire our claim first and touch the shared file
      # only once nobody is left holding one (see _owners_release; Codex r4 P1 #3662785235).
      _prl_cdx="$(codex_prompts_dir)"
      if [ -n "$_prl_cdx" ]; then
        for _prc in $HARNESS_PR_LOOP_CMDS; do
          [ -f "$CMDDIR/$_prc.md" ] || continue
          if ! _owners_release "$_prl_cdx" "$_prc"; then
            if [ -f "$_prl_cdx/$_prc.md" ]; then
              echo "⚠️  $_prl_cdx/$_prc.md is still claimed by another harness target (or its ownership is unknown) — left in place (pr_loop disabled here, GLOBAL shared prompts)" >&2
            fi
            continue
          fi
          if [ -f "$_prl_cdx/$_prc.md" ] && cmp -s "$_prl_cdx/$_prc.md" "$CMDDIR/$_prc.md"; then
            rm -f "$_prl_cdx/$_prc.md"; _prl_gone="$_prl_gone $_prl_cdx/$_prc.md"
          elif [ -f "$_prl_cdx/$_prc.md" ]; then
            echo "⚠️  $_prl_cdx/$_prc.md differs from the generated prompt (edited) — left in place (pr_loop disabled, not removed)" >&2
          fi
        done
        rmdir "$_prl_cdx" 2>/dev/null || true   # prune only if now empty
      fi
    fi
    if [ -n "$(printf '%s' "$_prl_gone" | tr -d '[:space:]')" ]; then
      echo "⚠️  pr_loop.enabled is not true — reclaimed /sdd-pr-loop glue:$_prl_gone" >&2
    fi
  fi

  # CMDDIR cleanup (deferred from §5c and §7b): the antigravity deselect compare and the
  # gate-off pass above need the temp command bodies as their pristine reference.
  # Unconditional — always runs regardless of selection.
  rm -rf "$CMDDIR"
  # Model-routing diagnostic ledger (E17-F01): only de-duplicates stderr advisories.
  rm -f "$MODEL_DIAG"

  # ── done ────────────────────────────────────────────────────────────────────
  echo "──────────────────────────────────────────────────"
  if [ "$UPGRADE" = 1 ]; then
    ok "upgrade complete (v$VERSION)"
  else
    ok "install complete (v$VERSION)"
    echo
    echo "Next steps:"
    echo "  1. Edit .harness/specs/product.md for your product."
    echo "  2. Open the repo in Claude Code and run  /sdd-next  to bootstrap"
    echo "     (detect test/lint commands, draft your first epics)."
  fi

  LAST_UPGRADE="$UPGRADE"
}

# ── manifest auto-population (append-only upsert, never clobbers entries) ──────
# manifest_upsert <manifest-path> <repo-name>
#   Ensures the manifest has a top-level `repos:` header and a block for <repo-name>.
#   If the key already exists under repos:, the block is left untouched (a
#   bootstrap-filled test_command/delegate_cmd survives re-runs). New entries get a
#   relative path and TODO placeholders. Two-space repo keys match init.sh's grammar.
manifest_upsert() {
  _mf="$1"; _name="$2"
  if [ ! -f "$_mf" ]; then
    printf 'repos:\n' > "$_mf"
  elif ! grep -Eq '^repos:[[:space:]]*$' "$_mf"; then
    # File exists but has no top-level `repos:` header (empty or comments-only).
    # init.sh only recognizes repo entries AFTER a `repos:` line, so add it —
    # otherwise the appended child blocks below would be unreadable.
    printf 'repos:\n' >> "$_mf"
  fi
  # Already present UNDER repos:? — never clobber. Scope the check to the repos:
  # mapping so a same-named two-space key in an unrelated section (e.g. `metadata:`)
  # is not mistaken for the repo entry.
  if awk -v n="$_name" '
       /^repos:[[:space:]]*$/ { r=1; next }
       r && /^[^[:space:]#]/ { r=0 }
       r && $0 ~ ("^  " n ":[[:space:]]*$") { found=1 }
       END { exit found ? 0 : 1 }
     ' "$_mf"; then
    return 0
  fi
  # Build the entry as a single string with literal `\n` escapes — `awk -v` converts
  # them to newlines (a value with real newlines would error "newline in string").
  _blk='  '"$_name"':\n    path: ./'"$_name"'\n    init: ./init.sh         # TODO: confirm child init\n    test_command: ""        # TODO: set during bootstrap\n    delegate_cmd: ""        # TODO: wire executor'
  # Insert the entry INSIDE the repos: mapping — immediately before the next top-level
  # key after `repos:` (a column-0, non-comment, non-blank line), or at EOF when
  # repos: is the last section. Appending blindly at EOF would otherwise nest the entry
  # under a later top-level section (e.g. a trailing `metadata:`), which init.sh — and
  # therefore the coordinator — would not read.
  awk -v blk="$_blk" '
    /^repos:[[:space:]]*$/ { print; in_repos=1; next }
    in_repos && !inserted && /^[^[:space:]#]/ { print blk; inserted=1; in_repos=0 }
    { print }
    END { if (in_repos && !inserted) print blk }
  ' "$_mf" > "$_mf.uptmp" && mv "$_mf.uptmp" "$_mf"
}

# ── arg parsing ───────────────────────────────────────────────────────────────
UMBRELLA=""
RECURSIVE=0
DRY_RUN=0
SHARED_REPO=0
POSITIONAL=""
# Agent selection override (E08-F01): --agents=<csv> wins over HARNESS_AGENTS, which
# wins over the interactive prompt / no-TTY ALL default. Seed from the environment so
# `--agents` (parsed below) can supersede it; an empty value means "no override".
AGENTS_OVERRIDE="${HARNESS_AGENTS:-}"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --agents=*)
      # Explicit override; an empty value (`--agents=`) is treated as "no override"
      # (fall through to the prompt / ALL default), matching HARNESS_AGENTS="".
      AGENTS_OVERRIDE="${1#--agents=}"
      shift
      ;;
    --agents)
      [ "$#" -ge 2 ] || die "usage: $0 --agents=<csv> (e.g. --agents=claude,opencode)"
      AGENTS_OVERRIDE="$2"
      shift 2
      ;;
    --umbrella)
      [ "$#" -ge 2 ] || die "usage: $0 --umbrella <umbrella-dir> [--shared-repo] [--recursive] [--dry-run]"
      UMBRELLA="$2"
      shift 2
      ;;
    --shared-repo)
      # Opt-in: version-control the umbrella root (git init + ignore product children).
      # Umbrella mode only; validated below. See docs/UMBRELLA.md "Shared spec repository".
      SHARED_REPO=1
      shift
      ;;
    --recursive)
      RECURSIVE=1
      shift
      ;;
    --dry-run|--list)
      # Preview the cascade: list the coordinator + every git child that WOULD be
      # installed (with skip reasons), writing nothing. Umbrella mode only.
      DRY_RUN=1
      shift
      ;;
    --)
      shift
      ;;
    -*)
      die "unknown option: $1"
      ;;
    *)
      if [ -z "$POSITIONAL" ]; then POSITIONAL="$1"; else die "unexpected argument: $1"; fi
      shift
      ;;
  esac
done

# ── single-target mode (no --umbrella): behave exactly as before ──────────────
if [ -z "$UMBRELLA" ]; then
  [ "$DRY_RUN" = 0 ] || die "--dry-run/--list is umbrella-mode only (use with --umbrella)"
  [ "$SHARED_REPO" = 0 ] || die "--shared-repo is umbrella-mode only (use with --umbrella)"
  if [ "${POSITIONAL}" = "" ]; then die "usage: $0 <target-repo-path>"; fi
  TGT="$POSITIONAL"
  if [ ! -d "$TGT" ]; then die "target '$TGT' is not a directory"; fi
  TGT="$(CDPATH= cd -- "$TGT" && pwd)"
  if [ "$TGT" = "$SRC" ]; then die "target must differ from the harness source ($SRC)"; fi
  install_one "$TGT"
  exit 0
fi

# ── umbrella mode (cascade) ───────────────────────────────────────────────────
if [ ! -d "$UMBRELLA" ]; then die "umbrella dir '$UMBRELLA' is not a directory"; fi
if [ -n "$POSITIONAL" ]; then die "do not pass a positional <target> with --umbrella"; fi
# Resolve PHYSICAL paths (pwd -P) so a symlinked umbrella that points at the harness
# source is caught here — otherwise the coordinator install would self-install into
# the source checkout (same footgun the child-loop guard already prevents).
UMB="$(CDPATH= cd -- "$UMBRELLA" && pwd -P)"
if [ "$UMB" = "$(CDPATH= cd -- "$SRC" && pwd -P)" ]; then die "umbrella dir must differ from the harness source ($SRC)"; fi

if [ "$DRY_RUN" = 1 ]; then
  echo "══ umbrella cascade (DRY RUN — nothing will be written) → $UMB ══"
else
  echo "══ umbrella cascade → $UMB ══"
fi

# (a) coordinator profile into the umbrella dir.
if [ "$DRY_RUN" = 1 ]; then
  echo "would install coordinator profile → $UMB/.harness/"
  echo "would set/keep umbrella.manifest → ../umbrella.manifest.yaml (ENGAGES umbrella mode)"
  echo "── discovering git children (depth 1) ──"
  found_any=0
  for child in "$UMB"/*/; do
    [ -d "$child" ] || continue
    name="$(basename "$child")"
    case "$name" in .*) continue ;; .harness) continue ;; esac
    [ -e "$child/.git" ] || continue
    child_abs="$(CDPATH= cd -- "$child" && pwd -P)"
    if [ "$child_abs" = "$(CDPATH= cd -- "$SRC" && pwd -P)" ]; then
      echo "  skip  $name  (it is the harness source)"; continue
    fi
    found_any=1
    if ! printf '%s' "$name" | grep -Eq '^[a-z0-9-]+$'; then
      echo "  skip  $name  (name must match ^[a-z0-9-]+\$)"; continue
    fi
    echo "  would install + add manifest entry:  $name"
  done
  [ "$found_any" = 1 ] || echo "  (no git children found under $UMB at depth 1)"
  if [ "$SHARED_REPO" = 1 ]; then
    echo "── --shared-repo: version-control the umbrella root ──"
    if [ -e "$UMB/.git" ]; then
      echo "  would KEEP existing git repo at $UMB (never re-inits)"
    else
      echo "  would run: git init $UMB"
    fi
    echo "  would append-seed $UMB/.gitignore to ignore the discovered child repos above"
  fi
  echo "── end dry run — re-run without --dry-run/--list to apply ──"
  exit 0
fi

install_one "$UMB"

# Ensure the coordinator config carries an integration_command key (migration on a
# preserved config already handles this; on a fresh seed the shipped config has it).
# Then point umbrella.manifest at umbrella.manifest.yaml when it is unset/blank.
COORD_CFG="$UMB/.harness/harness.config.yaml"
migrate_config "$COORD_CFG"
# The manifest lives at the umbrella ROOT, but init.sh resolves umbrella.manifest
# relative to the harness dir (.harness/), so the default value is ../umbrella.manifest.yaml.
# When umbrella.manifest is blank (any form: ``, `""`, `''`, each with an optional
# trailing comment — migrate_config emits exactly that), point it at the root manifest.
# This operates ONLY inside the top-level `umbrella:` section, so a nested `manifest:`
# elsewhere is never matched or rewritten. A real value is preserved (skip activation).
if [ -z "$(_cfg_umbrella_manifest_value "$COORD_CFG")" ]; then
  awk '
    /^umbrella:[[:space:]]*(#.*)?$/ { u=1; print; next }
    u && /^[^[:space:]#]/ { u=0 }
    u && !done && $0 ~ /^[[:space:]]+manifest:[[:space:]]*("")?[[:space:]]*(#.*)?$/ {
      sub(/manifest:.*/, "manifest: \"../umbrella.manifest.yaml\""); done=1; print; next
    }
    u && !done && $0 ~ /^[[:space:]]+manifest:[[:space:]]*('"''"')[[:space:]]*(#.*)?$/ {
      sub(/manifest:.*/, "manifest: \"../umbrella.manifest.yaml\""); done=1; print; next
    }
    { print }
  ' "$COORD_CFG" > "$COORD_CFG.umtmp" && mv "$COORD_CFG.umtmp" "$COORD_CFG"
  info "coordinator umbrella.manifest -> ../umbrella.manifest.yaml — UMBRELLA MODE ENGAGED (init.sh now runs the coordinator loop; unset this value to revert to single-repo)"
fi

# Locked design: the auto-populated manifest ALWAYS lives at the umbrella root
# (`<umbrella>/umbrella.manifest.yaml`, read by init.sh as ../umbrella.manifest.yaml).
# If a coordinator has been pointed at a CUSTOM non-root path, the cascade does not
# try to write there — child `path:` entries are relative to the manifest's own dir,
# so a non-root manifest would mis-resolve every child. Warn and use the root file.
MANIFEST="$UMB/umbrella.manifest.yaml"
_cfg_manifest="$(_cfg_umbrella_manifest_value "$COORD_CFG")"
case "$_cfg_manifest" in
  ""|../umbrella.manifest.yaml|./umbrella.manifest.yaml|umbrella.manifest.yaml) : ;;  # the supported root location
  *)
    echo "⚠️  coordinator umbrella.manifest is a custom path ('$_cfg_manifest') — the cascade only auto-populates the root '$UMB/umbrella.manifest.yaml'. Point umbrella.manifest there, or maintain the custom manifest by hand." ;;
esac

# (b) discover immediate git children + (c) populate the manifest.
echo "── discovering git children (depth 1) ──"
if [ "$RECURSIVE" = 1 ]; then
  info "--recursive: deeper scan is accepted but deferred; scanning depth 1 only"
fi
[ -f "$MANIFEST" ] || printf 'repos:\n' > "$MANIFEST"   # R11

found_any=0
INSTALLED_CHILDREN=""   # newline-separated names of children actually installed (for --shared-repo)
for child in "$UMB"/*/; do
  # the literal glob (no matches) yields the pattern itself — guard it.
  [ -d "$child" ] || continue
  name="$(basename "$child")"
  # R9: skip dotfile dirs and the umbrella's own .harness.
  case "$name" in
    .*) continue ;;
    .harness) continue ;;
  esac
  [ "$name" = ".harness" ] && continue
  # R8: git child iff `.git` exists as a directory OR a file.
  [ -e "$child/.git" ] || continue
  # Never install into the harness source itself — when the installer checkout is an
  # immediate child of the umbrella (e.g. `harness-sdd/harness-install.sh --umbrella ..`)
  # it would otherwise get .harness/, pointer blocks, and .claude/ glue written into it.
  # Compare PHYSICAL paths (pwd -P) so a symlinked child that resolves to the source
  # is caught too, not just a same-named real directory.
  child_abs="$(CDPATH= cd -- "$child" && pwd -P)"
  src_phys="$(CDPATH= cd -- "$SRC" && pwd -P)"
  if [ "$child_abs" = "$src_phys" ]; then
    echo "⚠️  skipping child '$name': it is the harness source ($SRC) — not installing into the harness itself"
    continue
  fi
  found_any=1
  # R13: directory name must satisfy the slice-id repo-key grammar.
  if ! printf '%s' "$name" | grep -Eq '^[a-z0-9-]+$'; then
    echo "⚠️  skipping child '$name': name must match ^[a-z0-9-]+\$ (slice-id repo-key grammar) — no install, no manifest entry"
    continue
  fi
  echo "── child: $name ──"
  install_one "$UMB/$name"   # R10
  manifest_upsert "$MANIFEST" "$name"   # R12, R14
  INSTALLED_CHILDREN="$INSTALLED_CHILDREN$name
"
done

if [ "$found_any" = 0 ]; then
  info "no git children found under $UMB (depth 1)"
fi

# (d) --shared-repo: make the umbrella ROOT its own git repo (a shared "spec repository")
# that tracks .harness/ + umbrella docs and git-ignores the product child repos. OPT-IN —
# this whole block is skipped without the flag, so the default stays a non-git parent dir.
if [ "$SHARED_REPO" = 1 ]; then
  echo "── --shared-repo: version-control the umbrella root ──"
  if [ -e "$UMB/.git" ]; then
    info "umbrella root already a git repo — leaving it as-is (never re-inits)"
  elif command -v git >/dev/null 2>&1; then
    ( cd "$UMB" && git init -q ) && info "git init $UMB (shared spec repository)"
  else
    echo "⚠️  git not found — skipped 'git init'. Install git and run 'git init' in $UMB yourself; the .gitignore below is still seeded."
  fi

  # The umbrella-root .gitignore already carries personal/runtime ignores (seeded by the
  # coordinator's install_one above). APPEND the product child repos so they are tracked
  # as their OWN repos, never as gitlinks/nested content in this shared spec repo. We ignore
  # ONLY the children we actually installed into (discovered git repos) — never a blanket
  # rule that could swallow tracked harness/doc content. Append-only + idempotent.
  IGN="$UMB/.gitignore"
  if [ -n "$INSTALLED_CHILDREN" ]; then
    grep -qF '# Product repos (each its own git repo) — tracked separately' "$IGN" 2>/dev/null \
      || printf '\n# Product repos (each its own git repo) — tracked separately, NOT in this shared spec repo.\n' >> "$IGN"
    printf '%s' "$INSTALLED_CHILDREN" | while IFS= read -r _c; do
      [ -n "$_c" ] || continue
      _pat="/$_c/"
      grep -qxF "$_pat" "$IGN" 2>/dev/null || printf '%s\n' "$_pat" >> "$IGN"
    done
    info "umbrella-root .gitignore ignores product child repos (append-only)"
  fi
  echo "   shared spec repo: $UMB tracks .harness/ + umbrella docs; product repos git-ignored."
fi

echo "══════════════════════════════════════════════════"
ok "umbrella cascade complete (v$VERSION)"
echo "   coordinator: $UMB/.harness   manifest: $MANIFEST"
