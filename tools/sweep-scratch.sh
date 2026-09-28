#!/bin/sh
# tools/sweep-scratch.sh — E34-F01 automated scratch-dir sweep (the disk-hygiene
# backstop for the `scratchpad/<feature-id>-<role>/` namespacing convention that
# agents/builder.md, agents/reviewer.md, agents/fixer.md and agents/pr-fixer.md
# document). Nothing removes a role's own scratch directory when it writes it — the
# convention only tells a role WHERE to write, never when to clean up. This tool is
# the "when": once the owning feature's TaskStore status is `done`, its scratch is
# reclaimable, and this is the only thing that reclaims it.
#
# usage: sweep-scratch.sh [<feature-id>] [--apply]
#
#   <feature-id>  optional, exactly `E[0-9]+-F[0-9]+` — restrict the scan to
#                 immediate scratchpad/ entries whose parsed feature id equals it.
#                 Absent ⇒ scan every immediate entry.
#   --apply       mutate the filesystem (remove eligible entries). Absent ⇒ dry-run:
#                 report only, touch nothing. This is the ONLY switch between the two
#                 modes — classification and reporting are identical in both (R1).
#
# FAIL-CLOSED, on five distinct axes:
#   - An entry whose name does not start with `<feature-id>-` is `unrecognized` and is
#     NEVER acted on, in any mode (R2).
#   - An entry whose feature id is absent from the TaskStore, or whose status is
#     anything other than `done`, is `skipped: <reason>` and never removed (R4).
#   - If the TaskStore itself cannot be read or parsed, the WHOLE scan aborts before
#     classifying or removing anything — a tool-level error, distinct from a
#     per-entry skip, and the process exits non-zero (R5).
#   - An entry whose resolved real path is not a direct child of the resolved
#     scratchpad/ directory (e.g. a symlink escaping it) is skipped and reported as an
#     anomaly, never deleted through (R6).
#   - If `store.tasks` in harness.config.yaml is anything other than `local` (the only
#     backend this tool reads status from), the tool refuses outright before touching
#     `state/tasks.json` or scratchpad/ at all, and exits non-zero (R12).
#
# The tool never mutates the TaskStore, never writes outside the one resolved
# scratchpad/ directory, and never globs or acts on scratchpad/ itself.
#
# Self-location and canonical-primary resolution deliberately mirror
# tools/fix-worktree.sh (E15-F02): this makes the sweep correct even when invoked
# from inside an isolated worktree — it always acts on the ONE canonical scratchpad/
# and the ONE canonical TaskStore, never on whichever checkout happened to invoke it.

set -u

die() { echo "sweep-scratch: $*" >&2; exit 1; }

usage() { die "usage: sweep-scratch.sh [<feature-id>] [--apply]"; }

absolute_dir() { (CDPATH= cd -- "$1" 2>/dev/null && pwd -P); }

is_feature_id() {
  printf '%s' "$1" | grep -Eq '^E[0-9]+-F[0-9]+$'
}

# ── arg parsing ────────────────────────────────────────────────────────────────────
APPLY=0
SCOPE=
for _arg in "$@"; do
  case "$_arg" in
    --apply)
      [ "$APPLY" -eq 0 ] || usage
      APPLY=1
      ;;
    *)
      is_feature_id "$_arg" || usage
      [ -z "$SCOPE" ] || usage
      SCOPE="$_arg"
      ;;
  esac
done

# ── self-location + canonical primary resolution (mirrors tools/fix-worktree.sh) ──
resolve_repository() {
  CALLER_TOP="$(git rev-parse --show-toplevel 2>/dev/null)" ||
    die "must run inside a non-bare Git worktree"
  CALLER_TOP="$(absolute_dir "$CALLER_TOP")" ||
    die "cannot resolve caller worktree"
  COMMON_DIR="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" ||
    die "cannot resolve shared Git directory"
  COMMON_DIR="$(absolute_dir "$COMMON_DIR")" ||
    die "cannot resolve shared Git directory"

  PRIMARY=
  PRIMARY_COUNT=0
  while IFS= read -r _line; do
    case "$_line" in
      "worktree "*)
        _candidate=${_line#worktree }
        [ -d "$_candidate" ] || continue
        _candidate_git="$(git -C "$_candidate" rev-parse --absolute-git-dir 2>/dev/null)" ||
          die "cannot inspect registered worktree: $_candidate"
        _candidate_git="$(absolute_dir "$_candidate_git")" ||
          die "cannot resolve Git directory for: $_candidate"
        if [ "$_candidate_git" = "$COMMON_DIR" ]; then
          PRIMARY="$(absolute_dir "$_candidate")"
          PRIMARY_COUNT=$((PRIMARY_COUNT + 1))
        fi
        ;;
      bare) die "bare worktree records are unsupported" ;;
    esac
  done <<EOF
$(git worktree list --porcelain 2>/dev/null)
EOF
  [ "$PRIMARY_COUNT" -eq 1 ] ||
    die "cannot identify exactly one canonical primary worktree"

  SELF_DIR="$(absolute_dir "$(dirname -- "$0")")" ||
    die "cannot locate helper"
  case "$SELF_DIR" in
    "$CALLER_TOP/tools")
      BOARD="$PRIMARY/state/tasks.json"
      CONFIG="$PRIMARY/harness.config.yaml"
      ;;
    "$CALLER_TOP/.harness/tools")
      BOARD="$PRIMARY/.harness/state/tasks.json"
      CONFIG="$PRIMARY/.harness/harness.config.yaml"
      ;;
    *) die "helper must run from tools/ or .harness/tools/ in the caller worktree" ;;
  esac
  # scratchpad/ is ALWAYS resolved at <primary>/scratchpad, never inside .harness/ —
  # it is where Builder/Reviewer/Fixer/PR-fixer sessions actually write, regardless
  # of source vs. installed layout.
  SCRATCHPAD="$PRIMARY/scratchpad"
}
resolve_repository

# ── TaskStore backend guard (R12) ──────────────────────────────────────────────────
# Everything below assumes the `local` TaskStore backend (`store.tasks: local` in
# harness.config.yaml, store/local.md): a flat JSON file this process reads directly.
# When `store.tasks` is `obsidian`, feature status lives in specs/ frontmatter instead
# (store/obsidian.md) and `tasks.json` is only an optional, possibly stale or absent,
# mirror — reading it as the source of truth here could leave completed scratch forever
# (mirror absent/stale) or delete still-active scratch (a stale mirror that still says
# `done`). Parsing every backend's canonical status source is out of scope for this
# feature (E34-F01.spec.md scopes liveness to "TaskStore status `done`", and this repo's
# own harness.config.yaml sets `store.tasks: local`), so refuse outright for any other
# configured backend instead: fail closed, exit non-zero, touch nothing.
_cfg_store_tasks() { # _cfg_store_tasks <file> — echoes store.tasks, or nothing if absent
  [ -f "$1" ] || return 0
  awk '
    /^store:[[:space:]]*(#.*)?$/ { in_store = 1; next }
    /^[^[:space:]#]/             { in_store = 0 }
    in_store {
      line = $0
      sub(/#.*$/, "", line)
      if (match(line, "^[[:space:]]+tasks[[:space:]]*:")) {
        v = substr(line, RSTART + RLENGTH)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
        gsub(/^"|"$/, "", v)
        gsub(/^\x27|\x27$/, "", v)
        if (v != "") { print v; exit }
      }
    }
  ' "$1"
}

STORE_TASKS="$(_cfg_store_tasks "$CONFIG" || :)"
STORE_TASKS="${STORE_TASKS:-local}"
[ "$STORE_TASKS" = "local" ] ||
  die "unsupported TaskStore backend store.tasks: $STORE_TASKS — this tool only reads the 'local' backend ($BOARD); refusing to scan or mutate scratchpad/ for any other backend"

# ── TaskStore read, ONCE, before classifying a single entry (R5) ──────────────────
# A read/parse failure here is a TOOL-LEVEL error: abort the whole scan, classify and
# remove nothing, exit non-zero. This is deliberately distinct from a per-entry R4
# skip, which never touches the exit code.
TASKSTORE_OUT="$(python3 - "$BOARD" <<'PYEOF'
import json
import sys

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    sys.exit(1)

if not isinstance(data, dict):
    sys.exit(1)

epics = data.get("epics")
if not isinstance(epics, list):
    sys.exit(1)

for epic in epics:
    if not isinstance(epic, dict):
        continue
    feats = epic.get("features")
    if not isinstance(feats, list):
        continue
    for feat in feats:
        if not isinstance(feat, dict):
            continue
        fid = feat.get("id")
        status = feat.get("status")
        if isinstance(fid, str) and isinstance(status, str):
            print(fid + "\t" + status)
PYEOF
)"
TASKSTORE_RC=$?
[ "$TASKSTORE_RC" -eq 0 ] ||
  die "cannot read or parse the TaskStore at $BOARD — aborting the whole scan; nothing was classified, nothing was removed (exit $TASKSTORE_RC)"

lookup_status() {
  printf '%s\n' "$TASKSTORE_OUT" | awk -F'\t' -v id="$1" '
    $1 == id { print $2; found = 1; exit }
    END { if (!found) print "__NOTFOUND__" }
  '
}

# ── classification (R2): leading E[0-9]+-F[0-9]+ followed by a hyphen ─────────────
# Echoes the parsed feature id, or nothing when the name does not match.
parse_fid() {
  _pf_name="$1"
  _pf_fid="$(printf '%s' "$_pf_name" | grep -Eo '^E[0-9]+-F[0-9]+' || :)"
  [ -n "$_pf_fid" ] || return 0
  _pf_rest="${_pf_name#"$_pf_fid"}"
  case "$_pf_rest" in
    -?*) printf '%s' "$_pf_fid" ;;
  esac
}

# ── R6 safety check: real path of the entry must be a DIRECT child of the resolved
# real path of scratchpad/ — dereferences symlinks, so a symlink pointing outside
# scratchpad/ (or a dangling one, or one to a non-directory) never passes.
is_safe_child() {
  [ -d "$1" ] || return 1
  _isc_real="$(CDPATH= cd -P -- "$1" 2>/dev/null && pwd -P)" || return 1
  [ -n "$_isc_real" ] || return 1
  [ "$(dirname -- "$_isc_real")" = "$SCRATCHPAD_REAL" ]
}

SCRATCHPAD_REAL=""
if [ -d "$SCRATCHPAD" ]; then
  SCRATCHPAD_REAL="$(absolute_dir "$SCRATCHPAD")" || die "cannot resolve scratchpad/ real path"
fi

TOTAL=0
N_REMOVED=0
N_ELIGIBLE=0
N_SKIPPED=0
N_UNRECOGNIZED=0
BYTES_RECLAIMED=0
# R13: set the instant an `rm -rf` actually fails (permissions, read-only fs, I/O
# error) on an otherwise-eligible entry — distinct from every other exit-code case,
# and the ONLY thing that flips the final exit non-zero once classification has
# begun (R7's tool-level errors abort before this point; a plain skip never sets it).
ANY_REMOVE_FAILED=0

if [ -n "$SCRATCHPAD_REAL" ]; then
  for _entry in "$SCRATCHPAD"/*; do
    [ -e "$_entry" ] || [ -L "$_entry" ] || continue
    _name="${_entry##*/}"
    _fid="$(parse_fid "$_name")"

    # R8: a scope argument restricts the scan to entries matching it — anything else
    # (including an unrecognized entry, whose parsed id is always empty) is not even
    # reported for that invocation.
    if [ -n "$SCOPE" ] && [ "$_fid" != "$SCOPE" ]; then
      continue
    fi

    TOTAL=$((TOTAL + 1))

    if [ -z "$_fid" ]; then
      N_UNRECOGNIZED=$((N_UNRECOGNIZED + 1))
      echo "$_name	unrecognized"
      continue
    fi

    _status="$(lookup_status "$_fid")"

    if [ "$_status" = "__NOTFOUND__" ]; then
      N_SKIPPED=$((N_SKIPPED + 1))
      echo "$_name	skipped: not-found"
      continue
    fi

    if [ "$_status" != "done" ]; then
      N_SKIPPED=$((N_SKIPPED + 1))
      echo "$_name	skipped: status:$_status"
      continue
    fi

    # status is done — the only case eligible for removal. Safety check right before
    # any removal (R6), never before: a non-done entry never reaches this line.
    if ! is_safe_child "$_entry"; then
      N_SKIPPED=$((N_SKIPPED + 1))
      echo "$_name	skipped: symlink-escape"
      continue
    fi

    if [ "$APPLY" -eq 1 ]; then
      _size_kb="$(du -sk "$_entry" 2>/dev/null | awk '{print $1}')"
      case "$_size_kb" in ''|*[!0-9]*) _size_kb=0 ;; esac
      if rm -rf -- "$_entry"; then
        N_REMOVED=$((N_REMOVED + 1))
        BYTES_RECLAIMED=$((BYTES_RECLAIMED + _size_kb * 1024))
        echo "$_name	removed"
      else
        N_SKIPPED=$((N_SKIPPED + 1))
        ANY_REMOVE_FAILED=1
        echo "$_name	skipped: remove-failed"
      fi
    else
      N_ELIGIBLE=$((N_ELIGIBLE + 1))
      echo "$_name	eligible"
    fi
  done
fi

echo "summary: total=$TOTAL removed=$N_REMOVED eligible=$N_ELIGIBLE skipped=$N_SKIPPED unrecognized=$N_UNRECOGNIZED bytes_reclaimed=$BYTES_RECLAIMED"
# R13: the full summary always prints first; only the exit code reflects a removal
# failure, and only when at least one occurred — every other case (dry-run, a clean
# --apply run, or --apply with only classification skips) still exits 0.
[ "$ANY_REMOVE_FAILED" -eq 0 ] || exit 1
exit 0
