#!/bin/sh
# harness-owned-paths.sh — the SINGLE definition of "which paths does the harness own".
#
# Prints git pathspecs, one per line, for callers that need to ask git about the installed
# harness. Two consumers, and the whole point is that they cannot disagree:
#
#   init.sh                 the E24-F01 drift guard — is the installed body committed?
#   harness-install.sh      the E24-F02 post-cascade landing audit — same question, N targets
#
# It existed inline in init.sh first. E99-F10 then needed FOUR corrections to that set in its
# first week — `.codex`/`.gemini` claimed wholesale, symlinked ledgers, non-regular ledger
# entries, wildcard basenames — and every one of them was a FALSE POSITIVE that failed the
# mandatory gate on a file the operator owns. A second inline copy in the installer would
# have had to relearn all four. Hence one file.
#
# Usage:
#   harness-owned-paths.sh body <harness-dir>   the installed body, minus project-owned
#   harness-owned-paths.sh all  <harness-dir>   body + generated front-end glue
#
#   <harness-dir> is the directory holding the harness (a target's `.harness/`, or the
#   repository root in the harness source layout). Pathspecs are printed RELATIVE TO THE
#   PROJECT ROOT — the parent of `.harness/`, or the harness dir itself in source layout —
#   because that is the directory the caller runs git from.
#
# Exit: 0 always on a valid mode; 2 on usage error. Prints nothing but pathspecs on stdout.

set -eu

mode="${1:-}"
hdir="${2:-}"
case "$mode" in
  body|all) ;;
  *) echo "usage: $0 <body|all> <harness-dir>" >&2; exit 2 ;;
esac
[ -n "$hdir" ] || { echo "usage: $0 <body|all> <harness-dir>" >&2; exit 2; }

# In an installed target the body lives under `.harness/`, so every pathspec carries that
# prefix. In the harness SOURCE layout there is no `.harness/` — the body is the repo root —
# and the guard is inert there anyway (no version stamp), but the prefix must still resolve.
case "$hdir" in
  */.harness) pfx=".harness/" ;;
  *)          pfx="" ;;
esac

# ── the installed body, minus PROJECT-OWNED paths ────────────────────────────────────────
# Ownership is expressed as an EXCLUSION, never as an enumeration of the ~29 owned files:
# enumerating would duplicate harness-install.sh's knowledge in a second place and silently
# drop out of scope on the next feature that adds a body file. The project-owned set is
# short, stable, and documented in the install manifest ("PROJECT-OWNED (seeded once, never
# clobbered on upgrade)").
#
# `telemetry.jsonl` needs no exclusion — the installer seeds `.harness/.gitignore` for it.
# `umbrella.manifest.yaml` is project-owned and simply never listed.
emit_body() {
  printf '%s\n' "$pfx"
  printf ':(exclude)%sharness.config.yaml\n' "$pfx"
  printf ':(exclude)%sinit.project.sh\n'     "$pfx"
  printf ':(exclude)%sspecs/product.md\n'    "$pfx"
  printf ':(exclude)%sspecs/epics/\n'        "$pfx"
  printf ':(exclude)%sstate/\n'              "$pfx"
  printf ':(exclude)%sprogress/\n'           "$pfx"
}

# ── generated front-end glue at the PROJECT ROOT ─────────────────────────────────────────
# Enumerated to the granularity the install manifest actually claims, never by directory.
# `.agents/` is described there as a USER-OWNED tree in which the installer owns only
# `rules/*`, `agents/*`, `workflows/*` and the `sdd-*` skill units — a blanket `.agents/`
# pathspec classified a project's own `.agents/skills/mine/SKILL.md` as harness drift and
# failed the mandatory gate, halting all agent work.
#
# `:(glob)` is required for the `sdd-*` wildcard; a plain wildcard pathspec matches nothing
# (verified against git 2.55.0).
emit_glue() {
  printf '%s\n' \
    ".claude/agents/" ".claude/commands/" \
    ".agents/rules/" ".agents/agents/" ".agents/workflows/" \
    ":(glob).agents/skills/sdd-*/**" \
    ".opencode/command/" ".opencode/agent/pr-fixer.md" \
    "opencode.json"

  # `.codex/agents/` and `.gemini/agents/` are namespaces the installer SHARES with the
  # operator — it preserves role files it did not write. Resolve them PER FILE from the
  # installer's own ownership ledger, `<harness-dir>/.model-agents/<tool>/`, which holds a
  # byte copy of each per-role file it last wrote. That listing IS the owned set: no
  # duplicated MODEL_ROLES list here, and it stays correct when that list changes.
  #
  # No ledger ⇒ claim NOTHING for that tool. Either nothing was generated (the `inherit`
  # default creates no `.gemini/agents/` at all) or ownership is unprovable, and claiming
  # nothing is the fail-safe direction: a missed drift costs a warning, a false positive
  # halts the harness.
  for _tool in codex gemini; do
    # REJECT A SYMLINKED LEDGER. `-d` and the glob both follow symlinks, so a symlinked
    # `.model-agents` or `.model-agents/<tool>` would enumerate an EXTERNAL directory and
    # turn arbitrary basenames there into "owned" pathspecs. The installer already refuses
    # to trust these exact components; this inherits that boundary rather than inventing a
    # weaker one. `-L` detects live and dangling links without dereferencing them.
    [ -L "$hdir/.model-agents" ] && break
    _sd="$hdir/.model-agents/$_tool"
    [ -L "$_sd" ] && continue
    [ -d "$_sd" ] || continue
    for _st in "$_sd"/*; do
      [ -L "$_st" ] && continue
      # A REGULAR FILE, not merely something that exists: the installer writes byte copies
      # and nothing else, so `-f` rejects a directory, fifo, socket and device in one test.
      # `-L` is tested first because `-f` follows symlinks.
      [ -f "$_st" ] || continue
      # `:(literal)` — a ledger basename is DATA, not a pattern. Without it a stamp named
      # `project-*.toml` is read as an fnmatch wildcard and claims every matching operator
      # file.
      printf ':(literal).%s/agents/%s\n' "$_tool" "${_st##*/}"
    done
  done
}

emit_body
[ "$mode" = "all" ] && emit_glue
exit 0
