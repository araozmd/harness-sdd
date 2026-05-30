#!/bin/sh
# harness-install.sh — install or upgrade the agent harness into a target repo.
#
#   ./harness-install.sh <target-repo-path>
#
# Idempotent: run once to install, re-run to upgrade.
#
#   - The harness BODY (agents, docs, store, templates, init.sh, config, AGENTS.md)
#     is copied into <target>/.harness/ and OVERWRITTEN on every run.
#   - PROJECT-authored content (specs/product.md, state/tasks.json, specs/epics,
#     progress) is seeded once on a fresh install and NEVER clobbered on upgrade.
#   - Claude Code glue (.claude/) and the entrypoint pointer blocks in
#     CLAUDE.md / AGENTS.md / GEMINI.md are regenerated each run; existing prose in
#     those files is preserved (only the marked block is replaced).
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

# ── args ────────────────────────────────────────────────────────────────────
if [ "${1:-}" = "" ]; then die "usage: $0 <target-repo-path>"; fi
TARGET="$1"
if [ ! -d "$TARGET" ]; then die "target '$TARGET' is not a directory"; fi
TARGET="$(CDPATH= cd -- "$TARGET" && pwd)"
if [ "$TARGET" = "$SRC" ]; then die "target must differ from the harness source ($SRC)"; fi

H="$TARGET/.harness"
UPGRADE=0
if [ -f "$H/.harness-version" ]; then UPGRADE=1; fi

echo "── harness install v$VERSION → $TARGET ──"
if [ "$UPGRADE" = 1 ]; then info "existing install (v$(cat "$H/.harness-version")) — upgrading"; fi
mkdir -p "$H"

# ── 1. harness body → .harness/  (verbatim, overwritten each run) ─────────────
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
copy specs/_templates
copy specs/glossary.md
chmod +x "$H/init.sh" 2>/dev/null || true
# NOTE: harness.config.yaml is intentionally NOT copied here — it is seeded once
# below (project-owned), so upgrades never erase bootstrap-set verification commands.
ok "harness body installed (.harness/)"

# ── 2. project workspace → .harness/  (seed once, never clobber) ──────────────
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
ok "project workspace ready (.harness/specs, state, progress)"

# ── 3. version stamp + manifest ───────────────────────────────────────────────
printf '%s\n' "$VERSION" > "$H/.harness-version"
cat > "$H/manifest.txt" <<EOF
harness-sdd install manifest — v$VERSION
Generated by harness-install.sh. Do not edit by hand.

HARNESS-OWNED  (overwritten on every upgrade):
  .harness/AGENTS.md  .harness/init.sh
  .harness/agents/  .harness/docs/  .harness/store/  .harness/specs/_templates/
  .harness/specs/glossary.md
  .claude/agents/*  .claude/commands/sdd-next.md   (repo root, regenerated)
  CLAUDE.md / AGENTS.md / GEMINI.md  -> only the harness:begin..end block

PROJECT-OWNED  (seeded once, never clobbered on upgrade):
  .harness/harness.config.yaml   (verification commands + store backend)
  .harness/init.project.sh       (project-specific init.sh gate checks)
  .harness/specs/product.md  .harness/specs/epics/
  .harness/state/tasks.json  .harness/progress/
EOF

# ── 4. entrypoint pointer blocks (idempotent marked region) ───────────────────
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

# ── 5. Claude Code sub-agent shims + /sdd-next (regenerated each run) ──────────
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

$ARGUMENTS may name a specific feature id (e.g. `E02-F01`); if given, operate on it.
EOF
ok "Claude Code agents + /sdd-next installed (.claude/)"

# ── 6. opencode.json (create if absent; never clobber an existing one) ────────
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

# ── done ──────────────────────────────────────────────────────────────────────
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
