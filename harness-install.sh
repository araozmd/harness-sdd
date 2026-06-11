#!/bin/sh
# harness-install.sh — install or upgrade the agent harness into a target repo.
#
#   ./harness-install.sh <target-repo-path>
#   ./harness-install.sh --umbrella <umbrella-dir> [--shared-repo] [--recursive] [--dry-run|--list]
#
# Idempotent: run once to install, re-run to upgrade.
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
      printf '    provider: ""          # ""|none disables; github-projects implemented; jira|azure-boards stubs\n'
      printf '    owner: ""             # github-projects: org/user login\n'
      printf '    project_number: 0     # github-projects: Project number\n'
      printf '    repo: ""              # github-projects: owner/repo holding the issues\n'
      printf '    # status_map:         # optional: harness status -> board column name (omit ⇒ identity)\n'
      printf '    #   pending: "Todo"\n'
      printf '    #   done: "Done"\n'
    } >> "$_cfg"
  fi
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

# _mc_insert_after <file> <header-regex> <line>  — insert <line> immediately after the
# first line matching <header-regex>, leaving every other line byte-for-byte intact.
_mc_insert_after() {
  _f="$1"; _re="$2"; _line="$3"
  awk -v re="$_re" -v add="$_line" '
    { print }
    !done && $0 ~ re { print add; done=1 }
  ' "$_f" > "$_f.mctmp" && mv "$_f.mctmp" "$_f"
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
    info "seeded harness.config.yaml (verification commands blank)"
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
  _ignores='telemetry.jsonl'
  case "$_tlog" in
    ''|telemetry.jsonl|/*) : ;;                 # default, unset, or absolute → nothing extra
    *) _ignores="$_ignores
$_tlog" ;;                                       # relative override → also ignore it
  esac
  if [ ! -f "$H/.gitignore" ]; then
    { printf '# Local-only telemetry log (see .harness/agents/orchestrator.md "## Telemetry").\n'
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
  # (.claude/settings.local.json), a scheduler lock (.claude/scheduled_tasks.lock), and
  # browser-MCP scratch at the PROJECT ROOT — none of which belong in VCS, while the
  # harness-GENERATED .claude/agents and .claude/commands DO. Seed/extend the project-root
  # .gitignore with TARGETED, append-only ignores (never clobbering existing entries), so a
  # shared repo stays free of one developer's local state. Full model:
  # .harness/docs/CONFIG-LAYERING.md.
  _root_ignores='.claude/settings.local.json
.claude/scheduled_tasks.lock'
  if [ ! -f "$TARGET/.gitignore" ]; then
    { printf '# Personal/runtime agent state — never commit (see .harness/docs/CONFIG-LAYERING.md).\n'
      printf '%s\n' "$_root_ignores"
      printf '# Per-tool MCP scratch dirs your setup may create — add your own (example):\n'
      printf '#.playwright-mcp/\n'; } > "$TARGET/.gitignore"
    info "seeded project-root .gitignore (personal/runtime agent state)"
  else
    printf '%s\n' "$_root_ignores" | while IFS= read -r _pat; do
      [ -n "$_pat" ] || continue
      grep -qF "$_pat" "$TARGET/.gitignore" || printf '%s\n' "$_pat" >> "$TARGET/.gitignore"
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
  CLAUDE.md / AGENTS.md / GEMINI.md  -> only the harness:begin..end block

PROJECT-OWNED  (seeded once, never clobbered on upgrade):
  .harness/harness.config.yaml   (verification commands + store backend)
  .harness/init.project.sh       (project-specific init.sh gate checks)
  .harness/specs/product.md  .harness/specs/epics/
  .harness/state/tasks.json  .harness/progress/
  umbrella.manifest.yaml         (umbrella mode only: coordinator manifest)
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
3. Product/source code lives at the repo root; harness bookkeeping lives in
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
  write_pointer CLAUDE.md
  write_pointer AGENTS.md
  write_pointer GEMINI.md
  ok "entrypoint pointers written (CLAUDE.md, AGENTS.md, GEMINI.md)"

  # ── 5. Claude Code sub-agent shims + /sdd-next (regenerated each run) ────────
  mkdir -p "$TARGET/.claude/agents" "$TARGET/.claude/commands"
  emit_agent() { # emit_agent <name> <tools> <description>
    cat > "$TARGET/.claude/agents/$1.md" <<EOF
---
name: $1
description: $3
tools: $2
---

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
  emit_agent architect "Read, Write, Edit, Grep, Glob, Bash" \
    "The Spec Author. Writes the 4-file spec in EARS. No production code."
  emit_agent builder "Read, Write, Edit, Bash, Grep, Glob" \
    "The Implementer. Writes code from an APPROVED spec, one task at a time."
  emit_agent reviewer "Read, Bash, Grep, Glob, Edit" \
    "The Evaluator. Verifies against the spec, runs tests, approves or rejects."
  emit_agent scout "Read, Grep, Glob, Bash" \
    "Read-only codebase reconnaissance. Writes findings to progress/."

  cat > "$TARGET/.claude/commands/sdd-next.md" <<'EOF'
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

$ARGUMENTS may name a specific feature id (e.g. `E01-F01`); if given, operate on it.
EOF

  cat > "$TARGET/.claude/commands/sdd-new.md" <<'EOF'
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

  cat > "$TARGET/.claude/commands/sdd-plan.md" <<'EOF'
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
   `.harness/specs/epics/<id>-<slug>/epic.md` = title + one-paragraph business brief
   only (no `F01`, no feature spec).
8. **Re-validate** `.harness/state/tasks.json` against
   `.harness/store/tasks.schema.json`. If it fails, report the failure and do NOT claim
   a successful plan.
9. **Report** the artifacts written (`.harness/specs/vision.md`,
   `.harness/specs/architecture.md`, each `.harness/specs/adr/NNNN-*.md`), the seeded
   `draft` epics (ids + titles + `epic.md` paths), and tell the human to **run
   `/sdd-drill <epic-id>`** next. Do NOT spawn the Architect, do NOT write any feature
   spec, and do NOT advance any epic past `draft` — the Planner produces, never specs.
EOF

  cat > "$TARGET/.claude/commands/sdd-drill.md" <<'EOF'
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
8. **Re-validate** `.harness/state/tasks.json` against `.harness/store/tasks.schema.json`. If
   it fails, report the failure and do NOT claim a successful drill.
9. Present the **single epic-level decision** (one decision, not per feature):
   - **approve** → flip the epic `draft → planned` and stamp `autonomous: true` on every
     seeded feature (all-or-nothing); or
   - **keep gated** → flip the epic `draft → planned`, leaving every seeded feature
     `autonomous: false` so each parks at the per-feature spec-approval gate.
   Re-validate again after the flip/stamp.
10. **Report** the seeded features (ids + titles + `spec_path`s), the inbox briefs + ADR
    ids, any ADR deltas, and the decision taken; tell the human to **run `/sdd-next`** to
    execute. Do NOT spawn the Architect, do NOT write any feature `.spec/.plan/.tasks/.tests`,
    and advance ONLY the target epic to `planned` — the Driller decomposes, never specs.
EOF

  cat > "$TARGET/.claude/commands/sdd-fix.md" <<'EOF'
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
   the intended fix, and how to verify. Where the shape forks, offer **at most 3** options
   as **text-only** (markdown/ASCII) mockups — never images. Keep it short.
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
   (problem + intended fix + how to verify) from
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
  ok "Claude Code agents + /sdd-next + /sdd-new + /sdd-plan + /sdd-drill + /sdd-fix installed (.claude/)"

  # ── 5b. OpenCode commands (regenerated each run) ────────────────────────────
  # Claude Code reads .claude/commands/; OpenCode reads .opencode/command/. Mirror
  # the just-written command bodies there so /sdd-next, /sdd-new, /sdd-plan,
  # /sdd-drill and /sdd-fix show up in OpenCode too. With no `agent:` frontmatter the command runs
  # under the primary agent, which is the orchestrator in the opencode.json below.
  mkdir -p "$TARGET/.opencode/command"
  cp "$TARGET/.claude/commands/sdd-next.md"  "$TARGET/.opencode/command/sdd-next.md"
  cp "$TARGET/.claude/commands/sdd-new.md"   "$TARGET/.opencode/command/sdd-new.md"
  cp "$TARGET/.claude/commands/sdd-plan.md"  "$TARGET/.opencode/command/sdd-plan.md"
  cp "$TARGET/.claude/commands/sdd-drill.md" "$TARGET/.opencode/command/sdd-drill.md"
  cp "$TARGET/.claude/commands/sdd-fix.md"   "$TARGET/.opencode/command/sdd-fix.md"
  ok "OpenCode commands /sdd-next + /sdd-new + /sdd-plan + /sdd-drill + /sdd-fix installed (.opencode/)"

  # ── 6. opencode.json (create if absent; never clobber an existing one) ──────
  if [ ! -f "$TARGET/opencode.json" ]; then
    cat > "$TARGET/opencode.json" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "instructions": [".harness/AGENTS.md"],
  "agent": {
    "orchestrator": { "mode": "primary",  "description": "The Leader: routes the next task, delegates. Never writes code.", "prompt": "{file:./.harness/agents/orchestrator.md}" },
    "architect":    { "mode": "subagent", "description": "Spec Author: writes the 4-file spec (EARS).",                     "prompt": "{file:./.harness/agents/architect.md}" },
    "builder":      { "mode": "subagent", "description": "Implementer: writes code from an approved spec.",                 "prompt": "{file:./.harness/agents/builder.md}" },
    "reviewer":     { "mode": "subagent", "description": "Evaluator: verifies against the spec, runs tests.",               "prompt": "{file:./.harness/agents/reviewer.md}" },
    "scout":        { "mode": "subagent", "description": "Read-only recon; writes findings to progress/.",                  "prompt": "{file:./.harness/agents/scout.md}" }
  }
}
EOF
    ok "opencode.json created"
  else
    info "opencode.json exists — left untouched (point it at .harness/ manually if you use OpenCode)"
  fi

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
while [ "$#" -gt 0 ]; do
  case "$1" in
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
