#!/bin/sh
# harness-install.sh — install or upgrade the agent harness into a target repo.
#
#   ./harness-install.sh [--agents=<csv>] [--builder-backend=<value>] [--pr-loop=<true|false>] [--with-opencode-parallel=<true|false>] <target-repo-path>
#   ./harness-install.sh --umbrella <umbrella-dir> [--shared-repo] [--recursive] [--dry-run|--list]
#
# Idempotent: run once to install, re-run to upgrade.
#
# Agent selection (E08-F01): the installer stamps a SELECTABLE set of coding-agent
# front-ends — claude (CLAUDE.md + .claude/), gemini (GEMINI.md), opencode
# (opencode.json + .opencode/command/), antigravity (.agents/, E07-F01). Resolution:
#   - --agents=<csv> or HARNESS_AGENTS=<csv> (comma-separated keys) → that set, no
#     prompt (the override always wins). An unknown key aborts non-zero.
#   - --agents=host / HARNESS_AGENTS=host (E19-F01) → the ONE front-end this installer
#     session is running in, detected from that CLI's session env markers. `host` is a
#     RESOLUTION MODE, not an agent key: it is never a picker row and never written to
#     .harness/.agents, and it must be the whole value (`--agents=host,gemini` aborts).
#     Undetected is normal, never an error: it falls back to ALL on a target with no
#     existing install, and to that target's persisted selection on one that has an
#     install — so it never silently widens or narrows. HARNESS_HOST_AGENT=<key>
#     declares the host explicitly for a front-end with no verified marker, and
#     `--print-agents <target>` previews the verdict + baseline without writing anything.
#   - else an interactive TTY → a checkbox picker, pre-checked (E19-F02) from the saved
#     .harness/.agents set on an existing install (ALL for a pre-E08 one that saved none),
#     and on a target with NO existing install from the DETECTED HOST ALONE — ALL when the
#     host is undetected. That pre-check is a default, not a restriction: any other
#     front-end is one keystroke away before you confirm, which is why the guess is only
#     ever made here, where a human can correct it. See docs/INSTALL.md → "The
#     fresh-install default".
#   - else (no TTY, no override) → ALL agents (preserves the historical behavior).
# The resolved set is persisted to .harness/.agents (a dot-file beside .harness-version;
# dot-prefixed to avoid colliding with the .harness/agents/ role-bodies dir) and re-prompted
# on every re-run, decoupled from VERSION/upgrade detection. A re-run that DESELECTS
# an agent deletes that agent's harness-owned, regenerated glue and warns (it never
# touches the shared AGENTS.md entrypoint or the .harness/ body; a hand-edited
# opencode.json is left in place with a warning).
#
# Builder execution backend (E20-F01): the installer's SECOND question, asked as a plain
# line-oriented prompt right after the front-end picker confirms (never a row inside it).
# It sets execution.builder.backend in <target>/.harness/harness.config.yaml:
#   - in-session (DEFAULT) → the Builder writes the code in the CLI session it runs in.
#   - delegate             → the Builder shells out to execution.builder.delegate_cmd,
#                            which owns implementation.
# Resolution: --builder-backend=<value> wins over HARNESS_BUILDER_BACKEND, which wins over
# the prompt; an empty value means "no override" (like --agents=). An illegal value aborts
# non-zero BEFORE anything is written. With no TTY and no override nothing is asked and the
# target's current value is left byte-identical, so CI keeps today's behavior exactly.
# Pressing Enter keeps whatever the target already has, so a re-run cannot silently change
# it. Selecting `delegate` while delegate_cmd is still unset is allowed on purpose: the
# installer writes the choice and warns, rather than diverge from what the human asked for
# by silently downgrading — the Builder then stops and reports at run time.
# Change it later by RE-RUNNING the installer (or by hand-editing that key).
#
# PR review loop (E20-F02): the installer's THIRD question, asked as a plain line-oriented
# prompt right after the second one. It sets pr_loop.enabled in
# <target>/.harness/harness.config.yaml, whose two legal values are `true` and `false`:
#   - false (DEFAULT, opt-in) → no /sdd-pr-loop glue is stamped anywhere.
#   - true                    → /sdd-pr-loop + the pr-fixer sub-agent are stamped into
#                               every selected front-end, and flipping back to false
#                               reclaims all of it in that same run (E18-F01 §7b).
# THE DEFAULT DOES NOT CHANGE: pressing Enter keeps whatever the target already has, which
# on a fresh install is `false` — a fresh seed never inherits this repo's own `true`.
# Resolution: --pr-loop=<value> wins over the prompt; an empty value means "no override".
# An illegal value aborts non-zero BEFORE anything is written. With no TTY and no override
# nothing is asked and the config is left byte-identical, so CI keeps today's behavior.
# There is deliberately NO environment twin: HARNESS_PR_LOOP_ENABLED is E18-F01's PER-RUN
# gate override (like HARNESS_AUTO_MERGE / HARNESS_MAX_ROUNDS) and is NEVER persisted —
# when it disagrees with the resolved value the installer says so once, rather than letting
# the run's behavior quietly diverge from what the file records.
# NO INSTALL-TIME PREFLIGHT is run: the installer is POSIX sh with zero dependencies and
# never invokes `gh` or `jq`. /sdd-pr-loop needs the Codex GitHub App on the repo plus an
# authed `gh`; the prompt SAYS so, and /sdd-pr-loop's own fail-fast diagnoses it at the one
# moment it can be accurate (the App may legitimately be installed after the harness).
# Change it later by RE-RUNNING the installer (or by hand-editing that key).
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
  builder-heavy: inherit  # try: reasoning — the escalation tier (E17-F02); same body as
                          # `builder`, differs only by the model it resolves to (ADR-0002).
                          # Left `inherit` it is NOT heavier than `builder`.
  reviewer: inherit       # try: standard
  scout: inherit          # try: cheap
  doc-critic: inherit     # try: cheap
  # Exact-value escape hatch: `pin.<front-end>.<tier>`, written VERBATIM in that
  # front-end's own vocabulary. REQUIRED for codex and opencode, which have no
  # floating tier alias — an unpinned tier there stamps no MODEL. The role artifact
  # itself is still written (selecting Codex always registers all seven
  # .codex/agents/*.toml); only the `model` key is omitted, as for the `inherit` tier.
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
# The installer ASKS for `enabled` (E20-F02) — a follow-up prompt right after the
# builder-backend question, on a TTY — and takes --pr-loop=<true|false> for scripted
# runs. Enter keeps the current value, so the opt-in default never flips by itself. No
# preflight runs at install time; the prompt just states the precondition. RE-RUN the
# installer to change it later, or edit the value below: only that one scalar is ever
# rewritten, so every comment and hand-edit in this file survives. HARNESS_PR_LOOP_ENABLED
# below is a PER-RUN override — it gates ONE run and is NEVER persisted back here.
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

  # --- execution block (E20-F01 builder backend) ---
  # Top-level, append-only at EOF. Keyed off the TOP-LEVEL `execution:` header ONLY (the
  # same shape the mirror: / fix_lane: / models: / pr_loop: entries use): header absent ⇒
  # append the whole block, header present ⇒ do NOTHING. Deliberately NOT an
  # _mc_insert_after of a nested key: a present-but-partial `execution:` block would gain a
  # SECOND `builder:` mapping, which is invalid YAML and strictly worse than the status quo.
  # An absent block is behaviorally equivalent to the values below (agents/builder.md treats
  # a missing key as `in-session`), so a config that predates `execution:` keeps working —
  # the block is appended so the knob, and the installer's follow-up prompt, are
  # discoverable in the file the human actually edits.
  #
  # Keep this text BYTE-IDENTICAL to the `execution:` block of the source
  # harness.config.yaml — the same convergence rule the models: and pr_loop: entries above
  # state, for the same reason: a FRESH install copies the config verbatim and never
  # migrates, an UPGRADE only migrates, and the two must not end up documenting the same
  # values with different comments. Only the POSITION differs (the source block sits
  # mid-file; migration can only append at EOF), which is why the convergence check in
  # tests/test_installer_toggles.sh compares the extracted BLOCK, not the whole file.
  # If you edit one, edit the other.
  if ! grep -Eq '^execution:[[:space:]]*(#.*)?$' "$_cfg"; then
    cat >> "$_cfg" <<'EOF'

# Builder execution backend. The installer ASKS for this — a follow-up prompt right after
# the front-end picker, on a TTY — and takes --builder-backend=<in-session|delegate> or
# HARNESS_BUILDER_BACKEND=<value> for scripted runs (the flag wins). RE-RUN the installer
# to change it later, or edit the value below: only that one scalar is ever rewritten, so
# every comment and hand-edit in this file survives.
execution:
  # The harness's single extension point for plugging in an EXTERNAL executor
  # without forking any agent role file. Scope is structural: only roles listed
  # here can be delegated, and only the Builder is delegatable today.
  #
  # The Orchestrator is deliberately NOT a key and never will be — it is the loop
  # that reads this config and invokes delegate_cmd, so it always runs in the host
  # code-agent. Architect / Reviewer / Scout also always run in-session. To make a
  # new role delegatable later, add a sibling key here (e.g. `architect:`).
  builder:
    #   in-session -> the Builder agent implements the code itself, in this CLI
    #                 session (DEFAULT). Works with ANY single coding agent and
    #                 adds zero dependencies — this is what keeps the harness
    #                 universal for engineers who run only one CLI.
    #   delegate   -> the Builder does NOT write code; it shells out to
    #                 `delegate_cmd`, which owns implementation (and may own PR
    #                 creation/review too). Opt in only when an executor is wired.
    #                 Selecting it while delegate_cmd is still empty installs fine
    #                 and WARNS; the Builder stops and reports at run time.
    backend: in-session

    # Read ONLY when backend: delegate. The Builder invokes it as:
    #     <delegate_cmd> <feature-id> <abs-spec-path>
    # It must exit 0 on success, non-zero to signal failure back to the Builder.
    delegate_cmd: ""
EOF
  fi

  # --- change_size block (E21-F01 change-size discipline) ---
  # Top-level, append-only at EOF, ADVISORY: nothing here refuses work, so a migrated target
  # behaves identically until a human acts on what the Driller/Architect now report. Keep this
  # heredoc byte-identical to the tail of the source harness.config.yaml so a FRESH install
  # (which copies the config verbatim) and an UPGRADED install (which only migrates) converge
  # on the same text. The presence check tolerates a trailing comment on the `change_size:`
  # line so a target that annotated it never gets a duplicate block on the next upgrade.
  if ! grep -Eq '^change_size:[[:space:]]*(#.*)?$' "$_cfg"; then
    cat >> "$_cfg" <<'EOF'

# Change-size discipline (E21-F01) — ADVISORY in two tiers, never a hard block.
# Both tiers produce a RECORDED DECISION; neither refuses work. A single hard cap is the
# wrong instrument twice over: an agent-written change is legitimately denser than a
# hand-written one, and a rename sweep or a generated contract can be thousands of lines at
# near-zero review risk per line. An absent block behaves exactly as the values below.
# Budgets are PRODUCTION lines — tests are a deliberate quality choice already enforced by
# the Reviewer (a passing test per R-id) and must not be penalised by the instrument that
# governs review surface.
change_size:
  advise_lines: 1500       # production lines added ⇒ split, or record one line saying why not
  escalate_lines: 3000     # production lines added ⇒ recorded split plan, or an explicit override naming the reason
  advise_files: 25         # files touched, advise tier
  escalate_files: 50       # files touched, escalate tier
  # Drill-time proxy: R-ids in ONE feature spec. It is the only size signal that exists
  # before any code does, and each R-id obliges a test. Consumed by the Driller (split at
  # decomposition) and the Architect (stop and report rather than spec an over-budget feature).
  max_requirements: 12
  # Path classifiers for the pre-PR check (E21-F02), one EXTENDED REGEX per entry, MATCHED
  # AGAINST THE REPO-RELATIVE PATH and ADDED to the built-in multi-ecosystem defaults (they
  # never replace them). A wrong classifier does not make the number slightly off — it makes
  # it meaningless, so extend these rather than letting a repo's tests count as production.
  test_paths: []           # extra test-file patterns, e.g. - "(^|/)spec/"
  generated_paths: []      # extra generated/vendored patterns, excluded from the budget entirely
EOF
  fi

  # --- escalation block (E17-F03 deterministic Builder escalation) ---
  # Top-level, append-only at EOF. Keep this text BYTE-IDENTICAL to the tail of the source
  # harness.config.yaml: a FRESH install copies the config and never migrates, an UPGRADE
  # only migrates, and the two must converge on the same bytes. Seeding only one of the two
  # is precisely the defect E17-F02's mutation battery caught.
  #
  # Seeded at 2 (E17-F05). E17-F03 had to seed 0 because two review rounds killed two attempts
  # to INFER whether escalating would help — "heavy: inherit resolves like builder"
  # (#3716706727) and "arm on a non-inherit tier" (#3716777878, which misses that
  # codex/opencode stamp nothing for an unpinned tier). Both were this installer's
  # `resolve_model` being re-derived elsewhere. It is no longer re-derived anywhere: this
  # installer records the verdict in `.harness/.escalation-arming` (§6b) and the rule reads it,
  # so a positive default cannot downgrade a target the resolver says is unarmed.
  #
  # THIS ONLY SEEDS WHEN THE BLOCK IS ABSENT. A target already carrying `after_rejections: 0`
  # keeps it: the installer cannot distinguish a leftover E17-F03 default from a deliberate
  # veto, and rewriting an operator-owned value is worse than the gap. Such targets get
  # automatic escalation only after editing the key themselves — stated in the CHANGELOG.
  if ! grep -Eq '^escalation:[[:space:]]*(#.*)?$' "$_cfg"; then
    cat >> "$_cfg" <<'EOF'

# Deterministic Builder escalation (E17-F03), armed by the installer (E17-F05).
# After this many Reviewer rejections, subsequent builds spawn `builder-heavy` instead of
# `builder`. The counter is the EXISTING build<->review round (agents/orchestrator.md), so
# this adds no second source of truth. A spec may also start heavy from round 1 with
# `complexity: complex` in its frontmatter.
#
# `0` turns escalation OFF ENTIRELY — neither trigger fires. It is your hard veto, and
# nothing below overrides it. The shipped value is 2.
#
# ESCALATION NEEDS A SECOND YES, AND THE INSTALLER SUPPLIES IT. `harness-install.sh` asks its
# own model resolver what `builder` and `builder-heavy` resolve to on every front-end it
# stamps, and records the comparison in `.harness/.escalation-arming`. Escalation fires only
# while that verdict reads `armed` — i.e. `builder-heavy` resolves to a DIFFERENT model on
# every selected front-end. Otherwise the harness declines and names the front-end to fix,
# because escalating into a role that resolves to nothing is a DOWNGRADE: it abandons
# whatever `models.builder` was set to, exactly when the build was struggling.
#   claude / gemini / antigravity  a built-in tier alias is enough
#   codex / opencode               a tier alone stamps NOTHING — you must also set the
#                                  matching `pin.<front-end>.<tier>` in the models: block
# The verdict is computed at INSTALL time, so re-run the installer after changing any of it.
# WHAT THIS DOES NOT CHECK: that the model is STRONGER, or that it exists at all. The harness
# has no model list and invents none, so `pin.claude.reasoning: haiku` arms. Ranking is yours;
# what the check closes is the silent downgrade to no model at all.
#
# Under `execution.builder.backend: delegate` escalation is INAPPLICABLE — the external
# executor picks its own model — and the harness never escalates on that path.
escalation:
  after_rejections: 2
EOF
  fi

  # --- workers block (E17-F04 worker roster) ---
  # Top-level, append-only at EOF, OPT-IN and INERT: seeded `false`, so a migrated target
  # grows the discoverable knob and NO roster file. Keep this text BYTE-IDENTICAL to the
  # tail of the source harness.config.yaml — a FRESH install copies the config verbatim and
  # never migrates, an UPGRADE only migrates, and the two must converge on the same bytes
  # (tests/test_install.sh asserts it). Presence check tolerates a trailing comment on the
  # `workers:` line so a target that annotated it never gets a duplicate block.
  if ! grep -Eq '^workers:[[:space:]]*(#.*)?$' "$_cfg"; then
    cat >> "$_cfg" <<'EOF'

# Worker roster (E17-F04) — OPT-IN, local-only, and INERT by default.
# `true` ⇒ every install writes `.harness/workers.json`: which of the harness's front-end
# CLIs THIS MACHINE can invoke, recorded as versioned data (`schema: 1`) so an external
# router can read one file instead of re-probing the environment every time. Nothing in
# the harness itself consumes it.
#
# PRESENCE IS A `PATH` LOOKUP ONLY. The harness NEVER executes a rostered CLI, for any
# purpose — version detection included, which is why CLI version requirements are
# documented in comments here rather than checked. A data file cannot spawn a process.
#
# ONLY the literal `true` enables it: an absent block, an absent key, an empty value and
# any other value all mean OFF — and while it is off an existing roster is RECLAIMED
# (removed) on the next install, so flipping this back to false leaves nothing behind.
#
# The roster describes ONE MACHINE, is regenerated (overwritten) on every install, and is
# gitignored — the same local-only treatment telemetry.jsonl gets, for the same reason:
# committing it would put one developer's CLI set into a shared repo.
workers:
  roster: false
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
# The seeded config is a COPY of this repo's harness.config.yaml, so any pr_loop value the
# harness sets FOR ITSELF would otherwise become every target's default. Two keys are
# therefore forced back to the shipped defaults on seed:
#
#   enabled              -> false   the loop needs the Codex GitHub App; defaulting it on
#                                   would ship a command that can only fail its preflight.
#   blocking_severities  -> P0,P1   this repo raises it to P0,P1,P2 because it builds GATES,
#                                   where a "P2" is the gate vouching for something it never
#                                   checked or halting all agent work — consequences no
#                                   application-code severity scale is calibrated for. That
#                                   reasoning is a property of what THIS repo builds, not a
#                                   universal default: for an ordinary product repo, blocking
#                                   on P2 spends review rounds on findings that never blocked
#                                   anything, which is the exact cost E21 exists to control.
#
# Any comment lines the harness wrote to explain its own choice are dropped with the value,
# so a seeded target reads the shipped default and its rationale, not this repo's.
seed_pr_loop_optin() {
  awk '
    function flush(  i) { for (i = 1; i <= cn; i++) print cbuf[i]; cn = 0 }
    /^pr_loop:[[:space:]]*(#.*)?$/ { p = 1; print; next }
    p && /^[^[:space:]#]/ { flush(); p = 0 }
    # Buffer comment lines inside the block: a run of them immediately above a key may be
    # explaining a value this seed is about to overwrite, and prose left standing under a
    # replaced value is worse than no prose. Which it was is only known at the next line.
    p && /^[[:space:]]*#/ { cbuf[++cn] = $0; next }
    p && /^[[:space:]]+enabled:/ {
      cn = 0                                   # drop the harness'"'"'s own rationale with the value
      print "  enabled: false                 # opt-in master gate; ONLY `true` stamps /sdd-pr-loop glue"
      next
    }
    p && /^[[:space:]]+blocking_severities:/ {
      cn = 0
      print "  blocking_severities: \"P0,P1\"   # comma-separated severities that block a merge"
      next
    }
    p { flush(); print; next }                 # a kept key keeps its comments
    { print }
    END { flush() }
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

# set_umbrella_root <file> <value> — write `root:` inside the top-level `umbrella:`
# section, replacing an existing key or appending one at the end of the section.
# Section-scoped like every other config writer here, and idempotent (E24-F03 R1).
#
# The cascade calls this so a child's config RECORDS its umbrella: §1 needs the value on
# the very first install, before the config seed/preserve stage has run, and a later
# single-target re-run of the installer in that child must reach the same layout without
# the cascade's env var.
set_umbrella_root() {
  [ -f "$1" ] || return 0
  awk -v v="$2" '
    /^umbrella:[[:space:]]*(#.*)?$/ { u=1; print; next }
    # Leaving the section: emit the key here if it was never seen, so an older config
    # without `root:` gains one instead of silently ignoring the cascade.
    u && /^[^[:space:]#]/ { if (!seen) { print "  root: \"" v "\""; seen=1 } u=0 }
    u && /^[[:space:]]+root:/ { print "  root: \"" v "\""; seen=1; next }
    { print }
    END { if (u && !seen) print "  root: \"" v "\"" }
  ' "$1" > "$1.umbtmp" && mv "$1.umbtmp" "$1"
}

# _cfg_umbrella_root_value <file> — print the umbrella.root value (unquoted,
# comment-stripped) from inside the top-level `umbrella:` section; empty if unset.
# Same scoping as _cfg_umbrella_manifest_value above (E24-F03).
_cfg_umbrella_root_value() {
  [ -f "$1" ] || return 0
  awk '
    /^umbrella:[[:space:]]*(#.*)?$/ { u=1; next }
    u && /^[^[:space:]#]/ { u=0 }
    u && /^[[:space:]]+root:/ {
      sub(/^[[:space:]]+root:[[:space:]]*/, "")
      # ONE RULE, stated once, instead of a special case per metacharacter. Three review
      # rounds landed on this function because each fix answered a sample rather than the
      # requirement, and every patch traded one gap for the next:
      #   E99-F13    strip comments before quotes  -> `"/a#b"`      read as `/a`
      #   r1 #3712741520  stop at the FIRST quote  -> `"/a"b"`      read as `/a`
      #   r2 #3712898952  require a bare remainder -> `"/a#b" # c`  read as `/a`
      #
      # The requirement: `set_umbrella_root` writes `"<path>"` — outer quotes it adds
      # itself, the path verbatim between them, NO escaping of any kind — and an operator
      # may add a trailing comment. So the closing quote is THE LAST QUOTE ON THE LINE
      # FOLLOWED BY NOTHING BUT OPTIONAL WHITESPACE AND AN OPTIONAL `#` COMMENT. Everything
      # between it and the opening quote is the value, `#` and `"` alike. Scanning from the
      # right is what makes that true: the first candidate it accepts is the last one.
      # The format has NO escaping, so `"/a" # b"` is genuinely ambiguous — value `/a` with
      # comment `# b"`, or value `/a" # b`. Rank the two readings instead of hoping one
      # predicate covers both: the machine-written form is authoritative, a comment is a
      # courtesy for a hand-edited file.
      q = substr($0, 1, 1)
      if (q == "\"" || q == "'\''") {
        # PASS 1 — exactly what set_umbrella_root writes: `"<path>"`, nothing after it.
        # At most ONE quote can qualify (an earlier one would have a quote in its
        # remainder, which is not whitespace), so this pass cannot be ambiguous and its
        # direction cannot matter.
        for (i = length($0); i > 1; i--)
          if (substr($0, i, 1) == q && substr($0, i + 1) ~ /^[[:space:]]*$/) {
            print substr($0, 2, i - 2); exit
          }
        # PASS 2 — hand-edited: a trailing comment follows the closing quote. Several
        # quotes CAN qualify here (`"/a" # b" # c`), so direction is load-bearing: take the
        # FIRST, so the comment begins as early as the line allows and is never swallowed
        # into the value.
        for (i = 2; i <= length($0); i++)
          if (substr($0, i, 1) == q && substr($0, i + 1) ~ /^[[:space:]]*#/) {
            print substr($0, 2, i - 2); exit
          }
      }
      # Unquoted (or opened with a quote that never closes): a plain scalar, where a
      # comment starts at the first `#`. Unchanged from before E99-F13 — existing
      # hand-written configs depend on exactly this.
      sub(/[[:space:]]*#.*$/, ""); gsub(/^"|"$|^'\''|'\''$/, ""); print; exit
    }
  ' "$1"
}

# ── E24-F03 / ADR-0004: the umbrella-resolved body ───────────────────────────────────
# THE TIER LINE IS DRAWN BY WHAT READS THE FILE, not by what looks duplicated.
#
# The generated front-end glue resolves body paths inside the CHILD'S OWN `.harness/`
# (opencode.json interpolates `{file:./.harness/agents/<role>.md}`; the Codex role TOMLs
# say "Read .harness/agents/<role>.md"), so a body file can never be ABSENT from a child —
# only REDIRECTED. And a redirect only works where the consumer reads prose:
#
#   PROSE      an agent reads it and can follow a reference  ⇒ stub-able
#   PROGRAM    init.sh execs/parses it; CI runs it           ⇒ ALWAYS a local copy
#
# The example files are program-read in spirit: an operator COPIES FROM them to stand up
# an umbrella, so a stub in their place would be actively wrong.
#
# When a new body file's tier is unclear it belongs in the LOCAL list. The wrong answer
# there costs one copy; the wrong answer the other way breaks a standalone child at parse
# time, which is the failure this whole epic exists to prevent.
HARNESS_BODY_PROSE='AGENTS.md agents docs specs/_templates specs/glossary.md'
HARNESS_BODY_LOCAL='init.sh store tools umbrella.manifest.example.yaml umbrella.gitignore.example'

# The first line of every generated stub. It is the ONLY ownership signal used to tell a
# stub from a real body file — never file size, never a grep for prose.
HARNESS_STUB_SENTINEL='<!-- harness:umbrella-stub -->'

# umbrella_body_dir <harness-dir> — print the umbrella's `.harness` dir when this target
# is a child that can resolve one; print NOTHING otherwise (⇒ every caller falls back to
# the full local copy, which is the single-repo behaviour and is not a failure).
#
# "Resolves" is deliberately strict. A directory that merely exists is not an installed
# body, so `.harness-version` must be present — otherwise a child whose umbrella has been
# moved away would stub its whole prose tier against a path holding nothing. And the
# component is refused when it is a SYMLINK, matching the boundary every other ownership
# path in this installer already draws.
umbrella_body_dir() {
  _ubd_h="$1"
  # The cascade's value wins on a FRESH child, where §1 runs before any config exists.
  # It is exported only by the cascade child loop, and the same run persists it into the
  # child's config (set_umbrella_root), so a later standalone re-run reads it from there.
  _ubd_root="${HARNESS_UMBRELLA_ROOT:-}"
  [ -n "$_ubd_root" ] || _ubd_root="$(_cfg_umbrella_root_value "$_ubd_h/harness.config.yaml")"
  [ -n "$_ubd_root" ] || return 0
  case "$_ubd_root" in
    /*) _ubd_abs="$_ubd_root" ;;
    *)  _ubd_abs="$_ubd_h/$_ubd_root" ;;
  esac
  [ -L "$_ubd_abs" ] && return 0
  [ -d "$_ubd_abs" ] || return 0
  _ubd_body="$_ubd_abs/.harness"
  [ -L "$_ubd_body" ] && return 0
  [ -d "$_ubd_body" ] || return 0
  [ -f "$_ubd_body/.harness-version" ] || return 0
  ( CDPATH= cd -- "$_ubd_body" && pwd -P )
}

# gen_body_stub <body-relpath> <umbrella-root-as-written> <dest> — write the pointer stub.
#
# The text depends ONLY on the body-relative path and the configured umbrella root. It
# never interpolates VERSION and never reads the file it replaces, which is what makes
# "an umbrella upgrade leaves child stubs byte-identical" true by construction rather
# than by test (E24-F03 R7).
gen_body_stub() {
  _gbs_rel="$1"; _gbs_root="$2"; _gbs_dest="$3"
  _gbs_target="${_gbs_root%/}/.harness/$_gbs_rel"
  mkdir -p "$(dirname "$_gbs_dest")"
  {
    printf '%s\n' "$HARNESS_STUB_SENTINEL"
    printf '# Umbrella-resolved: `%s`\n\n' "$_gbs_rel"
    printf 'This repository resolves its harness body from its umbrella. The authoritative\n'
    printf 'copy of this file — not this stub — is:\n\n'
    printf '    %s\n\n' "$_gbs_target"
    printf 'Read that file and follow it exactly.\n\n'
    printf '**If that path does not exist**, you are in a checkout separated from its umbrella\n'
    printf '(a lone clone, a CI job, a PR reviewer'"'"'s tree). That is a supported state, not a\n'
    printf 'broken one: `.harness/init.sh`, this repository'"'"'s verification gate and its PR loop\n'
    printf 'all still work here — only the prose body is remote. To materialise a full local\n'
    printf 'copy, run the harness installer against this repository.\n'
  } > "$_gbs_dest"
}

# child_is_full_copy <harness-dir> — true when this target already holds REAL prose-tier
# files (not stubs). E24-F03 R9: a fresh cascade must never silently swap an existing
# child's 29 body files for stubs — that conversion is destructive, needs a pristine
# check, and is E24-F04's job. Detected by the sentinel alone.
child_is_full_copy() {
  _cfc_h="$1"
  for _cfc_rel in $HARNESS_BODY_PROSE; do
    _cfc_p="$_cfc_h/$_cfc_rel"
    if [ -f "$_cfc_p" ]; then
      head -n 1 "$_cfc_p" 2>/dev/null | grep -qxF "$HARNESS_STUB_SENTINEL" || return 0
    elif [ -d "$_cfc_p" ]; then
      for _cfc_f in "$_cfc_p"/*; do
        [ -f "$_cfc_f" ] || continue
        head -n 1 "$_cfc_f" 2>/dev/null | grep -qxF "$HARNESS_STUB_SENTINEL" || return 0
      done
    fi
  done
  return 1
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

# _cfg_execution_builder_value <file> <key> — print the `execution.builder.<key>` scalar
# (unquoted, comment-stripped) from inside the TOP-LEVEL `execution:` section's `builder:`
# mapping; empty if the file, the section, the mapping or the key is absent (E20-F01).
#
# Same section-scoped shape as _cfg_pr_loop_value, ONE NESTING LEVEL DEEPER: the `builder:`
# mapping is entered only inside `execution:`, and it is left again as soon as a line
# appears at or above `builder:`'s own indentation. So neither a `builder:` under another
# top-level section (e.g. `fix_lane:`) nor a SIBLING of `builder:` inside `execution:`
# (e.g. a future `architect:`) can ever be read as this key. Commented example lines never
# match — the `#` precedes the key.
#
# DO NOT "SIMPLIFY" THE SCOPE GUARDS HERE OR IN set_builder_backend. Today `builder:` is
# the only mapping under `execution:` and `backend:` occurs exactly once as a key in the
# whole config, so dropping the `e &&` / `b &&` guards is behaviorally invisible AND
# passes the suite (Reviewer mutations S1/S2 on E20-F01 confirmed this). They become
# load-bearing the moment a second mapping lands under `execution:` — which is precisely
# what E20-F02 does. Whoever adds it should also add a fixture with a decoy `backend:`
# under a sibling/other section, which is what makes these guards falsifiable.
_cfg_execution_builder_value() {
  [ -f "$1" ] || return 0
  awk -v k="$2" '
    BEGIN { gsub(/\./, "[.]", k); re = "^[[:space:]]+" k ":" }
    /^execution:[[:space:]]*(#.*)?$/ { e=1; b=0; next }
    e && /^[^[:space:]#]/ { e=0; b=0 }
    e && /^[[:space:]]+[^[:space:]#]/ {
      match($0, /^[[:space:]]*/); ind = RLENGTH
      if ($0 ~ /^[[:space:]]+builder:[[:space:]]*(#.*)?$/) { b=1; bind=ind; next }
      if (b && ind <= bind) { b=0 }
      if (b && $0 ~ re) {
        sub(/^[[:space:]]+[^:]*:[[:space:]]*/, ""); sub(/[[:space:]]*#.*$/, "")
        gsub(/^"|"$|^'\''|'\''$/, ""); print; exit
      }
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

# _cfg_workers_roster_is_true <file> — exit 0 ONLY when <file> has a top-level `workers:`
# section whose DIRECT child `roster:` key carries one of the three literal enabling forms
# `true`, `"true"` or `'true'` (each with an optional real trailing ` # comment`), and whose
# section is free of tab indentation. Any other line, any other value, a tab anywhere in the
# section's indentation, an absent key, an absent section, a missing file: exit 1.
#
# WHITELIST, NOT A DECODER. The previous shape of this helper decoded the scalar and
# compared the result to `true`, and lost that game once per review round — a `#` inside a
# quoted scalar, a `roster:` nested under `workers.options`, a doubled-quote escape
# (`roster: 'true''#disabled'` decodes to the string `true'#disabled`), and after those,
# block scalars (`roster: >`), tags (`roster: !!str true`), anchors, tabs… Each fix taught
# the decoder one more corner of YAML and left the next corner open, because a hand-rolled
# awk YAML decoder cannot be completed. The contract does not need one: R2 says ONLY the
# literal `true` enables the roster and EVERYTHING else — including anything malformed or
# unexpected — leaves it OFF. That is a positive match that FAILS CLOSED. A shape nobody
# anticipated is not decoded and compared; it simply does not match, so it is OFF.
#
# Two rules carry it, and both are load-bearing:
#   1. DIRECT CHILDREN ONLY. The indent of the section's first key line (blank and
#      comment-only lines skipped) is the direct-child indent; deeper lines belong to some
#      nested mapping and are ignored entirely, so `workers.options.roster: true` leaves
#      `workers.roster` absent — and absent is OFF.
#   2. The first direct `roster:` line decides, and it enables only on a FULL-LINE match of
#      the whitelist. `#` may only start a comment when a SPACE precedes it, so neither
#      `true#disabled` nor `"true"#x` can shed a suffix and pass as `true`.
#
# INDENTATION AND SEPARATION ARE SPACES, NEVER TABS — and that is a YAML rule, not a style
# preference: a tab may not indent a mapping, so `workers:\n\troster: true` is not a document
# with the key set, it is a MALFORMED document a real parser refuses outright. `[[:space:]]`
# spans the tab, which would have accepted exactly that and enabled the roster on a file
# nothing else can load. Matching literal spaces closes the axis in one move rather than one
# whitespace character at a time.
#
# THE TAB RULE COVERS THE WHOLE SECTION, NOT JUST THE PREFIX BEFORE THE KEY. A tab in the
# indentation of ANY line of the `workers:` section makes the document unparseable, so the
# section is malformed and the gate is OFF wherever that line sits relative to `roster:` —
# before it (`workers:\n\tjunk: 1\n  roster: true`) or after it
# (`workers:\n  roster: true\n\tjunk: 1`) alike. One malformed-document class must not have
# two answers depending on line order, which is what stopping at the first `roster:` line
# produced. So the scan CANNOT stop the moment it has a value: it records the FIRST direct
# `roster:` line's verdict, then keeps reading to the END of the section (a new top-level
# key, a dedent back out, or EOF) before answering. Nothing skips a tab-polluted line
# either: measuring its indent with spaces yields 0, so `workers:\n\tjunk: 1\n  roster: true`
# ALSO fixes the direct-child indent at 0 and makes the `roster:` line read as a descendant —
# two independent reasons for OFF on one unparseable file. Skipping such a line instead would
# let the next well-formed line set the indent, i.e. fail OPEN on exactly the input this rule
# exists to reject. A tab on a blank or comment-only line is not indentation of anything and
# is left alone, as those lines carry no indent signal to begin with.
#
# SCOPED TO THE SECTION, NOT TO THE FILE. This reads one key; it is not a document validator.
# A tab in some OTHER top-level section leaves `workers:` alone, because vetoing on any tab
# anywhere in the file would turn one stray tab in an unrelated block into a silent global
# opt-out — a denial of service on the gate that no message here could explain.
# Section-scoped like _cfg_pr_loop_value, so a same-named key under ANOTHER top-level
# section can never change roster behavior; commented example lines never match either.
#
# DO NOT REPLACE THIS WITH A DECODE-AND-COMPARE, and do not widen the three accepted forms.
# Every new YAML shape that "ought" to work belongs OFF unless the spec says otherwise.
_cfg_workers_roster_is_true() {
  [ -f "$1" ] || return 1
  awk -v q="'" '
    BEGIN {
      ok = "^ *roster: +(true|\"true\"|" q "true" q ")( *$| +#)"
      cind = -1
    }
    /^workers:[[:space:]]*(#.*)?$/ { w=1; cind=-1; next }
    w {
      if ($0 ~ /^[[:space:]]*(#.*)?$/) next          # blank or comment-only: no indent signal
      if ($0 ~ /^[^[:space:]]/) { w=0; next }        # a new top-level key ends the section
      match($0, /^ */); ind = RLENGTH                # indent is SPACES — a tab cannot indent YAML
      if (substr($0, ind + 1, 1) == "\t") tab = 1    # …and one tab voids the WHOLE section
      if (cind < 0) cind = ind                       # first key line fixes the child indent
      if (ind < cind) { w=0; next }                  # dedented back out of the section
      if (ind > cind) next                           # deeper: a descendant, not workers.roster
      if ($0 !~ /^ *roster:/) next                   # some other direct child
      if (seen) next                                 # the FIRST direct roster: already decided
      seen = 1
      if ($0 ~ ok) hit = 1                           # …and ONLY the whitelist enables
    }
    END { exit((hit && !tab) ? 0 : 1) }
  ' "$1"
}

# worker_roster_enabled — exit 0 ONLY when `workers.roster` resolves to the literal `true`
# (E17-F04 R1/R2). The gate is OPT-IN, modelled on pr_loop_enabled: an absent block, an
# absent key, an empty value and any other value alike mean OFF, and NO roster is written.
#
# DELIBERATELY CONFIG-ONLY — there is no env override twin of HARNESS_PR_LOOP_ENABLED here.
# The roster describes this machine and is regenerated on every run, so a per-run env
# override would let one scripted run leave behind a file the target's own config says
# should not exist. The spec names exactly one gate; this reads exactly that one.
# Reads the target config through $H, which is empty before install_one sets it
# (⇒ default: disabled).
worker_roster_enabled() {
  [ -n "${H:-}" ] || return 1
  _cfg_workers_roster_is_true "$H/harness.config.yaml"
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
# repository-local skills and roles are stamped by §5d/§5f.
#
# ── host front-end detection: the marker table (E19-F01) ──────────────────────
# Consumed ONLY by detect_host, i.e. only by the `--agents=host` resolution mode.
# One row per DETECTABLE agent key, whitespace-separated:
#
#     <agent-key> <MARKER_VAR> [<MARKER_VAR> …]
#
# A row MATCHES when ANY of its variables is set and non-empty (R2). Exactly one
# matching key ⇒ that key (R3); zero ⇒ undetected (R4); two or more ⇒ undetected
# plus one stderr diagnostic (R5) — nesting (one CLI shelling out to another)
# inherits the outer CLI's markers, so a tie CANNOT be broken from the environment.
#
# RULES — these are requirements, not style:
#   * SESSION MARKERS ONLY. A variable qualifies only when the front-end INJECTS it
#     into the environment of the processes it launches. A variable a human exports
#     in a shell profile proves they use that tool *somewhere*; it never proves THIS
#     installer run was launched from it.
#   * FORBIDDEN BY NAME (R6): CODEX_HOME, HOME, TERM_PROGRAM, and any variable whose
#     name ends in _API_KEY (GEMINI_API_KEY, OPENCODE_API_KEY, ANTHROPIC_API_KEY …).
#     CODEX_HOME especially — tests/test_install.sh exports it suite-wide, so a
#     CODEX_HOME row would look correct in CI and be wrong on every real machine.
#     (Observed inside a live Claude Code session: CODEX_HOME unset, while
#     CODEX_COMPANION_SESSION_ID held the *Claude Code* session id — a name prefix is
#     not evidence.)
#   * EVERY NON-`claude` ROW REQUIRES EMPIRICAL VERIFICATION (R8), recorded in an
#     adjacent comment naming the CLI + version it was observed on. The procedure:
#     `env | sort` in a plain terminal, `env | sort` from inside the CLI's own
#     shell tool, then `comm -13` the two; accept a variable only if it is in that
#     delta, names the CLI's SESSION rather than its config/credentials, and is
#     present in the CLI's DEFAULT mode. If nothing qualifies, ADD NO ROW: a
#     front-end with no verified marker is simply UNDETECTABLE, which degrades to
#     the fallback (today's behavior). That is an expected outcome, not a defect.
#   * `host` is NOT an agent key. It never joins AGENT_KEYS, never appears as a
#     picker row, and is never written to .harness/.agents (R17, R18).
#
# PROVENANCE — one entry per key, recording the CLI + VERSION each of that row's marker
# variables was observed on (R8). Every name below appeared in the `comm -13` delta
# between a plain login shell and a shell the CLI itself spawned, on 2026-07-28; none of
# them was present in the plain login shell (the only front-end name that WAS is
# OPENCODE_API_KEY — a credential, and forbidden by R6, which is the whole point).
#
# FORMAT IS LOAD-BEARING, do not reflow: an entry starts with the agent key at exactly
# three spaces of indent and continues on more deeply indented lines. Each entry names
# ONLY the variables that entry's row actually ships, and REJECTED candidates are listed
# in their own section below — so a negative mention can never be mistaken for evidence.
# tests/test_agents_host.sh parses this block and fails the build if a row carries a
# variable this block does not record under that key, or if the entry names no version.
#
#   claude      Claude Code 2.1.220 — CLAUDECODE=1 and CLAUDE_CODE_ENTRYPOINT=cli, in a
#               shell spawned by the session, in default mode.
#   codex       codex-cli 0.145.0 — CODEX_THREAD_ID=<session uuid>, matching the session
#               id the CLI printed. Observed via `codex exec`, BOTH under the seatbelt
#               sandbox and with the sandbox bypassed on a pty, so it is not a
#               sandbox-only artifact.
#   opencode    opencode 1.18.5 — OPENCODE=1 and OPENCODE_PID=<pid>, observed via
#               `opencode run`.
#   antigravity agy 1.1.8 — ANTIGRAVITY_AGENT=1 and ANTIGRAVITY_CONVERSATION_ID=<uuid>,
#               observed via `agy -p` (the same run also carried a CLI-versioned
#               ANTIGRAVITY_LS_VERSION, which is why the version claim is exact).
#
# NO ROW — undetectable, and that is an ACCEPTED outcome, not a defect: it degrades to
# the fallback, i.e. today's behavior (R8).
#   gemini      the gemini CLI is not installed on the verification machine, so nothing
#               could be observed for it. A gemini user declares the host explicitly
#               with HARNESS_HOST_AGENT=gemini (R9) instead of the harness guessing.
#
# REJECTED CANDIDATES — recorded so the next contributor does not re-litigate them. None
# of these may appear in a row: CODEX_SANDBOX and CODEX_SANDBOX_NETWORK_DISABLED (they
# vanish when codex runs with the sandbox off); CODEX_CI (a mode flag, not a session id);
# AGENT (opencode sets it, but the name belongs to no front-end in particular);
# GEMINI_CLI (it did NOT appear in the agy delta, and it could not discriminate gemini
# from antigravity anyway); every *_API_KEY and CODEX_HOME (ambient config/credentials,
# forbidden by R6).
#
# Caveat recorded honestly: codex/opencode/antigravity were exercised through each
# CLI's NON-INTERACTIVE entrypoint (`exec`/`run`/`-p`), which is the mode a scripted
# install runs under. If an interactive TUI session turns out not to export the same
# name, that front-end is merely undetected there — the fallback keeps the install
# byte-identical to today, so the failure mode is inert.
HOST_MARKERS="
claude CLAUDECODE CLAUDE_CODE_ENTRYPOINT
codex CODEX_THREAD_ID
opencode OPENCODE OPENCODE_PID
antigravity ANTIGRAVITY_AGENT ANTIGRAVITY_CONVERSATION_ID
"
#
# ── the worker roster: how each agent key is INVOKED (E17-F04) ────────────────
# Consumed ONLY by write_worker_roster, i.e. only by the `.harness/workers.json` roster.
# It answers a question no other table here asks — "what would you TYPE to run this CLI,
# and can it be driven headlessly" — which is why it exists at all rather than being
# folded into AGENT_KEYS or HOST_MARKERS.
#
# PLACEMENT IS LOAD-BEARING, and so is this header. It sits AFTER the closing quote of
# HOST_MARKERS, and its provenance header below reads `# WORKER_INVOKE PROVENANCE` rather
# than a bare `# PROVENANCE`. tests/test_agents_host.sh finds the host-evidence block by
# the POSITIONAL range `/^# PROVENANCE/,/^HOST_MARKERS="$/` and treats ANY `#   <agent-key>
# …` line inside it as host evidence for that key. The entries below are exactly that
# shape, so above the table — or under a bare `# PROVENANCE` header — they would be
# absorbed into the host-evidence range and R8's guard could be satisfied by text that is
# not host evidence at all. Do not move this block, and do not rename its header.
#
#     <agent-key> <command-name> [<capability> …]
#
# ONLY NON-DERIVABLE CAPABILITIES BELONG IN A ROW. `harness-selected` is derived from
# membership in $SELECTED and `host-detectable` from having a HOST_MARKERS row above, so
# restating either here would make this a THIRD table describing the same five front-ends
# — the body-and-its-copy divergence this repo has already paid for. `non-interactive` is
# the one genuinely new fact, and the command name the one genuinely new datum.
#
# PRESENCE IS NEVER EXECUTION (R8). The command name below is looked up with
# `command -v <name> >/dev/null 2>&1` and used as a BOOLEAN — its stdout is discarded and
# no rostered CLI is ever run, for version detection or anything else. A roster entry
# records no filesystem path either (spec E17-F04 → Recorded decision 4); adding one is a
# `schema` bump, not a tweak.
#
# WORKER_INVOKE PROVENANCE — one entry per key, recording the entrypoint each
# `non-interactive` claim was verified with. Same discipline the HOST_MARKERS block imposes
# above: an UNVERIFIED claim must never ship, so a key with nothing observed carries no tag.
#
#   claude      `claude -p <prompt>` — scriptable, prompt-in, prints and exits.
#   codex       `codex exec` — the same non-interactive entrypoint the HOST_MARKERS
#               provenance above already records for codex-cli 0.145.0.
#   opencode    `opencode run` — ditto, opencode 1.18.5.
#   antigravity `agy -p` — ditto, agy 1.1.8.
#
# NO `non-interactive` CLAIM — unverified, and that is an ACCEPTED outcome, not a defect:
# the entry still ships (this machine can invoke it), with the harness vouching for nothing
# further.
#   gemini      the gemini CLI is not installed on the verification machine, so no
#               entrypoint could be observed for it — the same reason it has no
#               HOST_MARKERS row. Claiming one anyway is exactly the defect the
#               HOST_MARKERS R8 rule exists to prevent.
WORKER_INVOKE="
claude claude non-interactive
gemini gemini
opencode opencode non-interactive
antigravity agy non-interactive
codex codex non-interactive
"
#
# Harness-OWNED generated basenames (stems; all files are <stem>.md). These are the
# ONLY files a deselection may delete, so a selective re-run never removes a user's
# own agents/commands sharing the same dir (Codex r2 P1). Keep in sync with the
# emit_agent calls and the command-copy loops in install_one().
HARNESS_CLAUDE_SHIMS="orchestrator architect builder builder-heavy reviewer scout doc-critic pr-fixer"
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
# The seven roles the installer emits an agent definition for. Adding a further role
# variant is ONE new name here + one `models:` line — no config migration, because the map
# is flat and keyed off role names and an unlisted role falls through to `models.default`.
# `builder-heavy` (E17-F02) is that shape in practice: same instruction body as `builder`,
# differing only by the tier resolve_model returns for it (ADR-0002).
MODEL_ROLES="orchestrator architect builder builder-heavy reviewer scout doc-critic"

# Set to 1 to force every resolution to EMPTY (used to regenerate the "model-free" body
# an older opencode.json is compared against). Never set outside that narrow window.
MODELS_OFF=0
# Run-scoped stderr de-duplication ledger (set in install_one). resolve_model runs inside
# `$(...)` subshells, so an in-memory flag would not survive; the marker file does. Seven
# roles × five front-ends is 35 resolutions per run — without this the output degenerates
# into thirty-five identical advisory lines.
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
# no model value rather than having the harness invent a model id. That omits the `model`
# key; it never suppresses the role artifact itself.
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

# escalation_verdict <front-end> — would escalating from `builder` to `builder-heavy`
# actually change the model on this front-end? Prints exactly one of:
#
#   raise    heavy resolves to a non-empty value that DIFFERS from builder's
#   none     heavy resolves to NOTHING while builder resolves to something  ← the downgrade
#   same     both resolve to the identical non-empty value
#   neither  neither resolves — both inherit the session model
#
# WHY THIS LIVES HERE AND NOT IN tools/builder-role.sh (E17-F05). Two E17-F03 review rounds
# killed two attempts to answer this question from the CONFIG: "heavy: inherit resolves like
# builder" (#3716706727) and "arm on a non-inherit tier" (#3716777878, which misses that
# codex/opencode stamp nothing for an unpinned tier). Both were re-derivations of a subset of
# `resolve_model`, which owns the per-front-end alias tables and the pin rules — so each
# approximation was wrong on a different front-end. This function re-derives NOTHING: it calls
# `resolve_model` and compares the two strings it gets back. That is the entire feature.
#
# WHAT IT DOES NOT PROVE. `resolve_model` returns opaque vendor strings, and the harness has
# no model list and deliberately invents none (E17-F01). So `raise` means the model CHANGES,
# not that it is STRONGER — `pin.claude.reasoning: haiku` reads as `raise`. Ranking lives in
# the tier vocabulary the operator chose. What this closes is the downgrade-to-nothing case,
# which is the one an operator cannot see coming; it is not a model-strength check and no
# doc may say it is.
#
# The four arms are total over (empty × empty), so no default arm silently absorbs a
# combination. Locals are prefixed because POSIX sh has none.
escalation_verdict() {
  _ev_b="$(resolve_model "$1" builder)"
  _ev_h="$(resolve_model "$1" builder-heavy)"
  if   [ -n "$_ev_h" ] && [ "$_ev_h" != "$_ev_b" ]; then printf 'raise\n'
  elif [ -z "$_ev_h" ] && [ -n "$_ev_b" ];          then printf 'none\n'
  elif [ -z "$_ev_h" ] && [ -z "$_ev_b" ];          then printf 'neither\n'
  else                                                   printf 'same\n'
  fi
}

# agent_known <key> — true (exit 0) iff <key> is a registered agent key (R7, R10).
agent_known() {
  for _k in $AGENT_KEYS; do [ "$_k" = "$1" ] && return 0; done
  return 1
}

# marker_present <var-name> — true (exit 0) iff the NAMED environment variable is set
# and NON-EMPTY (R2). The `${…:-}` guard is load-bearing: detect_host runs under
# `set -eu`, where a bare expansion of an unset marker would abort the whole install.
# A variable set to the empty string is deliberately NOT present.
marker_present() {
  eval "_mp_val=\${$1:-}"
  [ -n "$_mp_val" ]
}

# detect_host — print the ONE agent key this installer session appears to be running
# INSIDE, or print nothing when it cannot tell (R1, R3-R5, R9-R11).
#
# Contract: the verdict goes to STDOUT (it is consumed via `$(…)`, the same contract
# tui_select/toggle_select already use); every diagnostic goes to STDERR. It reads,
# writes and creates NO file, makes no network call, and NEVER exits non-zero — a miss
# is normal operation, not an error (R11). Detection is a best-effort NARROWING; the
# caller decides what an empty verdict falls back to.
detect_host() {
  # 1. Explicit declaration wins outright (R9) — the escape hatch for a front-end whose
  #    session marker cannot be honestly verified, set once in a shell profile.
  _dh_decl="${HARNESS_HOST_AGENT:-}"
  if [ -n "$_dh_decl" ]; then
    _dh_n=0; _dh_one=""
    for _dh_t in $_dh_decl; do _dh_n=$((_dh_n + 1)); _dh_one="$_dh_t"; done
    if [ "$_dh_n" -eq 1 ] && agent_known "$_dh_one"; then
      printf '%s\n' "$_dh_one"
      return 0
    fi
    # Any other value — an unknown token, several tokens, or the literal `host` —
    # warns ONCE naming the value and continues as if the variable were unset (R10).
    # Never `die`: a mistyped declaration must not block an install.
    echo "⚠️  ignoring HARNESS_HOST_AGENT='$_dh_decl' — expected exactly one of: $AGENT_KEYS" >&2
  fi

  # 2. Walk the marker table and collect every key with at least one present marker.
  #    The walk runs in a subshell (it inherits the environment, which is all it reads),
  #    so nothing here can leak state into the caller.
  _dh_hits="$(
    printf '%s\n' "$HOST_MARKERS" | while IFS= read -r _dh_row; do
      [ -n "$_dh_row" ] || continue
      _dh_key=""
      for _dh_var in $_dh_row; do
        if [ -z "$_dh_key" ]; then _dh_key="$_dh_var"; continue; fi
        if marker_present "$_dh_var"; then printf '%s\n' "$_dh_key"; break; fi
      done
    done
  )"
  [ -z "$_dh_hits" ] || _dh_hits="$(normalize_keys "$_dh_hits")"

  # 3. Exactly one hit wins; anything else is UNDETECTED. Ambiguity is deliberately not
  #    a tie-break — the table is not ordered by confidence and the first hit never wins.
  _dh_n=0
  for _dh_k in $_dh_hits; do _dh_n=$((_dh_n + 1)); done
  if [ "$_dh_n" -eq 1 ]; then
    printf '%s\n' "$_dh_hits"
  elif [ "$_dh_n" -gt 1 ]; then
    echo "⚠️  host detection ambiguous — session markers present for: $(printf '%s' "$_dh_hits" | tr '\n' ' ') — treating the host as undetected" >&2
  fi
  return 0
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

# codex_prompts_dir — resolve the retired GLOBAL Codex prompts dir for migration only.
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

# precheck_baseline <target> [<host-verdict>] — print, one per line and sorted, the agent keys the
# interactive picker PRE-CHECKS for <target>. It is the SINGLE source of that answer
# (E19-F01 R26): the picker seeds from it, `--print-agents` reports it as `baseline=`, and
# host_fallback_set asks it for an existing install's shape — so no second copy of "what
# should be checked here?" can diverge from it.
#
# Three cases, first match wins (E19-F02 R1-R4):
#
#   EXISTING INSTALL, with a persisted selection  → that selection            (R3)
#   EXISTING INSTALL, no persisted selection      → ALL keys                  (R4)
#   NO existing install                           → the detected host alone,  (R1)
#                                                   or ALL when undetected    (R2)
#
# "Existing install" is the VERSION STAMP (`.harness/.harness-version`), never the mere
# presence of `.harness/.agents`, and THAT TEST IS THE WHOLE "an upgrade must not silently
# narrow" GUARANTEE (E19-F02 R4/R9): a pre-E08 install carries every front-end's glue and
# no persisted selection, so if it fell through to the detection branch a human pressing
# Enter on the pre-checked picker would DELETE four working front-ends. The stamp is also
# what keeps orphan metadata — a copied or half-restored `.agents` with no stamp — from
# being read as an install (E19-F01 R13).
#
# That definition is SHARED, not local to this helper: install_one's PRIOR_AGENTS gates on
# the same stamp (E19-F02 R14), so a target this helper calls "no install" also grants no
# removal authority. Were the two to disagree, confirming the host-narrowed picker on an
# orphan target would delete the other recorded front-ends' pristine glue.
#
# The detection branch is a PRE-CHECK, not a decision: it only seeds a picker that is
# already on screen, where one keystroke adds any other front-end before confirming. It
# is therefore reached only where a human can correct it — a no-TTY run with no override
# never consults this helper and still resolves to ALL (R5), and detection can never
# narrow anything a run did not choose. The key is emitted ALONE: never unioned with
# `claude` or any other key, or every non-Claude user would keep getting glue they never
# asked for (R1).
#
# OPTIONAL SECOND ARGUMENT — an ALREADY-COMPUTED detect_host verdict to REUSE instead of
# calling detect_host a second time. detect_host's diagnostics are contract-bound to fire
# ONCE per run (E19-F01 R5's ambiguity line, R10's invalid-declaration warning), so a
# caller that has already asked the question and now needs this helper's answer on the same
# code path must hand the verdict down rather than ask again — `--print-agents` prints
# `host=` and then `baseline=`, and asking twice printed every diagnostic twice.
#
# Supplied-ness is tested with `$#`, never with emptiness: EMPTY is a meaningful verdict
# (undetected), so `precheck_baseline "$t" ""` means "reuse this undetected verdict" while
# `precheck_baseline "$t"` still means "go detect". That keeps the parameter purely
# ADDITIVE — every existing one-argument call site is byte-unchanged (R22).
#
# The verdict travels as a PARAMETER, not a cache: this helper stores nothing, so there is
# no per-run state that could leak from one target to the next when the installer processes
# several (`--umbrella`). Each target's call carries its own verdict or computes one.
precheck_baseline() {
  if [ -f "$1/.harness/.harness-version" ]; then
    if [ -f "$1/.harness/.agents" ]; then
      normalize_keys "$(cat "$1/.harness/.agents")"
    else
      normalize_keys "$AGENT_KEYS"
    fi
  else
    if [ "$#" -ge 2 ]; then _pb_host="$2"; else _pb_host="$(detect_host)"; fi
    if [ -n "$_pb_host" ]; then
      printf '%s\n' "$_pb_host"
    else
      normalize_keys "$AGENT_KEYS"
    fi
  fi
}

# host_fallback_keeps_selection <target> — true when an UNDETECTED `host` run would preserve
# <target>'s persisted selection (R14) rather than falling back to ALL (R13).
#
# That is the case only when the target is an EXISTING INSTALL *and* carries a selection:
# the version stamp is the spec's definition of "existing install", and a stamped install
# with no `.harness/.agents` is a legacy pre-E08 one, whose R14 answer is ALL anyway. So
# this single predicate is exactly the R13/R14 branch, and it also decides which of the two
# undetected report lines R25 requires.
host_fallback_keeps_selection() {
  [ -f "$1/.harness/.harness-version" ] && [ -f "$1/.harness/.agents" ]
}

# host_fallback_set <target> — the set an UNDETECTED `host` run resolves to for <target>:
# its persisted selection on an existing install (R14), ALL otherwise (R13).
#
# This is the SINGLE source of the undetected-fallback answer, and since E19-F02 it has
# exactly ONE caller: the undetected arm of resolve_agents's `host` branch.
#
# `--print-agents`'s `baseline=` line does NOT come from here any more — it reports
# precheck_baseline, i.e. the set the interactive picker would pre-check (E19-F02 R6),
# which is the question that diagnostic exists to answer. DO NOT POINT IT BACK HERE: on a
# fresh DETECTED target this helper answers ALL while the run would install the one
# detected key, so the preview would advertise the pre-F02 default the feature replaced.
# Nothing is lost by the repoint — for an UNDETECTED target the two helpers agree in every
# shape (persisted selection on a stamped install that has one, ALL otherwise, including
# the orphan-metadata corner where a `.harness/.agents` carries no version stamp).
#
# It cannot affect a run that never names `host`: its one call site is gated on `host` —
# resolve_agents reaches that arm only when the override value is exactly `host`. The
# interactive picker and the no-override defaults still go through precheck_baseline /
# AGENT_KEYS untouched (R22).
host_fallback_set() {
  if host_fallback_keeps_selection "$1"; then
    precheck_baseline "$1"
  else
    normalize_keys "$AGENT_KEYS"
  fi
}

# override_host_kind <csv> — classify an --agents/HARNESS_AGENTS override with respect to
# the `host` RESOLUTION MODE (E19-F01). Exit status:
#   0 → every token is `host`      ⇒ resolve via detect_host          (R12-R15)
#   1 → no `host` token at all     ⇒ validate_csv, exactly as before  (R22)
#   2 → `host` mixed with another  ⇒ reject                           (R16)
# Classifying `host` HERE, *before* validate_csv, is what keeps it out of validate_csv's
# token grammar — the structural guarantee that `host` can never be validated as a key,
# offered as a picker row, or persisted to .harness/.agents (R17, R18). It also makes the
# mixed-token error specific instead of the generic "unknown agent key 'host'".
override_host_kind() {
  _ohk_host=0; _ohk_other=0
  _ohk_ifs="$IFS"; IFS=','
  for _ohk_tok in $1; do
    IFS="$_ohk_ifs"
    _ohk_tok="$(printf '%s' "$_ohk_tok" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    if [ -n "$_ohk_tok" ]; then
      if [ "$_ohk_tok" = "host" ]; then _ohk_host=1; else _ohk_other=1; fi
    fi
    IFS=','
  done
  IFS="$_ohk_ifs"
  [ "$_ohk_host" = 1 ] || return 1
  [ "$_ohk_other" = 0 ] || return 2
  return 0
}

# resolve_agents <target> — resolve the SELECTED agent set for this run (R1, R5,
# R6, R9, R11). Resolution order, first match wins, decoupled from VERSION/UPGRADE:
#   1. Override (R5/R7): a non-empty $AGENTS_OVERRIDE (from --agents/HARNESS_AGENTS)
#      → validate_csv, no prompt — wins over persisted + TTY.
#      1a. E19-F01: the whole-value token `host` is a RESOLUTION MODE handled inside this
#          arm — SELECTED becomes detect_host's single key, or host_fallback_set when the
#          host is undetected. It is honored uniformly, interactive or not (R15), because
#          it is an explicit instruction exactly like `--agents=claude`. Mixed with any
#          other token it is rejected (R16). Nothing outside this arm changes: a run that
#          does not NAME `host` cannot reach any of it (R22).
#   2. Interactive (R1/R9): else if stdin is a TTY → the pre-check baseline comes from
#      precheck_baseline (R26) and, since E19-F02, has three cases: an EXISTING install's
#      persisted .harness/.agents (ALL for a pre-E08 one that saved none), and on a target
#      with NO existing install the DETECTED HOST ALONE — ALL when the host is undetected.
#      The narrowing happens only here, where the picker is already on screen and one
#      keystroke adds any other front-end back before confirming. On a raw-capable
#      TTY this runs the arrow-key + spacebar checkbox picker (tui_select); when
#      raw mode is unavailable it gracefully falls back to the numbered
#      toggle_select. Both resolve the identical SELECTED set from the same baseline.
#   3. No-TTY default (R6): else → ALL keys (back-compat: stamp everything).
# Sets the global SELECTED to a sorted, newline-separated key list.
resolve_agents() {
  _t="$1"
  if [ -n "${AGENTS_OVERRIDE:-}" ]; then
    if override_host_kind "$AGENTS_OVERRIDE"; then _kind=0; else _kind=$?; fi
    if [ "$_kind" = 2 ]; then
      die "'host' is a resolution mode, not an agent key — pass it as the ENTIRE value (--agents=host), never mixed with other keys (got '$AGENTS_OVERRIDE')"
    fi
    if [ "$_kind" = 0 ]; then
      _host="$(detect_host)"
      if [ -n "$_host" ]; then
        SELECTED="$_host"
        info "agents: host detected — selecting '$_host' only"
      else
        # Undetected is NORMAL operation, never an error. Fall back to this target's
        # current shape so the run can only ever preserve it (R13/R14), and say WHICH
        # fallback applied (R25) — the two cases must be distinguishable in the text.
        #
        # Both the set and the branch come from the shared host_fallback_* helpers, so the
        # fallback has one definition (R26). "Existing install" is the VERSION STAMP there,
        # per the spec's own definition — NOT the presence of .harness/.agents.
        #
        # `--print-agents`'s `baseline=` reports precheck_baseline (E19-F02 R6); for every
        # UNDETECTED target — the only kind that reaches this line — the two agree, so the
        # preview still cannot disagree with what this arm resolves.
        SELECTED="$(host_fallback_set "$_t")"
        if host_fallback_keeps_selection "$_t"; then
          info "agents: host undetected — keeping this install's selection ($(printf '%s' "$SELECTED" | tr '\n' ' '))"
        else
          info "agents: host undetected — selecting all front-ends ($(printf '%s' "$SELECTED" | tr '\n' ' '))"
        fi
      fi
    else
      SELECTED="$(validate_csv "$AGENTS_OVERRIDE")"
      info "agents: explicit selection ($(printf '%s' "$SELECTED" | tr '\n' ' '))"
    fi
  elif [ -t 0 ]; then
    _base="$(precheck_baseline "$_t")"
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

# ── the second question: execution.builder.backend (E20-F01) ──────────────────
# The installer's only OTHER question. Deliberately a plain line-oriented `read`
# follow-up asked AFTER the front-end picker has resolved — not a row in tui_select /
# toggle_select. Those are keyed on AGENT_KEYS and emit a sorted key list through
# normalize_keys; an enum has no [x]/[ ] meaning there, and the raw-mode picker (stty
# state, EXIT/INT traps, raw byte-3 Ctrl-C) is the highest-risk code in this file. A
# `read` prompt also works identically on BOTH interactive rungs, so this toggle needs
# no fallback ladder of its own (E20-F01 R1/R3).
#
# E20-F02 adds `pr_loop.enabled` by appending ONE more prompt behind this same
# resolver/writer pair — a linear seam, not a framework for N toggles.

# builder_backend_answer <answer> <current> — the answer→value mapping, and the ONLY
# place the prompt's semantics live (R2). PURE: no `read`, no config access, no file
# write, no global. Prints the resolved value and nothing else.
#
#   ""  (Enter)          → <current>   … the CURRENT value, never a hard-coded default
#   1 | in-session       → in-session
#   2 | delegate         → delegate
#   anything else        → <current>   … forgiving on purpose (see below)
#
# A typo is forgiving HERE and fatal in the flag (R5): a human at a prompt sees the
# outcome reported on the very next line and re-runs, while a typo'd flag in a script is
# silent. Same asymmetry the harness already applies to `--agents` (unknown key aborts)
# versus the picker (an out-of-range number is ignored with a note).
#
# SHAPE CONTRACT (R2): `sed -n '/^builder_backend_answer() {$/,/^}$/p'` must yield a
# complete, sourceable definition, so the test suite can exercise this truth table
# without a pty. The opening line is exactly `builder_backend_answer() {` and NO line
# inside the body may be exactly `}`. Do not reformat.
builder_backend_answer() {
  case "$1" in
    1|in-session) printf '%s\n' "in-session" ;;
    2|delegate)   printf '%s\n' "delegate" ;;
    *)            printf '%s\n' "$2" ;;
  esac
}

# builder_backend_prompt <current> — ask the follow-up question. The menu goes to
# STDERR (the resolved value is this function's stdout, read via command substitution).
#
# KEEP THIS FUNCTION THIS THIN. It is the only part of the feature a POSIX suite cannot
# drive — there is no pty — so every decision it feeds lives in builder_backend_answer
# above, which the suite extracts and unit-tests. Logic that migrates in here becomes
# untestable, and a structural check in tests/test_installer_toggles.sh fails if any
# appears. No loop, no re-ask, no config read, no write.
builder_backend_prompt() {
  _bbp_cur="$1"
  printf '\n' >&2
  printf '%s\n' "Which builder backend should this install use? (E20-F01)" >&2
  printf '%s\n' "  1) in-session   the Builder writes the code itself, in this CLI session" >&2
  printf '%s\n' "  2) delegate     the Builder shells out to execution.builder.delegate_cmd" >&2
  printf '%s\n' "                  (set that command too — delegate does nothing without it)" >&2
  printf '%s' "  choose 1/2 [Enter keeps $_bbp_cur]: " >&2
  _bbp_ans=""
  read -r _bbp_ans || :
  printf '\n' >&2
  builder_backend_answer "$_bbp_ans" "$_bbp_cur"
}

# resolve_builder_backend <target> — set the globals BUILDER_BACKEND (the resolved
# value) and BUILDER_BACKEND_SOURCE (how it resolved, for the one report line).
# Precedence, first match wins — the same ladder --agents uses:
#   1. a non-empty $BUILDER_BACKEND_OVERRIDE (--builder-backend / HARNESS_BUILDER_BACKEND),
#      already validated against the legal values at parse time (R4/R5);
#   2. else an interactive TTY → the follow-up prompt, pre-selected from the current
#      effective value (R1);
#   3. else the current effective value — a no-op, so a non-interactive run with no
#      override asks nothing and changes nothing (R6).
# CURRENT EFFECTIVE VALUE = the target config's backend key when that file exists, else
# the built-in `in-session`. On a FRESH install the config does not exist yet at this
# point, so the default is `in-session` — exactly what the seeded file will contain (R10).
BUILDER_BACKEND="in-session"
BUILDER_BACKEND_SOURCE="unchanged"
resolve_builder_backend() {
  _rbb_cfg="$1/.harness/harness.config.yaml"
  _rbb_cur="in-session"
  if [ -f "$_rbb_cfg" ]; then
    _rbb_v="$(_cfg_execution_builder_value "$_rbb_cfg" backend)"
    if [ -n "$_rbb_v" ]; then _rbb_cur="$_rbb_v"; fi
  fi
  if [ -n "${BUILDER_BACKEND_OVERRIDE:-}" ]; then
    BUILDER_BACKEND="$BUILDER_BACKEND_OVERRIDE"
    BUILDER_BACKEND_SOURCE="explicit --builder-backend/HARNESS_BUILDER_BACKEND"
  elif [ -t 0 ]; then
    BUILDER_BACKEND="$(builder_backend_prompt "$_rbb_cur")"
    BUILDER_BACKEND_SOURCE="interactive prompt"
  else
    BUILDER_BACKEND="$_rbb_cur"
    BUILDER_BACKEND_SOURCE="unchanged"
  fi
}

# set_builder_backend <config-file> <value> — replace ONLY the value token on the
# `backend:` line inside the top-level `execution:` section's `builder:` mapping.
#
# The config is NEVER rewritten wholesale: this file is heavily commented BY DESIGN and
# those comments are the harness's load-bearing documentation of its own knobs. The
# line's indentation and everything after the value (spacing + any trailing comment)
# survive verbatim, and every other byte of the file is untouched (R7). Callers skip this
# entirely when the value already matches, so an unchanged run is trivially byte-identical
# (R8). Same `$f.tmp` + `mv` shape as seed_pr_loop_optin / _mc_insert_after.
set_builder_backend() {
  awk -v val="$2" '
    /^execution:[[:space:]]*(#.*)?$/ { e=1; b=0; print; next }
    e && /^[^[:space:]#]/ { e=0; b=0 }
    e && !done && /^[[:space:]]+[^[:space:]#]/ {
      match($0, /^[[:space:]]*/); ind = RLENGTH
      if ($0 ~ /^[[:space:]]+builder:[[:space:]]*(#.*)?$/) { b=1; bind=ind; print; next }
      if (b && ind <= bind) { b=0 }
      if (b && match($0, /^[[:space:]]*backend:[[:space:]]*/)) {
        pre = substr($0, 1, RLENGTH)
        tail = substr($0, RLENGTH + 1)
        if (tail !~ /^#/) { sub(/^[^[:space:]]+/, "", tail) }
        if (pre !~ /[[:space:]]$/) { pre = pre " " }
        if (tail ~ /^#/) { tail = " " tail }
        print pre val tail
        done = 1
        next
      }
    }
    { print }
  ' "$1" > "$1.bbtmp" && mv "$1.bbtmp" "$1"
}

# ── the THIRD question: pr_loop.enabled (E20-F02) ─────────────────────────────
# One more prompt behind the SAME resolver/writer pair the second question uses — a
# linear seam, deliberately NOT a framework for N toggles. Everything E20-F01 said about
# why this is a plain `read` prompt rather than a picker row applies here unchanged, and
# more strongly: this is an ENUM of two booleans, not a multi-select.
#
# WHY ASK AT ALL. `/sdd-pr-loop` only functions on a repo that has the Codex GitHub App
# installed plus an authed `gh` (and `jq`). On any other repo the correct value is `false`,
# and the human running the installer is the only one who knows which repo is which. The
# key has been settable since E18-F01 — by hand-editing YAML, discoverable only by reading
# source comments. This makes it audible.
#
# WHAT THIS DOES NOT DO. It does not change the opt-in default (still `false`, on a fresh
# install and on an upgrade — pressing Enter never turns the loop on), it does not touch
# seed_pr_loop_optin, pr_loop_enabled, _cfg_pr_loop_value, the §5 unconditional CMDDIR
# generation or the §7b reclamation pass, and it runs NO install-time preflight: the
# installer is POSIX sh with zero dependencies and never invokes `gh` or `jq`. The
# precondition is stated in the prompt text instead, and /sdd-pr-loop's own fail-fast
# reports it at the one moment it can be accurate.

# pr_loop_answer <answer> <current> — the answer→value mapping, and the ONLY place the
# prompt's semantics live (R2). PURE: no `read`, no config access, no file write, no
# global. Prints one of the two literals `true` / `false` and nothing else.
#
#   ""  (Enter)              → <current>   … the CURRENT value, never a hard-coded default
#   1 | n | no | false       → false
#   2 | y | yes | true       → true
#   anything else            → <current>   … forgiving on purpose (see below)
#
# The word forms are case-insensitive (bracket patterns — POSIX sh `case` has no
# case-folding operator and this file adds no dependencies).
#
# THE RAW ANSWER IS NEVER WRITTEN TO THE CONFIG. E18-F01 R18b makes `Yes`, `1` and `True`
# all resolve the gate OFF (only the literal `true` is true), so an implementation that
# passed the answer through would write a value that reads back as the OPPOSITE of what
# the human chose. Only the mapped literal is ever emitted.
#
# A typo is forgiving HERE and fatal in the flag (R4): a human at a prompt sees the outcome
# reported on the very next line and re-runs, while a typo'd flag in a script is silent.
# Same asymmetry E20-F01 and `--agents` already apply.
#
# SHAPE CONTRACT (R2): `sed -n '/^pr_loop_answer() {$/,/^}$/p'` must yield a complete,
# sourceable definition, so the test suite can exercise this truth table without a pty.
# The opening line is exactly `pr_loop_answer() {` and NO line inside the body may be
# exactly `}`. Do not reformat.
pr_loop_answer() {
  case "$1" in
    1|[nN]|[nN][oO]|[fF][aA][lL][sS][eE]) printf '%s\n' "false" ;;
    2|[yY]|[yY][eE][sS]|[tT][rR][uU][eE]) printf '%s\n' "true" ;;
    *)                                    printf '%s\n' "$2" ;;
  esac
}

# pr_loop_prompt <current> — ask the third question. The menu goes to STDERR (the
# resolved value is this function's stdout, read via command substitution).
#
# KEEP THIS FUNCTION THIS THIN. It is the only part of the feature a POSIX suite cannot
# drive — there is no pty — so every decision it feeds lives in pr_loop_answer above,
# which the suite extracts and unit-tests. Logic that migrates in here becomes untestable,
# and a structural check in tests/test_installer_toggles.sh fails if any appears. No loop,
# no re-ask, no config read, no write, no preflight.
#
# The text NAMES the precondition (the Codex GitHub App + an authed `gh`) on purpose: that
# sentence is this feature's entire substitute for an install-time probe, so R1 makes it
# falsifiable — the suite asserts both names are present.
pr_loop_prompt() {
  _plp_cur="$1"
  printf '\n' >&2
  printf '%s\n' "Enable the Codex PR review loop on this install? (E20-F02)" >&2
  printf '%s\n' "  1) false   stamp no /sdd-pr-loop glue — the opt-in default" >&2
  printf '%s\n' "  2) true    stamp /sdd-pr-loop + the pr-fixer sub-agent" >&2
  printf '%s\n' "             NEEDS the Codex GitHub App on this repo plus an authed \`gh\`." >&2
  printf '%s\n' "             Nothing is probed now; the first /sdd-pr-loop run reports it." >&2
  printf '%s' "  choose 1/2 [Enter keeps $_plp_cur]: " >&2
  _plp_ans=""
  read -r _plp_ans || :
  printf '\n' >&2
  pr_loop_answer "$_plp_ans" "$_plp_cur"
}

# resolve_pr_loop <target> — set the globals PR_LOOP_CHOICE (the resolved value) and
# PR_LOOP_CHOICE_SOURCE (how it resolved, for the one report line).
# Precedence, first match wins — the same ladder --agents and --builder-backend use:
#   1. a non-empty $PR_LOOP_OVERRIDE (--pr-loop), already validated against the legal
#      values at parse time (R4);
#   2. else an interactive TTY → the prompt, pre-selected from the current effective
#      value (R1);
#   3. else the current effective value — a no-op, so a non-interactive run with no
#      override asks nothing and changes nothing (R6).
#
# CURRENT EFFECTIVE VALUE = `true` ONLY when the target config's gate key reads exactly
# `true`; an absent file, an absent block, an absent key, an empty or malformed value all
# normalize to `false` (the E18-F01 R18/R18b normalization). On a FRESH install the config
# does not exist yet at this point, so the current value is the built-in `false` — which is
# also what seed_pr_loop_optin will force into the freshly copied file moments later. "No
# answer ⇒ off" is therefore enforced TWICE, and the only route to `true` on a fresh
# install is an explicit `2` / `yes` / `--pr-loop=true` (R9; E18-F01 R15).
#
# It deliberately does NOT consult HARNESS_PR_LOOP_ENABLED. That variable is E18-F01's
# PER-RUN gate override (the same family as HARNESS_AUTO_MERGE / HARNESS_MAX_ROUNDS) and
# persisting it would silently and permanently disable a target's configured loop — see
# the arg-parsing note beside PR_LOOP_OVERRIDE (R5).
PR_LOOP_CHOICE="false"
PR_LOOP_CHOICE_SOURCE="unchanged"
resolve_pr_loop() {
  _rpl_cfg="$1/.harness/harness.config.yaml"
  _rpl_cur="false"
  if [ -f "$_rpl_cfg" ]; then
    if [ "$(_cfg_pr_loop_value "$_rpl_cfg" enabled)" = "true" ]; then _rpl_cur="true"; fi
  fi
  if [ -n "${PR_LOOP_OVERRIDE:-}" ]; then
    PR_LOOP_CHOICE="$PR_LOOP_OVERRIDE"
    PR_LOOP_CHOICE_SOURCE="explicit --pr-loop"
  elif [ -t 0 ]; then
    PR_LOOP_CHOICE="$(pr_loop_prompt "$_rpl_cur")"
    PR_LOOP_CHOICE_SOURCE="interactive prompt"
  else
    PR_LOOP_CHOICE="$_rpl_cur"
    PR_LOOP_CHOICE_SOURCE="unchanged"
  fi
}

# set_pr_loop_enabled <config-file> <value> — write the gate key inside the TOP-LEVEL
# `pr_loop:` section, and nowhere else.
#
# The config is NEVER rewritten wholesale: this file is heavily commented BY DESIGN and
# those comments are the harness's load-bearing documentation of its own knobs. Two shapes,
# one canonical result:
#
#   • the key EXISTS → replace ONLY the value token. The line's indentation and everything
#     after the value (spacing + any trailing comment) survive verbatim, and every other
#     byte of the file is untouched — including a same-named `enabled:` key under any OTHER
#     top-level section, which the `p &&` section guard is what keeps safe (R7).
#   • the section exists with NO `enabled:` key → insert the CANONICAL line immediately
#     after the header. E18-F01 R18b constructs exactly that config, and without this
#     branch resolving `true` there would silently do nothing (R7).
#
# BYTE CONVERGENCE (R10, E18-F01 R17). $_spl_tail below is the tail of the ONE canonical
# gate line — the line seed_pr_loop_optin writes into a freshly seeded config and the line
# migrate_config appends into an upgraded one. Because both of those start from the same
# bytes, replacing just the value token on either yields the same bytes, and the inserted
# line is built from that same tail rather than hand-aligned. So a seeded target and a
# stripped-then-migrated one converge for BOTH values. If you edit the canonical line in
# seed_pr_loop_optin or migrate_config, edit this tail with it.
#
# Callers skip this entirely when the value already matches, so an unchanged run is
# trivially byte-identical (R8). Same `$f.tmp` + `mv` shape as seed_pr_loop_optin /
# set_builder_backend / _mc_insert_after.
set_pr_loop_enabled() {
  _spl_f="$1"; _spl_v="$2"
  _spl_tail='                 # opt-in master gate; ONLY `true` stamps /sdd-pr-loop glue'
  if awk '
      /^pr_loop:[[:space:]]*(#.*)?$/ { p=1; next }
      p && /^[^[:space:]#]/ { p=0 }
      p && /^[[:space:]]+enabled:/ { found=1 }
      END { exit found ? 0 : 1 }
    ' "$_spl_f"; then
    awk -v val="$_spl_v" '
      /^pr_loop:[[:space:]]*(#.*)?$/ { p=1; print; next }
      p && /^[^[:space:]#]/ { p=0 }
      p && !done && match($0, /^[[:space:]]+enabled:[[:space:]]*/) {
        pre = substr($0, 1, RLENGTH)
        tail = substr($0, RLENGTH + 1)
        if (tail !~ /^#/) { sub(/^[^[:space:]]+/, "", tail) }
        if (pre !~ /[[:space:]]$/) { pre = pre " " }
        if (tail ~ /^#/) { tail = " " tail }
        print pre val tail
        done = 1
        next
      }
      { print }
    ' "$_spl_f" > "$_spl_f.prwtmp" && mv "$_spl_f.prwtmp" "$_spl_f"
  else
    _mc_insert_after "$_spl_f" '^pr_loop:[[:space:]]*(#.*)?$' "  enabled: $_spl_v$_spl_tail"
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
  # BEFORE anything is written this run, then resolve the new SELECTED set. This is
  # decoupled from VERSION — a re-run at the SAME version still reconciles, which is
  # E08-F01 R11 — but it is NOT decoupled from "is this an existing install?".
  #
  # ONE DEFINITION OF "EXISTING INSTALL", used by the baseline AND by removal
  # authority (E19-F02 R14): the VERSION STAMP. precheck_baseline treats a
  # `.harness/.agents` with no `.harness/.harness-version` — orphan metadata from a
  # copied or half-restored `.harness/` — as NO install and pre-checks the detected
  # host alone. If the same orphan file still seeded PRIOR_AGENTS here, the two halves
  # would disagree about what the target IS: confirming that one-key picker would
  # reconcile every OTHER recorded key as "deselected" and delete pristine glue the
  # run never installed (e.g. GEMINI.md). A target with no stamp is not an install, so
  # it grants NO removal authority: PRIOR_AGENTS stays empty and this run only adds.
  # (Codex P2 #3664630744.)
  PRIOR_AGENTS=""
  if [ "$UPGRADE" = 1 ] && [ -f "$H/.agents" ]; then
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
  # The SECOND question (E20-F01), asked back to back with the picker and before any
  # output from the body copy. Only RESOLVED here — the value is applied later, at the
  # config seed/preserve stage, where the file is guaranteed to exist.
  resolve_builder_backend "$TARGET"
  # The THIRD question (E20-F02), asked back to back with the other two so every question
  # this run will ask is behind us before the body copy prints anything. RESOLVED ONLY —
  # the write happens at §2b, after seed/preserve + seed_pr_loop_optin + migrate_config,
  # where the file and its `pr_loop:` block are both guaranteed to exist. That ordering is
  # the whole feature: §2b precedes §5 (stamping) and §7b (gate-off reclamation), so a
  # prompt answer is reconciled INSIDE THIS RUN through E18-F01's existing machinery.
  resolve_pr_loop "$TARGET"

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
  # stub_files_in <dir-under-$H> <umbrella-root> — walk a tree ALREADY MATERIALISED by
  # `cp -R` and replace each REGULAR file's contents with a pointer stub, in place.
  #
  # Note the direction: this does not build the shape, it only thins what `cp -R` built.
  # That inversion is the point — see stub_tree below.
  #
  # Globs, not `find | while read`: a glob is newline-safe by construction, and this repo has
  # already been bitten by paths containing newlines. `find -exec` cannot help here because
  # `gen_body_stub` is a shell function, not a command. The `-e` guard skips a pattern that
  # matched nothing (it expands to itself); three mutually disjoint patterns are needed so
  # that no entry is visited — or recursed into — twice:
  #   *        every name not starting with `.`
  #   .[!.]*   dotfiles whose second character is not a dot   (`.x`, `.hidden`)
  #   ..?*     double-dot names with at least one more char   (`..draft.md`), never `..`
  # `.??*` in place of the second looks like a simplification and is not: it requires three
  # characters, so it omits a two-character dotfile like `.x`. (Codex r5 P2 #3706053982.)
  #
  # A missed name is now a THINNING miss, not a SHAPE miss: the file is still present with
  # `cp -R`'s own content, merely not stubbed. That is the whole safety win of the inversion.
  stub_files_in() {
    _sfi_dir="$1"; _sfi_root="$2"
    for _sfi_f in "$_sfi_dir"/* "$_sfi_dir"/.[!.]* "$_sfi_dir"/..?*; do
      [ -e "$_sfi_f" ] || continue
      if [ -L "$_sfi_f" ]; then
        # `cp -R` preserves a symlink as a symlink; so must we. Descending instead would
        # follow it — `[ -d ]` dereferences — and a self- or ancestor-referencing link like
        # `docs/self -> .` expands into `docs/self/self/...` until the OS resolution limit.
        # Reproduced end-to-end: 264 entries under a child's docs/ against 8 in a control,
        # with the cascade still reporting its ordinary status. Stubbing it would be just as
        # wrong the other way — the write would land on the link's TARGET.
        # (Codex r6 P2 #3710311338.)
        continue
      elif [ -d "$_sfi_f" ]; then
        # SUBSHELL, not a bare call. POSIX sh has no local variables, so a recursive call
        # would overwrite this frame's `_sfi_dir`/`_sfi_root` and every sibling processed
        # AFTER a nested directory would be handled with the wrong frame.
        # (Codex r4 P2 #3705960408.)
        ( stub_files_in "$_sfi_f" "$_sfi_root" ) || return 1
      elif [ -f "$_sfi_f" ]; then
        # `rm -f` first: `cp -R` may preserve a read-only mode, and gen_body_stub writes
        # with `>`, which cannot open a 0444 file.
        #
        # BOTH are checked. `set -e` does not help here: this function runs as the left
        # operand of `||` in the recursion above, and POSIX shells suppress `set -e` for the
        # whole of that operand — so an unchecked failure would be swallowed and the loop
        # would carry on to `install complete`. (Codex r7 P2 #3711176789.)
        #
        # These two checks are DEFENCE IN DEPTH and are deliberately not claimed as tested:
        # the `chmod -R u+w` in stub_tree removes the only trigger a portable fixture can
        # build, and deleting these `|| return 1`s leaves the suite green. What remains
        # reachable is environmental — a full disk, a read-only mount, ENAMETOOLONG — which
        # the suite cannot create without root or platform-specific tricks. Kept because the
        # failure they guard against is silent, and silence is what made r7 expensive.
        rm -f "$_sfi_f" || return 1
        gen_body_stub "${_sfi_f#"$H"/}" "$_sfi_root" "$_sfi_f" || return 1
      fi
    done
  }

  # stub_tree <relpath> <umbrella-root> — mirror one prose-tier path as pointer stubs,
  # preserving the SOURCE's shape so every path a consumer opens still exists.
  #
  # THE SHAPE IS PRODUCED BY `cp -R`, NOT REIMPLEMENTED. The requirement is literally "the
  # same shape the full-copy path produces", and the full-copy path is `cp -R` — so the
  # honest way to satisfy it is to make the same call and then thin the result, rather than
  # to re-derive `cp -R`'s traversal semantics in POSIX sh.
  #
  # The earlier implementation walked the SOURCE and created entries itself, which meant
  # rediscovering those semantics one filesystem shape at a time: nested directories
  # (r2 #3705758419), recursion frames (r4 #3705960408), `..name` and two-character dot
  # names (r5 #3706053982), then directory symlinks (r6 #3710311338) — four blocking
  # findings in one function, each a shape the walk had not anticipated, with FIFOs,
  # hardlinks and permission bits still unexamined. Copying first ends THAT class: whatever
  # `cp -R` does with an exotic entry, the child gets byte-for-byte, because it IS the
  # full-copy path. Only the thinning is ours.
  #
  # It does not end every class, and the honest record is that it opened a smaller one:
  # `cp -R` carries the SOURCE's modes across, so a `0555` directory or a `0444` file — which
  # the old source-walk never reproduced, because it built the destination fresh — arrived
  # unwritable and the thinning could not overwrite it (r7 #3711176789). The `chmod` below
  # closes that categorically, and unlike the shape class it has a single precondition
  # (the copy must be writable) rather than one bug per filesystem feature.
  stub_tree() {
    _st_rel="$1"; _st_root="$2"; _st_src="$SRC/$_st_rel"; _st_dst="$H/$_st_rel"
    if [ ! -e "$_st_src" ]; then die "source missing: $_st_rel"; fi
    mkdir -p "$(dirname "$_st_dst")"
    rm -rf "$_st_dst"
    cp -R "$_st_src" "$_st_dst"
    if [ -L "$_st_dst" ]; then
      :                       # a symlinked tier root: left exactly as the full path leaves it
    elif [ -d "$_st_dst" ]; then
      # `chmod -R` does NOT follow symlinks encountered during traversal — verified against a
      # tree holding a link to an external 0444 file, which kept its mode — so this cannot
      # reach outside the copy. A stub is new content anyway; inheriting the source file's
      # read-only bit onto a pointer would only make the next upgrade harder.
      chmod -R u+w "$_st_dst" || die "cannot make the copied prose tier writable: $_st_rel"
      stub_files_in "$_st_dst" "$_st_root" \
        || die "failed to stub the prose tier: $_st_rel"
    else
      rm -f "$_st_dst" || die "cannot replace the copied prose file: $_st_rel"
      gen_body_stub "$_st_rel" "$_st_root" "$_st_dst" \
        || die "failed to stub the prose file: $_st_rel"
    fi
  }

  # The PROGRAM-READ tier is copied unconditionally, in every layout. init.sh execs
  # tools/ and parses store/; a pointer is not a schema (ADR-0004).
  for _body_rel in $HARNESS_BODY_LOCAL; do copy "$_body_rel"; done

  # The PROSE tier is stubbed only for a child that resolves an umbrella AND is not
  # already carrying a real body. Otherwise it is copied, exactly as before — which is
  # every single-repo install, and every already-installed child (R9: converting one is
  # destructive and belongs to E24-F04, not to a routine re-run).
  _umb_body="$(umbrella_body_dir "$H")"
  _umb_root_cfg="${HARNESS_UMBRELLA_ROOT:-$(_cfg_umbrella_root_value "$H/harness.config.yaml")}"
  BODY_LAYOUT=full
  if [ -n "$_umb_body" ] && ! child_is_full_copy "$H"; then
    BODY_LAYOUT=thin
    for _body_rel in $HARNESS_BODY_PROSE; do stub_tree "$_body_rel" "$_umb_root_cfg"; done
    ok "prose body resolved from the umbrella at $_umb_root_cfg (stubs; init.sh, store/, tools/ stay local)"
  else
    for _body_rel in $HARNESS_BODY_PROSE; do copy "$_body_rel"; done
    if [ -n "$_umb_body" ]; then
      info "child already holds a full body — left as-is (converting it is E24-F04)"
    fi
  fi
  chmod +x "$H/init.sh" 2>/dev/null || true
  chmod +x "$H/tools/telemetry-report.py" 2>/dev/null || true
  chmod +x "$H/tools/sync-board.mjs" 2>/dev/null || true
  chmod +x "$H/tools/tasks-lock.py" 2>/dev/null || true   # E15-F01 board write lock helper
  chmod +x "$H/tools/validate-board.py" 2>/dev/null || true   # E15-F01 shared board validator (init.sh + tasks-lock)
  chmod +x "$H/tools/fix-worktree.sh" 2>/dev/null || true   # E15-F02 isolated fix-worktree lifecycle helper
  chmod +x "$H/tools/task-diagnostics.py" 2>/dev/null || true   # E16-F01 warn-only dependency diagnostics
  chmod +x "$H/tools/next-task.mjs" 2>/dev/null || true   # E16-F03 deterministic read-only selector
  chmod +x "$H/tools/wait-for-codex.sh" 2>/dev/null || true   # E18-F01 /sdd-pr-loop background Codex watcher
  chmod +x "$H/tools/change-size.sh" 2>/dev/null || true   # E21-F02 advisory pre-PR change-size check
  chmod +x "$H/tools/pr-round-trend.sh" 2>/dev/null || true   # E21-F03 pr-loop convergence trend
  chmod +x "$H/tools/pr-stack-guard.sh" 2>/dev/null || true   # E21-F04 stacked-PR merge-order guard
  chmod +x "$H/tools/pr-gate.sh" 2>/dev/null || true   # E99 deterministic pr-loop merge/fix/budget verdict
  chmod +x "$H/tools/run-tests.sh" 2>/dev/null || true   # E99 concurrent suite runner, failures-only output
  chmod +x "$H/tools/opencode-model-helper.sh" 2>/dev/null || true   # E22-F01 OpenCode model pin helper
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

  # ── 2a. persist the umbrella linkage (E24-F03 R1) ───────────────────────────
  # The cascade passes the umbrella root by env because §1 needs it BEFORE this stage
  # exists to read. Record it now, so the child's own config carries it: a later
  # single-target re-run in that child, and `init.sh`'s report, both read it from here
  # with no env var in sight. Skipped entirely when the value already matches, so an
  # ordinary re-run leaves the file byte-identical.
  if [ -n "${HARNESS_UMBRELLA_ROOT:-}" ]; then
    if [ "$(_cfg_umbrella_root_value "$H/harness.config.yaml")" != "$HARNESS_UMBRELLA_ROOT" ]; then
      set_umbrella_root "$H/harness.config.yaml" "$HARNESS_UMBRELLA_ROOT"
      info "recorded umbrella.root: $HARNESS_UMBRELLA_ROOT"
    fi
  fi

  # ── 2b. apply the resolved builder backend (E20-F01) ────────────────────────
  # Runs HERE, after seed/preserve + migrate_config, so the file and its `execution:`
  # block are both guaranteed to exist. The writer is skipped ENTIRELY when the value
  # already matches — not merely re-written with the same content — so a non-interactive
  # run with no override leaves the config byte-identical, mtime included (R6, R8).
  _bb_cfg="$H/harness.config.yaml"
  _bb_cur="$(_cfg_execution_builder_value "$_bb_cfg" backend)"
  if [ "$_bb_cur" != "$BUILDER_BACKEND" ]; then
    set_builder_backend "$_bb_cfg" "$BUILDER_BACKEND"
  fi
  # `delegate` with no command wired is a real install, loudly incomplete — never a
  # silent downgrade to in-session and never an abort (R11). Refusing would be an
  # unbreakable chicken-and-egg: delegate_cmd is a value the installer does not prompt
  # for, so "no delegate until a command is wired" means the prompt could never turn
  # delegation on. agents/builder.md already STOPS and reports if it is still empty at
  # run time, so the broken install fails where a human can act on it.
  if [ "$BUILDER_BACKEND" = "delegate" ] \
     && [ -z "$(_cfg_execution_builder_value "$_bb_cfg" delegate_cmd)" ]; then
    echo "⚠️  builder backend is 'delegate' but execution.builder.delegate_cmd is empty — set it in $_bb_cfg, or the Builder will stop and report instead of implementing" >&2
  fi
  # Exactly ONE report line per target, from the same resolver every path feeds (R12).
  # NOT on --print-agents, whose stdout is frozen at two lines — that flag exits long
  # before install_one.
  info "builder backend: $BUILDER_BACKEND ($BUILDER_BACKEND_SOURCE)"

  # ── 2c. apply the resolved pr_loop gate (E20-F02) ───────────────────────────
  # Runs HERE for two reasons. (1) The file exists: on a fresh install the config has just
  # been copied AND normalized to the opt-in default by seed_pr_loop_optin, on an upgrade
  # migrate_config has just appended the block if it was missing. seed_pr_loop_optin is
  # untouched and still runs FIRST, so a fresh install can never inherit this repo's own
  # `enabled: true` — only an explicit answer or flag can leave it on (R9; E18-F01 R15).
  # (2) It is upstream of §5 and §7b, so the resolved value is what pr_loop_enabled reads
  # for the rest of the run: turning it on stamps /sdd-pr-loop + pr-fixer, turning it off
  # runs the §7b reclamation, both in this single run and with zero changes to E18-F01 (R11).
  #
  # The writer is skipped ENTIRELY when the value already matches — not merely re-written
  # with the same content — so a non-interactive run with no override leaves the config
  # byte-identical, mtime included (R6, R8).
  _prl_cfg="$H/harness.config.yaml"
  _prl_cur="false"
  if [ "$(_cfg_pr_loop_value "$_prl_cfg" enabled)" = "true" ]; then _prl_cur="true"; fi
  if [ "$_prl_cur" != "$PR_LOOP_CHOICE" ]; then
    set_pr_loop_enabled "$_prl_cfg" "$PR_LOOP_CHOICE"
  fi
  # HARNESS_PR_LOOP_ENABLED is E18-F01's PER-RUN gate override and this feature does not
  # change that by one byte: it is never persisted, and it keeps winning over the config
  # for what THIS run stamps (E18-F01 R20). The two can therefore disagree, so say so once
  # — silently stamping the opposite of what the file now records is the surprise this
  # warning exists to prevent. Nothing is printed when it is unset or agrees (R5).
  if [ -n "${HARNESS_PR_LOOP_ENABLED:-}" ]; then
    _prl_env="false"
    if [ "$HARNESS_PR_LOOP_ENABLED" = "true" ]; then _prl_env="true"; fi
    if [ "$_prl_env" != "$PR_LOOP_CHOICE" ]; then
      echo "⚠️  HARNESS_PR_LOOP_ENABLED=$HARNESS_PR_LOOP_ENABLED is a PER-RUN override — it gates THIS run only and was NOT persisted; $_prl_cfg records $PR_LOOP_CHOICE (use --pr-loop=<true|false>, or the installer's prompt, to persist a value)" >&2
    fi
  fi
  # Exactly ONE report line per target, on STDOUT, from the same resolver every path feeds
  # (R12). The marker carries a colon so it cannot collide with §7b's stderr announcement
  # ("pr_loop.enabled is not true — reclaimed …"), which is counted by no one.
  info "pr_loop.enabled: $PR_LOOP_CHOICE ($PR_LOOP_CHOICE_SOURCE)"

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
  if [ ! -f "$H/progress/lessons.md" ]; then
    cat > "$H/progress/lessons.md" <<'LESSONS_EOF'
# Earned lessons (append-only)

> One entry per lesson that cost a review round, a rejection, or a debugging session to
> learn. Every role reads this file at session start; any lane may append. Never rewrite
> or delete an entry — supersede it with a newer one. Format:
>
>     - [YYYY-MM-DD <lane>] <the lesson, one or two lines, imperative>
LESSONS_EOF
    info "seeded progress/lessons.md (earned-lessons ledger)"
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
  # Also ignore the PER-RUN agent output dirs under .harness/progress/ (E99-F06). The harness
  # SOURCE has always ignored these (`progress/*/` in its own root .gitignore) but that ignore
  # was never propagated to consumers, so in an installed target every run dir was committable
  # — and in practice got committed, shipping agent scratch inside the product diff where a PR
  # reviewer re-reads it every round. The re-inclusions matter and MUST follow the ignore line:
  # `progress/*/` excludes the `inbox` directory itself, and git does not descend into an
  # excluded directory, so `!progress/inbox/**` alone would NOT re-include the briefs — the
  # directory has to be re-included first. progress/inbox/ holds the durable per-feature briefs
  # the Architect specs from. Loose FILES directly under progress/ (README.md, history.md,
  # .gitkeep) are never matched by `progress/*/`, which matches directories only — the explicit
  # re-inclusions below mirror the source .gitignore and are defensive, not load-bearing.
  # NOTE: a new ignore rule does not untrack a file that is ALREADY tracked; an existing target
  # must run `git rm -r --cached .harness/progress/<run-dir>` once itself. The installer
  # deliberately does not do that — untracking files in someone's repo is not an installer's call.
  # Also ignore the OpenCode concurrency marker (E22-F01). It is machine-specific runtime state
  # written by /sdd-test-concurrency; committing it would make other developers' installers
  # trust a probe result from a different OpenCode version or setup.
  # Also ignore Python bytecode (E99-F71/F89). __pycache__/ and *.pyc come from running
  # tools/*.py locally; the harness SOURCE has always ignored them in its own root .gitignore,
  # but that ignore was never propagated to consumers, so every installed target accumulated
  # untracked .pyc files. Left untracked-but-not-ignored they land in
  # `ls-files --others --exclude-standard`, which is what tools/change-size.sh counts.
  #
  # NOTE what is deliberately NOT here: .codex-skills/ and .model-agents/. They are installer
  # output, but so is .claude/agents — and the documented install workflow is
  # committed-and-shared, so ignoring a generated AGENT SURFACE would keep it out of a fresh
  # clone entirely. They stay tracked and are excluded from the change-size budget by the
  # built-in `generated` classifier in tools/change-size.sh instead. Bytecode is different:
  # it is machine-local, never shared, and nothing reads it from a clone.
  # Also ignore the worker roster (E17-F04). `.harness/workers.json` describes THIS
  # MACHINE's invocable CLIs, so committing it would put one developer's local CLI set
  # into a shared repo — the same reason telemetry.jsonl is ignored. UNCONDITIONAL, like
  # every entry here and unlike the roster's own opt-in write gate: `.harness/.gitignore`
  # is append-only on upgrade, so a GATED line could never be removed once the gate had
  # been on. That makes a gate here incoherent rather than conservative (R11).
  _ignores='telemetry.jsonl
workers.json
jira.pat
state/tasks.json.lock
.pr-loop/
.opencode-parallel
__pycache__/
*.pyc
progress/*/
!progress/.gitkeep
!progress/README.md
!progress/inbox/
!progress/inbox/**'
  case "$_tlog" in
    ''|telemetry.jsonl|/*) : ;;                 # default, unset, or absolute → nothing extra
    *) _ignores="$_ignores
$_tlog" ;;                                       # relative override → also ignore it
  esac
  if [ ! -f "$H/.gitignore" ]; then
    { printf '# Local-only telemetry log (see .harness/agents/orchestrator.md "## Telemetry").\n'
      printf '# Jira mirror PAT file (mirror.board.pat_file default) — never commit a PAT.\n'
      printf '# Per-run agent output under progress/ is ephemeral scratch; the inbox briefs and\n'
      printf '# the loose files directly under progress/ stay tracked (order matters — the\n'
      printf '# re-inclusions must follow progress/*/).\n'
      printf '%s\n' "$_ignores"; } > "$H/.gitignore"
    info "seeded .harness/.gitignore (telemetry log + progress run dirs ignored)"
  else
    # Whole-LINE match (-x). A substring match is unsafe now that the list carries negations:
    # `!progress/inbox/` is a substring of `!progress/inbox/**`, so a file holding only the
    # latter would suppress the former — and without the directory re-inclusion git never
    # descends into progress/inbox/, silently ignoring every brief. Append-only either way:
    # a target's own entries are never rewritten or reordered.
    # Guard the trailing newline first: appending to a file whose last line lacks one would
    # fuse the first pattern onto it, corrupting both entries silently.
    if [ -s "$H/.gitignore" ] && [ "$(tail -c 1 "$H/.gitignore" | wc -l)" -eq 0 ]; then
      printf '\n' >> "$H/.gitignore"
    fi
    printf '%s\n' "$_ignores" | while IFS= read -r _pat; do
      [ -n "$_pat" ] || continue
      grep -qxF "$_pat" "$H/.gitignore" || printf '%s\n' "$_pat" >> "$H/.gitignore"
    done
    info ".harness/.gitignore ensured (telemetry log + progress run dirs ignored)"
  fi

  # Personal/runtime agent state must never be committed to a SHARED project (e.g. a
  # spec/umbrella repo a team clones). Claude Code writes per-developer config
  # (.claude/settings.local.json), a scheduler lock (.claude/scheduled_tasks.lock), local
  # prompt override files, and browser-MCP scratch at the PROJECT ROOT — none of which belong in VCS, while the
  # harness-GENERATED .claude/agents and .claude/commands DO. Seed/extend the project-root
  # .gitignore with TARGETED, append-only ignores (never clobbering existing entries), so a
  # shared repo stays free of one developer's local state. Full model:
  # .harness/docs/CONFIG-LAYERING.md.
  # *.mutbak is deliberately NOT seeded (2026-09-04 reversal of E99-F71's ignore). The
  # ignore contradicted reviewer.md's own discipline: mutation backups must stay VISIBLE in
  # `git status` so a killed mid-campaign lane leaves detectable residue (the E99-F207
  # incident-class). The 26x change-size overstatement E99-F71 fixed is now handled at the
  # measurer instead — tools/change-size.sh classifies `\.mutbak$` as generated — so the
  # budget never sees them while git always does. The migration below WARNS about a bare
  # `*.mutbak` line an earlier version seeded (never deletes — provenance is unprovable).
  #
  # NOTE what is deliberately NOT here: .agents/, .codex/ and .opencode/. An earlier revision
  # ignored them as "installer output", and Codex raised a correct P1: the documented install
  # workflow is committed-and-shared, so those ignores would leave every Codex skill and role,
  # every Antigravity rule and workflow, and every OpenCode command absent from a fresh clone —
  # treating .claude/ as first-class and every other front end as second-class. They stay
  # TRACKED; tools/change-size.sh excludes them from the budget via its built-in `generated`
  # classifier, which removes the distortion without hiding the files.
  #
  # (A new ignore never untracks an ALREADY-tracked file — a target that committed one of
  # these must run `git rm -r --cached <path>` once itself; see the note above.)
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
    # A file whose last line lacks a trailing newline would FUSE the first appended
    # pattern onto it (`secret.envAGENTS.local.md`) — corrupting both entries silently.
    # Guard once, before any append.
    if [ -s "$TARGET/.gitignore" ] && [ "$(tail -c 1 "$TARGET/.gitignore" | wc -l)" -eq 0 ]; then
      printf '\n' >> "$TARGET/.gitignore"
    fi
    printf '%s\n' "$_root_ignores" | while IFS= read -r _pat; do
      [ -n "$_pat" ] || continue
      grep -qxF "$_pat" "$TARGET/.gitignore" || printf '%s\n' "$_pat" >> "$TARGET/.gitignore"
    done
    # Migration (2026-09-04, WARN-ONLY): an earlier version seeded a bare `*.mutbak`
    # ignore, which hides mutation residue from `git status` and defeats reviewer.md's
    # visibility rule. The installer cannot prove any given line's provenance — an
    # operator may have added the same rule for their own workflow — and this file is
    # append-only for user entries, so nothing is deleted: the contradiction is NAMED
    # and the removal is the operator's one-line call.
    if grep -qxF '*.mutbak' "$TARGET/.gitignore"; then
      echo "⚠️  .gitignore ignores '*.mutbak' — this hides mutation-campaign residue from git status, defeating reviewer.md's visibility rule (an earlier harness seeded it; change-size.sh now classifies .mutbak instead). If the rule is not deliberately yours, delete that line. (warn-only)" >&2
    fi
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
  .agents/skills/sdd-*/SKILL.md       SHARED \$sdd-* repository skill instructions, read by
                                      BOTH Codex and Antigravity; installed while EITHER is
                                      selected, reclaimed when the LAST one is (ADR-0003)
  .agents/skills/sdd-*/agents/openai.yaml
                                      explicit-only invocation policy — written wherever the
                                      unit is, since Codex discovers the directory itself
  .codex/agents/*.toml                seven selected Codex role definitions (model optional)
  .harness/.codex-skills/             last-written skill-unit ownership stamps (historical
                                      name; it stamps shared units — ADR-0003)
  CLAUDE.md / AGENTS.md / GEMINI.md  -> only the harness:begin..end block

OPENCODE CONCURRENCY PROBE  (E22-F01):
  .opencode/command/sdd-test-concurrency.md   (always installed for OpenCode)
  .harness/.opencode-parallel                   (marker: 'supported' or 'sequential')
  /sdd-fix-parallel is stamped for OpenCode ONLY when the marker is 'supported' or when
  the installer is run with --with-opencode-parallel=true; otherwise it is omitted.

PR LOOP GLUE  (OPT-IN — created ONLY while pr_loop.enabled reads exactly true; a fresh
install seeds false, so none of this exists until you turn it on — E18-F01):
  .claude/commands/sdd-pr-loop.md   .opencode/command/sdd-pr-loop.md
  .agents/workflows/sdd-pr-loop.md  .agents/skills/sdd-pr-loop/SKILL.md (shared unit)
  .claude/agents/pr-fixer.md  .opencode/agent/pr-fixer.md  .agents/agents/pr-fixer.md
  Flipping pr_loop.enabled back to false on a re-run RECLAIMS all of the above
  (pristine-only in the user-owned .agents/ tree) and prunes
  empty dirs. No pr-fixer artifact is ever created for the codex or gemini front-ends.

CODEX LEGACY MIGRATION:
  Current installs never create or overwrite \$CODEX_HOME/prompts/sdd-*.md. Ungated
  legacy prompts are preserved because cross-target ownership is unknowable. Only a
  byte-pristine sdd-pr-loop with a readable ledger proving no live owners is reclaimed.

MODEL ROUTING:
  .gemini/agents/*               per-role Gemini agent definitions (regenerated)
  .codex/agents/*                per-role Codex agent definitions, PROJECT-LOCAL
                                 (never written to \$CODEX_HOME / ~/.codex)
  .harness/.opencode.stamp       byte copy of the last opencode.json the installer wrote
                                 (enables re-stamping, and proves ownership across a
                                 generated-shape change such as a new role)
  .harness/.model-agents/        byte copies of the last generated .gemini/.codex per-role
                                 files, kept only while those files exist (lets a switch
                                 back to \`inherit\` reclaim them instead of orphaning them)
  .harness/.escalation-arming    whether escalating to \`builder-heavy\` would actually change
                                 the model, computed from resolve_model at install time and
                                 read by tools/builder-role.sh. First line \`armed\`/\`blocked\`,
                                 then one \`<front-end>=<verdict>\` per selected front-end,
                                 where <verdict> is raise|none|same|neither|unstamped.
                                 \`unstamped\` means the installer DECLINED to rewrite that
                                 front-end's live artifact (edited opencode.json, foreign or
                                 symlinked .codex/agents/builder*.toml), so the resolved model
                                 is not the one it will run.
                                 ABSENT means escalation is OFF — either this
                                 installer has not run here, or no role resolves to a model.
                                 Written only while at least one role resolves (the same gate
                                 .gemini/agents/ uses) and removed when none does.
  Gemini remains conditional on a concrete model. Selected Codex always has all seven roles;
  inherited or unpinned roles omit model, while concrete pins add it role by role. Codex
  role replacement/reclamation requires a matching last-written ownership stamp.

BODY LAYOUT  (E24-F03 / ADR-0004):
  This target holds the ${BODY_LAYOUT} body layout.
  full  every body path is a local copy — single-repo installs, and every child that
        already carried a full body when this ran (converting one is destructive and
        is E24-F04, never a side effect of a re-run).
  thin  the PROSE tier is pointer stubs resolved from umbrella.root; the PROGRAM tier
        is still a local copy, because init.sh execs and parses it.
    prose (stub-able) : AGENTS.md agents/ docs/ specs/_templates/ specs/glossary.md
    program (local)   : init.sh store/ tools/ + the example files an operator copies from
  Every generated front-end glue file is PROGRAM tier and always local.

PROJECT-OWNED  (seeded once, never clobbered on upgrade):
  .harness/harness.config.yaml   (verification commands + store backend + change_size budget)
  .harness/init.project.sh       (project-specific init.sh gate checks)
  .harness/specs/product.md  .harness/specs/epics/
  .harness/state/tasks.json  .harness/progress/
  umbrella.manifest.yaml         (umbrella mode only: coordinator manifest)

AGENT SELECTION  (E08-F01):
  .harness/.agents               harness-owned: the selected agent keys, one per line
                                 (claude|gemini|opencode|antigravity|codex), overwritten each run.
  Choose with --agents=<csv> / HARNESS_AGENTS=<csv>, an interactive toggle list, or
  (no TTY, no override) ALL. --agents=host resolves to the single front-end this
  installer session runs in (session env markers; HARNESS_HOST_AGENT=<key> declares it
  explicitly). \`host\` is a resolution MODE — it is never a picker row and never appears
  in .harness/.agents; an undetected host keeps this target's current shape. Preview with
  --print-agents <target>, which writes nothing.
  Deselecting an agent on a re-run REMOVES its glue above
  (its pointer block / .claude|.opencode dir / generated opencode.json) and warns;
  the shared AGENTS.md entrypoint and the .harness/ body are never removed.

BUILDER EXECUTION BACKEND  (E20-F01) — the installer's second question:
  execution.builder.backend in .harness/harness.config.yaml. Legal values:
    in-session   (DEFAULT) the Builder writes the code in this CLI session
    delegate     the Builder shells out to execution.builder.delegate_cmd
  Choose with the follow-up prompt (asked after the agent picker, on a TTY only),
  or with --builder-backend=<value> / HARNESS_BUILDER_BACKEND=<value>; the flag wins
  over the env var and an empty value means "no override". An illegal value aborts
  before anything is written. No TTY and no override ⇒ nothing asked, the target's
  current value untouched. Only that one scalar is ever rewritten — every comment and
  hand-edit in the file survives. Choosing \`delegate\` without setting delegate_cmd
  installs anyway and WARNS (the Builder stops and reports at run time).
  RE-RUN the installer to change it later.

PR REVIEW LOOP  (E20-F02) — the installer's third question:
  The pr_loop.enabled gate in .harness/harness.config.yaml. Legal values:
    false        (DEFAULT, opt-in) no /sdd-pr-loop glue is stamped at all
    true         /sdd-pr-loop + the pr-fixer sub-agent are stamped into every
                 selected front-end (flipping back to false reclaims all of it)
  Choose with the follow-up prompt (asked after the backend question, on a TTY only)
  or with --pr-loop=<true|false>; an empty value means "no override". An illegal
  value aborts before anything is written. No TTY and no override ⇒ nothing asked,
  the target's current value untouched. Only that one scalar is ever rewritten.
  The loop NEEDS the Codex GitHub App on the repo plus an authed \`gh\` — the
  installer probes NOTHING at install time; /sdd-pr-loop's own preflight reports it.
  HARNESS_PR_LOOP_ENABLED stays a PER-RUN override: it gates a single run and is
  never persisted (the installer warns once if it disagrees with the stored value).
  RE-RUN the installer to change it later.
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
    return 0
  }

  # opencode_parallel_wanted — decide whether /sdd-fix-parallel should be stamped for
  # OpenCode on this run. Honors --with-opencode-parallel=<true|false>; otherwise reads
  # the marker written by /sdd-test-concurrency. Default is skip (no marker or marker
  # says sequential). (E22-F01)
  opencode_parallel_wanted() {
    case "${OPENCODE_PARALLEL_OVERRIDE:-}" in
      true) return 0 ;;
      false) return 1 ;;
    esac
    if [ -f "$TARGET/.harness/.opencode-parallel" ]; then
      _opw="$(head -n 1 "$TARGET/.harness/.opencode-parallel" | tr -d '[:space:]')"
      [ "$_opw" = "supported" ] && return 0
    fi
    return 1
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
  # gen_opencode_legacy <dest> — the model-free body as the PREVIOUS release generated it.
  # DERIVED from the current model-free body by dropping the one line E17-F02 added, so the
  # two can never diverge: hand-building this body is the error-prone path (a version differing
  # by a single blank line fails IDENTICALLY to the bug it is meant to fix — same warning,
  # same stale role set, no signal). Consumed by the §5g re-stamp test and the §7 removal
  # test, which is why it lives beside gen_opencode_json rather than in either caller.
  #
  # This exists ONCE. It is not the start of a list: from E17-F02 onward every write of
  # opencode.json also writes .harness/.opencode.stamp (§5g), so a future shape change is
  # recognised by the stamp alone and needs no further legacy candidate. A target still on
  # the PRE-doc-critic five-role shape is knowingly not covered — that addition carried this
  # same defect, and such a target can delete opencode.json and re-run.
  gen_opencode_legacy() {
    _ocl_tmp="$(mktemp 2>/dev/null || mktemp -t harness-ocl)"
    MODELS_OFF=1; gen_opencode_json "$_ocl_tmp"; MODELS_OFF=0
    grep -v '"builder-heavy":' "$_ocl_tmp" > "$1"
    rm -f "$_ocl_tmp"
  }

  gen_opencode_json() {
    _oc_m_orchestrator="$(_oc_model orchestrator)"
    _oc_m_architect="$(_oc_model architect)"
    _oc_m_builder="$(_oc_model builder)"
    _oc_m_reviewer="$(_oc_model reviewer)"
    _oc_m_scout="$(_oc_model scout)"
    _oc_m_doc_critic="$(_oc_model doc-critic)"
    _oc_m_builder_heavy="$(_oc_model builder-heavy)"
    cat > "$1" <<EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "instructions": [".harness/AGENTS.md"],
  "agent": {
    "orchestrator": { "mode": "primary",  "description": "The Leader: routes the next task, delegates. Never writes code.", ${_oc_m_orchestrator}"prompt": "{file:./.harness/agents/orchestrator.md}" },
    "architect":    { "mode": "subagent", "description": "Spec Author: writes the 4-file spec (EARS).",                     ${_oc_m_architect}"prompt": "{file:./.harness/agents/architect.md}" },
    "builder":      { "mode": "subagent", "description": "Implementer: writes code from an approved spec.",                 ${_oc_m_builder}"prompt": "{file:./.harness/agents/builder.md}" },
    "builder-heavy":{ "mode": "subagent", "description": "Implementer at the escalation tier; same body as builder.",       ${_oc_m_builder_heavy}"prompt": "{file:./.harness/agents/builder-heavy.md}" },
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
builder-heavy	The Implementer at the escalation tier. Same instruction body and same discipline as `builder`; differs only by the model it resolves to (ADR-0002).
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

  # gen_codex_agent <role> <description> <dest> — one `.codex/agents/<role>.toml`,
  # written inside the target repo alongside the repository-local skill surface.
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
  model_agent_stamp_tree_is_symlinked() {
    [ -L "$H/.model-agents" ] || [ -L "$H/.model-agents/$1" ]
  }

  model_agent_stamp_destination_is_symlinked() {
    model_agent_stamp_tree_is_symlinked "$1" \
      || [ -L "$H/.model-agents/$1/$2" ]
  }

  # opencode_stamp_is_symlinked — true iff .harness/.opencode.stamp is a symlink (live or
  # dangling). `cmp`, `cp` and redirection all FOLLOW a symlink, so an operator-planted (or
  # hostile) link would both lend a foreign file's bytes to the ownership comparison and let
  # a `cp` overwrite that file's external target. `test -L` detects the link without
  # dereferencing it. Same rule the .model-agents and .codex/agents stamps already apply.
  #
  # This guard became LOAD-BEARING when the stamp write turned unconditional (E17-F02):
  # before that, an all-`inherit` target ran `rm -f` on this path, which UNLINKS a symlink
  # instead of writing through it, so the hazard could not arise. Verified against v0.55.0.
  # (Codex #3715169411.)
  opencode_stamp_is_symlinked() {
    [ -L "$H/.opencode.stamp" ]
  }

  # escalation_arming_is_symlinked — true iff .harness/.escalation-arming is a symlink (live
  # or dangling). Same rule, and the same reason, as opencode_stamp_is_symlinked: redirection
  # FOLLOWS a link, so writing through one would overwrite a file that may be outside the
  # repository. Here the guard is load-bearing beyond hygiene — this artifact decides which
  # MODEL runs a build, so a followed link is a path by which something outside `.harness/`
  # could assert `armed`. Both the write AND the removal are refused: `rm -f` would unlink the
  # symlink, silently un-arming a target through a path the operator never asked about.
  escalation_arming_is_symlinked() {
    [ -L "$H/.escalation-arming" ]
  }

  # ── the model-routing stamp ledger (E17-F05) ─────────────────────────────────
  # The verdict must describe what the front-end WILL ACTUALLY RUN, not merely what the
  # config asks for. Those two diverge whenever the installer declines to rewrite a live
  # artifact it does not own — an edited `opencode.json`, or a foreign/edited/symlinked
  # `.codex/agents/builder*.toml`. In every such case `resolve_model` still reports the
  # DESIRED model while the role on disk keeps whatever it had, so the verdict would read
  # `armed` for a front-end that will run the build with no heavy model at all: the same
  # downgrade this feature exists to prevent, arriving through a different door.
  # (Codex #3717508457, reproduced on an opencode target — the installer printed
  # "model routing changes were NOT applied" and the verdict still read `armed`.)
  #
  # Only codex and opencode can reach this ledger. claude (§5), gemini (§5e) and antigravity
  # write their per-role artifacts unconditionally, with no refusal branch, so a selected one
  # of those is always stamped with what `resolve_model` just returned.
  #
  # A FILE, not a shell variable, and that is load-bearing: §5f iterates
  # `ag_personas | while … read`, a PIPELINE, whose body POSIX sh runs in a SUBSHELL — a
  # variable assigned in there dies at `done` and the ledger would silently always read
  # empty, which fails OPEN (armed). The file survives the subshell.
  _UNSTAMPED_FILE="$(mktemp 2>/dev/null || mktemp -t harness-unstamped)"
  mark_unstamped() {
    grep -qx "$1" "$_UNSTAMPED_FILE" 2>/dev/null || printf '%s\n' "$1" >> "$_UNSTAMPED_FILE"
  }
  fe_unstamped() {
    grep -qx "$1" "$_UNSTAMPED_FILE" 2>/dev/null
  }

  # verify_codex_builder_roles_stamped — did the two roles the verdict compares actually end
  # up carrying what `resolve_model` just returned?
  #
  # OUTCOME-BASED, and that is the whole point. The first version of this marked `unstamped`
  # at each refusal SITE inside install_codex_agent — and missed one: §5f's own per-file
  # pre-check `continue`s BEFORE install_codex_agent is ever called, so a symlinked
  # builder-heavy.toml still produced `armed` over a live role with no model.
  # (Codex #3717604849, reproduced.) A list of refusal sites is something a future branch can
  # silently fall outside of; comparing the live file against a freshly generated one cannot.
  # Any path that leaves them different is caught — including paths that do not exist yet.
  #
  # It re-derives nothing: it calls the installer's own `gen_codex_agent` and `cmp`, the same
  # way the verdict calls `resolve_model` rather than reimplementing it.
  #
  # Scoped to `builder`/`builder-heavy`: a hand-edited `scout.toml` says nothing about whether
  # escalating raises the Builder's model, and blocking on it would fire on the wrong signal.
  verify_codex_builder_roles_stamped() {
    if codex_agent_tree_is_symlinked; then mark_unstamped codex; return 0; fi
    _vcb_tmp="$(mktemp 2>/dev/null || mktemp -t harness-vcb)"
    for _vcb_r in builder builder-heavy; do
      _vcb_dest="$TARGET/.codex/agents/$_vcb_r.toml"
      # A symlinked destination is never FOLLOWED for the comparison: `cmp` reads through a
      # link and could otherwise report a foreign file as byte-identical to ours.
      if [ -L "$_vcb_dest" ] || [ ! -f "$_vcb_dest" ]; then
        mark_unstamped codex
        continue
      fi
      _vcb_desc="$(ag_personas | awk -F'	' -v r="$_vcb_r" '$1==r {print $2; exit}')"
      gen_codex_agent "$_vcb_r" "$_vcb_desc" "$_vcb_tmp"
      cmp -s "$_vcb_dest" "$_vcb_tmp" || mark_unstamped codex
    done
    rm -f "$_vcb_tmp"
  }

  # write_escalation_arming — record, for the front-ends selected on THIS run, whether
  # escalating to `builder-heavy` would actually change the model (E17-F05).
  #
  # Format — first line is exactly one word so the consuming rule needs no parser:
  #
  #     armed|blocked
  #     <front-end>=<raise|none|same|neither|unstamped>   one per selected front-end
  #
  # `armed` iff EVERY selected front-end is `raise`. A conservative AND, because
  # tools/builder-role.sh cannot know which front-end it is running under: the config does not
  # say, and the five are chosen at install time, not at build time. Passing the front-end as
  # an argument would only move the guess into agents/orchestrator.md, where it is prose and
  # untestable. The cost, stated: a mixed target where four front-ends would raise and one
  # lacks a pin gets no escalation ANYWHERE — deliberate, since the AND never downgrades
  # anyone, and the detail lines name the offender so the fix is one pin and one re-run.
  #
  # Only `raise` arms. `same`/`neither` are not harmful — neither downgrades — but arming on
  # them would spend a build round, a progress/history.md line and a telemetry record
  # announcing an escalation that provably cannot change the outcome: the build re-runs on the
  # identical model and fails the identical way, while the operator reads that a heavier
  # Builder was tried. A misleading record is worse than a legible decline.
  #
  # GATED on `models_any`, the same gate `.gemini/agents/` uses (E17-F01 R11): a target with
  # every role on `inherit` — the shipped default — must not grow a file a never-configured
  # target lacks. When nothing resolves, an existing artifact is REMOVED rather than left
  # stale, which is the reclamation reclaim_model_agents performs for the per-role stamps.
  #
  # Detail lines are emitted in $AGENT_KEYS order, not selection order, so re-installing the
  # same target twice yields a byte-identical file.
  write_escalation_arming() {
    if escalation_arming_is_symlinked; then
      echo "⚠️  .harness/.escalation-arming is a symlink — escalation arming verdict not written (link and its target left unchanged)" >&2
      return 0
    fi

    _ea_any=0
    for _ea_k in $AGENT_KEYS; do
      agent_selected "$_ea_k" || continue
      if models_any "$_ea_k"; then _ea_any=1; fi
    done

    # Nothing resolves anywhere ⇒ no verdict to record. Absence and "blocked" both mean
    # escalation is off and both have the same remedy (configure models.builder-heavy, re-run
    # the installer), so folding them together costs nothing and keeps an unconfigured target
    # byte-identical to what it was before this feature existed.
    if [ "$_ea_any" = 0 ]; then
      if [ -f "$H/.escalation-arming" ]; then
        rm -f "$H/.escalation-arming"
        info "escalation arming verdict reclaimed (no role resolves to a model any more)"
      fi
      return 0
    fi

    _ea_body=""
    _ea_armed=1
    _ea_seen=0
    for _ea_k in $AGENT_KEYS; do
      agent_selected "$_ea_k" || continue
      _ea_seen=1
      # `unstamped` outranks whatever resolve_model would say: the config's answer is about
      # a file this run did not write, so it describes a model the front-end will not use.
      if fe_unstamped "$_ea_k"; then
        _ea_v=unstamped
      else
        _ea_v="$(escalation_verdict "$_ea_k")"
      fi
      [ "$_ea_v" = raise ] || _ea_armed=0
      _ea_body="$_ea_body$_ea_k=$_ea_v
"
    done
    # No front-end selected at all cannot happen on a real run, but an AND over an empty set
    # is vacuously true — which would arm a target nothing was checked for. Guard it.
    [ "$_ea_seen" = 1 ] || _ea_armed=0

    if [ "$_ea_armed" = 1 ]; then _ea_first=armed; else _ea_first=blocked; fi
    { printf '%s\n' "$_ea_first"; printf '%s' "$_ea_body"; } > "$H/.escalation-arming"
    if [ "$_ea_armed" = 1 ]; then
      ok "escalation armed — builder-heavy resolves to a different model on every selected front-end"
    else
      info "escalation NOT armed — see .harness/.escalation-arming for which front-end blocked it"
    fi
  }

  # ── the worker roster (E17-F04) ──────────────────────────────────────────────
  # `.harness/workers.json` answers ONE question, once, as versioned data: which of the
  # harness's front-end CLIs can THIS MACHINE invoke, and what can the harness vouch for
  # about each. An external router (the epic's `multi-cli-orchestrator`) reads it instead of
  # rediscovering the answer every time. Nothing in the harness consumes it.
  #
  # MODELLED ON write_escalation_arming — WITH TWO DELIBERATE DIVERGENCES, both of which
  # fail silently if carried across:
  #   1. NO `agent_selected … || continue` FILTER. The roster's whole point is telling a
  #      router about CLIs this install did NOT wire up, so selection is recorded as the
  #      `harness-selected` CAPABILITY and is never a filter (R5). On a machine where every
  #      front-end is selected a filtered roster is byte-identical to a correct one, which
  #      is why only tests/test_worker_roster.sh's narrowed-selection fixture can catch it.
  #   2. RECLAMATION IS TRIGGERED BY THE GATE, AND ONLY THE GATE. write_escalation_arming
  #      also reclaims when its detection comes back empty, because an empty arming file
  #      means nothing. An empty roster MEANS something — this machine can invoke none of
  #      the harness's front-ends — and a consumer must be able to tell that from "no roster
  #      was ever written". So gate on + nothing resolves ⇒ a well-formed `"workers": []`.

  # worker_roster_is_symlinked — true iff .harness/workers.json is a symlink (live or
  # dangling). Same rule and same reason as escalation_arming_is_symlinked: redirection
  # FOLLOWS a link, so writing through one would overwrite a file that may be outside the
  # repository. Both the write AND the reclamation are refused (R12) — `rm -f` would unlink
  # the symlink, destroying an operator's link through a path they never asked about.
  worker_roster_is_symlinked() {
    [ -L "$H/workers.json" ]
  }

  # worker_roster_detect — one row per rostered key, on stdout, in $AGENT_KEYS order:
  #
  #     <key> <command> [<capability> …]        capabilities sorted, may be empty
  #
  # PRESENCE IS A `PATH` LOOKUP AND NOTHING ELSE (R8): `command -v <name> >/dev/null 2>&1`,
  # used as a BOOLEAN. No rostered CLI is executed — not for version detection, not for
  # anything — and the lookup's stdout is DISCARDED rather than captured. That discard is
  # load-bearing (R5, spec → Recorded decision 4): the value is relative whenever the
  # matching PATH component is relative, it is environment-derived content in a JSON file,
  # and it can hold bytes a JSON string cannot represent. An entry records no filesystem
  # path; recording one re-opens six closed review findings and needs a `schema` bump.
  #
  # $AGENT_KEYS ORDER, CAPABILITIES SORTED — not detection order, not PATH order. These are
  # the degrees of freedom that are NOT roster inputs, and removing them is what makes R9's
  # byte-identity hold for equal inputs.
  worker_roster_detect() {
    for _wr_k in $AGENT_KEYS; do
      _wr_row="$(printf '%s\n' "$WORKER_INVOKE" | awk -v k="$_wr_k" '$1 == k { print; exit }')"
      [ -n "$_wr_row" ] || continue
      _wr_cmd="$(printf '%s\n' "$_wr_row" | awk '{ print $2 }')"
      [ -n "$_wr_cmd" ] || continue
      command -v "$_wr_cmd" >/dev/null 2>&1 || continue

      # The table carries ONLY the non-derivable tags (today: `non-interactive`).
      _wr_caps="$(printf '%s\n' "$_wr_row" | awk '{ for (i = 3; i <= NF; i++) print $i }')"
      # `harness-selected` is derived from $SELECTED — the SELECTION, not a write outcome.
      # The installer has refusal branches that leave a selected front-end's glue unwritten
      # (a hand-edited opencode.json, an edited/symlinked Codex role), and the roster has no
      # ledger that would know, so this tag claims exactly what it can prove and no more.
      # Do NOT reach for the §6b unstamped ledger here: it is scoped to model-routing
      # artifacts, only codex/opencode can reach it, and it is removed before this runs.
      if agent_selected "$_wr_k"; then
        _wr_caps="$_wr_caps
harness-selected"
      fi
      # `host-detectable` is derived from having a HOST_MARKERS row — read, never edited.
      if printf '%s\n' "$HOST_MARKERS" | awk -v k="$_wr_k" '$1 == k { f = 1 } END { exit !f }'; then
        _wr_caps="$_wr_caps
host-detectable"
      fi

      _wr_out="$_wr_k $_wr_cmd"
      for _wr_c in $(printf '%s\n' "$_wr_caps" | awk 'NF' | LC_ALL=C sort); do
        _wr_out="$_wr_out $_wr_c"
      done
      printf '%s\n' "$_wr_out"
    done
  }

  # write_worker_roster — symlink guard → gate → detect → emit, in that order.
  #
  # JSON EMISSION — THE INVARIANT THAT REPLACES AN ESCAPER. Every value written below is a
  # HARNESS-AUTHORED LITERAL from a closed set: `key` from $AGENT_KEYS, `command` and the
  # non-derivable tags from $WORKER_INVOKE, the derived tags from the fixed vocabulary, and
  # `generated_by` the fixed literal `harness-install.sh` (never `$0` — an
  # invocation-dependent path would be environment-derived JSON content AND a fourth input
  # to R9's byte-identity). All are `[a-z-]+` tokens spelled out in this file, so none can
  # hold `"`, `\` or a C0 control character and NO escaping is required. An escaper over
  # inputs that provably need none is code no fixture could distinguish from its absence.
  # ADDING A FIELD CARRYING ENVIRONMENT-DERIVED CONTENT RE-INCURS CLASS-WIDE JSON ESCAPING
  # (`"`, `\`, and C0 U+0000–U+001F) — follow tools/change-size.sh's `_json_escape`, the
  # artifact E99-F08 shipped after a hand-rolled emitter handled control characters one
  # reported bug at a time, and NEVER tools/pr-round-trend.sh's `sed` version, which covers
  # only `\` and `"`. Such a field is a `schema` change anyway, so the obligation lands
  # where a fixture can test it.
  #
  # STRUCTURE still needs care, independently of content: no trailing comma after the last
  # workers[] entry, and a well-formed `"workers": []` when nothing resolved.
  write_worker_roster() {
    if worker_roster_is_symlinked; then
      echo "⚠️  .harness/workers.json is a symlink — worker roster not written (link and its target left unchanged)" >&2
      return 0
    fi

    if ! worker_roster_enabled; then
      # The GATE is the whole reclamation trigger (R3). "Nothing resolved" is not one.
      if [ -f "$H/workers.json" ]; then
        rm -f "$H/workers.json"
        info "worker roster reclaimed (.harness/workers.json removed — workers.roster is not enabled)"
      fi
      return 0
    fi

    _wr_rows="$(mktemp 2>/dev/null || mktemp -t harness-roster)"
    worker_roster_detect > "$_wr_rows"
    _wr_count="$(awk 'END { print NR + 0 }' "$_wr_rows")"

    # Overwritten unconditionally from freshly detected state (R10): the file is derived
    # data the installer owns outright, so nothing here merges with what was on disk.
    #
    # UNLINK FIRST — `>` alone cannot discharge R10. A first install under a restrictive
    # umask (say 0222) leaves workers.json mode 0444, and the redirection below then fails
    # outright. What that failure DOES is shell-dependent, and BOTH outcomes are wrong:
    # under dash and zsh the redirection error trips `set -eu` (line 101) and aborts the
    # install midway, after other artifacts have already been rewritten; under bash — which
    # is macOS `sh`, the shell this suite runs under — a redirection failure on a COMPOUND
    # command does not exit the shell, so the install continues, the STALE roster survives,
    # and the info() below reports a write that never happened. The second is the quieter
    # failure and the worse one: R10 is violated with a success message printed over it.
    # Removing the destination first sidesteps both. The containing .harness/ is writable
    # even when the file is not (unlink needs no write bit on the file), a symlinked
    # destination was already refused above (R12), and the file is the harness's own
    # derived data — so this can only ever unlink a regular file the installer owns.
    rm -f "$H/workers.json"
    {
      printf '{\n'
      printf '  "schema": 1,\n'
      printf '  "generated_by": "harness-install.sh",\n'
      printf '  "capability_vocabulary": ["harness-selected", "host-detectable", "non-interactive"],\n'
      if [ "$_wr_count" -gt 0 ]; then
        printf '  "workers": [\n'
        _wr_n=0
        while IFS= read -r _wr_line; do
          [ -n "$_wr_line" ] || continue
          _wr_n=$((_wr_n + 1))
          [ "$_wr_n" -eq 1 ] || printf ',\n'
          _wr_ek=""; _wr_ec=""; _wr_ecaps=""; _wr_i=0
          for _wr_f in $_wr_line; do
            _wr_i=$((_wr_i + 1))
            case "$_wr_i" in
              1) _wr_ek="$_wr_f" ;;
              2) _wr_ec="$_wr_f" ;;
              *) if [ -z "$_wr_ecaps" ]; then _wr_ecaps="\"$_wr_f\""
                 else _wr_ecaps="$_wr_ecaps, \"$_wr_f\""; fi ;;
            esac
          done
          printf '    {"key": "%s", "command": "%s", "capabilities": [%s]}' \
            "$_wr_ek" "$_wr_ec" "$_wr_ecaps"
        done < "$_wr_rows"
        printf '\n  ]\n'
      else
        printf '  "workers": []\n'
      fi
      printf '}\n'
    } > "$H/workers.json"

    rm -f "$_wr_rows"
    info "worker roster written (.harness/workers.json — $_wr_count invocable front-end CLI(s) on this machine)"
  }

  stamp_model_agent() {
    if model_agent_stamp_destination_is_symlinked "$1" "$2"; then
      echo "⚠️  .harness/.model-agents/$1/$2 has a symlinked stamp component — ownership stamp not written" >&2
      return 0
    fi
    mkdir -p "$H/.model-agents/$1"
    cp "$3" "$H/.model-agents/$1/$2"
  }

  # Codex's project-local role namespace is shared with the operator. Reject symlinks
  # at every destination component before an ownership comparison or write: `test -f`,
  # `cmp`, and redirection all follow them. `test -L` detects both live and dangling
  # links without dereferencing their external targets.
  codex_agent_tree_is_symlinked() {
    [ -L "$TARGET/.codex" ] || [ -L "$TARGET/.codex/agents" ]
  }

  codex_agent_destination_is_symlinked() {
    codex_agent_tree_is_symlinked || [ -L "$TARGET/.codex/agents/$1" ]
  }

  discard_codex_agent_stamp() {
    if model_agent_stamp_destination_is_symlinked codex "$1"; then
      echo "⚠️  .harness/.model-agents/codex/$1 has a symlinked stamp component — ownership stamp left unchanged" >&2
      return 0
    fi
    rm -f "$H/.model-agents/codex/$1"
    if ! model_agent_stamp_tree_is_symlinked codex; then
      rmdir "$H/.model-agents/codex" 2>/dev/null || true
      [ -L "$H/.model-agents" ] || rmdir "$H/.model-agents" 2>/dev/null || true
    fi
  }

  # install_codex_agent <file> <candidate> — selected Codex installs replace a role
  # only when ownership is safe: the path is absent, already equals the current
  # generated body, or still equals the last body this installer stamped.
  install_codex_agent() {
    _ica_file="$1"; _ica_src="$2"
    _ica_dest="$TARGET/.codex/agents/$_ica_file"
    _ica_stamp="$H/.model-agents/codex/$_ica_file"
    if codex_agent_destination_is_symlinked "$_ica_file"; then
      echo "⚠️  .codex/agents/$_ica_file has a symlinked destination component — selected Codex install left it unchanged" >&2
      discard_codex_agent_stamp "$_ica_file"
      return 0
    fi
    if model_agent_stamp_destination_is_symlinked codex "$_ica_file"; then
      echo "⚠️  .harness/.model-agents/codex/$_ica_file has a symlinked stamp component — selected Codex install left the live role and stamp unchanged" >&2
      return 0
    fi
    _ica_safe=0
    if [ ! -e "$_ica_dest" ]; then
      _ica_safe=1
    elif [ -f "$_ica_dest" ] && [ -f "$_ica_stamp" ] \
         && cmp -s "$_ica_dest" "$_ica_stamp"; then
      _ica_safe=1
    elif [ -f "$_ica_dest" ] && cmp -s "$_ica_dest" "$_ica_src"; then
      _ica_safe=1
    fi
    if [ "$_ica_safe" = 0 ]; then
      echo "⚠️  .codex/agents/$_ica_file is foreign or edited — selected Codex install left it unchanged" >&2
      return 0
    fi
    mkdir -p "$TARGET/.codex/agents"
    cat "$_ica_src" > "$_ica_dest"
    stamp_model_agent codex "$_ica_file" "$_ica_dest"
    return 0
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
    _rma_tree_safe=1
    if [ "$_rma_fe" = codex ] && codex_agent_tree_is_symlinked; then
      _rma_tree_safe=0
      echo "⚠️  $_rma_sub has a symlinked destination component — left in place (deselected '$_rma_fe' not removed)" >&2
    fi
    if model_agent_stamp_tree_is_symlinked "$_rma_fe"; then
      _rma_tree_safe=0
      echo "⚠️  .harness/.model-agents/$_rma_fe has a symlinked stamp component — live artifacts and ownership stamps left unchanged" >&2
    fi
    if [ "$_rma_tree_safe" = 1 ] && [ -d "$TARGET/$_rma_sub" ]; then
      _rma_tmp="$(mktemp 2>/dev/null || mktemp -t harness-ma)"
      _rma_gone="$(ag_personas | while IFS='	' read -r _rma_r _rma_d; do
        [ -n "$_rma_r" ] || continue
        _rma_f="$_rma_r.$_rma_ext"
        if [ "$_rma_fe" = codex ] \
           && codex_agent_destination_is_symlinked "$_rma_f"; then
          echo "⚠️  $_rma_sub/$_rma_f is a symlinked destination — left in place (deselected '$_rma_fe' not removed)" >&2
          continue
        fi
        if model_agent_stamp_destination_is_symlinked "$_rma_fe" "$_rma_f"; then
          echo "⚠️  .harness/.model-agents/$_rma_fe/$_rma_f has a symlinked stamp component — live artifact and stamp left unchanged" >&2
          continue
        fi
        [ -f "$TARGET/$_rma_sub/$_rma_f" ] || continue
        if [ "$_rma_fe" = codex ]; then
          # Codex lives in a shared project-local namespace. Reclamation requires the
          # last-written stamp; a fresh body cannot prove that a same-named file is ours.
          if [ -f "$_rma_stamp/$_rma_f" ] \
             && cmp -s "$TARGET/$_rma_sub/$_rma_f" "$_rma_stamp/$_rma_f"; then
            remove_if_pristine "$_rma_sub/$_rma_f" "$_rma_stamp/$_rma_f" "$_rma_fe"
          else
            echo "⚠️  $_rma_sub/$_rma_f has no matching last-written stamp (foreign or edited) — left in place (deselected '$_rma_fe' not removed)" >&2
          fi
        else
          # Gemini retains its existing compatibility fallback for pre-stamp targets.
          "$_rma_gen" "$_rma_r" "$_rma_d" "$_rma_tmp"
          _rma_ref="$_rma_tmp"
          if [ -f "$_rma_stamp/$_rma_f" ] \
             && cmp -s "$TARGET/$_rma_sub/$_rma_f" "$_rma_stamp/$_rma_f"; then
            _rma_ref="$_rma_stamp/$_rma_f"
          fi
          remove_if_pristine "$_rma_sub/$_rma_f" "$_rma_ref" "$_rma_fe"
        fi
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
    if ! model_agent_stamp_tree_is_symlinked "$_rma_fe" && [ -d "$_rma_stamp" ]; then
      ag_personas | while IFS='	' read -r _rma_r _rma_d; do
        [ -n "$_rma_r" ] || continue
        _rma_stamp_file="$_rma_r.$_rma_ext"
        if model_agent_stamp_destination_is_symlinked "$_rma_fe" "$_rma_stamp_file"; then
          echo "⚠️  .harness/.model-agents/$_rma_fe/$_rma_stamp_file has a symlinked stamp component — ownership stamp left unchanged" >&2
          continue
        fi
        rm -f "$_rma_stamp/$_rma_stamp_file"
      done
      rmdir "$_rma_stamp" 2>/dev/null || true
      [ -L "$H/.model-agents" ] || rmdir "$H/.model-agents" 2>/dev/null || true
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
  # builder-heavy (E17-F02): the escalation tier. The tool list is copied EXACTLY from
  # `builder` above — ADR-0002 says the two variants differ only by resolved model, so a
  # different tool list would be a behavioral difference the ADR forbids. Both shims point
  # at their own canonical body, and .harness/agents/builder-heavy.md is itself a pointer
  # at builder.md, so the instruction text still exists in exactly one place.
  emit_agent builder-heavy "Read, Write, Edit, Bash, Grep, Glob" \
    "The Implementer at the escalation tier. Same instruction body and same discipline as \`builder\`; differs only by the model it resolves to (ADR-0002)."
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
  # Codex comment. GATED on the opt-in pr_loop.enabled — unlike the seven roles above it is
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
   - `in-review` → spawn **reviewer**; approve → open the PR and LEAVE it `in-review`
     (`done` is written only after the work merges — see `agents/orchestrator.md`
     “Writing `done`”), reject → back to `in-progress`.
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

  # /sdd-test-concurrency (OpenCode only) — probes whether this OpenCode session can
  # spawn subagents concurrently. The marker it writes drives whether
  # harness-install.sh stamps /sdd-fix-parallel for OpenCode.
  cat > "$CMDDIR/sdd-test-concurrency.md" <<'EOF'
---
description: Probe whether this OpenCode session can run subagents concurrently
---

Run a concurrency probe. This command spawns two trivial subagents and measures whether
OpenCode executes them in parallel.

1. Run `./.harness/init.sh` from the project root. If it exits non-zero, STOP: the harness
   considers this environment broken and the probe must not write a capability marker.
2. Prepare a temp directory under `.harness/progress/opencode-concurrency-probe/`
   (remove any previous probe first). This lives in the Scout role's allowed output area
   so the subagents do not have to violate their read-only contract.
3. Spawn **two** identical `scout` subagents **in the same response / at the same time**
   using the `task` tool. Give each subagent this exact job, with its own index `N` (1 or
   2) and the temp directory `DIR`:

   - Write `date -u +%FT%T` to `DIR/start-N.txt`
   - Sleep for 5 seconds
   - Write `date -u +%FT%T` to `DIR/end-N.txt`
   - Report completion

   Do not read files, do not run tests, do not modify source code. The only output must
   be the four timestamp files.
4. Wait until **both** subagents finish.
5. Read the four timestamps and compute the wall-clock span from the earliest start to
   the latest end.
   - If the span is **less than 8 seconds**, OpenCode ran the subagents concurrently.
   - Otherwise, OpenCode ran them sequentially.
6. Write the result to `.harness/.opencode-parallel` as exactly one word:
   - `supported`   (concurrent)
   - `sequential`  (sequential)
7. Report the result to the human:
    - **concurrent**: `/sdd-fix-parallel` is supported. Re-run the installer with
      `--with-opencode-parallel=true` to stamp it, or just re-run the installer if the marker
      already says `supported`.
   - **sequential**: `/sdd-fix-parallel` is NOT supported on this OpenCode setup. Use
     serial `/sdd-fix` for bounded fix batches.

This command changes no TaskStore state, no feature status, and no source code.
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

Use a `while` loop so the round counter can be restarted. `round_dir=.harness/.pr-loop/<pr>/round-<round>`;
`max_rounds` is read from `pr_loop.max_rounds` (default 4).

`max_rounds` is a budget for the **PR**, not for one invocation of this command. Resume the
counter from the highest round already in the cache, so re-running `/sdd-pr-loop` cannot
silently grant a fresh budget — PR #86 reached round 12 against `max_rounds: 4` exactly that
way, and the `needs-human` hand-off that should have fired at round 4 never did. The
base-change restart below moves the stale rounds to `stale-<ts>/`, so it correctly
re-derives round 1 on its own.

```bash
round=1
for _d in .harness/.pr-loop/$pr_number/round-*/; do
  [ -d "$_d" ] || continue                       # unmatched glob — no cache yet
  _n="${_d%/}"; _n="${_n##*/round-}"
  case "$_n" in ''|*[!0-9]*) continue ;; esac
  [ "$_n" -ge "$round" ] && round=$((_n + 1))
done
while [ "$round" -le "$max_rounds" ]; do
  round_dir=".harness/.pr-loop/$pr_number/round-$round"
  mkdir -p "$round_dir"
```

### 0. Preflight — BEFORE posting anything

```bash
sh .harness/tools/wait-for-codex.sh preflight "$pr_number"
```

It checks `gh` on PATH, `gh auth status`, `jq` on PATH, a resolvable repo slug, and that
the PR exists and is OPEN. It posts **nothing**. On a non-zero exit (`5`), **STOP** and
report its one-line diagnostic verbatim — do not post `@codex review`, do not poll, do
not fall back to a hand-rolled check. A repo without the Codex GitHub App should leave
`pr_loop.enabled` at its opt-in default of `false` rather than run this loop.

### 0b. Base-change detection (stacked PRs only)

On round 2+, before triggering a new Codex review, check whether the base branch has
changed since the last round — when a stacked PR's parent is rebased (review fixes), the
child's `baseRefOid` moves, and the child must be re-reviewed from scratch (R5).

```bash
# Only stacked PRs (base != default branch) get base-change detection. A PR targeting the
# default branch naturally sees baseRefOid move as other PRs merge; restarting review on
# every such change would destroy the ordinary single-PR lane.
default_branch="$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || echo '')"
# Fetch the current baseRefName fresh — a stacked child may have been retargeted before
# the first review round, and round 1 must validate stack ancestry too.
base_ref="$(gh pr view "$pr_number" --json baseRefName --jq '.baseRefName' 2>/dev/null || echo '')"
if [ -n "$default_branch" ] && [ -n "$base_ref" ] && [ "$base_ref" != "$default_branch" ]; then
  prior_round_dir=".harness/.pr-loop/$pr_number/round-$(( round - 1 ))"
  prior_base_name="$(jq -r '.baseRefName // ""' "$prior_round_dir/pr.json" 2>/dev/null || echo '')"
  prior_base_oid="$(jq -r '.baseRefOid // ""' "$prior_round_dir/pr.json" 2>/dev/null || echo '')"
  if [ -n "$prior_base_name" ] && [ "$prior_base_name" != "$default_branch" ] && [ -n "$prior_base_oid" ]; then
    current_base_oid="$(gh pr view "$pr_number" --json baseRefOid --jq '.baseRefOid' 2>/dev/null || echo '')"
    # Fail closed on either side of the comparison being unreadable — a missing
    # prior cache or a transient API failure must not silently bypass the detection.
    if [ -z "$current_base_oid" ]; then
      echo "base-change detection: could not read current baseRefOid — restarting from round 1" >&2
      stale_dir=".harness/.pr-loop/$pr_number/stale-$(date -u +%s)"
      mkdir -p "$stale_dir"
      for d in .harness/.pr-loop/$pr_number/round-*/; do
        [ -d "$d" ] && mv "$d" "$stale_dir/"
      done
      round=1
      continue
    elif [ "$current_base_oid" != "$prior_base_oid" ]; then
      echo "baseRefOid changed (${prior_base_oid:0:7} -> ${current_base_oid:0:7}) — parent rebased" >&2
      # Verify the child has actually been restacked onto the new parent tip before
      # restarting review. An unrestacked child would be reviewed with superseded parent
      # commits in its diff. The restack procedure is in docs/WORKFLOW.md.
      head_ref_oid="$(gh pr view "$pr_number" --json headRefOid --jq '.headRefOid' 2>/dev/null || echo '')"
      # Fail closed when the head OID is unreadable — an empty head OID must not bypass
      # the ancestry check, because an unrestacked child could then be reviewed with
      # superseded parent commits and merged after its parent lands.
      if [ -z "$head_ref_oid" ]; then
        echo "base-change detection: could not read headRefOid — refusing to restart review" >&2
        gh pr edit "$pr_number" --add-label needs-human >/dev/null 2>&1 || true
        return 1
      fi
      if command -v git >/dev/null 2>&1; then
        # Fetch the refs before checking ancestry — in a fresh or shallow clone, or
        # after a force-push, the OIDs from GitHub may not exist locally and
        # `git merge-base` would exit 128 (error) instead of 1 (non-ancestor).
        git fetch origin --no-tags --depth=50 2>/dev/null || true
        if ! git merge-base --is-ancestor "$current_base_oid" "$head_ref_oid" 2>/dev/null; then
          echo "child has not been restacked onto the new parent tip — restack before restarting review" >&2
          echo "See docs/WORKFLOW.md 'Restack procedure'" >&2
          # Archive the cache and pause, not restart. The child needs a manual rebase.
          stale_dir=".harness/.pr-loop/$pr_number/stale-$(date -u +%s)"
          mkdir -p "$stale_dir"
          for d in .harness/.pr-loop/$pr_number/round-*/; do
            [ -d "$d" ] && mv "$d" "$stale_dir/"
          done
          # Do not continue the loop — the child needs human intervention to restack.
          # Set needs-human and exit.
          gh pr edit "$pr_number" --add-label needs-human >/dev/null 2>&1 || true
          return 1
        fi
      fi
      echo "parent rebased; discarding prior round cache, restarting from round 1" >&2
      # Move the stale round directories out of the active cache path so stall/trend
      # evaluation cannot accidentally consume them. The handover summary still reports
      # their existence, but the active round-1 starts fresh.
      stale_dir=".harness/.pr-loop/$pr_number/stale-$(date -u +%s)"
      mkdir -p "$stale_dir"
      for d in .harness/.pr-loop/$pr_number/round-*/; do
        [ -d "$d" ] && mv "$d" "$stale_dir/"
      done
      round=1
      continue
    fi
  fi
fi
```

If the base changed, discard prior round-cache data for merge-gate evaluation and restart
the round counter from 1. This detection activates only when the PR's `baseRefName` is
not the default branch — a PR targeting `main` has `baseRefOid` that tracks the default
branch's head, which changes on every merge anyway, so the check is inert there.

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

- `pr.json` — `gh pr view --json reviews,comments,statusCheckRollup,headRefOid,baseRefName,baseRefOid`
- `review-comments.json` — `repos/<o>/<r>/pulls/<n>/comments`, paginated + flattened —
  **the inline findings**, anchored to file/line. Returned by neither `--json comments`
  (issue comments only) nor `reviews[*].body` (summary banner only).
- `issue-comments.json` — `repos/<o>/<r>/issues/<n>/comments`, paginated, scanned for a
  clean banner posted past the first 100 comments.
- `reactions.json` — reactions on the `@codex review` comment (Codex reacts 👍 when it
  has nothing to say).
- `trigger-ts.txt` — the freshness anchor, resolved once at startup.

When the watcher exits, the harness re-invokes you. **Record its exit code as the round's
`outcome` (step 2b) and then branch on it** — never re-poll by hand:

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

### 2b. Record the round's OUTCOME — at every terminal state, including the aborts

The moment the watcher exits, write **one word** to `$round_dir/outcome`. Do it on **every**
path out of step 2, including the ones that abort the round without classifying anything.

```bash
case "$watcher_rc" in
  0)   echo findings   > "$round_dir/outcome" ;;   # review landed WITH findings
  3)   echo clean      > "$round_dir/outcome" ;;   # review landed, zero findings
  2|5) echo timeout    > "$round_dir/outcome" ;;   # ceiling hit / no Codex activity at all
  *)   echo unresolved > "$round_dir/outcome" ;;   # usage / precondition error (exit 4)
esac
```

Write `unresolved` on the two **later** aborts that never reach a classification either: the
unreadable-`headRefOid` path in step 3 (`head_ok=0`) and a `pr-gate.sh` `unresolved` verdict
(exit `9`). Every round in the cache ends with exactly one of `findings`, `clean`, `timeout`,
`unresolved` on disk.

**An outcome file is EVIDENCE, and a step that did not observe the review may not overwrite
it.** Two later steps also want to write `unresolved` — step 3 when it cannot read
`headRefOid`, step 5 when the gate reports unreadable input. Before any of them overwrites a
recorded outcome, ask the only question that matters: *does the exit code I am reacting to
actually carry information about whether a review landed?*

- **It does** when the step observed the review state itself. `.harness/tools/pr-gate.sh` exit `9`
  (`unresolved`) is the one such case: the gate ran `wait-for-codex.sh evaluate` against this
  round's own files and nothing resolved. That may replace a recorded outcome.
- **It does not** when the step merely failed to READ something. `.harness/tools/pr-gate.sh` exit `4`
  (`blocking.json` missing or not a JSON array) and a `pr.json` too broken to yield a
  `headRefOid` are statements about the **cache**, not about Codex. A review may well have
  landed and been recorded seconds earlier.

Overwriting in the second case destroys the evidence and then misreports it: the trend files
the round under **NEVER REVIEWED** and sends the operator to check the Codex GitHub App and
the watcher ceiling — for a round where a review demonstrably landed, and where the step that
actually failed is classification. So the later sites use this, never a bare `echo`:

```bash
# outcome_mark_unresolved <round-dir> — record `unresolved` ONLY when nothing has already
# observed a review. A recorded `findings`/`clean` is evidence and survives; the round then
# reads as `reviewed-uncounted` (a review landed, the count is missing), which is both true
# and the remedy the operator needs.
outcome_mark_unresolved() {
  case "$(head -n 1 "$1/outcome" 2>/dev/null | tr -d ' \t\r\n')" in
    findings|clean) : ;;                      # a review landed — do not overwrite evidence
    *) echo unresolved > "$1/outcome" ;;
  esac
}
```

The `case` in step 2b above needs no such guard: the watcher IS the observer, its exit code is
the observation, and it is the FIRST write to the file — there is no evidence there yet to
destroy.

**Why a file for something the length of `blocking.json` seemed to imply.** It did not imply
it. "Reviewed, nothing blocked" and "no review ever landed" are both `[]`, byte for byte.
Measured on araozmd/harness-sdd#141: the rounds went 2 blocking → round 2 **watcher timeout**
(exit `2`, zero Codex activity) → 2 blocking, the timed-out round was recorded as `[]`, and
`pr-round-trend.sh` answered *"converging — the finding rate is coming down. One more round is
rational."* Deleting that one file changed the verdict. The flat 2,2 was the honest signal and
the tool never saw it — so the bias ran toward "spend another round" exactly when review was
**not landing**, and recording a timeout as a clean round was silently rewarded.

**Do NOT "solve" that by omitting `blocking.json` on a timeout.** Then *absent* means two
things as well ("timed out" and "aborted before classifying"), and the trend would answer
`insufficient` — quietly hiding a run that is failing to get reviewed at all. **A timeout is
information: it is recorded, and it is reported.** `.harness/tools/pr-round-trend.sh` keeps
`timeout` and `unresolved` rounds out of the finding **rate** and prints them in their own
block.

### 3. Parse and classify comments

Classification is **code, not prose** (E99-F149): every lane used to hand-roll the same
jq and every copy got a rule subtly wrong. Run the shipped classifier — it is pure and
offline (reads only the round files, invokes no `gh`):

```bash
blocking_set="$(<read pr_loop.blocking_severities from harness.config.yaml>)"  # e.g. "P0,P1"
sh .harness/tools/wait-for-codex.sh classify "$round_dir" "$blocking_set"
classify_rc=$?
```

The set is whatever `pr_loop.blocking_severities` lists — **read it, do not assume it**.
The shipped default is `P0,P1`, but a repo may raise it (a harness that ships *gates* has
good reason to: there, a finding tagged P2 can still mean the gate vouching for something
it never checked). Whatever is NOT in that list is non-blocking for this repo; `nit` is
not in any default.

What the classifier implements (the behavioral contract, owned and tested in
`tools/wait-for-codex.sh` + the harness's own suite — do **not** re-implement it inline):

- It scans **`review-comments.json` (the inline findings)**, plus `pr.json`
  `reviews[*].body` and `issue-comments.json` as **advisory** streams. Codex tags
  severity as a **badge image**, not bare text — e.g.
  `![P2 Badge](https://img.shields.io/badge/P2-yellow?style=flat)`. It matches
  `P0|P1|P2|nit` **case-insensitively** and **word-boundary anchored** anywhere in the
  body (this catches both the badge alt-text/URL form and any bare-text form);
  **first match wins** by position; **default to `P2`** when nothing matches.
- **Only FRESH Codex inline comments count for this round** — the same freshness guard
  the watcher applies (see step 2): filed against the head commit **and**
  `created_at >= trigger.created_at` (read from `trigger-ts.txt`), **and** authored by
  the Codex bot. A stale thread GitHub re-anchored to head, a human comment that merely
  mentions "P1", or a bot comment on another commit can never enter `blocking.json`.
- Fresh Codex `reviews[*].body` / `issue-comments.json` entries carrying a severity tag
  land in `body-findings.json` — **advisory, never blocking**: they have no `path:line`,
  so nothing could act on them, and an unactionable blocker would wedge the round.
- **A head oid it could not read is not a head oid — it fails closed.** On a missing or
  truncated `pr.json` (or a missing findings stream) it exits **6**, removes any stale
  `blocking.json`, and writes nothing.

It writes into the round dir:

```
fresh-comments.json  # inline comments on head, at/after the trigger (raw fresh stream)
comments.json        # the Codex-authored subset, each with a severity attached
blocking.json        # filtered to the CONFIGURED blocking severities — the MERGE GATE reads this
body-findings.json   # advisory severity-tagged review bodies / issue comments (never blocking)
status.json          # statusCheckRollup snapshot
```

With `classify_rc` = 6 there is no `blocking.json` and no `acted.json`: call
`outcome_mark_unresolved "$round_dir"` — **not** a bare `echo`, because a `pr.json` you
could not read is a statement about the cache and not about Codex, so a `findings`/`clean`
the watcher already recorded must survive it — and take the `needs-human` terminal state of
step 5's cap row (label, hand over, return failure). Only `classify_rc` = 0 with an empty
`blocking.json` means "zero fresh blocking findings".

To re-check the round files offline at any point (no `gh`, no network), run
`sh .harness/tools/wait-for-codex.sh evaluate "$round_dir"` — exit `0` findings,
`3` clean, `1` pending, applying exactly the watcher's resolution rules.

**Do NOT write `acted.json` here.** The round's acted-on set is recorded at **dispatch**, in
step 5, and this step must not pre-compute it. Classification answers "what did the
configuration block?"; that answer is `blocking.json` and it is complete. Whether any finding
is *acted on* is not known yet — the gate has not been asked, and its answer can be `merge`,
in which case the round acts on nothing at all. A set written here would record **intent**,
and the round can contradict it two steps later. `acted.json` has to mean *these findings
were acted on* or it is not an honest input to a convergence rate.

### 4. Stall detection

Compare `blocking.json` to the **previous round**'s (`round-<n-1>/blocking.json`) by
comment id (or, if ids are unstable, by `(path, line, severity, body-hash)`). If **any**
blocking comment id appears in both rounds, the fixes are not landing: **escalate to the
`max_rounds - 1` behavior immediately**, even if the current round is 1 or 2.

### 4b. Convergence trend — is the review converging, or just resampling? (E21-F03)

Stall detection above catches the *same* finding surviving a fix. This catches the other
failure: *different* findings arriving at a steady rate, round after round, because the diff
is larger than one review pass can cover.

```bash
# Pass the diff width when it is measurable — see "which remedy" below. Both flags are
# optional; without them the tool keeps its default (split) remedy.
_cs="$(sh .harness/tools/change-size.sh --format json 2>/dev/null || echo '{}')"
_df="$(printf '%s' "$_cs" | jq -r '.total_files // empty' 2>/dev/null || true)"
_dl="$(printf '%s' "$_cs" | jq -r '.total_lines // empty' 2>/dev/null || true)"
sh .harness/tools/pr-round-trend.sh --cache ".harness/.pr-loop/$pr_number" \
   ${_df:+--diff-files "$_df"} ${_dl:+--diff-lines "$_dl"}
```

It reads only `round-*/outcome`, `round-*/acted.json` and `round-*/blocking.json` — files
this loop already writes — no `gh`, no network, no new state. It reports the per-round count,
a verdict, the rounds that were never reviewed, and where the findings concentrate:

| verdict | meaning | what it implies |
|---|---|---|
| `converging` | the rate is coming down | one more round is rational |
| `non-converging` | the last 3 **reviewed** rounds each produced a blocking finding | more rounds will not help — see the remedy it prints |
| `insufficient` | fewer than 3 **reviewed** rounds with a readable count | no conclusion yet |

**Only rounds that were actually reviewed enter the rate.** A round that leaves the rate is
neither counted nor dropped — it is reported, in **one of two blocks that must not be
confused**, because they have opposite remedies:

| block | JSON | means | remedy |
|---|---|---|---|
| `NEVER REVIEWED` | `not_reviewed[]` | `outcome` is `timeout`/`unresolved` — the review did not resolve | the watcher, the ceiling, the Codex App. Another round buys nothing until that is fixed |
| `NOT COUNTED` | `uncounted[]` | there is no number to trend, and the review is **not** what failed: either an `outcome` proves a review landed and the count file is missing/unparseable (`reviewed-uncounted`), or nothing on disk says what happened (`no-record`) | re-derive the round with `wait-for-codex.sh evaluate`, re-run step 3 for that round dir, or rebuild it from the gh API |

Read `NEVER REVIEWED` first; it is the only one of the two that says something is wrong
upstream. A `reviewed-uncounted` round sent to that remedy is an operator inspecting a healthy
component while the broken step goes unnamed. A round with **no** `outcome` on disk but a
readable count (a cache written before this file existed) is different again: it is named
under `unrecorded_rounds[]`, still counted so an old cache still trends, but its verdict is
flagged as possibly optimistic rather than quietly trusted.

**Severity overrides show up as overrides.** The count comes from `acted.json`, so a P2 you
judged blocking is in the rate — and the report says how many of the findings were overrides
and at which severity. The merge gate is unaffected: it still reads `blocking.json`.

**This round's `acted.json` does not exist yet.** It is written at dispatch, in step 5, which
has not run — so the trend sees earlier rounds through what they *acted on* and the current
round through its `blocking.json`. That is the right reading here (nothing has been acted on
yet), and it means the verdict at this point is final for every earlier round and provisional
for this one. **Re-run the trend when you build the handover summary**, after the round has
disposed of its findings; that later verdict is the one that goes into a terminal message.

A flat rate does not mean the fixes are bad. It means the reviewer is sampling a surface
larger than one pass can cover, so another round buys another *sample*, not more confidence —
and a clean round would be indistinguishable from one that happened to land somewhere quiet.
On the PR that motivated this (17,202 additions, twelve rounds), the rate never decayed:
`1 3 1 2 1 3 1 2 2 1 2 1`. Rounds 5–12 cost roughly 2M input tokens and 8 hours to keep
rediscovering that the diff was too big.

**Which remedy a non-converging verdict prints.** "Split this PR" is right for a 17,202-line
diff and unfollowable on a small one — and unfollowable advice teaches operators to ignore the
tool. When the caller supplies `--diff-files` **and** every finding sits in a single file, the
tool says so and recommends changing the region's shape instead of splitting. Without
`--diff-files` it cannot know how wide the diff is, so it keeps the split remedy. (viernes-web
PR #85: 2 files, ~150 lines, all four findings in one function, `SPLIT THIS PR` — the operator
overrode it by hand and wrote the reasoning into the handover.)

This is **advisory and it never blocks**: the tool exits 0 at every verdict, it does not
change when the cap fires, and it never merges or fails a PR on its own. Carry the verdict
into the handover summary, and — at the cap — into the `needs-human` message.

### 5. Branch on round

**Ask the gate FIRST — before branching on the budget.** The verdict already folds the
round budget in, so the table below is a rendering of the gate's answer, not a second
opinion beside it:

```bash
sh .harness/tools/pr-gate.sh evaluate "$round_dir" --round "$round" --max-rounds "$max_rounds"
gate_rc=$?
```

**The gate's verdict is binding, and it is asked exactly ONCE per round.** `merge` (0) means
the review is finished: leave this step entirely, **break the loop before advancing the round
counter**, and go to step 6 then "ready to merge". Breaking preserves the successful `round`
value, so the Ready-to-merge section reads `round-$round/pr.json` from the correct round.
(The one thing that may follow a `merge` verdict without merging is an explicit, recorded
**override** — see "When you judge the badge wrong" below. It does not change what the gate
said, only what this round does about one finding, and it is never taken silently.)
`fix` (6), `escalate` (7) and `needs-human` (8) select the rows below. `unresolved` (9) and
unreadable input (4) both take the `needs-human` terminal state, but they must **not** write
the same thing. Exit `9` is an OBSERVATION — the gate ran `wait-for-codex.sh evaluate` against
this round's own files and nothing resolved — so `echo unresolved > "$round_dir/outcome"` may
replace whatever is there. Exit `4` is a failure to READ `blocking.json` and says nothing
about whether Codex answered, so it calls `outcome_mark_unresolved "$round_dir"` and a
recorded `findings`/`clean` survives: that round is `reviewed-uncounted`, not unreviewed.
Never read an empty `blocking.json` as clean.

The gate answers the budget question from `blocking.json` alone when findings remain, and
proves a review actually landed (via `wait-for-codex.sh evaluate`) only when the blocking set
is empty — because an empty set means two opposite things, "reviewed, nothing blocking" and
"no review landed", and only the first may merge.

**Do not fix non-blocking findings to make the PR look clean.** `blocking.json` is already
filtered to `pr_loop.blocking_severities`; whatever that key omits is excluded **by
configuration, not by oversight**. A non-blocking comment sitting on a PR the gate calls
`merge` is not unfinished work — it is work this loop was told not to do. If it deserves
attention it deserves its own PR, where it gets reviewed on its own diff instead of extending
a review that already converged.

**Which severities those are is a per-repo fact, so read the key.** Under the default `P0,P1`
this rule is about P2 and nit. In a repo that configures `P0,P1,P2`, P2 findings **are**
blocking and this paragraph does not apply to them — treating them as excluded there would
silently defeat the configured threshold and could authorize a merge over real blocking work.

That instruction exists because the loop stopped honouring it. On PR #89 every round reported zero
blocking findings and the loop still spent three rounds and three commits on P2s; on PR #86
rounds 6-8 were clean and it ran to round 12. Across this repo 20 of 43 Codex-fix commits
addressed P2s — roughly half the fix budget spent on findings that never blocked anything.

#### When you judge the badge wrong

`pr_loop.blocking_severities` is a **threshold**, and a threshold can be wrong about one
finding. On viernes-ai/viernes-web PR #85 a Codex **P2** was a live claim-steal race;
merging on the gate's word would have shipped it. That is not the paragraph above — you are
not making the PR look clean, you are answering a defect — and there are exactly **two**
honest moves. *Fix it quietly and say nothing* is neither, and it is what actually happened.

1. **Raise the threshold.** Add the severity to `pr_loop.blocking_severities` and re-run the
   round. The gate then blocks on its own authority and nothing is overridden. Prefer this
   whenever the repo will keep producing findings at that severity — a threshold you override
   every round is a threshold that is simply set wrong.
2. **Override this one finding.** Act on it despite the `merge` verdict, and record it with
   `acted_append … override` below. You are declining the gate's verdict **for this round's
   fix work only**: the gate is asked again next round with the same conservative filter, and
   `blocking.json` is never edited to dress an override up as configuration.

**Recording is not permission.** An `override` row does not authorize the work — it makes the
work *countable*. That is the entire point: three **unrecorded** overrides is how PR #85 spent
four rounds while `pr-round-trend.sh` reported *"no round with a readable blocking.json —
nothing to trend"*, and the one tool built to detect non-convergence stayed silent through a
textbook non-converging run. A non-zero `overrides:` line in that report is a question for the
configuration, not a licence to keep going.

Branching on the budget first is the ordering bug this replaces: at the cap round the
`max_rounds` row stopped with `needs-human` before anything consulted the findings, so a
**clean final round could never merge** — the loop handed a green PR to a human. Only a cap
round that still has blocking findings is a hand-over.

#### Record what this round acted on — at DISPATCH, never in advance

```bash
# acted_append <id> <path> <line> <severity> <configured|override>
#
# Call it at the MOMENT a finding is disposed of as blocking: immediately before handing it
# to a pr-fixer, before starting an in-session fix, or as the cap row lists it as a surviving
# blocking comment. One call, one row, one finding.
acted_append() {
  _a="$round_dir/acted.json"
  [ -s "$_a" ] || printf '[]\n' > "$_a"
  case "${5:-configured}" in override) _ov=true ;; *) _ov=false ;; esac
  jq --argjson id "$1" --arg p "$2" --argjson l "${3:-0}" --arg s "$4" --argjson o "$_ov" \
     '. + [{id:$id, path:$p, line:$l, severity:$s, override:$o}]' "$_a" > "$_a.tmp" \
    && mv "$_a.tmp" "$_a"
}
```

`acted.json` means **these findings were acted on**, and `.harness/tools/pr-round-trend.sh`
uses it as the round's finding count precisely because that is a claim about what happened
rather than about what a filter would have kept. So it is appended by the code paths that *do*
the acting — the three rows below and the in-session variant under them — and by nothing else.
A round that disposes of no finding writes no `acted.json`, and the trend reads its
`blocking.json` instead; a round that acted writes one row per finding, `override: true` on
each one whose severity `pr_loop.blocking_severities` excludes.

**A finding declared blocking is acted on whether or not it was fixed.** The cap row does not
fix anything, but naming a comment in the `needs-human` hand-over is this round's disposition
of it, and leaving those rows out would make the cap round read as a quiet zero — the trailing
zero that turns a flat series back into `converging` on exactly the report that exists to stop
that.

| Round | Behavior |
|---|---|
| below `max_rounds - 1` | For each blocking comment: **`acted_append` it first**, then spawn one **`pr-fixer`** sub-agent, passing it the PR number, comment id, file path, line and body. It commits one fix and writes `fix-<comment_id>.md` into the round dir. After all fixers return, `git push`. |
| `max_rounds - 1` | **`acted_append` every comment going into the prompt**, then build **one combined fix prompt** (all blocking comments concatenated) and escalate to a **different worker** if the host CLI offers one; where no router exists, run one combined **in-session** pass instead. Then push. |
| `max_rounds` (cap) | Stop the loop. `gh pr edit "$pr_number" --add-label needs-human`. **`acted_append` every blocking comment that survived** — the cap round disposes of them by declaring them, not by fixing them. Post the handover summary listing every round, the surviving comments, and the cache path — **and the trend verdict, re-run after these rows exist**. When it is `non-converging`, the message must say what the tool's remedy line says, and must show the per-round series and the concentration list that make the case. Return failure. |

At the default `max_rounds: 4` that is rounds 1–2 per-comment, round 3 combined
escalation, round 4 `needs-human`. A `max_rounds` below `3` simply has no per-comment
fixer rounds.

**Front-ends without a `pr-fixer` sub-agent** (codex, gemini) do not spawn one: apply each
blocking comment's fix **in-session**, under the same discipline — one `acted_append` call,
one comment, one targeted fix, one commit, one `fix-<comment_id>.md` note — then push once at
the end of the round. The absence of a sub-agent changes who writes the code; it does not
change what the round records about the work it did.

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

**Do not ask the gate again.** It was asked once, at step 5, and its verdict is what routed
you here. `blocking.json` still holds THIS round's findings — the fixer commits do not rewrite
it — so a second call necessarily returns `fix`/`escalate` again and sends you back through
step 5 on the same stale set, forever. One round, one verdict.

What remains is to confirm the fix commits did not break anything, then **advance**: bump the
round counter and trigger a fresh `@codex review` (step 1). The new review is what produces
the next round's blocking set.

If checks are still pending, wait for them; if any fail, treat the failure like a blocking
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

### Round advance

After the per-round gates and fixes complete:

```bash
round=$(( round + 1 ))
done
```

A green round breaks **before** this increment — see step 6. The terminal states below
run with `round` pointing at the round that just verified, not one past it.

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

**Re-run the trend here**, not just at step 4b. Every round has now disposed of its findings,
so every `acted.json` that is ever going to exist exists — including the current round's, which
step 4b could not see. The verdict that goes into either terminal message is this one:

```bash
sh .harness/tools/pr-round-trend.sh --cache ".harness/.pr-loop/$pr_number" \
   ${_df:+--diff-files "$_df"} ${_dl:+--diff-lines "$_dl"}
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

**A resolve you could not complete is not a resolve.** The `resolveReviewThread` mutation
can fail on its own — a transient 5xx, a token without write access — and a thread that
stayed unresolved is exactly the review feedback the merge gate exists to protect. So
check **every** mutation's exit status and raise `merge_ok` only once they have **all**
succeeded; branch protection may or may not catch the leftover thread, and this loop must
not depend on it. Mind the shape of the loop while you do: `... | while read` runs its
body in a **subshell** in POSIX sh, so a failure recorded there dies at the `done` and is
silently forgotten. Feed the loop from a here-document instead and it runs in the current
shell, where the flag survives.

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
  # Enumeration completed; every unresolved thread is provably Codex's — resolve them,
  # and raise `merge_ok` only if every mutation actually reported success. The loop reads
  # from a here-document rather than from `printf ... | while`, because a piped loop body
  # is a subshell: `resolve_ok=0` set in there would never reach this shell.
  resolve_ok=1
  while read -r _allcodex tid; do
    [ -z "$tid" ] && continue
    gh api graphql -f query='
      mutation($id:ID!){ resolveReviewThread(input:{threadId:$id}){ thread{ id isResolved } } }' \
      -f id="$tid" >/dev/null || resolve_ok=0   # try the rest, but remember the failure
  done <<UNRESOLVED
$unresolved
UNRESOLVED
  if [ "$resolve_ok" = 1 ]; then
    merge_ok=1        # all requested threads resolved; nothing is left to merge over
  else
    echo "a Codex thread could not be resolved — needs-human, not merging" >&2
  fi
fi
```

**If `merge_ok=0`, stop here** — go straight to the needs-human terminal state and run
**none** of the merge commands below.

While `pr_loop.auto_merge` is **false**, stop after posting the all-gates-green summary
and hand back to the human — resolve threads if you like, but **do not merge**. That
hand-back **completes** the loop: **return success**. It is the one terminal state where an
unmerged PR is the intended outcome, so never route it to needs-human.

Where `pr_loop.auto_merge` is **true**, merge with the configured `merge_strategy`,
deleting the remote branch in the same call. **First, invoke the stacked-PR merge-order
guard (R2):** before `gh pr merge`, fetch the open-PR list and call the offline guard to
verify this PR is not stacked on an unmerged parent. On exit 6, refuse the merge and
enter the `needs-human` terminal state with the guard's diagnostic naming the parent PR.
The guard is called with JSON the pr-loop already fetches; the only additional network
call is a lightweight `gh pr list`.

```bash
# Stacked-PR merge-order guard (E21-F04 R2). Fail closed on every error: a guard that
# cannot prove safety must not authorize a merge.
default_branch="${default_branch:-$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || echo '')}"
guard_ok=1
guard_deferred=0
# Fetch the current baseRefName immediately before authorizing the merge — the PR may
# have been retargeted after the round cache was written, and a stale cached default-
# branch value would bypass the guard entirely for a newly stacked child.
if ! base_ref="$(gh pr view "$pr_number" --json baseRefName --jq '.baseRefName' 2>/dev/null)" || [ -z "$base_ref" ]; then
  guard_ok=0
  echo "sdd-pr-loop: merge refused — could not read current baseRefName" >&2
  gh pr edit "$pr_number" --add-label needs-human >/dev/null 2>&1 || true
elif [ "$base_ref" = "$default_branch" ]; then
  : # targeting the default branch — not stacked, guard_ok stays 1
elif [ -n "$base_ref" ]; then
  open_prs_json=".harness/.pr-loop/$pr_number/open-prs.json"
  if ! gh pr list --state open --json number,headRefName --limit 1000 > "$open_prs_json" 2>/dev/null; then
    guard_ok=0
    echo "sdd-pr-loop: merge refused — could not fetch open PR list" >&2
    gh pr edit "$pr_number" --add-label needs-human >/dev/null 2>&1 || true
  else
    # Refresh pr.json with the current base before evaluating the guard — a PR
    # retargeted after the round cache was written would otherwise be evaluated
    # with stale data.
    gh pr view "$pr_number" --json reviews,comments,statusCheckRollup,headRefOid,baseRefName,baseRefOid > ".harness/.pr-loop/$pr_number/round-$round/pr.json" 2>/dev/null || echo '{}' > ".harness/.pr-loop/$pr_number/round-$round/pr.json"
    guard_rc=0
    sh .harness/tools/pr-stack-guard.sh evaluate ".harness/.pr-loop/$pr_number/round-$round/pr.json" "$open_prs_json" --default-branch "$default_branch" || guard_rc=$?
    if [ "$guard_rc" = 0 ]; then
      : # guard_ok stays 1
    elif [ "$guard_rc" = 6 ]; then
      guard_ok=0
      guard_deferred=1
      echo "sdd-pr-loop: merge deferred — parent PR is still open (guard exit 6)" >&2
      sh .harness/tools/pr-stack-guard.sh evaluate ".harness/.pr-loop/$pr_number/round-$round/pr.json" "$open_prs_json" --default-branch "$default_branch" 2>&1 >&2
    else
      guard_ok=0
      echo "sdd-pr-loop: merge refused — stack guard returned exit $guard_rc" >&2
      sh .harness/tools/pr-stack-guard.sh evaluate ".harness/.pr-loop/$pr_number/round-$round/pr.json" "$open_prs_json" --default-branch "$default_branch" 2>&1 >&2
      gh pr edit "$pr_number" --add-label needs-human >/dev/null 2>&1 || true
    fi
  fi
fi
```

Track whether the merge command itself
**succeeded** (`merged`) — separate from `merge_ok`, which only recorded thread
eligibility — so cleanup never runs on a failed or pending merge:

```bash
merged=0
if [ "${guard_ok:-1}" != "1" ]; then
  if [ "${guard_deferred:-0}" = "1" ]; then
    # Exit 6 from pr-stack-guard.sh — parent is still open, which is a normal
    # waiting state in a healthy stack. Report it and exit gracefully without
    # needs-human; the child retries after the parent lands.
    echo "sdd-pr-loop: merge deferred — parent PR is still open" >&2
  else
    echo "merge-order guard refused — needs-human, not merging" >&2
  fi
elif [ "${merge_ok:-0}" != "1" ]; then
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
`max_rounds` cap, a watcher timeout (exit `2`), an unresolved non-Codex thread, a
stacked-PR merge-order guard refusal (exit `6`), or a merge that would not land.

**Say what the human should conclude.** Include the step-4b trend output **verbatim,
including its `NEVER REVIEWED` block** — a cap reached because reviews kept timing out is a
completely different hand-over from a cap reached on a flat finding rate, and the human cannot
tell them apart from the round count. A `converging` verdict means the loop simply ran out of
rounds and resuming is reasonable. A `non-converging` verdict means more rounds will not help:
state plainly what the tool's remedy line says — **split** the PR when the findings spread
across files, or change the shape of the one region they all land in when they do not — show
the per-round series, and list the files the findings concentrate on. Without this, the
observed human response to the cap is to post
`@codex review` again — which on the PR that motivated this feature happened eight more
times, for roughly 2M input tokens and 8 hours, before anyone concluded the diff was too
large to review in one pass.

**Every path into this state returns failure**, whatever the reason — the only successes
are a merge that actually landed and the `auto_merge: false` hand-back above. So an
unmerged PR is a success **only** when auto-merge was off; when auto-merge was on and the
merge did not land, that is this state, and it is a failure.

## Cache layout

```
.harness/.pr-loop/<pr>/
  round-1/
    pr.json                   # reviews summary, issue comments, checks, head oid, base branch + oid
    review-comments.json      # the inline findings (source of truth)
    issue-comments.json       # paginated issue-comment stream (clean-banner scan)
    reactions.json            # reactions on the @codex trigger comment (👍 = clean)
    trigger-ts.txt            # freshness anchor
    outcome                   # ONE WORD: findings | clean | timeout | unresolved (step 2b)
    fresh-comments.json, comments.json, blocking.json, status.json
    acted.json                # appended at DISPATCH (step 5): one row per finding this round
                              # acted on, severity + override per row. Absent when the round
                              # acted on nothing.
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
    # The concurrency probe is always available so a user can verify /sdd-fix-parallel
    # support before (or after) installing it.
    cp "$CMDDIR/sdd-test-concurrency.md" "$TARGET/.opencode/command/sdd-test-concurrency.md"
    # /sdd-fix-parallel requires native concurrent sub-agent delegation. Without an
    # explicit override or a supported marker from a prior /sdd-test-concurrency run,
    # leave it out of the OpenCode command surface (E22-F01).
    for _c in $HARNESS_SDD_CMDS; do
      if [ "$_c" = "sdd-fix-parallel" ] && ! opencode_parallel_wanted; then
        continue
      fi
      cp "$CMDDIR/$_c.md" "$TARGET/.opencode/command/$_c.md"
    done
    # If a previous run installed /sdd-fix-parallel but the marker now says sequential
    # (or the user forced it off), remove the command ONLY if it is byte-identical to the
    # harness-generated source. A user-authored command with the same name must survive.
    if ! opencode_parallel_wanted; then
      _fp="$TARGET/.opencode/command/sdd-fix-parallel.md"
      if [ -f "$_fp" ]; then
        if cmp -s "$CMDDIR/sdd-fix-parallel.md" "$_fp"; then
          rm -f "$_fp"
          echo "⚠️  removed deselected agent 'opencode' glue: sdd-fix-parallel.md (in .opencode/command/)" >&2
        else
          echo "⚠️  kept user-edited .opencode/command/sdd-fix-parallel.md (not harness-owned)" >&2
        fi
      fi
    fi
    if opencode_parallel_wanted; then
      ok "OpenCode commands /sdd-next + /sdd-new + /sdd-plan + /sdd-drill + /sdd-fix + /sdd-fix-parallel installed (.opencode/)"
    else
      ok "OpenCode commands /sdd-next + /sdd-new + /sdd-plan + /sdd-drill + /sdd-fix + /sdd-test-concurrency installed (.opencode/); /sdd-fix-parallel skipped (run /sdd-test-concurrency, then re-run installer with --with-opencode-parallel=true to add it)"
    fi
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

  # skill_unit_claimed — true while ANY front-end that READS `.agents/skills/` is selected.
  # ADR-0003: a skill unit is ONE shared artifact per command, not one per front-end. Codex
  # discovers repository skills there, and so does Antigravity (its bundled customization
  # guide documents `.agents/skills/<name>/SKILL.md` with `name` + `description`
  # frontmatter — exactly what gen_skill_body emits).
  #
  # ADD A FRONT-END HERE THE MOMENT IT LEARNS TO READ THAT SURFACE. Forgetting fails in the
  # destructive direction and in silence: its units are reclaimed out from under it by the
  # OTHER front-end's deselection, and the pristine-only guard does not save them because
  # they genuinely are pristine — just pristine for someone else.
  skill_unit_claimed() {
    agent_selected codex || agent_selected antigravity
  }

  # gen_skill_body <command> <dest> — adapt the canonical command body to the shared
  # repository-local skill format. The adapter explicitly maps text accompanying the
  # `$skill` mention to the canonical body's `$ARGUMENTS` term.
  gen_skill_body() {
    _gcs_name="$1"; _gcs_dest="$2"; _gcs_src="$CMDDIR/$_gcs_name.md"
    _gcs_desc="$(sed -n 's/^description: //p' "$_gcs_src" | sed -n '1p')"
    {
      printf '%s\n' '---'
      printf 'name: %s\n' "$_gcs_name"
      printf 'description: %s\n' "$_gcs_desc"
      printf '%s\n' '---'
      printf '\n## Invocation adapter\n\n'
      printf 'When explicitly invoked — as `$%s` (Codex'"'"'s spelling) or `/%s` (Antigravity'"'"'s) — treat all text accompanying that mention as the value of `$ARGUMENTS` in the canonical instructions below.\n' "$_gcs_name" "$_gcs_name"
      printf '\n## Canonical workflow\n'
      sed -n '5,$p' "$_gcs_src"
    } > "$_gcs_dest"
  }

  gen_codex_skill_policy() {
    cat > "$1" <<'EOF'
policy:
  allow_implicit_invocation: false
EOF
  }

  # A skill unit is an ownership unit rooted in a shared repository namespace, claimed by
  # every front-end that reads it (ADR-0003). Reject any symlinked writable component or
  # destination file before generation, comparison, stamping, reclamation, or writes.
  skill_unit_destination_is_symlinked() {
    _csd_cmd="$1"
    _csd_live="$TARGET/.agents/skills/$_csd_cmd"
    [ -L "$TARGET/.agents" ] \
      || [ -L "$TARGET/.agents/skills" ] \
      || [ -L "$_csd_live" ] \
      || [ -L "$_csd_live/SKILL.md" ] \
      || [ -L "$_csd_live/agents" ] \
      || [ -L "$_csd_live/agents/openai.yaml" ]
  }

  codex_skill_stamp_is_symlinked() {
    _css_cmd="$1"
    _css_stamp="$H/.codex-skills/$_css_cmd"
    codex_skill_stamp_tree_is_symlinked "$_css_cmd" \
      || [ -L "$_css_stamp/SKILL.md" ] \
      || [ -L "$_css_stamp/agents" ] \
      || [ -L "$_css_stamp/agents/openai.yaml" ]
  }

  codex_skill_stamp_tree_is_symlinked() {
    _cst_stamp="$H/.codex-skills/$1"
    [ -L "$H/.codex-skills" ] \
      || [ -L "$_cst_stamp" ]
  }

  codex_skill_stamp_leaf_is_symlinked() {
    _csl_cmd="$1"
    _csl_rel="$2"
    codex_skill_stamp_tree_is_symlinked "$_csl_cmd" && return 0
    case "$_csl_rel" in
      agents/openai.yaml)
        [ -L "$H/.codex-skills/$_csl_cmd/agents" ] \
          || [ -L "$H/.codex-skills/$_csl_cmd/$_csl_rel" ]
        ;;
      *)
        [ -L "$H/.codex-skills/$_csl_cmd/$_csl_rel" ]
        ;;
    esac
  }

  discard_codex_skill_stamp() {
    _dcs_stamp="$H/.codex-skills/$1"
    if codex_skill_stamp_is_symlinked "$1"; then
      echo "⚠️  .harness/.codex-skills/$1 has a symlinked stamp component — ownership stamp left unchanged" >&2
      return 0
    fi
    rm -f "$_dcs_stamp/SKILL.md" "$_dcs_stamp/agents/openai.yaml"
    rmdir "$_dcs_stamp/agents" 2>/dev/null || true
    rmdir "$_dcs_stamp" 2>/dev/null || true
    [ -L "$H/.codex-skills" ] || rmdir "$H/.codex-skills" 2>/dev/null || true
  }

  # install_skill_unit <command> — manage SKILL.md + agents/openai.yaml as one
  # ownership unit. Both artifacts are updated only when each existing path is current
  # generated output or matches its last-written stamp.
  #
  # The policy companion is written UNCONDITIONALLY, including where `codex` is not
  # selected (ADR-0003). Codex discovers repository skills from the directory itself, not
  # from this installer's front-end selection, so a SKILL.md on disk WITHOUT its
  # explicit-only companion is an implicitly-invocable mutating workflow for anyone who
  # runs Codex in that repo. The reclaim path already encodes this reasoning in the other
  # direction ("a surviving SKILL.md retains its companion"); this keeps it symmetric.
  # To Antigravity the file is an unrecognised optional sibling and therefore inert.
  #
  # `$H/.codex-skills/` keeps its historical name on purpose — see ADR-0003. Renaming it
  # orphans the ownership proof on every installed target, after which each live unit
  # reads as "foreign or edited" and becomes permanently unreclaimable.
  install_skill_unit() {
    _ics_cmd="$1"
    _ics_live="$TARGET/.agents/skills/$_ics_cmd"
    _ics_stamp="$H/.codex-skills/$_ics_cmd"
    if skill_unit_destination_is_symlinked "$_ics_cmd"; then
      echo "⚠️  .agents/skills/$_ics_cmd has a symlinked destination component — selected Codex install left the skill unit unchanged" >&2
      discard_codex_skill_stamp "$_ics_cmd"
      return 0
    fi
    if codex_skill_stamp_is_symlinked "$_ics_cmd"; then
      echo "⚠️  .harness/.codex-skills/$_ics_cmd has a symlinked stamp component — selected Codex install left the live skill unit and stamp unchanged" >&2
      return 0
    fi
    _ics_tmp="$(mktemp -d 2>/dev/null || mktemp -d -t harness-codex-skill)"
    mkdir -p "$_ics_tmp/agents"
    gen_skill_body "$_ics_cmd" "$_ics_tmp/SKILL.md"
    gen_codex_skill_policy "$_ics_tmp/agents/openai.yaml"
    _ics_safe=1
    for _ics_rel in SKILL.md agents/openai.yaml; do
      _ics_dest="$_ics_live/$_ics_rel"
      _ics_ref="$_ics_tmp/$_ics_rel"
      _ics_old="$_ics_stamp/$_ics_rel"
      if [ ! -e "$_ics_dest" ]; then
        :
      elif [ -f "$_ics_dest" ] && [ -f "$_ics_old" ] \
           && cmp -s "$_ics_dest" "$_ics_old"; then
        :
      elif [ -f "$_ics_dest" ] && cmp -s "$_ics_dest" "$_ics_ref"; then
        :
      else
        _ics_safe=0
      fi
    done
    if [ "$_ics_safe" = 0 ]; then
      echo "⚠️  .agents/skills/$_ics_cmd is a foreign or edited skill unit — selected Codex install left SKILL.md and agents/openai.yaml unchanged" >&2
      rm -rf "$_ics_tmp"
      return 0
    fi
    mkdir -p "$_ics_live/agents" "$_ics_stamp/agents"
    cat "$_ics_tmp/SKILL.md" > "$_ics_live/SKILL.md"
    cat "$_ics_tmp/agents/openai.yaml" > "$_ics_live/agents/openai.yaml"
    cp "$_ics_live/SKILL.md" "$_ics_stamp/SKILL.md"
    cp "$_ics_live/agents/openai.yaml" "$_ics_stamp/agents/openai.yaml"
    rm -rf "$_ics_tmp"
    return 0
  }

  # reclaim_skill_units <command-list> — reclaim each proven path independently.
  # A stamp-owned SKILL.md remains removable when its companion is missing/edited.
  # Conversely, when an edited SKILL.md survives, retain its policy companion so the
  # still-discoverable mutating workflow does not become implicitly invocable.
  reclaim_skill_units() {
    _rcs_cmds="$1"; _rcs_gone=""
    for _rcs_cmd in $_rcs_cmds; do
      _rcs_live="$TARGET/.agents/skills/$_rcs_cmd"
      _rcs_stamp="$H/.codex-skills/$_rcs_cmd"
      _rcs_skill="$_rcs_live/SKILL.md"
      _rcs_skill_stamp="$_rcs_stamp/SKILL.md"
      _rcs_policy="$_rcs_live/agents/openai.yaml"
      _rcs_policy_stamp="$_rcs_stamp/agents/openai.yaml"
      _rcs_skill_survives=0

      if skill_unit_destination_is_symlinked "$_rcs_cmd"; then
        echo "⚠️  .agents/skills/$_rcs_cmd has a symlinked destination component — skill unit left in place" >&2
        discard_codex_skill_stamp "$_rcs_cmd"
        continue
      fi
      if codex_skill_stamp_tree_is_symlinked "$_rcs_cmd"; then
        echo "⚠️  .harness/.codex-skills/$_rcs_cmd has a symlinked stamp directory component — live skill unit and ownership stamps left unchanged" >&2
        continue
      fi

      if [ -e "$_rcs_skill" ]; then
        if codex_skill_stamp_leaf_is_symlinked "$_rcs_cmd" SKILL.md; then
          _rcs_skill_survives=1
          echo "⚠️  .harness/.codex-skills/$_rcs_cmd/SKILL.md is a symlinked stamp leaf — corresponding live skill and stamp left unchanged" >&2
        elif [ -f "$_rcs_skill" ] && [ -f "$_rcs_skill_stamp" ] \
           && cmp -s "$_rcs_skill" "$_rcs_skill_stamp"; then
          rm -f "$_rcs_skill"
          _rcs_gone="$_rcs_gone .agents/skills/$_rcs_cmd/SKILL.md"
        else
          _rcs_skill_survives=1
          echo "⚠️  .agents/skills/$_rcs_cmd/SKILL.md has no matching last-written stamp (foreign or edited) — left in place" >&2
        fi
      fi

      if [ -e "$_rcs_policy" ]; then
        if codex_skill_stamp_leaf_is_symlinked "$_rcs_cmd" agents/openai.yaml; then
          echo "⚠️  .harness/.codex-skills/$_rcs_cmd/agents/openai.yaml is a symlinked stamp leaf — corresponding live policy and stamp left unchanged" >&2
        elif [ "$_rcs_skill_survives" = 1 ]; then
          echo "⚠️  .agents/skills/$_rcs_cmd/agents/openai.yaml retained as the explicit-only policy companion of the surviving SKILL.md" >&2
        elif [ -f "$_rcs_policy" ] && [ -f "$_rcs_policy_stamp" ] \
             && cmp -s "$_rcs_policy" "$_rcs_policy_stamp"; then
          rm -f "$_rcs_policy"
          _rcs_gone="$_rcs_gone .agents/skills/$_rcs_cmd/agents/openai.yaml"
        else
          echo "⚠️  .agents/skills/$_rcs_cmd/agents/openai.yaml has no matching last-written stamp (foreign or edited) — left in place" >&2
        fi
      fi
      if ! codex_skill_stamp_leaf_is_symlinked "$_rcs_cmd" SKILL.md; then
        rm -f "$_rcs_stamp/SKILL.md"
      fi
      if ! codex_skill_stamp_leaf_is_symlinked "$_rcs_cmd" agents/openai.yaml; then
        rm -f "$_rcs_stamp/agents/openai.yaml"
      fi
      rmdir "$_rcs_stamp/agents" 2>/dev/null || true
      rmdir "$_rcs_stamp" 2>/dev/null || true
      rmdir "$_rcs_live/agents" 2>/dev/null || true
      rmdir "$TARGET/.agents/skills/$_rcs_cmd" 2>/dev/null || true
    done
    [ -L "$H/.codex-skills" ] || rmdir "$H/.codex-skills" 2>/dev/null || true
    rmdir "$TARGET/.agents/skills" 2>/dev/null || true
    rmdir "$TARGET/.agents" 2>/dev/null || true
    [ -n "$_rcs_gone" ] && printf '%s\n' "$_rcs_gone"
    return 0
  }

  # migrate_legacy_codex_prompts — retire the pre-0.48 machine-global prompt surface.
  # The directory is resolved only for migration and is never created. Ungated prompts
  # are always ownership-unknown and therefore preserved. The gated prompt requires both
  # byte identity and a readable ownership ledger proving there are no live owners.
  migrate_legacy_codex_prompts() {
    _mlc_dir="$(codex_prompts_dir)"
    [ -n "$_mlc_dir" ] && [ -d "$_mlc_dir" ] || return 0
    _mlc_removed=""
    for _mlc_cmd in $HARNESS_OWNED_CMDS; do
      _mlc_file="$_mlc_dir/$_mlc_cmd.md"
      [ -f "$_mlc_file" ] || continue
      if ! _is_pr_loop_cmd "$_mlc_cmd"; then
        echo "⚠️  legacy Codex prompt $_mlc_file has unknown cross-target ownership — preserved" >&2
        continue
      fi
      if ! cmp -s "$_mlc_file" "$CMDDIR/$_mlc_cmd.md"; then
        echo "⚠️  legacy Codex prompt $_mlc_file differs from the generated legacy reference (edited) — preserved" >&2
        continue
      fi
      if ! _owners_release "$_mlc_dir" "$_mlc_cmd"; then
        echo "⚠️  legacy Codex prompt $_mlc_file has live or unknown ownership — preserved" >&2
        continue
      fi
      rm -f "$_mlc_file"
      _mlc_removed="$_mlc_removed $_mlc_cmd.md"
    done
    rmdir "$_mlc_dir" 2>/dev/null || true
    [ -n "$_mlc_removed" ] \
      && echo "⚠️  migrated byte-pristine legacy Codex prompts:$_mlc_removed" >&2
    return 0
  }

  # ── 5d. Shared repository skill units (gated on ANY claiming front-end) ──────
  # BOTH Codex and Antigravity discover project skills under
  # `.agents/skills/<name>/SKILL.md`, and one generated unit satisfies both contracts —
  # so this writes ONE shared unit per command rather than one per front-end (ADR-0003).
  # The surface is fully repository-local and never requires or writes HOME / CODEX_HOME.
  # The old global prompts resolver remains below only for safe migration.
  if skill_unit_claimed; then
    _cdx_cmds="$HARNESS_SDD_CMDS"
    if pr_loop_enabled; then _cdx_cmds="$HARNESS_OWNED_CMDS"; fi
    for _c in $_cdx_cmds; do
      install_skill_unit "$_c"
    done
    ok "shared skill units \$sdd-next + \$sdd-new + \$sdd-plan + \$sdd-drill + \$sdd-fix + \$sdd-fix-parallel installed (.agents/skills/ — project-local, read by Codex + Antigravity)"
  fi
  if agent_selected codex || printf '%s\n' "$PRIOR_AGENTS" | grep -qx codex; then
    migrate_legacy_codex_prompts
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
      # Stamp safety is bookkeeping-only for Gemini: a rejected ownership stamp must
      # never suppress its established selected live-role generation semantics.
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

  # ── 5f. Codex per-role agent definitions (gated only on selected `codex`) ──────
  # Role registration is independent from model routing: all seven project-local TOMLs
  # always exist for selected Codex. `gen_codex_agent` omits `model` when the role
  # inherits or its tier is unpinned, and adds it only for a concrete resolved pin.
  if agent_selected codex; then
    _codex_agent_tmp="$(mktemp 2>/dev/null || mktemp -t harness-codex-agent)"
    if codex_agent_tree_is_symlinked; then
      echo "⚠️  .codex/agents has a symlinked destination component — selected Codex install left role definitions unchanged" >&2
      ag_personas | while IFS='	' read -r _cxr _cxd; do
        [ -n "$_cxr" ] || continue
        discard_codex_agent_stamp "$_cxr.toml"
      done
    else
      ag_personas | while IFS='	' read -r _cxr _cxd; do
        [ -n "$_cxr" ] || continue
        if codex_agent_destination_is_symlinked "$_cxr.toml"; then
          echo "⚠️  .codex/agents/$_cxr.toml is a symlinked destination — selected Codex install left it unchanged" >&2
          discard_codex_agent_stamp "$_cxr.toml"
          continue
        fi
        gen_codex_agent "$_cxr" "$_cxd" "$_codex_agent_tmp"
        install_codex_agent "$_cxr.toml" "$_codex_agent_tmp"
      done
    fi
    rm -f "$_codex_agent_tmp"
    # Whatever the loop above did or declined to do, this asks the only question the arming
    # verdict cares about: are the two Builder roles on disk what we just generated?
    verify_codex_builder_roles_stamped
    ok "Codex per-role agent definitions installed (.codex/agents/ — project-local)"
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
      # E17-F02: a THIRD candidate — the body the PREVIOUS release generated. Without it,
      # adding a role to the `agent:` map locks every already-installed target out
      # permanently: on-disk is the old shape, no stamp exists yet (pre-E17-F02 the stamp
      # was kept only for bodies carrying a model key), the generated reference is the new
      # shape, so nothing matches, so the file is never rewritten, so it never gains the
      # stamp that would let it be rewritten. Verified against v0.55.0.
      _oc_legacy="$(mktemp 2>/dev/null || mktemp -t harness-ocl)"
      gen_opencode_legacy "$_oc_legacy"
      if { [ -f "$H/.opencode.stamp" ] && ! opencode_stamp_is_symlinked \
           && cmp -s "$TARGET/opencode.json" "$H/.opencode.stamp"; } \
         || cmp -s "$TARGET/opencode.json" "$_oc_free" \
         || cmp -s "$TARGET/opencode.json" "$_oc_legacy"; then
        cat "$_oc_new" > "$TARGET/opencode.json"
        _oc_written=1
        info "opencode.json regenerated (pristine harness stamp; model routing applied)"
      else
        echo "⚠️  opencode.json differs from the generated stamp (edited) — left untouched; model routing changes were NOT applied" >&2
      fi
      rm -f "$_oc_free" "$_oc_legacy"
    fi
    # The stamp records WHAT WE LAST WROTE, unconditionally (E17-F02). It used to be kept
    # only for bodies carrying a model key, on the reasoning that "a model-free body is
    # already reproducible from gen_opencode_json" — true only for the installer VERSION
    # that wrote it, which adding a role falsifies. Stamping every write is what makes the
    # legacy candidate above a one-off rather than the first entry in a growing list: from
    # here on, a shape change is provable from the stamp alone. Same mechanism, and the
    # same reason, as the Codex role TOMLs — a fresh body cannot prove a same-named file is
    # ours. This REVISES E17-F01 R11 in one clause: an unconfigured target now carries
    # .harness/.opencode.stamp. R11's substance holds — the stamp is harness-owned metadata
    # inside .harness/ (beside .agents and .harness-version), it is removed on deselect
    # (§7), and an all-`inherit` target stays diff -r-identical to one whose models: block
    # was stripped, because both grow the same stamp.
    if [ "$_oc_written" = 1 ]; then
      if opencode_stamp_is_symlinked; then
        # NEVER `cp` through the link: that overwrites its target, which may be outside the
        # repository entirely. Leave both the link and its target untouched and say so — the
        # next run simply re-derives pristineness from the generated bodies, exactly as a
        # target with no stamp does.
        echo "⚠️  .harness/.opencode.stamp is a symlink — ownership stamp not written (link and its target left unchanged)" >&2
      else
        cp "$TARGET/opencode.json" "$H/.opencode.stamp"
      fi
    fi
    # Same question, asked the same way: is the live opencode.json what we just generated?
    # Outcome rather than intent — this also catches a write that silently did not land,
    # which `_oc_written` alone would report as success.
    cmp -s "$TARGET/opencode.json" "$_oc_new" 2>/dev/null || mark_unstamped opencode
    rm -f "$_oc_new"
  fi

  # ── 6b. escalation arming verdict (E17-F05) ─────────────────────────────────
  # Placed AFTER every per-front-end artifact has been generated (§5e/§5f/§6) so that
  # resolve_model's run-scoped warn-once ledger has already emitted its diagnostics: the
  # verdict calls resolve_model again and would otherwise be the first caller for a
  # front-end that generates nothing, moving a diagnostic to a confusing place.
  write_escalation_arming
  rm -f "$_UNSTAMPED_FILE"

  # ── 6c. worker roster (E17-F04) ─────────────────────────────────────────────
  # Placed after §2 (so the target's harness.config.yaml exists and the gate is readable)
  # and after the selection is resolved (so `harness-selected` has its evidence). It reads
  # $AGENT_KEYS, $WORKER_INVOKE, $HOST_MARKERS and $SELECTED and writes one derived data
  # file; it stamps nothing, executes nothing, and no other stage depends on it.
  write_worker_roster

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
          # Pristine-only removal: a user-authored file with the same name as a harness
          # command (e.g. a custom sdd-fix-parallel.md) must survive OpenCode deselection.
          _oc_tmp="$(mktemp 2>/dev/null || mktemp -t harness-oc)"
          _oc_removed=''
          for _oc_cmd in $HARNESS_OWNED_CMDS sdd-test-concurrency; do
            _oc_rel="$(remove_if_pristine ".opencode/command/$_oc_cmd.md" "$CMDDIR/$_oc_cmd.md" opencode)"
            [ -n "$_oc_rel" ] && _oc_removed="$_oc_removed $_oc_cmd.md"
          done
          # E18-F01 R4/R7: `.opencode/agent/` is a pr_loop-owned dir. Compare the pr-fixer
          # shim against a freshly-generated body, then rmdir the subdir and the parent —
          # each only when empty, so a user's own file-based agent survives.
          gen_oc_agent pr-fixer "$PR_FIXER_DESC" "$_oc_tmp"
          _oc_rel="$(remove_if_pristine ".opencode/agent/pr-fixer.md" "$_oc_tmp" opencode)"
          [ -n "$_oc_rel" ] && _oc_removed="$_oc_removed pr-fixer.md"
          rm -f "$_oc_tmp"
          [ -n "$_oc_removed" ] && echo "⚠️  removed deselected agent 'opencode' glue:$_oc_removed (in .opencode/)" >&2
          rmdir "$TARGET/.opencode/agent" 2>/dev/null || true
          rmdir "$TARGET/.opencode/command" 2>/dev/null || true
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
            # E17-F02: also accept the body a PREVIOUS release generated, or deselecting on
            # a target installed before this release would misreport a pristine file as
            # edited and leave it behind. Same candidate, same reason, as §5g.
            _ref_legacy="$(mktemp 2>/dev/null || mktemp -t harness-ocl)"
            gen_opencode_legacy "$_ref_legacy"
            if { [ -f "$H/.opencode.stamp" ] && ! opencode_stamp_is_symlinked \
                 && cmp -s "$TARGET/opencode.json" "$H/.opencode.stamp"; } \
               || cmp -s "$TARGET/opencode.json" "$_ref" \
               || cmp -s "$TARGET/opencode.json" "$_ref_legacy"; then
              rm -f "$TARGET/opencode.json"
              rm -f "$H/.opencode.stamp"
              echo "⚠️  removed deselected agent 'opencode' glue: opencode.json (pristine generated)" >&2
            else
              echo "⚠️  opencode.json differs from the generated stamp (edited) — left in place (deselected 'opencode' not removed)" >&2
            fi
            rm -f "$_ref" "$_ref_legacy"
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
          # Shared skill units (ADR-0003, E99-F09 R5): Antigravity is a CLAIMANT of
          # `.agents/skills/`, so its deselection reclaims those units — but ONLY when no
          # other claimant remains. With `codex` still selected the unit is still live glue
          # for it, and reclaiming here would delete another front-end's working commands
          # (the exact failure this decision exists to prevent). Reclaim is idempotent, so
          # deselecting BOTH front-ends in one run simply finds the paths already gone.
          if ! agent_selected codex; then
            _agskills_gone="$(reclaim_skill_units "$HARNESS_OWNED_CMDS")"
            [ -n "$_agskills_gone" ] \
              && echo "⚠️  removed deselected agent 'antigravity' skill units:$_agskills_gone" >&2
          fi
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
          # Symmetric to the antigravity case above (ADR-0003, E99-F09 R4): the skill unit
          # is SHARED, so it survives Codex's deselection while Antigravity still claims it.
          # Its `agents/openai.yaml` companion goes with it and is NOT reclaimed separately —
          # a surviving, still-discoverable SKILL.md without the explicit-only policy would
          # become implicitly invocable for anyone who runs Codex in the repo, which is the
          # same reasoning the partial-unit reclaim below already applies to edited units.
          if ! agent_selected antigravity; then
            _cdx_removed="$(reclaim_skill_units "$HARNESS_OWNED_CMDS")"
            [ -n "$_cdx_removed" ] \
              && echo "⚠️  removed deselected agent 'codex' skills:$_cdx_removed" >&2
          fi
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
  # dirs and byte-pristine comparison inside the shared `.agents/` tree — then prune only
  # dirs left empty.
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
    # ANY claiming front-end, not just codex (ADR-0003, E99-F09 R6): the gated unit is
    # shared, so an antigravity-only target would otherwise keep an orphaned
    # `.agents/skills/sdd-pr-loop/` advertising a loop the operator turned off.
    if skill_unit_claimed; then
      _prl_gone="$_prl_gone $(reclaim_skill_units "$HARNESS_PR_LOOP_CMDS")"
    fi
    if [ -n "$(printf '%s' "$_prl_gone" | tr -d '[:space:]')" ]; then
      echo "⚠️  pr_loop.enabled is not true — reclaimed /sdd-pr-loop glue:$_prl_gone" >&2
    fi
  fi

  # ── stale slash-command references (2026-09-04, warn-only) ──────────────────
  # A target's hand-written prose (CLAUDE.md outside the harness block, AGENTS.md,
  # GEMINI.md) can keep invoking a command a past harness version installed — the
  # observed case is `/pr-loop`, the pre-E18 name of `/sdd-pr-loop`: sessions read the
  # entrypoint, follow the stale reference, and hunt for a skill that no longer exists.
  # The harness owns only its marked block, so it cannot rewrite user prose — but it CAN
  # name the divergence. Scan for /sdd-* tokens not in the current generation set ($CMDDIR is
  # the complete, version-authoritative command list), plus the known-renamed /pr-loop.
  for _sr_f in CLAUDE.md AGENTS.md GEMINI.md; do
    [ -f "$TARGET/$_sr_f" ] || continue
    _sr_refs="$(grep -oE '/(sdd-[a-z-]+|pr-loop)\b' "$TARGET/$_sr_f" 2>/dev/null | sort -u || true)"
    [ -n "$_sr_refs" ] || continue
    printf '%s\n' "$_sr_refs" | while IFS= read -r _sr_tok; do
      _sr_name="${_sr_tok#/}"
      if [ "$_sr_name" = "pr-loop" ]; then
        echo "⚠️  $_sr_f references \`/pr-loop\`, which this harness does not install — the current command is \`/sdd-pr-loop\` (gated by pr_loop.enabled). Update the reference. (warn-only)" >&2
        continue
      fi
      # A gated-OFF command is unavailable even though $CMDDIR holds its body — the
      # bodies are generated unconditionally as the reclamation reference, so the
      # existence check alone would suppress this warning exactly when the gate-off
      # pass has removed the command from every installed surface (Codex #160 round-5).
      _sr_gated=0
      for _sr_prc in $HARNESS_PR_LOOP_CMDS; do
        [ "$_sr_name" = "$_sr_prc" ] && _sr_gated=1
      done
      if [ "$_sr_gated" = 1 ] && ! pr_loop_enabled; then
        echo "⚠️  $_sr_f references \`$_sr_tok\`, but pr_loop.enabled is not true, so that command is not installed on any surface. Enable the gate or update the reference. (warn-only)" >&2
        continue
      fi
      [ -f "$CMDDIR/$_sr_name.md" ] \
        || echo "⚠️  $_sr_f references \`$_sr_tok\`, which v$VERSION does not generate — a stale reference sends sessions hunting for a missing skill. Update or remove it. (warn-only)" >&2
    done
  done

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
# Diagnostic only (E19-F01): report what `--agents=host` WOULD resolve to for a target,
# then exit 0 without touching anything. Single-target mode only.
PRINT_AGENTS=0
# Agent selection override (E08-F01): --agents=<csv> wins over HARNESS_AGENTS, which
# wins over the interactive prompt / no-TTY ALL default. Seed from the environment so
# `--agents` (parsed below) can supersede it; an empty value means "no override".
AGENTS_OVERRIDE="${HARNESS_AGENTS:-}"
# Builder backend override (E20-F01): --builder-backend=<value> wins over
# HARNESS_BUILDER_BACKEND, which wins over the interactive follow-up prompt / the target's
# current value. Seeded from the environment so the flag (parsed below) can supersede it;
# an empty value means "no override", exactly like --agents=.
BUILDER_BACKEND_OVERRIDE="${HARNESS_BUILDER_BACKEND:-}"
# PR review loop override (E20-F02): --pr-loop=<true|false> wins over the interactive
# third question, which wins over the target's current value.
#
# SEEDED FROM NOTHING — there is deliberately NO environment twin, and in particular this
# is NOT seeded from HARNESS_PR_LOOP_ENABLED. That variable is E18-F01's PER-RUN gate
# override, documented in harness.config.yaml, docs/INSTALL.md, README.md and the
# /sdd-pr-loop body as one of five per-run knobs (HARNESS_AUTO_MERGE, HARNESS_MAX_ROUNDS,
# …). Making one member of that family persist while the other four stay per-run is an
# inconsistency no reader can infer from the name, and it turns
# `HARNESS_PR_LOOP_ENABLED=false ./harness-install.sh <target>` from "don't stamp on this
# run" into "permanently disable this target's loop". The layering is: the FLAG (and the
# prompt) persists, the ENV overrides the run — with one warning at §2c when they disagree.
PR_LOOP_OVERRIDE=""

# OpenCode parallel-fix override (E22-F01): --with-opencode-parallel=<true|false>
# forces the /sdd-fix-parallel command to be (or not be) stamped for the OpenCode
# front-end. Without the flag, the installer reads the marker written by the
# /sdd-test-concurrency command: supported → stamp, absent/sequential → skip.
# This keeps a command that requires concurrent subagents off OpenCode installs that
# cannot satisfy it. Default is "auto" (read marker). Explicit true/false override.
OPENCODE_PARALLEL_OVERRIDE=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --pr-loop=*)
      # Explicit override; an empty value (`--pr-loop=`) is treated as "no override"
      # (fall through to the prompt / no-op), matching --agents= and --builder-backend=.
      PR_LOOP_OVERRIDE="${1#--pr-loop=}"
      shift
      ;;
    --pr-loop)
      [ "$#" -ge 2 ] || die "usage: $0 --pr-loop=<true|false>"
      PR_LOOP_OVERRIDE="$2"
      shift 2
      ;;
    --with-opencode-parallel=*)
      OPENCODE_PARALLEL_OVERRIDE="${1#--with-opencode-parallel=}"
      shift
      ;;
    --with-opencode-parallel)
      [ "$#" -ge 2 ] || die "usage: $0 --with-opencode-parallel=<true|false>"
      OPENCODE_PARALLEL_OVERRIDE="$2"
      shift 2
      ;;
    --builder-backend=*)
      # Explicit override; an empty value (`--builder-backend=`) is treated as "no
      # override" (fall through to the prompt / no-op), matching HARNESS_BUILDER_BACKEND="".
      BUILDER_BACKEND_OVERRIDE="${1#--builder-backend=}"
      shift
      ;;
    --builder-backend)
      [ "$#" -ge 2 ] || die "usage: $0 --builder-backend=<in-session|delegate>"
      BUILDER_BACKEND_OVERRIDE="$2"
      shift 2
      ;;
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
    --print-agents)
      # Diagnostic (E19-F01, R23): print `host=<detected key or empty>` and
      # `baseline=<keys>` for <target> and exit 0, creating/modifying NOTHING. It is the
      # answer to "what would --agents=host do here?" and the only way to observe
      # detection without installing. Single-target mode only (R24).
      PRINT_AGENTS=1
      shift
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

# Validate the builder-backend override HERE — after the parse loop, before target
# resolution and before any install_one — so an illegal value aborts non-zero with
# nothing created or modified in the target (E20-F01 R5). A typo'd flag in a script is
# silent, which is why this aborts where the interactive prompt merely keeps the current
# value: at a prompt a human sees the outcome on the next line and re-runs.
case "${BUILDER_BACKEND_OVERRIDE:-}" in
  ""|in-session|delegate) ;;
  *) die "unknown builder backend '$BUILDER_BACKEND_OVERRIDE' — legal values are 'in-session' and 'delegate' (--builder-backend=<value> / HARNESS_BUILDER_BACKEND)" ;;
esac

# Same place, same reason, for the pr_loop override (E20-F02 R4): an illegal value aborts
# non-zero here — after the parse loop, before target resolution and before any
# install_one — so nothing is created or modified in the target. A typo'd flag in a script
# is silent, which is why this aborts where the interactive prompt merely keeps the current
# value.
case "${PR_LOOP_OVERRIDE:-}" in
  ""|true|false) ;;
  *) die "unknown pr_loop value '$PR_LOOP_OVERRIDE' — legal values are 'true' and 'false' (--pr-loop=<value>)" ;;
esac

# OpenCode parallel-fix override validation (E22-F01). Same abort-before-write discipline.
case "${OPENCODE_PARALLEL_OVERRIDE:-}" in
  ""|true|false) ;;
  *) die "unknown --with-opencode-parallel value '$OPENCODE_PARALLEL_OVERRIDE' — legal values are 'true' and 'false'" ;;
esac

# ── single-target mode (no --umbrella): behave exactly as before ──────────────
if [ -z "$UMBRELLA" ]; then
  [ "$DRY_RUN" = 0 ] || die "--dry-run/--list is umbrella-mode only (use with --umbrella)"
  [ "$SHARED_REPO" = 0 ] || die "--shared-repo is umbrella-mode only (use with --umbrella)"
  if [ "${POSITIONAL}" = "" ]; then die "usage: $0 <target-repo-path>"; fi
  TGT="$POSITIONAL"
  if [ ! -d "$TGT" ]; then die "target '$TGT' is not a directory"; fi
  TGT="$(CDPATH= cd -- "$TGT" && pwd)"
  if [ "$TGT" = "$SRC" ]; then die "target must differ from the harness source ($SRC)"; fi
  if [ "$PRINT_AGENTS" = 1 ]; then
    # Diagnostic short-circuit (R23): two lines on stdout, then exit 0 — BEFORE
    # install_one, so nothing is created or modified anywhere, on a TTY or off it, on a
    # fresh dir or an installed target. Both values come from the same helpers the real
    # resolution uses (detect_host / precheck_baseline), so this can never disagree with
    # what a real run would do (R26) — including on a fresh target that carries orphan
    # `.harness/.agents` metadata with no version stamp, where the answer is ALL and the
    # persisted file is not it.
    #
    # `baseline=` is precheck_baseline, i.e. exactly what the interactive picker would
    # pre-check here (E19-F02 R6) — which is also what an undetected `--agents=host` run
    # falls back to, since host_fallback_set defers to this same helper for an existing
    # install and both branches answer ALL otherwise. On a DETECTED run the two readings
    # differ only where the old value was a hypothetical: it used to report the
    # if-undetected fallback even though detection had just succeeded, so a fresh target
    # inside Claude Code advertised all five while `--agents=host` installed one.
    #
    # Detection runs EXACTLY ONCE here and the verdict is handed to precheck_baseline
    # (which would otherwise detect again for a target with no existing install). Its
    # stderr diagnostics are one-per-run by contract — the ambiguity line for competing
    # markers (E19-F01 R5) and the invalid-HARNESS_HOST_AGENT warning (R10) — and a
    # second call printed each of them twice. The verdict is passed DOWN as an argument,
    # never cached in a global, so no state survives this block.
    _pa_host="$(detect_host)"
    printf 'host=%s\n' "$_pa_host"
    printf 'baseline=%s\n' "$(precheck_baseline "$TGT" "$_pa_host" | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
    exit 0
  fi
  install_one "$TGT"
  exit 0
fi

# ── umbrella mode (cascade) ───────────────────────────────────────────────────
# --print-agents is a single-target diagnostic: it reports on ONE target's baseline, and a
# cascade has no single baseline to report. Reject the combination before anything is
# written or discovered (R24).
[ "$PRINT_AGENTS" = 0 ] || die "usage: $0 --print-agents <target-repo-path> (single-target mode only; not valid with --umbrella)"
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
  # E24-F03 R1: tell the child where its umbrella is.
  #
  # DERIVED FROM THE PHYSICAL PATH, never hard-coded. A hard-coded `../../` is right only
  # when the child is a real directory at depth 1: this loop deliberately accepts a
  # SYMLINKED child (see the source-identity check above, which resolves `child_abs` with
  # `pwd -P` precisely because a child may be a link). For one of those, `..` from the
  # child's `.harness/` is resolved by the kernel against the link's TARGET, so `../../`
  # lands outside the umbrella entirely — the child then installs a full body AND persists
  # an unreachable `umbrella.root`. Reproduced before fixing. (Codex r3 P2 #3705849222.)
  #
  # A RELATIVE value keeps the whole umbrella tree movable, so it stays the normal case;
  # the absolute physical path is the fallback for a child that resolves outside the
  # umbrella, where no relative path would survive the link anyway.
  #
  # Set and UNSET explicitly rather than `VAR=v install_one …`: a variable assignment
  # prefixing a FUNCTION call persists after the function returns in POSIX sh, so the
  # prefix form would leave every later target — including a coordinator re-install —
  # believing it is a child of something.
  _umb_phys="$(CDPATH= cd -- "$UMB" && pwd -P)"
  case "$child_abs" in
    "$_umb_phys"/*)
      # One `../` to leave `.harness/`, then one per component of the child's path under
      # the umbrella (normally just the child's own directory name).
      _crel="${child_abs#"$_umb_phys"/}"
      _ucomp=1
      while : ; do
        case "$_crel" in
          */*) _crel="${_crel#*/}"; _ucomp=$((_ucomp + 1)) ;;
          *)   break ;;
        esac
      done
      HARNESS_UMBRELLA_ROOT=""
      _ui=0
      while [ "$_ui" -le "$_ucomp" ]; do
        HARNESS_UMBRELLA_ROOT="../$HARNESS_UMBRELLA_ROOT"
        _ui=$((_ui + 1))
      done
      ;;
    *)
      # The child resolves outside the umbrella (a symlink to a repo elsewhere). Record the
      # absolute physical umbrella path — umbrella_body_dir accepts either form.
      HARNESS_UMBRELLA_ROOT="$_umb_phys"
      ;;
  esac
  install_one "$UMB/$name"   # R10
  unset HARNESS_UMBRELLA_ROOT
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

# (e) landing audit (E24-F02) — "complete" must mean STATE REACHED, not files written.
#
# The cascade used to print its green banner after WRITING files, with no opinion about
# whether any of it was committed. A real five-child cascade produced exactly that banner
# and left 26-29 uncommitted files in every child, indefinitely: agents there then read
# agent prompts no commit describes, and three children ran the change-size classifier
# against a committed config with no change_size block while migrate_config had already
# appended it on disk. Nothing failed. That is the defect.
#
# E24-F01 made the CONSUMER notice (init.sh refuses to run on an unlanded harness). This is
# the producing side, so the guard is a backstop rather than the normal way anyone finds out
# — one operator upgrading N repos in one command is exactly where N-way manual follow-up
# gets skipped.
#
# It REPORTS; it never commits. Committing into N repos the operator did not ask you to
# commit into is a far larger claim on their working tree, and the constraints it would have
# to honour (never stage unrelated work, never touch a foreign branch) are the accidents this
# whole epic exists to prevent.
echo "── landing audit ──"

# audit_one <target-dir> <label> — print this target's line; echo "unlanded" on stdout's
# LAST line only when it is. Kept as a function so the pathspec list can be expanded through
# positional parameters inside a subshell: `git status` has no --pathspec-from-file, and the
# specs carry `:(exclude)` / `:(glob)` / `:(literal)` magic plus a target path that may
# contain spaces, so neither word-splitting nor xargs is safe here.
audit_one() {
  _t="$1"; _label="$2"
  if ! git -C "$_t" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf '   no git    %-26s (not a work tree — cannot verify)\n' "$_label"
    return 2
  fi
  _spec="$("$SRC/tools/harness-owned-paths.sh" all "$_t/.harness" 2>/dev/null || true)"
  if [ -z "$_spec" ]; then
    printf '   no spec   %-26s (ownership helper unavailable — cannot verify)\n' "$_label"
    return 2
  fi
  # Is ANY owned path git-ignored? Ask git for the COMPLETE set, then subtract the ignores
  # the harness deliberately seeds itself.
  #
  # A body git cannot see has nothing in the index, so `git status` reports no entries even
  # immediately after the cascade wrote all of it: the audit would print `landed` and claim
  # the target committed over a body that was never committed. A false CLEAN is the worst
  # output this audit can emit.
  #
  # THREE narrower probes were tried across three review rounds, and each missed a real case:
  #   ls-files-empty          a FRESH cascade also has nothing tracked — identical state to
  #                           an ignored body, opposite meaning; broke the primary case.
  #   check-ignore .harness   misses a partially-ignored body (`.harness/tools/`).
  #   witness files           samples a few paths, so an ignored subtree containing none of
  #                           them (`.harness/docs/`, `.claude/commands/`) slipped through.
  #
  # Each fix was a narrower sample and each invited the next gap, so this one inverts the
  # question: take git's COMPLETE ignored set over the owned pathspecs and subtract the
  # short, deliberate local-only list. New body subtrees are then covered automatically; only
  # a new deliberate ignore needs maintenance, in the one file that owns that knowledge.
  # `-z` below, not the default porcelain: git QUOTES any path containing whitespace,
  # non-ASCII bytes, backslashes or control characters — `".harness/custom/my log.jsonl"` —
  # and the subtraction patterns are built from raw config values, so a quoted path never
  # matched and the target reported "cannot verify" forever. `-z` emits raw paths, which
  # sidesteps git's whole quoting grammar rather than reimplementing its C-style unescaping
  # (which `core.quotePath` also influences). The NUL delimiters are turned into newlines
  # for the line-oriented filter below — but embedded newlines are neutralised FIRST.
  #
  # `tr '\0' '\n'` alone was wrong, and not in the safe direction I first claimed: it splits
  # a path containing a literal newline into two lines, the second loses the `!! ` prefix and
  # is dropped by the sed, and if the FIRST fragment happens to match a local-only pattern
  # (`telemetry.jsonl` followed by a newline, say) the whole record is subtracted and the
  # target reports `landed`. A false CLEAN, not an over-count.
  #
  # Under `-z` a newline can ONLY appear inside a path — records are NUL-terminated and git
  # emits no newline delimiters — so mapping newlines to \001 before splitting on NUL is
  # unambiguous, keeps each record whole, and needs no NUL-aware tooling (BSD awk cannot take
  # NUL as RS, and this installer is POSIX sh with no new dependencies).
  #
  # LC_ALL=C for the whole pipeline because these are RAW BYTES, not text. A filename may
  # hold bytes that are not valid in the ambient locale; a multibyte-aware `grep` may then
  # refuse to match — or drop — the line, silently changing the count, and BSD `sed` fails
  # outright with an illegal byte sequence. Byte semantics are what every stage here wants,
  # and the repo already takes the same precaution in tools/run-tests.sh.
  _lo="$("$SRC/tools/harness-owned-paths.sh" local-only "$_t/.harness" 2>/dev/null || true)"
  _lo_alt="$(printf '%s' "$_lo" | tr '\n' '|' | sed 's/|$//')"
  [ -n "$_lo_alt" ] || _lo_alt='$^'        # match nothing rather than everything if empty
  _ign=$(
    # ONE locale for the whole pipeline, not per command. Every stage below consumes raw
    # bytes, and prefixing only some of them is how the previous attempt left `sed` in the
    # ambient locale after fixing both greps — on BSD sed that is an illegal-byte-sequence
    # failure, not a mismatch. Export once; nothing here wants text semantics.
    LC_ALL=C; export LC_ALL
    set --
    while IFS= read -r _p; do [ -n "$_p" ] && set -- "$@" "$_p"; done <<ISPEC
$_spec
ISPEC
    GIT_OPTIONAL_LOCKS=0 git -C "$_t" status --porcelain -z -uall --ignored=matching -- "$@" 2>/dev/null \
      | tr '\n' '\001' | tr '\0' '\n' | sed -n 's/^!! //p' | grep -Ev "$_lo_alt" | grep -c '' || true
  )
  if [ "${_ign:-0}" -gt 0 ]; then
    printf '   no vcs    %-26s (%s owned path(s) git-ignored — cannot verify)\n' "$_label" "$_ign"
    return 2
  fi
  # -uall for the reason E99-F10 established: an upgrade that ADDS a body file leaves it
  # untracked, and status.showUntrackedFiles=no would hide exactly the divergence being audited.
  #
  # GIT_OPTIONAL_LOCKS=0 because R9 says this audit never writes a target's git state, and a
  # plain `git status` does: install_one removes and recopies the body immediately before
  # this call, so tracked-file mtimes all change and status rewrites `.git/index` to refresh
  # its stat cache. That is a real write, on every idempotent landed cascade. The variable is
  # git's documented way to suppress exactly that opportunistic write.
  # A status that FAILED is not a status that found nothing. `git status` can exit non-zero
  # on a corrupt or unreadable index, and piping it straight into `grep -c` discarded that:
  # the count came back 0 and the audit printed `landed` over a target it never inspected —
  # a false CLEAN, the one output this audit must never produce. Check the exit status and
  # emit a sentinel instead of a count.
  _n=$(
    # Same byte locale as the ignore probe. This query uses DEFAULT porcelain, which quotes
    # unusual paths and is therefore ASCII — but only while `core.quotePath` is on, and that
    # is a config the operator can turn off. With it off, raw bytes reach `grep -c` here too,
    # and a dropped line under-counts, which tips a divergent target toward `landed`.
    LC_ALL=C; export LC_ALL
    set --
    while IFS= read -r _p; do [ -n "$_p" ] && set -- "$@" "$_p"; done <<SPEC
$_spec
SPEC
    if _st="$(GIT_OPTIONAL_LOCKS=0 git -C "$_t" status --porcelain -uall -- "$@" 2>/dev/null)"; then
      # An empty status is 0 changes; `printf '' | grep -c ''` would say 1.
      if [ -z "$_st" ]; then printf '0\n'; else printf '%s\n' "$_st" | grep -c '' || true; fi
    else
      printf 'ERR\n'
    fi
  )
  if [ "$_n" = "ERR" ]; then
    printf '   no read   %-26s (git status failed — cannot verify)\n' "$_label"
    return 2
  fi
  if [ "${_n:-0}" -gt 0 ]; then
    printf '   unlanded  %-26s %s harness-owned path(s)\n' "$_label" "$_n"
    return 1
  fi
  printf '   landed    %-26s\n' "$_label"
  return 0
}

_audit_unlanded=0
_audit_unverified=0
_audit_total=0
# Fed from a here-document, not a pipe: `... | while read` runs its body in a SUBSHELL in
# POSIX sh, so every counter incremented in there would die at the `done`.
while IFS= read -r _c; do
  [ -n "$_c" ] || continue
  _audit_total=$((_audit_total + 1))
  # 0 landed, 1 unlanded, 2 unverifiable — counted separately so the closing line can
  # state what was actually established rather than over-claiming.
  _rc=0
  if [ "$_c" = "." ]; then
    audit_one "$UMB" "(coordinator)" || _rc=$?
  else
    audit_one "$UMB/$_c" "$_c" || _rc=$?
  fi
  case "$_rc" in
    1) _audit_unlanded=$((_audit_unlanded + 1)) ;;
    2) _audit_unverified=$((_audit_unverified + 1)) ;;
  esac
done <<AUDIT
.
$INSTALLED_CHILDREN
AUDIT

echo "══════════════════════════════════════════════════"
if [ "$_audit_unlanded" -gt 0 ]; then
  echo "   coordinator: $UMB/.harness   manifest: $MANIFEST"
  echo "❌ install: the cascade wrote an upgrade that is NOT COMMITTED in $_audit_unlanded of $_audit_total target(s)." >&2
  echo "   Commit the harness files in each, or agents there run on a body no commit describes." >&2
  echo "   Nothing was committed for you — this installer never writes to a target's git state." >&2
  # Exit 3, deliberately NOT the generic die() code 1: "the install broke" and "the install
  # succeeded and is unlanded" are different outcomes, and a wrapper or CI job that cannot
  # tell them apart loses the only information that makes the code actionable.
  exit 3
fi
if [ "$_audit_unverified" -gt 0 ]; then
  # Say only what was established. "every target committed" over a target whose body could
  # not be inspected is the same over-claim, one level up, that this whole epic is about.
  ok "umbrella cascade complete (v$VERSION) — $((_audit_total - _audit_unverified)) of $_audit_total target(s) verified committed, $_audit_unverified not verifiable"
else
  ok "umbrella cascade complete (v$VERSION) — every target committed"
fi
echo "   coordinator: $UMB/.harness   manifest: $MANIFEST"
